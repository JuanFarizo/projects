-- P4 Gradle safety net (T1) and the silent false green (T2, G1). Run via tests/run.sh. Spec: specs/006-p4-gradle.md
-- (decision D28: first class = jdt.ls-driven parity proven here, no second Gradle runner). Fixture:
-- tests/fixtures/gradle-boot ($NV4J_GRADLE_FIXTURE, Groovy DSL, Spring Boot 3.5.13, Gradle 9.7.1 wrapper committed,
-- JUnit 5 with junit-platform-launcher declared). run.sh resolves it once (offline first, then online, D31) and prints
-- `SKIP 67_gradle.lua` when Gradle cannot resolve it. Nothing in this check edits the fixture on disk; throwaway
-- projects live in /tmp/nv4j/gradle67-<pid> (removed afterwards).
-- Budgets (specs/006 "Budgets"; import is info only, MEASURED not invented: latency.jsonl gradle_import):
-- nearest test warm <= 10 s (P3 budget), rs started <= 20 s, rS started <= 60 s.
--  attached          : jdt.ls attached to the fixture's controller and ready; import time logged (info).
--  root_dir          : jdt.ls root_dir and nv4j.root.project are the fixture dir (kind "build"), java.project.getAll lists
--                      the gradle-boot project.
--  spring_ls         : the Spring LS answers on the Gradle project: workspace/symbol "@/" lists `@/hello`, "@+" the
--                      bean (Calculator), completion of `server.po` in application.properties lists server.port.
--  keys              : <leader>tr/tt/tp bound in the test buffer with Nv4J's descs; <leader>rs/rS/rd global.
--  test_nearest      : <leader>tr on `adds` run twice (cold info, warm <= 10 s): 1 passed 0 failed 0 skipped, a RemoteTestRunner
--                      launch seen by nvim-dap, quickfix title "Nv4J tests: 1 passed...".
--  test_class        : <leader>tt in CalculatorTest: 2/0/0.   test_project: <leader>tp: 3/1/0 (the failing class included), 1 launch.
--  failure_shown     : CalculatorFailingTest: 1 passed 1 failed, quickfix entry at the `assertEquals(7` line with the
--                      message, nv4j_tests diagnostic on that line.
--  run_cp            : <leader>rs (jdt.ls classpath, java -cp): "Started GradleBootApplication in" in the terminal, <= 20 s,
--                      the session command is a java -cp ...; stopped with the stop key, no JVM left.
--  run_bootrun       : <leader>rS: the command line is the wrapper, `<fixture>/gradlew bootRun` (not bare gradle), cwd the
--                      fixture, "Started GradleBootApplication in" <= 60 s, stopped, no JVM left (the Gradle daemon stays).
--  debug_started     : <leader>rd: nvim-dap session, the app starts (session running, JVM seen), terminate leaves no JVM.
--  launcher_gradle_layout (T2 a, unit): debug.junit_launcher with a Gradle cache layout (.../junit-platform-engine/<ver>/<hash>/
--                      junit-platform-engine-<ver>.jar) swaps the bundled launcher for the cache's launcher of the same
--                      version; the Maven layout still works; no launcher in the cache = one WARN naming the dependency.
--  launcher_missing  : a plain Gradle project (not Boot: the Boot build gets the launcher anyway, measured) with junit-jupiter 5.12.2 and no
--                      junit-platform-launcher (the standard Gradle 8 setup, G1): nearest 1/0/0, class 2/0/0, project 2/0/0, launcher
--                      swapped (debug.launchers_replaced).
--  crash_closed / crash_partial / crash_never (T2 b, stub twins, no Gradle): dap.run stubbed with a fake JVM whose stream (1) connects
--                      and closes with nothing, (2) sends a test tree and a started test and closes without %RUNTIME, (3) never
--                      connects; each ends with result.error naming the cause (the last NoClassDefFoundError line of the JVM console),
--                      never 0/0/0 without error, and an ERROR notification names it, the lock is released.
--  empty_done_ok     : a stream that ends complete (%RUNTIME) with 0 tests (a class with no tests) is NOT an error.
--  fixture_restored  : the fixture's sources are unchanged on disk afterwards.
-- Controls (NV4J_67_CONTROL=<names>, comma list, see specs/006 and tests-runner.md): noclient (wait_ready never answers), nokeys
-- (tests.bind a no-op), markers (Gradle markers removed from nv4j.root),
-- stubtests (nv4j.tests.run fabricates a result), stubrun (nv4j.run.spring_boot does nothing), nowrapper (gradlew not
-- executable for nv4j.run), plus NV4J_SPRING=0 for spring_ls; T2 controls swap the HEAD debug.lua / tests.lua back in.
-- Timings: /tmp/nv4j/logs/latency.jsonl (gradle_import, gradle_test_nearest_*, gradle_run_cp, gradle_run_bootrun).
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local F = require("fixture")
local P = "67_gradle."
local WARM_BUDGET_MS, RS_BUDGET_MS, RS_GRADLE_BUDGET_MS = 10000, 20000, 60000
local RUN_TIMEOUT_MS = 150000
local RUNNER = "org.eclipse.jdt.internal.junit.runner.RemoteTestRunner"
local CONTROL = vim.env.NV4J_67_CONTROL or ""
local MAINCLASS = "gradleboot.GradleBootApplication"

local fixture = vim.env.NV4J_GRADLE_FIXTURE
if not fixture or vim.fn.isdirectory(fixture) == 0 then
  lsp.report(P .. "attached", false, "NV4J_GRADLE_FIXTURE not set or not a directory (run through tests/run.sh)")
  return lsp.finish()
end
fixture = vim.uv.fs_realpath(fixture)
local src = fixture .. "/src/main/java/gradleboot/"
local tdir = fixture .. "/src/test/java/gradleboot/"
local snap = F.snapshot(fixture)
local PID = vim.fn.getpid()
local TMP = "/tmp/nv4j/gradle67-" .. PID
vim.fn.delete(TMP, "rf")

local function jvms() -- JVMs of the fixture app (rs, rS and rd all run GradleBootApplication)
  local out = {}
  for p in vim.fn.system({ "pgrep", "-f", MAINCLASS }):gmatch("%d+") do out[#out + 1] = tonumber(p) end
  return out
end
local function cleanup()
  vim.fn.delete(TMP, "rf")
end

-- ── controls ──────────────────────────────────────────────────────────────────────────────────
local R = require("nv4j.run")
local root_mod = require("nv4j.root")
local tests = require("nv4j.tests")
local dbg = require("nv4j.debug")
local dap = require("dap")
local function has(c) return (","..CONTROL..","):find(","..c..",", 1, true) ~= nil end
if has("markers") then
  root_mod.build_markers = vim.tbl_filter(function(m) return not m:find("gradle", 1, true) end, root_mod.build_markers)
end
if has("stubtests") then
  tests.run = function(o)
    vim.schedule(function()
      if o.on_done then o.on_done({ passed = 1, failed = 0, skipped = 0, failures = {}, tests = { { method = "adds", state = "passed" } } }) end
    end)
  end
end
if has("stubrun") then
  R.spring_boot = function() end
end
if has("nowrapper") then
  local exe = vim.fn.executable
  vim.fn.executable = function(p)
    if type(p) == "string" and p:find("/gradlew$") then return 0 end
    return exe(p)
  end
end
if has("noclient") then
  lsp.wait_ready = function() return nil end
end
if has("nokeys") then
  tests.bind = function() end
end
if CONTROL ~= "" then io.stdout:write("\nCONTROL " .. CONTROL .. " active\n") end

local notes = E.capture_notify()
local function notes_since(n)
  local out = {}
  for i = n + 1, #notes do out[#out + 1] = notes[i] end
  return out
end
local function short_notes(list)
  return table.concat(vim.tbl_map(function(n) return n.msg:gsub("\n", " / ") end, list), " | "):sub(1, 400)
end
local function wait_until(ms, pred)
  local ok, r = pcall(vim.wait, ms, pred, 20)
  if ok then return r end
  return pred()
end
local function text(b)
  if not (b and vim.api.nvim_buf_is_valid(b)) then return "" end
  return table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "")
end

-- ── test run helpers (as 60_tests_runner) ────────────────────────────────────────────────────────
local launches = {}
dap.listeners.on_config["n67"] = function(c)
  if c.mainClass == RUNNER then launches[#launches + 1] = c end
  return c
end
-- every nv4j.tests.run call (also the ones the keys make) reports its result here
local last_done
local orig_run = tests.run
tests.run = function(o)
  o = vim.tbl_extend("force", {}, o or {})
  local inner = o.on_done
  o.on_done = function(r)
    last_done = r
    if inner then inner(r) end
  end
  return orig_run(o)
end

--- One run: `how` is a key (<leader>tr...) pressed in buffer b at lnum, or a scope for tests.run. Returns result, ms, evidence.
local function run(how, b, lnum, extra)
  vim.api.nvim_set_current_buf(b)
  if lnum then vim.api.nvim_win_set_cursor(0, { lnum, 0 }) end
  last_done = nil
  local before = #launches
  local replaced0 = dbg.launchers_replaced or 0
  local t0 = E.now()
  local ok, why
  if how:sub(1, 8) == "<leader>" then
    local m = vim.fn.maparg(how, "n", false, true)
    ok, why = pcall(function() m.callback() end)
  else
    ok, why = pcall(tests.run, vim.tbl_extend("force", { scope = how, bufnr = b, lnum = lnum }, extra or {}))
  end
  if not ok then return nil, 0, { err = tostring(why), launches = 0 } end
  vim.wait((extra and extra.wait_ms) or RUN_TIMEOUT_MS, function() return last_done ~= nil end, 20)
  local ms = E.now() - t0
  local ev = { launches = #launches - before, replaced = (dbg.launchers_replaced or 0) - replaced0,
    title = vim.fn.getqflist({ title = 0 }).title or "" }
  if not last_done then ev.err = "no result" end
  vim.wait(300) -- the session tear-down settles before the next run
  return last_done, ms, ev
end
local function fmt(r, ev)
  if not r then return "no result" .. (ev and ev.err and (": " .. ev.err) or "") end
  return ("passed %s, failed %s, skipped %s%s; launches %d; qf '%s'"):format(tostring(r.passed), tostring(r.failed),
    tostring(r.skipped), r.error and (", error: " .. r.error:gsub("\n", " ")) or "", ev.launches, ev.title:sub(1, 70))
end
local function counts(r, p, f, s) return r and r.passed == p and r.failed == f and r.skipped == s and not r.error end
local function title_of(p, f, s) return ("%d passed, %d failed, %d skipped"):format(p, f, s) end
local function real(r, ev, want) return r ~= nil and ev.launches >= 1 and ev.title:find("^Nv4J tests: " .. vim.pesc(want)) ~= nil end

-- ── import ────────────────────────────────────────────────────────────────────────────────────────
local CTRL_FILE = src .. "GreetingController.java"
local t_open = E.now()
local buf = lsp.open(CTRL_FILE)
local client = lsp.wait_ready(buf, 300000)
local import_ms = E.now() - t_open
E.log("gradle_import", client and import_ms or -1, 1)
lsp.report(P .. "attached", client ~= nil, client and ("jdtls ready %.1f s after the open (info: new or warm jdt.ls workspace and Gradle daemon; "
  .. "Maven twin demo is recorded by check 01)"):format(import_ms / 1000) or "jdtls not ready within 300 s (import of the Gradle project failed or is stuck)")
if not client then
  cleanup()
  return lsp.finish()
end
pcall(require, "config.keymaps")

local ok_all, err = pcall(function()
  -- root_dir
  local rt, hasbuild, kind = root_mod.project(CTRL_FILE)
  local projects = {}
  local pr = client:request_sync("workspace/executeCommand", { command = "java.project.getAll" }, 20000, buf)
  for _, p in ipairs(pr and pr.result or {}) do projects[#projects + 1] = tostring(p) end
  local listed = false
  for _, p in ipairs(projects) do if p:find("gradle%-boot") then listed = true end end
  local cdir = client.config.root_dir and vim.uv.fs_realpath(client.config.root_dir) or "?"
  lsp.report(P .. "root_dir", cdir == fixture and vim.uv.fs_realpath(rt) == fixture and hasbuild and kind == "build" and listed,
    ("jdt.ls root_dir %s, nv4j.root.project %s (kind %s, build file %s), java.project.getAll: %s (fixture %s)"):format(cdir,
      tostring(rt), kind, tostring(hasbuild), table.concat(projects, ","):sub(1, 120), fixture))

  if has("markers") then return end -- control: the later cases would only wait for their timeouts

  -- spring_ls: the Spring LS on the Gradle project
  vim.cmd("edit " .. vim.fn.fnameescape(fixture .. "/src/main/resources/application.properties"))
  local pbuf = vim.api.nvim_get_current_buf()
  local function spring_client()
    local c = vim.lsp.get_clients({ bufnr = pbuf, name = "spring-boot" })[1]
    return c and c.initialized and not c:is_stopped() and c or nil
  end
  vim.wait(60000, function() return spring_client() ~= nil end, 50)
  local sc = spring_client()
  if not sc then
    lsp.report(P .. "spring_ls", false, "no initialized spring-boot client on application.properties within 60 s (vim.g.nv4j_spring "
      .. tostring(vim.g.nv4j_spring) .. ")")
  else
    local function syms(q)
      local out = {}
      local r = sc:request_sync("workspace/symbol", { query = q }, 6000, pbuf)
      for _, x in ipairs(r and r.result or {}) do out[#out + 1] = x.name end
      return out
    end
    local function has_sym(list, pat)
      for _, n in ipairs(list) do if n:find(pat) then return true end end
      return false
    end
    local maps, beans, labels = {}, {}, {}
    local t0 = E.now()
    -- the index fills after jdt.ls's classpath event: poll (bounded) instead of one request
    wait_until(90000, function()
      maps, beans = syms("@/"), syms("@+")
      return has_sym(maps, "@/hello") and has_sym(beans, "[Cc]alculator")
    end)
    vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, { "server.po" })
    local r = sc:request_sync("textDocument/completion", { textDocument = { uri = vim.uri_from_bufnr(pbuf) },
      position = { line = 0, character = 9 } }, 10000, pbuf)
    local res = r and r.result or {}
    for _, it in ipairs(res.items or res) do labels[#labels + 1] = it.label end
    vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, vim.fn.readfile(fixture .. "/src/main/resources/application.properties"))
    vim.bo[pbuf].modified = false
    lsp.report(P .. "spring_ls", has_sym(maps, "@/hello") and has_sym(beans, "[Cc]alculator") and vim.tbl_contains(labels, "server.port"),
      ("mapping @/hello %s, bean Calculator %s (%d beans), completion server.po: %d item(s), server.port %s; answered after %.1f s"):format(
        has_sym(maps, "@/hello") and "found" or "MISSING", has_sym(beans, "[Cc]alculator") and "found" or "MISSING", #beans, #labels,
        vim.tbl_contains(labels, "server.port") and "listed" or "MISSING", (E.now() - t0) / 1000))
  end

  -- keys + test runs through the keys
  local tbuf = lsp.open(tdir .. "CalculatorTest.java")
  lsp.wait_ready(tbuf, 60000)
  vim.api.nvim_set_current_buf(tbuf)
  vim.wait(10000, function() return vim.fn.maparg("<leader>tr", "n", false, true).buffer == 1 end, 50)
  do
    local OWN = {}
    for _, k in ipairs(tests.keys or {}) do OWN[k[1]] = k[3] end
    local bad = {}
    for _, lhs in ipairs({ "<leader>tr", "<leader>tt", "<leader>tp" }) do
      local m = vim.fn.maparg(lhs, "n", false, true)
      if m.buffer ~= 1 or m.desc ~= OWN[lhs] then bad[#bad + 1] = lhs .. "=" .. tostring(m.desc) end
    end
    for _, lhs in ipairs({ "<leader>rs", "<leader>rS", "<leader>rd" }) do
      local m = vim.fn.maparg(lhs, "n", false, true)
      if not m.callback then bad[#bad + 1] = lhs .. " unbound" end
    end
    lsp.report(P .. "keys", #bad == 0, #bad == 0 and "tr/tt/tp buffer-local with Nv4J's descs, rs/rS/rd bound" or table.concat(bad, ", "))
  end

  local l = E.line_of(tbuf, "void adds") + 1
  local r1, ms1, ev1 = run("<leader>tr", tbuf, l)
  E.log("gradle_test_nearest_first", r1 and ms1 or -1, 1)
  local r2, ms2, ev2 = run("<leader>tr", tbuf, l)
  E.log("gradle_test_nearest_warm", r2 and ms2 or -1, 1)
  local name_ok = r2 and r2.tests[1] and r2.tests[1].method == "adds"
  lsp.report(P .. "test_nearest", counts(r2, 1, 0, 0) and real(r2, ev2, title_of(1, 0, 0)) and name_ok and ms2 <= WARM_BUDGET_MS,
    ("warm %.0f ms (budget %d), %s, test %s; first run %.0f ms, %s"):format(ms2, WARM_BUDGET_MS, fmt(r2, ev2),
      r2 and r2.tests[1] and tostring(r2.tests[1].method) or "-", ms1, fmt(r1, ev1)))

  local rc, msc, evc = run("<leader>tt", tbuf, l)
  lsp.report(P .. "test_class", counts(rc, 2, 0, 0) and real(rc, evc, title_of(2, 0, 0)),
    ("%.0f ms, %s (want 2/0/0)"):format(msc, fmt(rc, evc)))

  local rp, msp, evp = run("<leader>tp", tbuf, l)
  lsp.report(P .. "test_project", counts(rp, 3, 1, 0) and real(rp, evp, title_of(3, 1, 0)) and evp.launches == 1,
    ("%.0f ms, %s (want 3/1/0, one launch)"):format(msp, fmt(rp, evp)))

  local fbuf = lsp.open(tdir .. "CalculatorFailingTest.java")
  lsp.wait_ready(fbuf, 60000)
  local rf, msf, evf = run("class", fbuf, E.line_of(fbuf, "void passes") + 1)
  local lfail = E.line_of(fbuf, "assertEquals%(7") + 1
  local qf = vim.tbl_filter(function(it) return it.lnum == lfail and (it.text or ""):find("expected") end, vim.fn.getqflist())
  local diag = vim.tbl_filter(function(d) return d.lnum == lfail - 1 and d.source == "nv4j tests" end, vim.diagnostic.get(fbuf))
  lsp.report(P .. "failure_shown", counts(rf, 1, 1, 0) and real(rf, evf, title_of(1, 1, 0)) and #qf >= 1 and #diag >= 1,
    ("%.0f ms, %s; quickfix entry at line %d: %s; diagnostic: %s"):format(msf, fmt(rf, evf), lfail, #qf >= 1 and qf[1].text:sub(1, 50) or "MISSING",
      #diag >= 1 and "yes" or "MISSING"))
  vim.api.nvim_set_current_buf(buf)

  -- run: rs (java -cp), rS (gradlew bootRun), rd (debug)
  local start_err
  local function start_run(lhs)
    local n = #R.sessions
    local m = vim.fn.maparg(lhs, "n", false, true)
    local t0 = E.now()
    vim.api.nvim_set_current_buf(buf)
    local okc, cerr = pcall(m.callback)
    start_err = (not okc) and tostring(cerr):gsub("\n.*", "") or nil -- e.g. Neovim refusing to start 'gradle' (no wrapper)
    if okc then wait_until(60000, function() return #R.sessions > n end) end
    return R.sessions[n + 1], t0
  end
  local function started(s, budget)
    return s and wait_until(budget, function() return text(s.buf):find("Started GradleBootApplication in", 1, true) ~= nil end)
  end
  local function stop_and_check(s)
    local was = #jvms() > 0
    if s then R.stop(s) end
    local gone = wait_until(30000, function() return #jvms() == 0 end)
    return was, gone
  end
  vim.env.SERVER_PORT = "0" -- the app picks a free port (also set in application.properties)

  local n0 = #notes
  local s1, t1 = start_run("<leader>rs")
  local seen1 = started(s1, RS_BUDGET_MS)
  local ms_rs = E.now() - t1
  E.log("gradle_run_cp", seen1 and ms_rs or -1, 1)
  local cmd1 = s1 and s1.cmd and table.concat(s1.cmd, " ") or ""
  local was1, gone1 = stop_and_check(s1)
  lsp.report(P .. "run_cp", seen1 == true and ms_rs <= RS_BUDGET_MS and was1 and gone1 and not cmd1:find("gradlew", 1, true),
    seen1 and ("started %.0f ms after the key (budget %d), port %s, session cmd %s, JVM seen %s, gone after the stop key %s"):format(ms_rs,
      RS_BUDGET_MS, tostring(s1.port), cmd1:sub(1, 60) ~= "" and cmd1:sub(1, 60) or "(jdt.ls launch)", tostring(was1), tostring(gone1))
      or ("no 'Started GradleBootApplication in' within %d ms; session %s; terminal: %s; notes: %s"):format(RS_BUDGET_MS, s1 and "created" or "none",
        text(s1 and s1.buf):gsub("%s+", " "):sub(-300), short_notes(notes_since(n0))))

  n0 = #notes
  local s2, t2 = start_run("<leader>rS")
  local seen2 = started(s2, RS_GRADLE_BUDGET_MS)
  local ms_rS = E.now() - t2
  E.log("gradle_run_bootrun", seen2 and ms_rS or -1, 1)
  local cmd2 = s2 and s2.cmd or {}
  local wrapper = fixture .. "/gradlew"
  local was2, gone2 = stop_and_check(s2)
  lsp.report(P .. "run_bootrun", seen2 == true and cmd2[1] == wrapper and cmd2[2] == "bootRun" and s2.cwd and vim.uv.fs_realpath(s2.cwd) == fixture
      and was2 and gone2 and ms_rS <= RS_GRADLE_BUDGET_MS,
    ("command %s; cwd %s; started %s after %.0f ms (budget %d); JVM seen %s, gone after stop %s; notes: %s"):format(table.concat(cmd2, " "),
      tostring(s2 and s2.cwd), seen2 and "yes" or "NO", ms_rS, RS_GRADLE_BUDGET_MS, tostring(was2), tostring(gone2),
      seen2 and "" or (short_notes(notes_since(n0)) .. " / start error: " .. tostring(start_err) .. " / terminal: " .. text(s2 and s2.buf):gsub("%s+", " "):sub(-250))))

  n0 = #notes
  local nd = #R.sessions
  local md = vim.fn.maparg("<leader>rd", "n", false, true)
  vim.api.nvim_set_current_buf(buf)
  md.callback()
  wait_until(60000, function() return #R.sessions > nd end)
  local sd = R.sessions[nd + 1]
  local up = sd and wait_until(RS_BUDGET_MS * 3, function() return sd.state == "running" and #jvms() > 0 end)
  local has_dap = dap.session() ~= nil
  if dap.session() then dap.terminate() end
  local dgone = wait_until(30000, function() return #jvms() == 0 end)
  lsp.report(P .. "debug_started", up == true and has_dap and dgone,
    ("session %s, nvim-dap session %s, JVM seen %s, gone after terminate %s; notes: %s"):format(tostring(sd and sd.state), tostring(has_dap),
      tostring(up), tostring(dgone), up and "" or short_notes(notes_since(n0))))
  vim.env.SERVER_PORT = nil
end)
if not ok_all then lsp.report(P .. "error", false, tostring(err)) end
pcall(function() dap.terminate() end)
for _, s in ipairs(R.running()) do pcall(R.stop, s) end
if has("markers") then -- control: the T2 cases below do not depend on the root rule, skip their waits
  cleanup()
  return lsp.finish()
end

-- ── T2 (a), unit: the junit-platform-launcher of the engine's version in a Gradle cache layout ───────────────
do
  local base = TMP .. "/unit"
  local function touch(path, lines)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(lines or { "x" }, path)
    return path
  end
  local function bundled(dir)
    touch(dir .. "/META-INF/MANIFEST.MF", { "Manifest-Version: 1.0", "Bundle-SymbolicName: junit-platform-launcher;singleton:=true" })
    return dir
  end
  local gcache = base .. "/gradle/modules-2/files-2.1/org.junit.platform"
  local gengine = touch(gcache .. "/junit-platform-engine/1.12.2/aaaa1111/junit-platform-engine-1.12.2.jar")
  local glauncher = touch(gcache .. "/junit-platform-launcher/1.12.2/bbbb2222/junit-platform-launcher-1.12.2.jar")
  touch(gcache .. "/junit-platform-launcher/1.12.2/cccc3333/junit-platform-launcher-1.12.2-sources.jar")
  local mrepo = base .. "/m2/org/junit/platform"
  local mengine = touch(mrepo .. "/junit-platform-engine/1.12.2/junit-platform-engine-1.12.2.jar")
  local mlauncher = touch(mrepo .. "/junit-platform-launcher/1.12.2/junit-platform-launcher-1.12.2.jar")
  local lone = touch(base .. "/gradle2/modules-2/files-2.1/org.junit.platform/junit-platform-engine/1.12.2/dddd4444/junit-platform-engine-1.12.2.jar")
  local function cfg(engine, b) return { mainClass = RUNNER, classPaths = { "/p/classes", engine, bundled(b) } } end
  local n0 = #notes
  local before = dbg.launchers_replaced or 0
  local g = dbg.junit_launcher(cfg(gengine, base .. "/b1"))
  local m = dbg.junit_launcher(cfg(mengine, base .. "/b2"))
  local g_ok = g.classPaths[3] == glauncher
  local m_ok = m.classPaths[3] == mlauncher
  local replaced = (dbg.launchers_replaced or 0) - before
  local notes_n = #notes
  local w = dbg.junit_launcher(cfg(lone, base .. "/b3")) -- no launcher in this cache: unchanged + one WARN
  local wmsg
  for i = notes_n + 1, #notes do if notes[i].level == vim.log.levels.WARN and notes[i].msg:find("junit%-platform%-launcher") then wmsg = notes[i].msg end end
  local unchanged = w.classPaths[3] == base .. "/b3"
  lsp.report(P .. "launcher_gradle_layout", g_ok and m_ok and replaced == 2 and unchanged and wmsg ~= nil and wmsg:find("testRuntimeOnly", 1, true) ~= nil,
    ("Gradle layout swapped to %s: %s; Maven layout swapped: %s; replaced %d (want 2); launcher absent from the cache: classpath %s, WARN %s"):format(
      vim.fs.basename(glauncher), tostring(g_ok), tostring(m_ok), replaced, unchanged and "unchanged" or "CHANGED",
      wmsg and ("'" .. wmsg:sub(1, 70) .. "...'") or "MISSING"))
  vim.fn.delete(base, "rf")
end

-- ── T2 (a), live: a plain Gradle project WITHOUT the launcher dependency (the standard Gradle 8 setup) ──────────
-- Not the Boot fixture: the Boot fixture without the launcher line still got the launcher on the jdt.ls test classpath (measured, the Boot plugin or its BOM supplies it; not investigated), so only
-- a plain `testImplementation 'org.junit.jupiter:junit-jupiter:5.12.2'` + useJUnitPlatform() reproduces G1. The wrapper
-- and the versions are the fixture's (cached by run.sh's resolve step), nothing is downloaded.
local ok_v, err_v = pcall(function()
  local d = TMP .. "/nolauncher"
  vim.fn.mkdir(d .. "/src/test/java/x", "p")
  local cp = vim.fn.system({ "cp", "-R", fixture .. "/gradle", fixture .. "/gradlew", d .. "/" })
  vim.fn.writefile({ "rootProject.name = 'nolauncher'" }, d .. "/settings.gradle")
  vim.fn.writefile({ "plugins { id 'java' }", "repositories { mavenCentral() }",
    "dependencies { testImplementation 'org.junit.jupiter:junit-jupiter:5.12.2' }", "tasks.named('test') { useJUnitPlatform() }" }, d .. "/build.gradle")
  vim.fn.writefile({ "package x;", "", "import static org.junit.jupiter.api.Assertions.assertEquals;", "", "import org.junit.jupiter.api.Test;", "",
    "class CalcTest {", "    @Test", "    void adds() {", "        assertEquals(4, 2 + 2);", "    }", "", "    @Test", "    void multiplies() {",
    "        assertEquals(6, 2 * 3);", "    }", "}" }, d .. "/src/test/java/x/CalcTest.java")
  local vbuf = lsp.open(d .. "/src/test/java/x/CalcTest.java")
  local vc = lsp.wait_ready(vbuf, 300000)
  if not vc then
    lsp.report(P .. "launcher_missing", false, "jdt.ls did not import " .. d .. " " .. cp)
    return
  end
  local l = E.line_of(vbuf, "void adds") + 1
  local rn, msn, evn = run("nearest", vbuf, l)
  local rc, msc, evc = run("class", vbuf, l)
  local rp, msp, evp = run("project", vbuf, nil)
  lsp.report(P .. "launcher_missing", counts(rn, 1, 0, 0) and real(rn, evn, title_of(1, 0, 0)) and counts(rc, 2, 0, 0) and real(rc, evc, title_of(2, 0, 0))
      and counts(rp, 2, 0, 0) and real(rp, evp, title_of(2, 0, 0)) and evn.replaced >= 1,
    ("nearest %.0f ms, %s; class %.0f ms, %s; project %.0f ms, %s; launcher swapped in %d of the nearest run's launch(es); want 1/0/0, 2/0/0, 2/0/0"):format(
      msn, fmt(rn, evn), msc, fmt(rc, evc), msp, fmt(rp, evp), evn.replaced))
  vim.lsp.stop_client(vc.id, true)
end)
if not ok_v then lsp.report(P .. "launcher_missing", false, tostring(err_v)) end

-- ── T2 (b): a test JVM that dies is never a green 0/0/0 (stub twins, no Gradle) ────────────────────────────
-- dap.run is replaced by a fake JVM: it connects to the port the product put in the runner's `-port N` argument and
-- plays one scenario; the JVM's console is fed to nvim-dap's event_output listeners (what java-debug does).
local ok_s, err_s = pcall(function()
  local sbuf = lsp.open(tdir .. "CalculatorTest.java")
  lsp.wait_ready(sbuf, 60000)
  local l = E.line_of(sbuf, "void adds") + 1
  local orig_dap_run = dap.run
  local CAUSE = "Exception in thread \"main\" java.lang.NoClassDefFoundError: org/junit/platform/engine/OutputDirectoryCreator"
  local function scenario(kind)
    dap.run = function(config, opts)
      local port = tonumber((config.args or ""):match("%-port (%d+)"))
      local function console(category, out)
        for _, ln in pairs(dap.listeners.after.event_output) do pcall(ln, { config = config }, { category = category, output = out }) end
      end
      vim.defer_fn(function()
        console("stdout", "WARNING: fake test JVM starting\n")
        console("stderr", CAUSE .. "\n")
        console("stderr", "\tat org.junit.platform.launcher.core.LauncherConfig.<init>(LauncherConfig.java:1)\n")
        if kind == "never" or not port then return end
        local c = vim.uv.new_tcp()
        c:connect("127.0.0.1", port, function(cerr)
          if cerr then return end
          if kind == "partial" then
            c:write("%TESTC  1 v2\n%TSTTREE1,t1(gradleboot.CalculatorTest),true,1,false,-1,t1(),,\n%TSTTREE2,adds(gradleboot.CalculatorTest),false,1,false,1,adds(),,\n"
              .. "%TESTS  2,adds(gradleboot.CalculatorTest)\n")
          elseif kind == "empty_done" then
            c:write("%TESTC  0 v2\n%RUNTIME3\n")
          end
          vim.defer_fn(function() if not c:is_closing() then c:close() end end, 100)
        end)
      end, 100)
      -- the debug session ends shortly after: nvim-dap's `after` callback
      vim.defer_fn(function() if opts and opts.after then opts.after() end end, 600)
      return true
    end
  end
  local results = {}
  for _, kind in ipairs({ "closed", "partial", "never", "empty_done" }) do
    scenario(kind)
    local n0 = #notes
    local r, ms, ev = run("nearest", sbuf, l, { wait_ms = 20000 })
    local sh = notes_since(n0)
    local err_note
    for _, n in ipairs(sh) do if n.level == vim.log.levels.ERROR then err_note = n.msg end end
    results[kind] = { r = r, ms = ms, ev = ev, err_note = err_note, busy = tests._busy() }
  end
  dap.run = orig_dap_run
  local function good(x)
    return x.r ~= nil and x.r.error ~= nil and x.r.error:find("NoClassDefFoundError", 1, true) ~= nil and x.r.passed == 0 and x.err_note ~= nil
      and x.err_note:find("NoClassDefFoundError", 1, true) ~= nil and x.busy == nil
  end
  local function show(k)
    local x = results[k]
    return ("%s: %s (%.0f ms, ERROR notice %s, lock %s)"):format(k, x.r and (x.r.error and ("error '" .. x.r.error:gsub("\n", " "):sub(1, 90) .. "'")
      or title_of(x.r.passed, x.r.failed, x.r.skipped) .. ", no error") or "no result", x.ms, x.err_note and "yes" or "NO", x.busy == nil and "released" or "HELD")
  end
  lsp.report(P .. "crash_closed", good(results.closed), show("closed") .. " (want an error naming the cause, never 0/0/0 green)")
  lsp.report(P .. "crash_partial", good(results.partial), show("partial") .. " (tree and a started test, no %RUNTIME)")
  lsp.report(P .. "crash_never", good(results.never), show("never") .. " (the JVM never connected)")
  local x = results.empty_done
  lsp.report(P .. "empty_done_ok", x.r ~= nil and x.r.error == nil and x.r.passed == 0 and x.r.failed == 0 and x.busy == nil,
    ("a stream that ends complete (%%RUNTIME) with 0 tests: %s (not an error)"):format(x.r and (x.r.error and ("error '" .. x.r.error .. "'") or "no error") or "no result"))
end)
if not ok_s then lsp.report(P .. "crash_closed", false, tostring(err_s)) end

local d = F.diff(snap)
if #d.added + #d.changed + #d.missing > 0 then F.restore(snap, client) end
d = F.diff(snap)
lsp.report(P .. "fixture_restored", #d.added + #d.changed + #d.missing == 0, F.fmt(d))
cleanup()
lsp.finish()
