-- D25 `.nv4j` project marker. Run via tests/run.sh. Spec: specs/001-architecture.md "Problem: one jdt.ls
-- per loose-file directory". Code: nvim/lua/nv4j/root.lua (project, warn_loose), nvim/lua/plugins/java.lua.
-- Everything runs in a fresh temp dir /tmp/nv4j/d25-<pid> (never the fixture), removed at the end with
-- the jdtls-data/jdtls-config dirs of its roots; clients are stopped, then killed by pid if still alive.
--  order_*        : unit, root.lua project(): the nearest `.nv4j` beats a build marker below it, a nearer
--                   `.nv4j` beats a farther one, `.nv4j` beats the loose-file fallback; a `.nv4j` dir with a
--                   pom.xml of its own keeps has_marker (Spring Boot detected), without one has_marker is
--                   false (no Spring Boot, loose-file scaffolding); no `.nv4j`: build marker, git-root and
--                   loose rules unchanged; usage counts (nv4j/usage.lua) treat a `.nv4j` root as a project.
--  warn_unit      : deterministic twin of `warn` (stub clients): warns for a loose root while another loose
--                   client runs (text names both roots, the common parent and .nv4j, title Nv4J), once per
--                   root; never for a root that already has a client, a `.nv4j` or build root, or the
--                   first loose client.
--  warn_broad     : the warning names no folder when the common parent is $HOME, `/` or a short path
--                   (fewer than 3 segments): "the project folder that holds both" ($HOME stubbed under TMP).
--  project_home_warn : a `.nv4j` at $HOME is honoured as the root but warned once (title Nv4J).
--  usage_home     : a `.nv4j` at $HOME or above never enables the rg usage scan; a normal one does.
--  single_client  : files in 3 sibling dirs under one `.nv4j` -> exactly one jdt.ls client, root = the
--                   `.nv4j` dir, cross-directory reference resolves (no error in alpha/A.java using
--                   beta/B.java), the planted error in gamma/C.java is reported.
--  one_workspace  : one -data dir among the jdtls-data dirs of the 4 candidate roots (project + 3 subdirs).
--  rss            : RSS of that jdt.ls process, REPORT-ONLY: PASS with the measured MB in the detail; FAIL only when the pid
--                   cannot be found or its RSS cannot be read. The 2 GB figure is a proposal (specs/001 D25), not a budget
--                   (user ruling: stays "proposed", not applied).
--  warn           : without `.nv4j`, two sibling loose dirs -> two clients and exactly one WARN (title
--                   Nv4J, both roots, common parent, ".nv4j"); opening more files in both dirs adds none.
local lsp = require("lsp")
local P = "64_project_marker."
local RSS_PROPOSED_KB = 2048 * 1024 -- 2 GB, proposed from 1257 to 1294 MB measured for this project (specs/001 D25): printed, never enforced

local TMP = "/tmp/nv4j/d25-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
TMP = vim.uv.fs_realpath(TMP) -- /tmp is /private/tmp on macOS; roots come back resolved
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(text or "")
  f:close()
end

local root = require("nv4j.root")
local spring = require("nv4j.spring")

-- ── order (unit) ───────────────────────────────────────────────────────────────────────────────
local U = TMP .. "/unit"
write(U .. "/n1/.nv4j")
write(U .. "/n1/sub/pom.xml", "<project/>")
write(U .. "/n1/inner/.nv4j")
write(U .. "/n2/.nv4j")
write(U .. "/n2/pom.xml", "<project><parent><groupId>org.springframework.boot</groupId></parent></project>")
write(U .. "/b/pom.xml", "<project/>")
write(U .. "/g/pom.xml", "<project/>")
write(U .. "/g/m/pom.xml", "<project/>")
vim.fn.mkdir(U .. "/g/.git", "p")
vim.fn.mkdir(U .. "/l", "p")
local function order(name, file, want_root, want_marker, want_kind)
  local r, m, k = root.project(U .. "/" .. file)
  local want = U .. (want_root ~= "" and ("/" .. want_root) or "")
  lsp.report(P .. "order_" .. name, r == want and m == want_marker and k == want_kind,
    ("%s -> %s, %s, %s (want %s, %s, %s)"):format(file, r, tostring(m), tostring(k), want, tostring(want_marker), want_kind))
end
order("beats_build", "n1/sub/src/main/java/X.java", "n1", false, "nv4j")
order("nearest", "n1/inner/d/X.java", "n1/inner", false, "nv4j")
order("beats_loose", "n1/a/X.java", "n1", false, "nv4j")
order("with_pom", "n2/src/X.java", "n2", true, "nv4j")
order("build_unchanged", "b/src/X.java", "b", true, "build")
order("git_unchanged", "g/m/src/X.java", "g", true, "build")
order("loose_unchanged", "l/X.java", "l", false, "loose")
local b_n2, b_n1 = spring.boot_root(U .. "/n2/src/X.java"), spring.boot_root(U .. "/n1/a/X.java")
lsp.report(P .. "order_spring", b_n2 == U .. "/n2" and b_n1 == nil,
  ("boot_root: .nv4j+Boot pom -> %s (want %s); .nv4j without build file -> %s (want nil)"):format(tostring(b_n2), U .. "/n2", tostring(b_n1)))
local usage = require("nv4j.usage")
lsp.report(P .. "order_usage", usage.is_project(U .. "/n1") and not usage.is_project(U .. "/l"),
  ("usage counts: .nv4j root counted %s (want true), loose dir counted %s (want false)")
    :format(tostring(usage.is_project(U .. "/n1")), tostring(usage.is_project(U .. "/l"))))

-- ── warn_unit (deterministic twin of warn) ─────────────────────────────────────────────────────
local notes = {}
-- Notifications are recorded, not forwarded: LazyVim's start-up notify queue replays into whatever
-- vim.notify is at that moment, so forwarding to the saved one would loop.
local orig_notify = vim.notify
local broad_notes = {}
vim.notify = function(msg, level, o)
  if o and o.title == "Nv4J" and level == vim.log.levels.WARN then
    msg = tostring(msg)
    if msg:find("^Starting a second jdt.ls") then notes[#notes + 1] = msg end
    if msg:find("^A %.nv4j file in ") then broad_notes[#broad_notes + 1] = msg end
  end
end
local function stub(r) return { config = { root_dir = r } } end
do
  local W = TMP .. "/wunit"
  vim.fn.mkdir(W .. "/p/one", "p")
  vim.fn.mkdir(W .. "/p/two", "p")
  vim.fn.mkdir(W .. "/p/three", "p")
  local one, two, three = W .. "/p/one", W .. "/p/two", W .. "/p/three"
  local before = #notes
  local first = root.warn_loose(one, {}) -- first loose client: no warning
  local same = root.warn_loose(one, { stub(one) }) -- attaching to its own client
  local others = root.warn_loose(U .. "/n1", { stub(one) }) == nil and root.warn_loose(U .. "/b", { stub(one) }) == nil
  local m = root.warn_loose(two, { stub(one), stub(U .. "/b") })
  local again = root.warn_loose(two, { stub(one) })
  local nonloose_other = root.warn_loose(three, { stub(U .. "/n1"), stub(U .. "/b") })
  local ok = first == nil and same == nil and others and m ~= nil and again == nil and nonloose_other == nil
    and #notes - before == 1 and m:find(two, 1, true) and m:find(one, 1, true)
    and m:find("(" .. W .. "/p)", 1, true) and m:find(".nv4j", 1, true)
  lsp.report(P .. "warn_unit", ok,
    ("first %s, same %s, nv4j/build roots silent %s, second loose -> %s, again %s, non-loose others %s, notifications %d (want 1)")
      :format(tostring(first), tostring(same), tostring(others), m and ("%q"):format(m) or "nil", tostring(again),
        tostring(nonloose_other), #notes - before))
end

-- ── broad dirs: $HOME, `/`, short paths (stubbed $HOME under TMP) ─────────────────────────────
do
  local H = TMP .. "/home/me"
  vim.fn.mkdir(H .. "/a", "p")
  vim.fn.mkdir(H .. "/b", "p")
  local real_home = root.home
  root.home = function() return H end
  local ok_b, e_b = pcall(function()
    local m_home = root.warn_loose(H .. "/b", { stub(H .. "/a") }) or ""
    local m_root = root.warn_loose("/nv4j-d25-x/b", { stub("/nv4j-d25-y/a") }) or ""
    local m_short = root.warn_loose("/opt/nv4j-d25-b", { stub("/opt/nv4j-d25-a") }) or ""
    local generic = "create an empty .nv4j file in the project folder that holds both"
    local function ok_msg(m, bad) return m:find(generic, 1, true) ~= nil and not m:find("(" .. bad .. ")", 1, true) end
    lsp.report(P .. "warn_broad", ok_msg(m_home, H) and ok_msg(m_root, "/") and ok_msg(m_short, "/opt"),
      ("common parent $HOME -> %q; / -> %q; /opt -> %q (want %q, no dir named)"):format(m_home, m_root, m_short, generic))

    -- a .nv4j at $HOME and one above it: honoured as root, warned once each, no rg usage scan
    write(H .. "/.nv4j")
    write(TMP .. "/home/.nv4j")
    local usage = require("nv4j.usage")
    local r1, m1, k1 = root.project(H .. "/a/X.java")
    root.project(H .. "/b/Y.java")
    vim.wait(1000, function() return #broad_notes >= 1 end, 20)
    vim.wait(200)
    local n_home = #broad_notes
    local first_note = broad_notes[1] or ""
    lsp.report(P .. "project_home_warn", r1 == H and m1 == false and k1 == "nv4j" and n_home == 1 and first_note:find(H, 1, true) ~= nil,
      ("project under a $HOME .nv4j -> %s, %s, %s (want %s, false, nv4j); warnings %d after 2 lookups (want 1): %q")
        :format(r1, tostring(m1), tostring(k1), H, n_home, first_note))
    local u_home, u_above, u_n1 = usage.is_project(H), usage.is_project(TMP .. "/home"), usage.is_project(U .. "/n1")
    lsp.report(P .. "usage_home", not u_home and not u_above and u_n1,
      ("usage scan with .nv4j at $HOME %s, above $HOME %s (want false, false); at a project dir %s (want true)")
        :format(tostring(u_home), tostring(u_above), tostring(u_n1)))
  end)
  root.home = real_home
  if not ok_b then lsp.report(P .. "warn_broad", false, "error: " .. tostring(e_b)) end
  vim.fn.delete(TMP .. "/home", "rf")
end

-- ── helpers for the integration cases ──────────────────────────────────────────────────────────
local function data_dir(c)
  local cmd = c.config.cmd or {}
  for i, a in ipairs(cmd) do
    if a == "-data" then return cmd[i + 1] end
  end
end
local function project_name(r) return vim.fs.basename(r) .. "-" .. vim.fn.sha256(r):sub(1, 8) end
local paths = require("nv4j.paths")
local function pid_of(c)
  local d = data_dir(c)
  if not d then return nil end
  -- anchored to this nvim's children and this client's own -data dir
  local out = vim.fn.system({ "pgrep", "-P", tostring(vim.fn.getpid()), "-f", "-data " .. d .. "$" })
  return out:match("^(%d+)")
end
local function rss_kb(pid) return pid and tonumber(vim.trim(vim.fn.system({ "ps", "-o", "rss=", "-p", pid }))) end
local function stop_all()
  local clients = vim.lsp.get_clients({ name = "jdtls" })
  local pids = {}
  for _, c in ipairs(clients) do pids[#pids + 1] = pid_of(c) end
  for _, c in ipairs(clients) do c:stop() end
  vim.wait(15000, function() return #vim.lsp.get_clients({ name = "jdtls" }) == 0 end, 200)
  for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do c:stop(true) end
  vim.wait(5000, function()
    for _, p in ipairs(pids) do
      if vim.fn.system({ "ps", "-o", "pid=", "-p", p }):match("%d") then return false end
    end
    return true
  end, 200)
  for _, p in ipairs(pids) do
    if vim.fn.system({ "ps", "-o", "pid=", "-p", p }):match("%d") then vim.fn.system({ "kill", "-9", p }) end
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):sub(1, #TMP) == TMP then pcall(vim.api.nvim_buf_delete, b, { force = true }) end
  end
end
local function errors(buf)
  return vim.tbl_filter(function(d) return d.severity == vim.diagnostic.severity.ERROR end, vim.diagnostic.get(buf))
end
local roots_made = {}
local function open_ready(file)
  local buf = lsp.open(file)
  local c = lsp.wait_ready(buf, 180000)
  if c then roots_made[c.config.root_dir] = true end
  return buf, c
end
-- A file's errors settle after its own publish; one more pass for the cross-directory reference.
local function settle(buf, want_errors, ms)
  vim.wait(ms, function() return #errors(buf) == want_errors end, 200)
  return errors(buf)
end
local log = vim.env.NV4J_LOG or "(no NV4J_LOG)"

-- ── single_client, one_workspace, rss ──────────────────────────────────────────────────────────
local PR = TMP .. "/proj"
write(PR .. "/.nv4j")
write(PR .. "/alpha/A.java", "public class A {\n  int a() { return new B().b(); }\n}\n")
write(PR .. "/beta/B.java", "public class B {\n  int b() { return 1; }\n}\n")
write(PR .. "/gamma/C.java", "public class C {\n  int c() { String s = 1; return 0; }\n}\n")
local ok_all, err = pcall(function()
  local bufs, ready, not_ready = {}, 0, {}
  for _, f in ipairs({ "alpha/A.java", "beta/B.java", "gamma/C.java" }) do
    local b, c = open_ready(PR .. "/" .. f)
    bufs[#bufs + 1] = b
    if c then ready = ready + 1 else not_ready[#not_ready + 1] = f end
  end
  local clients = vim.lsp.get_clients({ name = "jdtls" })
  local a_err, c_err = settle(bufs[1], 0, 10000), settle(bufs[3], 1, 10000)
  local rs = vim.tbl_map(function(c) return c.config.root_dir end, clients)
  lsp.report(P .. "single_client",
    ready == 3 and #clients == 1 and clients[1].config.root_dir == PR and #a_err == 0
      and #c_err == 1 and c_err[1].message:find("cannot convert from int to String", 1, true) ~= nil,
    ("%d of 3 files ready%s, %d jdt.ls client(s) [%s] (want 1 at %s); alpha/A.java errors %d (want 0: B resolves), gamma/C.java errors %d (want 1 planted)%s; log %s")
      :format(ready, #not_ready > 0 and (" (not: " .. table.concat(not_ready, ", ") .. ")") or "", #clients, table.concat(rs, ", "), PR, #a_err, #c_err,
        a_err[1] and (": " .. a_err[1].message) or "", log))

  local cands = { PR, PR .. "/alpha", PR .. "/beta", PR .. "/gamma" }
  local present = {}
  for _, r in ipairs(cands) do
    if vim.uv.fs_stat(paths.jdtls_data .. "/" .. project_name(r)) then present[#present + 1] = project_name(r) end
  end
  local datas = {}
  for _, c in ipairs(clients) do datas[data_dir(c) or "?"] = true end
  local want = paths.jdtls_data .. "/" .. project_name(PR)
  lsp.report(P .. "one_workspace", #present == 1 and present[1] == project_name(PR) and vim.tbl_count(datas) == 1 and datas[want],
    ("jdtls-data dirs of the 4 candidate roots: [%s] (want only %s); client -data: [%s]")
      :format(table.concat(present, ", "), project_name(PR), table.concat(vim.tbl_keys(datas), ", ")))

  local pid = clients[1] and pid_of(clients[1])
  local rss = rss_kb(pid)
  lsp.report(P .. "rss", rss ~= nil,
    rss and ("jdt.ls pid %s RSS %.0f MB for 3 files in 3 dirs (report-only; proposed 2 GB, %s it)"):format(pid, rss / 1024,
      rss <= RSS_PROPOSED_KB and "under" or "OVER")
      or ("jdt.ls process or its RSS not found (pid %s)"):format(tostring(pid)))
end)
if not ok_all then lsp.report(P .. "single_client", false, "error: " .. tostring(err)) end
stop_all()

-- ── warn ───────────────────────────────────────────────────────────────────────────────────────
local LO = TMP .. "/loose"
write(LO .. "/one/One.java", "public class One {}\n")
write(LO .. "/one/OneB.java", "public class OneB {}\n")
write(LO .. "/two/Two.java", "public class Two {}\n")
write(LO .. "/two/TwoB.java", "public class TwoB {}\n")
ok_all, err = pcall(function()
  local before = #notes
  local _, c1 = open_ready(LO .. "/one/One.java")
  local after_first = #notes - before
  local _, c2 = open_ready(LO .. "/two/Two.java")
  local after_second = #notes - before
  open_ready(LO .. "/two/TwoB.java")
  open_ready(LO .. "/one/OneB.java")
  local clients = vim.lsp.get_clients({ name = "jdtls" })
  local m = notes[before + 1] or ""
  local one, two = LO .. "/one", LO .. "/two"
  local text_ok = m:find(two, 1, true) and m:find(one, 1, true) and m:find("(" .. LO .. ")", 1, true)
    and m:find("create an empty .nv4j file", 1, true)
  lsp.report(P .. "warn",
    c1 ~= nil and c2 ~= nil and #clients == 2 and after_first == 0 and after_second == 1 and #notes - before == 1 and text_ok,
    ("%d jdt.ls clients (want 2), warnings after 1st start %d (want 0), after 2nd %d (want 1), after 2 more files %d (want 1); text %q; log %s")
      :format(#clients, after_first, after_second, #notes - before, m, log))
end)
if not ok_all then lsp.report(P .. "warn", false, "error: " .. tostring(err)) end
stop_all()
vim.notify = orig_notify

-- cleanup: temp tree and the jdt.ls dirs of the roots this check made (exact names only)
for r in pairs(roots_made) do
  if r:sub(1, #TMP + 1) == TMP .. "/" then
    vim.fn.delete(paths.jdtls_data .. "/" .. project_name(r), "rf")
    vim.fn.delete(paths.jdtls_config .. "/" .. project_name(r), "rf")
  end
end
vim.fn.delete(TMP, "rf")
lsp.finish()
