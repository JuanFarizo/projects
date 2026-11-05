-- P4 Gradle T6 (G6): a build.gradle that does not compile (unclosed `dependencies {`). Run via tests/run.sh (gated like 67:
-- the live cases copy the Gradle fixture's wrapper; the build fails before any dependency is fetched, so no network).
-- Spec: specs/006-p4-gradle.md "T6". Throwaway files under /tmp/nv4j/gradle71-<pid> (removed at the end).
-- Root cause found (repro logs /tmp/nv4j/logs/g6-*): NOT the product. jdt.ls answers java.project.getAll with [] when the
-- Gradle import fails; tests/lib/lsp.lua wait_ready sent a new getAll on every evaluation of its vim.wait condition, each
-- reply woke the wait at once (about 4000 requests a second, nvim 96% CPU, jdt.ls 60%), and Neovim 0.12's vim.wait does
-- not time out when every round is under 1 ms. The product gap found on the way: jdt.ls puts the error on the project
-- FOLDER's URI, so nv4j.buildfile (build-file names only) said nothing.
--  wait_bounded      (deterministic twin of the hang, no jdt.ls): a stub jdtls client answering getAll with [] through
--                    vim.schedule (sub-ms, like the real one): lsp.wait_ready(buf, 1500) returns nil in <= 3 s with <= 6
--                    getAll requests. (HEAD harness: thousands of requests, control `oldwait`.)
--  folder_diag       (unit): a jdt.ls ERROR diagnostic on a project folder buffer with Gradle's "Could not compile build file
--                    '<dir>/build.gradle' ... @ line 3" message -> ONE ERROR notification titled "Build file" naming build.gradle,
--                    "build file has errors" and the line; the same diagnostics again -> no second one; cleared -> one INFO
--                    "build errors fixed".
--  folder_other      (unit, perf guard for 62_refactor.rename_package_fallback): a jdt.ls folder error that names no build file
--                    (jdt.ls's transient "The project was not built since its build path is incomplete", set and cleared 10
--                    times as during one 62 rename) -> no notification at all; a diagnostic of another namespace on the folder,
--                    and a jdt.ls error on a plain .java file -> nothing. Control `folderall` (the filter removed) FAILs it.
--  buildfile_kept    (unit): an error on a build.gradle buffer still gives "1 build error(s), the project classpath may be stale".
--  reimport_unit     (unit): with a failed folder, saving its build.gradle sends java.project.import to the jdt.ls of that root
--                    (stub client); a save in another project or after the errors cleared sends nothing.
--  broken_live       (live): throwaway Gradle project with the unclosed block, Main.java opened: one "Build file" ERROR naming
--                    build.gradle and line 3 within 120 s; nvim stays idle (CPU time over 8 s of plain waiting < 1.5 s, a
--                    scheduled callback runs in < 200 ms); lsp.wait_ready(buf, 5000) returns nil in <= 8 s with <= 14 getAll.
--  fixed_live        (live): build.gradle fixed and saved from Neovim -> "build errors fixed" and java.project.getAll lists the
--                    project within 120 s. jdt.ls does NOT reimport by itself (measured: nothing in 120 s, the failed project is
--                    not a jdt.ls project, its build file is not watched): nv4j.buildfile sends java.project.import on the save.
--  stream_unit       (unit, no jdt.ls): root.recover_stream (the client's on_error, plugins/java.lua) on INVALID_SERVER_JSON /
--                    INVALID_SERVER_MESSAGE of a running jdt.ls: stops that client (stub), remembers the root as refused and WARNs
--                    "corrupt message"; a second break in the same root only WARNs; other codes, other roots and a stopped client
--                    do nothing.
--  stream_live       (live, loose Main.java): after a simulated INVALID_SERVER_JSON on the real client (Client:_on_error) a NEW
--                    jdtls client attaches to the buffer within 120 s and answers java.project.getAll.
--  Flake 2026-11-04 16:54 (test-20261104-164008.log): jdt.ls sent a corrupt message (INVALID_SERVER_JSON at character 65536, then
--  "Content-Length not found in header: ...window/workDoneProgress/create..."), Neovim's parser stopped, no note and no project
--  for 120 s: broken_live and fixed_live FAIL lines now carry EVIDENCE (clients, refused roots, lsp.log on_error/exit lines,
--  capture dumps) and wait_ready's reason. This check runs with vim.g.nv4j_lsp_capture on (raw stdout dump on the next hit).
-- Controls (NV4J_71_CONTROL=<comma list>): oldwait (HEAD tests/lib/lsp.lua wait_ready for wait_bounded; the live wait_ready
-- step is skipped under it, it would spin), oldbuildfile (HEAD nvim/lua/nv4j/buildfile.lua), nonotify (buildfile.on_changed a
-- no-op), folderall (folder errors without a build file path notified again),
-- norecover (root.recover_stream a no-op: stream_unit and stream_live FAIL). Logs cited in specs/006 T6 and the T6/T7 report.
vim.o.confirm = false
vim.g.nv4j_lsp_capture = true -- raw stdout of jdt.ls dumped on INVALID_SERVER_JSON / abnormal exit (docs/HANDOFF-p3.md, flake A)
local lsp = require("lsp")
local E = require("edit")
local P = "71_gradle_broken."
local log = vim.env.NV4J_LOG or "(no NV4J_LOG)"
local CONTROL = vim.env.NV4J_71_CONTROL or ""
local function has(c) return ("," .. CONTROL .. ","):find("," .. c .. ",", 1, true) ~= nil end
local HERE = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize((debug.getinfo(1, "S").source:gsub("^@", ""))))) -- tests/
local NV = vim.fs.dirname(HERE)

local TMP = "/tmp/nv4j/gradle71-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
TMP = vim.uv.fs_realpath(TMP)
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(text or "")
  f:close()
end
local function short(s) return (tostring(s):gsub(vim.pesc(TMP), "TMP")) end
local function head_file(rel) -- the committed (HEAD) version of a repo file, for the controls
  local out = TMP .. "/head-" .. vim.fs.basename(rel)
  local git_root = vim.fn.systemlist({ "git", "-C", NV, "rev-parse", "--show-toplevel" })[1]
  local prefix = vim.fn.systemlist({ "git", "-C", NV, "rev-parse", "--show-prefix" })[1] or ""
  vim.fn.system({ "sh", "-c", ('git -C "%s" show "HEAD:%s%s" > "%s"'):format(git_root, prefix, rel, out) })
  return out
end

if has("oldbuildfile") then
  package.loaded["nv4j.buildfile"] = dofile(head_file("nvim/lua/nv4j/buildfile.lua"))
end
if has("folderall") then -- the current buildfile.lua with its "names a build file" folder filter switched off
  local src = table.concat(vim.fn.readfile(NV .. "/nvim/lua/nv4j/buildfile.lua"), "\n")
  local patched, n = src:gsub("if folder then %-%- keep only", "if false then -- keep only")
  assert(n == 1, "folderall control: filter line not found")
  patched = patched:gsub("build_file_of%(raw%[1%]%)", "(build_file_of(raw[1]) or name)")
  local f = TMP .. "/buildfile-folderall.lua"
  vim.fn.writefile(vim.split(patched, "\n"), f)
  package.loaded["nv4j.buildfile"] = dofile(f)
end
if has("norecover") then require("nv4j.root").recover_stream = function() return "ignored" end end
local bf = require("nv4j.buildfile")
if has("nonotify") then bf.on_changed = function() end end
bf.setup()
if CONTROL ~= "" then io.stdout:write("\nCONTROL " .. CONTROL .. " active\n") end

local notes = E.capture_notify()
local function build_notes(from)
  local out = {}
  for i = (from or 0) + 1, #notes do
    if notes[i].msg:find("build error", 1, true) or notes[i].msg:find("build file has errors", 1, true)
      or notes[i].msg:find("project error", 1, true) then
      out[#out + 1] = notes[i]
    end
  end
  return out
end
local function evidence(size0, buf) -- why no client / no note: clients, refused roots, lsp.log lines, capture dumps, wait_ready's reason
  local parts = {}
  local cl = {}
  for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do
    cl[#cl + 1] = ("%d %s %s"):format(c.id, short(c.config and c.config.root_dir or "?"), c:is_stopped() and "STOPPED" or "alive")
  end
  parts[#parts + 1] = "jdtls clients [" .. table.concat(cl, "; ") .. "]"
  local ref = {}
  for _, raw in pairs(require("nv4j.root").refused()) do ref[#ref + 1] = short(raw) end
  parts[#parts + 1] = "roots refused by the loose cap [" .. table.concat(ref, ", ") .. "]"
  local lines = {}
  local f = io.open(require("nv4j.paths").logs .. "/lsp.log", "rb")
  if f then
    f:seek("set", size0 or 0)
    for l in (f:read("*a") or ""):gmatch("[^\n]+") do
      if l:find("on_error", 1, true) or l:find("INVALID_SERVER", 1, true) or l:find("Bad file descriptor", 1, true)
        or l:find("exited", 1, true) or l:find("Content-Length not found", 1, true) then
        lines[#lines + 1] = (l:gsub("^.-log%.lua:%d+%s*", ""):sub(1, 220))
      end
    end
    f:close()
  end
  parts[#parts + 1] = ("lsp.log on_error/exit lines %d: %s"):format(#lines, table.concat(vim.list_slice(lines, 1, 3), " | "))
  local dumps = {}
  for _, st in pairs(require("nv4j.lspcapture").states()) do if st.last_dump then dumps[#dumps + 1] = st.last_dump end end
  parts[#parts + 1] = "capture dumps [" .. table.concat(dumps, ", ") .. "]"
  if buf and vim.api.nvim_buf_is_valid(buf) then
    local r, why = lsp.wait_ready(buf, 3000)
    parts[#parts + 1] = "wait_ready(3000): " .. (r and "ready" or tostring(why))
  end
  return table.concat(parts, "; ")
end
local function show(list)
  return table.concat(vim.tbl_map(function(n) return ("[%s] %s"):format(tostring(n.level), short(n.msg:gsub("\n", " / "))) end, list), " | "):sub(1, 500)
end

-- ── wait_bounded: deterministic twin of the hang ─────────────────────────────────────────────────
do
  local W = has("oldwait") and dofile(head_file("tests/lib/lsp.lua")) or lsp
  local LIMIT = 20000 -- the stub stops answering after this many requests, so the HEAD harness ends too (control)
  local n = 0
  local stub = {
    is_stopped = function() return false end,
    request = function(_, method, _, handler)
      if method ~= "workspace/executeCommand" then return false end
      n = n + 1
      if n > LIMIT then return false end
      vim.schedule(function() handler(nil, {}) end)
      return true, n
    end,
  }
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, TMP .. "/twin/Main.java")
  local orig = vim.lsp.get_clients
  vim.lsp.get_clients = function(f)
    if f and f.name == "jdtls" then return { stub } end
    return orig(f)
  end
  local t0 = vim.uv.hrtime()
  local ok, r = pcall(W.wait_ready, buf, 1500)
  local ms = (vim.uv.hrtime() - t0) / 1e6
  vim.lsp.get_clients = orig
  vim.api.nvim_buf_delete(buf, { force = true })
  lsp.report(P .. "wait_bounded", ok and r == nil and ms <= 3000 and n <= 6,
    ("wait_ready(1500) on an import that never lists a project: returned %s after %.0f ms with %d getAll requests (want nil, <= 3000 ms, <= 6)%s; log %s")
      :format(ok and tostring(r) or ("error " .. tostring(r)), ms, n, has("oldwait") and " [HEAD harness]" or "", log))
end

-- ── unit: folder diagnostics ──────────────────────────────────────────────────────────────────
local MSG = "The supplied phased action failed with an exception.\nA problem occurred configuring root project 'u'.\n"
  .. "Could not compile build file '%s/build.gradle'.\nstartup failed:\nbuild file '%s/build.gradle': 3: Unexpected input: '{' @ line 3, column 14.\n"
  .. "   dependencies {\n                ^\n1 error"
local NS = vim.api.nvim_create_namespace("nv4j71.jdtls")
local OTHER = vim.api.nvim_create_namespace("nv4j71.other")
local function diag(msg) return { { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = msg, source = "Java" } } end
local function dirbuf(dir)
  vim.fn.mkdir(dir, "p")
  local b = vim.fn.bufadd(dir)
  return b
end
do
  local D = TMP .. "/u"
  write(D .. "/build.gradle", "dependencies {\n")
  local b = dirbuf(D)
  local n0 = #notes
  vim.diagnostic.set(NS, b, diag(MSG:format(D, D)))
  local first = build_notes(n0)
  vim.diagnostic.set(NS, b, diag(MSG:format(D, D)))
  local again = build_notes(n0)
  local n1 = #notes
  vim.diagnostic.set(NS, b, {})
  local fixed = build_notes(n1)
  local f1 = first[1] and first[1].msg or ""
  lsp.report(P .. "folder_diag",
    #first == 1 and first[1].level == vim.log.levels.ERROR and f1:find("/u/build.gradle: build file has errors", 1, true) ~= nil
      and f1:find("@ line 3", 1, true) ~= nil
      and #again == 1 and #fixed == 1 and fixed[1].level == vim.log.levels.INFO and fixed[1].msg:find("build errors fixed", 1, true) ~= nil,
    ("first: %d note(s) %s; same diagnostics again: %d total (want 1); cleared: %s (want 1 INFO 'build errors fixed'); log %s")
      :format(#first, show(first), #again, show(fixed), log))
end
do
  local D = TMP .. "/v"
  local b = dirbuf(D)
  local n0 = #notes
  -- what jdt.ls puts on the demo folder during every 62_refactor rename (ten times in one run), set and cleared 10 times
  local t0 = vim.uv.hrtime()
  for _ = 1, 10 do
    vim.diagnostic.set(NS, b, diag("The project was not built since its build path is incomplete. Cannot find the class file for demo.billing.Bill. Fix the build path then try building this project"))
    vim.diagnostic.set(NS, b, {})
  end
  local transient_ms = (vim.uv.hrtime() - t0) / 1e6
  local generic = vim.list_slice(notes, n0 + 1)
  local D2 = TMP .. "/w"
  local b2 = dirbuf(D2)
  local n1 = #notes
  vim.diagnostic.set(OTHER, b2, diag(MSG:format(D2, D2)))
  local other = build_notes(n1)
  write(TMP .. "/x/Main.java", "class Main {}")
  local b3 = vim.fn.bufadd(TMP .. "/x/Main.java")
  vim.diagnostic.set(NS, b3, diag("Syntax error on token"))
  local java = build_notes(n1)
  lsp.report(P .. "folder_other",
    #generic == 0 and #other == 0 and #java == 0,
    ("transient jdt.ls folder error without a build file path, set and cleared 10 times: %d notification(s) in %.1f ms %s (want 0); other namespace on a folder: %d, jdt.ls error on a .java file: %d (want 0, 0); log %s")
      :format(#generic, transient_ms, show(generic), #other, #java, log))
end
do
  local D = TMP .. "/k"
  write(D .. "/build.gradle", "")
  local b = vim.fn.bufadd(D .. "/build.gradle")
  local n0 = #notes
  vim.diagnostic.set(NS, b, diag("Unresolved dependency: com.example.nonexistent:nothing:9.9.9"))
  local got = build_notes(n0)
  lsp.report(P .. "buildfile_kept",
    #got == 1 and got[1].msg:find("1 build error(s), the project classpath may be stale", 1, true) ~= nil,
    ("error on build.gradle: %s (want 1 '1 build error(s), the project classpath may be stale'); log %s"):format(show(got), log))
end

do
  local D = TMP .. "/u2"
  write(D .. "/build.gradle", "dependencies {\n")
  write(TMP .. "/other/build.gradle", "")
  local b = dirbuf(D)
  vim.diagnostic.set(NS, b, diag(MSG:format(D, D)))
  local sent = {}
  local stub = { config = { root_dir = D }, request = function(_, m, params) sent[#sent + 1] = m .. ":" .. tostring(params and params.command); return true, 1 end }
  local orig = vim.lsp.get_clients
  vim.lsp.get_clients = function(f) if f and f.name == "jdtls" then return { stub } end return orig(f) end
  local ok1 = pcall(bf.reimport, D .. "/build.gradle")
  local n_bad = #sent
  pcall(bf.reimport, TMP .. "/other/build.gradle")
  local n_other = #sent - n_bad
  vim.diagnostic.set(NS, b, {})
  local before_fixed = #sent
  pcall(bf.reimport, D .. "/build.gradle")
  local n_fixed = #sent - before_fixed
  vim.lsp.get_clients = orig
  lsp.report(P .. "reimport_unit", ok1 and n_bad == 1 and sent[1] == "workspace/executeCommand:java.project.import" and n_other == 0 and n_fixed == 0,
    ("save of the failed project's build.gradle: %d request(s) %s (want 1 java.project.import); save in another project: %d; after the errors cleared: %d (want 0, 0); log %s")
      :format(n_bad, table.concat(sent, ","), n_other, n_fixed, log))
end

-- ── unit: a corrupt jdt.ls stream restarts the client ──────────────────────────────────────────────
do
  local R = require("nv4j.root")
  R.clear_refused()
  local D = TMP .. "/stream"
  vim.fn.mkdir(D, "p")
  local stops, stopped = 0, false
  local client = { config = { root_dir = D }, is_stopped = function() return stopped end,
    stop = function(_, force) stops = stops + 1 stopped = force == true end }
  local other = { config = { root_dir = TMP .. "/elsewhere" }, is_stopped = function() return false end, stop = function() stops = stops + 100 end }
  local codes = vim.lsp.rpc.client_errors
  local n0 = #notes
  local list = { client, other }
  local get = function() return list end
  local r_other = R.recover_stream(D, codes.READ_ERROR, get)
  local r_none = R.recover_stream(TMP .. "/nowhere", codes.INVALID_SERVER_JSON, get)
  local r1 = R.recover_stream(D, codes.INVALID_SERVER_JSON, get)
  vim.wait(500, function() return stops > 0 end, 10)
  local refused = R.refused()[R.canon(D)] ~= nil
  local was_stopped = stopped
  local r2 = R.recover_stream(D, codes.INVALID_SERVER_MESSAGE, get) -- the stopped client no longer counts
  stopped = false
  local r3 = R.recover_stream(D, codes.INVALID_SERVER_MESSAGE, get) -- a client of the same root again: warn only
  vim.wait(200, function() return false end, 10)
  local warns = 0
  for i = n0 + 1, #notes do if notes[i].msg:find("corrupt message", 1, true) then warns = warns + 1 end end
  R.clear_refused()
  lsp.report(P .. "stream_unit",
    r_other == "ignored" and r_none == "no client" and r1 == "restart" and stops == 1 and was_stopped == true and refused
      and r2 == "no client" and r3 == "again" and warns == 2,
    ("other error code: %s (want ignored); other root: %s (want no client); first break: %s, stop(true) calls %d (want restart, 1), root remembered %s; "
      .. "stopped client: %s (want no client); same root again: %s (want again); corrupt-message WARNs %d (want 2); log %s")
      :format(r_other, r_none, r1, stops, tostring(refused), r2, r3, warns, log))
end

-- ── live: the real broken build ───────────────────────────────────────────────────────────────
local paths = require("nv4j.paths")
local LIVE = TMP .. "/live"
local function project_name(r) return vim.fs.basename(r) .. "-" .. vim.fn.sha256(r):sub(1, 8) end
local GOOD = "plugins { id 'java' }\nrepositories { mavenCentral() }\ndependencies {\n}\n"
local fixture = vim.env.NV4J_GRADLE_FIXTURE
if not fixture or vim.fn.isdirectory(fixture) == 0 then
  lsp.report(P .. "broken_live", false, "NV4J_GRADLE_FIXTURE not set (run through tests/run.sh)")
else
  local ok, err = pcall(function()
    vim.fn.mkdir(LIVE, "p")
    vim.fn.system({ "cp", "-R", fixture .. "/gradle", fixture .. "/gradlew", LIVE .. "/" })
    write(LIVE .. "/settings.gradle", "rootProject.name = 'broken71'\n")
    write(LIVE .. "/build.gradle", "plugins { id 'java' }\nrepositories { mavenCentral() }\ndependencies {\n    implementation 'org.slf4j:slf4j-api:2.0.16'\n")
    write(LIVE .. "/src/main/java/demo/Main.java", "package demo;\n\npublic class Main {\n  public static void main(String[] a) { System.out.println(1); }\n}\n")
    local lsplog = paths.logs .. "/lsp.log"
    local size0 = (vim.uv.fs_stat(lsplog) or { size = 0 }).size
    local n0 = #notes
    local t0 = vim.uv.hrtime()
    local buf = lsp.open(LIVE .. "/src/main/java/demo/Main.java")
    local function errs_note()
      for _, n in ipairs(build_notes(n0)) do
        if n.level == vim.log.levels.ERROR then return n end
      end
    end
    vim.wait(120000, function() return errs_note() ~= nil end, 200)
    local note = errs_note()
    local note_ms = (vim.uv.hrtime() - t0) / 1e6
    -- idle: CPU time of this nvim while it only waits (no harness polling)
    local function cpu() local r = vim.uv.getrusage(); return r.utime.sec + r.utime.usec / 1e6 + r.stime.sec + r.stime.usec / 1e6 end
    local c0 = cpu()
    vim.wait(8000, function() return false end, 200)
    local cpu_s = cpu() - c0
    local ts, ran = vim.uv.hrtime(), nil
    vim.schedule(function() ran = vim.uv.hrtime() end)
    vim.wait(2000, function() return ran ~= nil end, 10)
    local sched_ms = ran and (ran - ts) / 1e6 or -1
    -- the harness wait on the same broken import is bounded now
    local wr_ms, gets, wr = -1, -1, "skipped (oldwait control)"
    local no_client_why
    if not has("oldwait") then
      local client = vim.lsp.get_clients({ name = "jdtls", bufnr = buf })[1]
      if client then
        gets = 0
        local orig_req = client.request
        client.request = function(self, method, params, ...)
          if method == "workspace/executeCommand" and params and params.command == "java.project.getAll" then gets = gets + 1 end
          return orig_req(self, method, params, ...)
        end
        local tw = vim.uv.hrtime()
        wr = tostring(lsp.wait_ready(buf, 5000))
        wr_ms = (vim.uv.hrtime() - tw) / 1e6
        client.request = orig_req
      else
        wr = "no jdtls client"
        local _, why = lsp.wait_ready(buf, 3000)
        no_client_why = why
      end
    end
    local grew = (vim.uv.fs_stat(lsplog) or { size = 0 }).size - size0
    local all = build_notes(n0)
    local nmsg = note and note.msg or ""
    lsp.report(P .. "broken_live",
      note ~= nil and nmsg:find("build.gradle: build file has errors", 1, true) ~= nil and nmsg:find("line 3", 1, true) ~= nil
        and #all == 1 and cpu_s < 1.5 and sched_ms >= 0 and sched_ms < 200
        and (has("oldwait") or (wr == "nil" and wr_ms <= 8000 and gets <= 14)),
      ("note after %.0f ms: %s; build notes %d (want 1); nvim CPU %.2f s in 8 s of waiting (want < 1.5), schedule latency %.1f ms; wait_ready(5000) -> %s in %.0f ms with %d getAll (want nil, <= 8000, <= 14); lsp.log +%d B%s; log %s")
        :format(note_ms, show(note and { note } or {}), #all, cpu_s, sched_ms, wr, wr_ms, gets, grew,
          (note and wr == "nil") and "" or ("; EVIDENCE " .. evidence(size0, buf) .. (no_client_why and ("; wait_ready: " .. no_client_why) or "")), log))

    -- fixed_live: the user fixes the block and saves from Neovim
    local n1 = #notes
    vim.cmd("edit " .. vim.fn.fnameescape(LIVE .. "/build.gradle"))
    local gb = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(gb, 0, -1, false, vim.split(GOOD, "\n", { trimempty = true }))
    vim.cmd("silent write")
    local tf = vim.uv.hrtime()
    local client = vim.lsp.get_clients({ name = "jdtls" })[1]
    local listed = false
    local last_ask = 0
    vim.wait(120000, function()
      local fixed = false
      for i = n1 + 1, #notes do if notes[i].msg:find("build errors fixed", 1, true) then fixed = true end end
      if client and not listed and vim.uv.hrtime() - last_ask > 1e9 then
        last_ask = vim.uv.hrtime()
        client:request("workspace/executeCommand", { command = "java.project.getAll" }, function(e, r)
          if not e and type(r) == "table" and #r > 0 then listed = true end
        end)
      end
      return fixed and listed
    end, 200)
    local fixed_note
    for i = n1 + 1, #notes do if notes[i].msg:find("build errors fixed", 1, true) then fixed_note = notes[i] end end
    lsp.report(P .. "fixed_live", fixed_note ~= nil and listed,
      ("after the fix + :w: 'build errors fixed' %s, getAll lists the project %s, after %.0f ms (want both within 120 s); notes since: %s%s; log %s")
        :format(tostring(fixed_note ~= nil), tostring(listed), (vim.uv.hrtime() - tf) / 1e6, show(vim.list_slice(notes, n1 + 1)),
          (fixed_note ~= nil and listed) and "" or ("; EVIDENCE " .. evidence(size0, buf)), log))
  end)
  if not ok then lsp.report(P .. "broken_live", false, "error: " .. tostring(err)) end
  for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do c:stop() end
  vim.wait(15000, function() return #vim.lsp.get_clients({ name = "jdtls" }) == 0 end, 200)
  for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do c:stop(true) end
  -- the Gradle daemon this project started (same wrapper version as the fixture: stops that version's idle daemons)
  local jdk = vim.fn.system({ "nvim", "-l", HERE .. "/lib/jdk_home.lua", "21" }):gsub("%s+$", "")
  if vim.fn.isdirectory(jdk) == 1 and vim.fn.filereadable(LIVE .. "/gradlew") == 1 then
    vim.fn.system({ "sh", "-c", ('cd "%s" && JAVA_HOME="%s" ./gradlew --stop >/dev/null 2>&1'):format(LIVE, jdk) })
  end
  local rr = vim.uv.fs_realpath(LIVE) or LIVE
  vim.fn.delete(paths.jdtls_data .. "/" .. project_name(rr), "rf")
  vim.fn.delete(paths.jdtls_config .. "/" .. project_name(rr), "rf")
end

-- ── live: a corrupt stream on the real client ─────────────────────────────────────────────────────
do
  local ok, err = pcall(function()
    local D = TMP .. "/streamlive"
    write(D .. "/Main.java", "public class Main { public static void main(String[] a) { System.out.println(1); } }\n")
    local n0 = #notes
    local buf = lsp.open(D .. "/Main.java")
    local first
    vim.wait(180000, function() first = vim.lsp.get_clients({ name = "jdtls", bufnr = buf })[1]; return first ~= nil end, 200)
    local ready = first ~= nil and lsp.wait_ready(buf, 120000) ~= nil
    local old_id = first and first.id
    if first then first:_on_error(vim.lsp.rpc.client_errors.INVALID_SERVER_JSON, "simulated corrupt message") end
    local t0 = vim.uv.hrtime()
    local second
    vim.wait(120000, function()
      for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls", bufnr = buf })) do
        if c.id ~= old_id and not c:is_stopped() then second = c end
      end
      return second ~= nil
    end, 200)
    local answered = false
    if second then
      local res = second:request_sync("workspace/executeCommand", { command = "java.project.getAll" }, 60000, buf)
      answered = res ~= nil and res.err == nil
    end
    local warns = 0
    for i = n0 + 1, #notes do if notes[i].msg:find("corrupt message", 1, true) then warns = warns + 1 end end
    lsp.report(P .. "stream_live", ready and second ~= nil and answered and warns == 1 and (first and first:is_stopped()),
      ("first client ready %s (id %s), after the simulated break old client stopped %s, new client %s (id %s) attached after %.0f ms and answered getAll %s, corrupt-message WARNs %d (want 1); log %s")
        :format(tostring(ready), tostring(old_id), tostring(first and first:is_stopped()), tostring(second ~= nil), tostring(second and second.id),
          (vim.uv.hrtime() - t0) / 1e6, tostring(answered), warns, log))
  end)
  if not ok then lsp.report(P .. "stream_live", false, "error: " .. tostring(err)) end
  for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do c:stop(true) end
  vim.wait(15000, function() return #vim.lsp.get_clients({ name = "jdtls" }) == 0 end, 200)
  require("nv4j.root").clear_refused()
end

vim.fn.delete(TMP, "rf")
lsp.finish()
