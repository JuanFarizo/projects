-- D25 `.nv4j` project marker. Run via tests/run.sh. Spec: specs/001-architecture.md "Problem: one jdt.ls
-- per loose-file directory". Code: nvim/lua/nv4j/root.lua (project, warn_loose), nvim/lua/plugins/java.lua.
-- Everything runs in a fresh temp dir /tmp/nv4j/d25-<pid> (never the fixture), removed at the end with
-- the jdtls-data/jdtls-config dirs of its roots; clients are stopped, then killed by pid if still alive.
--  order_*        : unit, root.lua project(): a nearer `.nv4j` beats a farther one, `.nv4j` beats the
--                   loose-file fallback; a `.nv4j` dir with a pom.xml of its own keeps has_marker (Spring
--                   Boot detected); a `.nv4j` with no pom of its own does not steal a child Maven/Gradle
--                   module (that file keeps its build root); no `.nv4j`: build marker, git-root and
--                   loose rules unchanged; usage counts (nv4j/usage.lua) treat a `.nv4j` root as a project.
--  mm_*           : parent pom + two modules: `.nv4j` next to the parent pom is one Maven root; `.nv4j`
--                   with only child poms leaves each module its own Maven root; a loose file under that
--                   marker still uses the `.nv4j` dir.
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
--  rss            : RSS of that jdt.ls process: PASS with the measured MB in the detail; FAIL only when the pid
--                   cannot be found or its RSS cannot be read. No threshold here: jdt.ls memory has no limit (user ruling
--                   2026-11-02); the 2 GB warning is nv4j/memwatch.lua, covered by memwatch_unit.
--  memwatch_unit  : stub clients and stubbed RSS (no jdt.ls), memwatch.check: below the threshold no warning; at or above
--                   exactly one (title Nv4J, names the root and the MB); a second sample adds none; threshold 0 never
--                   warns; a non-jdtls client is ignored; a restarted client (new id) warns again.
--  cap_unit       : stub clients, loose-root cap (vim.g.nv4j_loose_max): refused only for a loose root with the cap
--                   reached by other running loose clients; same root, .nv4j/build roots, stopped clients, max=0 and
--                   max=2 with 1 running allowed; one "Not starting a second jdt.ls" warning per refused root.
--  warn           : without `.nv4j`, two sibling loose dirs -> one client (the second is refused: no jdt.ls on its
--                   files), exactly one WARN (title Nv4J, both roots, common parent, ".nv4j"); more files add none.
--  memwatch_live  : real jdt.ls, vim.g.nv4j_jdtls_warn_mb = 50 and nv4j_memwatch_ms = 1000 set before it attaches: exactly one
--                   "jdt.ls for <root> uses N MB" WARN within 60 s, none more 5 s later, timer stopped after the client stopped.
--  warn_off       : vim.g.nv4j_loose_max = 0 -> two clients and one "Starting a second jdt.ls" warning (old behaviour).
local lsp = require("lsp")
local P = "64_project_marker."

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
order("child_pom", "n1/sub/src/main/java/X.java", "n1/sub", true, "build")
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

-- multi-module Maven (unit): `.nv4j` next to the parent pom vs `.nv4j` with only child poms
local MM = TMP .. "/mm"
local PARENT_POM = "<project><groupId>x</groupId><artifactId>p</artifactId><packaging>pom</packaging>\n<modules><module>app</module><module>lib</module></modules></project>"
local APP_POM = "<project><parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId></parent></project>"
local LIB_POM = "<project><groupId>x</groupId><artifactId>lib</artifactId></project>"
write(MM .. "/parent/.nv4j")
write(MM .. "/parent/pom.xml", PARENT_POM)
write(MM .. "/parent/app/pom.xml", APP_POM)
write(MM .. "/parent/lib/pom.xml", LIB_POM)
write(MM .. "/parent/app/src/main/java/App.java", "class App {}")
write(MM .. "/parent/lib/src/main/java/Lib.java", "class Lib {}")
write(MM .. "/kids/.nv4j")
write(MM .. "/kids/app/pom.xml", APP_POM)
write(MM .. "/kids/lib/pom.xml", LIB_POM)
write(MM .. "/kids/app/src/main/java/App.java", "class App {}")
write(MM .. "/kids/lib/src/main/java/Lib.java", "class Lib {}")
write(MM .. "/kids/notes/x.java", "class X {}")
local function mm(name, file, want_root, want_marker, want_kind, want_boot)
  local r, m, k = root.project(file)
  local boot = spring.boot_root(file)
  local ok = r == want_root and m == want_marker and k == want_kind and boot == want_boot
  lsp.report(P .. "mm_" .. name, ok,
    ("%s -> %s, %s, %s boot=%s (want %s, %s, %s boot=%s)"):format(file:gsub(TMP, "TMP"),
      tostring(r):gsub(TMP, "TMP"), tostring(m), tostring(k), tostring(boot):gsub(TMP, "TMP"),
      tostring(want_root):gsub(TMP, "TMP"), tostring(want_marker), tostring(want_kind),
      tostring(want_boot):gsub(TMP, "TMP")))
end
mm("parent", MM .. "/parent/app/src/main/java/App.java", MM .. "/parent", true, "nv4j", MM .. "/parent")
mm("parent_lib", MM .. "/parent/lib/src/main/java/Lib.java", MM .. "/parent", true, "nv4j", MM .. "/parent")
mm("child_pom", MM .. "/kids/app/src/main/java/App.java", MM .. "/kids/app", true, "build", MM .. "/kids/app")
mm("child_lib", MM .. "/kids/lib/src/main/java/Lib.java", MM .. "/kids/lib", true, "build", nil)
mm("child_loose", MM .. "/kids/notes/x.java", MM .. "/kids", false, "nv4j", nil)

-- ── warn_unit (deterministic twin of warn) ─────────────────────────────────────────────────────
local notes = {}
-- Notifications are recorded, not forwarded: LazyVim's start-up notify queue replays into whatever
-- vim.notify is at that moment, so forwarding to the saved one would loop.
local orig_notify = vim.notify
local broad_notes = {}
vim.notify = function(msg, level, o)
  if o and o.title == "Nv4J" and level == vim.log.levels.WARN then
    msg = tostring(msg)
    if msg:find("^Starting a second jdt.ls") or msg:find("^Not starting a second jdt.ls") then notes[#notes + 1] = msg end
    if msg:find("^A %.nv4j file in ") then broad_notes[#broad_notes + 1] = msg end
  end
end
local function stub(r) return { config = { root_dir = r } } end
local function root_mod_warn(r, c) return root.warn_loose(r, c) end
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

-- ── cap_unit (loose-root cap, stub clients, no jdt.ls) ─────────────────────────────────────────
do
  local W = TMP .. "/capunit"
  for _, d in ipairs({ "a", "b", "c", "d", "e", "f", "g", "h" }) do vim.fn.mkdir(W .. "/p/" .. d, "p") end
  vim.fn.mkdir(W .. "/n", "p")
  write(W .. "/n/.nv4j")
  vim.fn.mkdir(W .. "/m", "p")
  write(W .. "/m/pom.xml", "<project/>")
  local function d(n) return W .. "/p/" .. n end
  local function stopped(r) return { config = { root_dir = r }, is_stopped = function() return true end } end
  local saved = vim.g.nv4j_loose_max
  local ok_c, e_c = pcall(function()
    vim.g.nv4j_loose_max = nil
    local before = #notes
    local function try(root, clients)
      local m, refused = root_mod_warn(root, clients)
      return m, refused
    end
    local m0, r0 = try(d("a"), {}) -- 0 loose clients
    local m1, r1 = try(d("b"), { stub(d("a")) }) -- 1 loose, other root
    local n_after_refuse = #notes - before
    local m1b, r1b = try(d("b"), { stub(d("a")) }) -- again: refused, not re-warned
    local _, rs = try(d("a"), { stub(d("a")) }) -- same root
    local _, rn = try(W .. "/n", { stub(d("a")) }) -- .nv4j root
    local _, rb = try(W .. "/m", { stub(d("a")) }) -- build root
    local _, rst = try(d("c"), { stopped(d("a")) }) -- stopped client does not count
    local _, rgone = try(d("b"), {}) -- running one is gone: same root as the refused one starts
    local n_mid = #notes - before
    local m_again, r_again = try(d("b"), { stub(d("a")) }) -- the slot was free in between: refused again, warns again
    local n_again = #notes - before
    vim.g.nv4j_loose_max = 0
    local m_off, r_off = try(d("e"), { stub(d("a")) })
    vim.g.nv4j_loose_max = 2
    local _, r2a = try(d("f"), { stub(d("a")) })
    local _, r2b = try(d("g"), { stub(d("a")), stub(d("b")) })
    local ok = m0 == nil and r0 == false
      and r1 == true and type(m1) == "string" and m1:find("^Not starting a second jdt.ls") ~= nil
      and m1:find(d("b"), 1, true) and m1:find(d("a"), 1, true) and m1:find(".nv4j", 1, true) and m1:find("(" .. W .. "/p)", 1, true)
      and n_after_refuse == 1 and m1b == nil and r1b == true and n_mid == 1
      and rs == false and rn == false and rb == false and rst == false and rgone == false
      and r_off == false and type(m_off) == "string" and m_off:find("^Starting a second jdt.ls") ~= nil
      and r2a == false and r2b == true
      and r_again == true and type(m_again) == "string" and n_again == 2
    lsp.report(P .. "cap_unit", ok,
      ("0 running -> refused %s (want false); 1 other -> refused %s, %q (want true, 'Not starting...'), warnings %d (want 1), repeat refused %s no new warning (%d total, want 1); same root %s, .nv4j root %s, build root %s, stopped client %s, none running %s (all want false); max=0 -> refused %s (want false, old 'Starting' warning); max=2: 1 running %s (want false), 2 running %s (want true); refused again after the slot was free: %s, warnings %d (want true, 2)")
        :format(tostring(r0), tostring(r1), tostring(m1), n_after_refuse, tostring(r1b), n_mid, tostring(rs), tostring(rn),
          tostring(rb), tostring(rst), tostring(rgone), tostring(r_off), tostring(r2a), tostring(r2b), tostring(r_again), n_again))
  end)
  vim.g.nv4j_loose_max = saved
  if not ok_c then lsp.report(P .. "cap_unit", false, "error: " .. tostring(e_c)) end
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

-- ── memwatch_unit (stub clients, stubbed RSS, no jdt.ls) ──────────────────────────────────────
do
  local ok_m, e_m = pcall(function()
    local mw = require("nv4j.memwatch")
    local function cl(id, name, r) return { id = id, name = name, config = { root_dir = r } } end
    local sent, rssmb = {}, {}
    local function note(msg, level, o) sent[#sent + 1] = { msg = msg, level = level, title = o and o.title } end
    local rss_of = function(c) return rssmb[c.id] end
    local warned = {}
    local a, sp = cl(1, "jdtls", "/p/a"), cl(9, "spring-boot", "/p/a")
    rssmb[1], rssmb[9] = 2047, 9000
    mw.check({ a, sp }, rss_of, warned, note, 2048)
    local below = #sent
    rssmb[1] = 2048
    mw.check({ a, sp }, rss_of, warned, note, 2048)
    local at = #sent
    local m = sent[1] or {}
    rssmb[1] = 3000
    mw.check({ a, sp }, rss_of, warned, note, 2048)
    local again = #sent
    local w0, n0 = {}, #sent
    mw.check({ a }, rss_of, w0, note, 0)
    local off = #sent - n0
    local b = cl(2, "jdtls", "/p/a") -- restarted: new client
    rssmb[2] = 2500
    mw.check({ b }, rss_of, warned, note, 2048)
    local restarted = #sent
    local ok = below == 0 and at == 1 and again == 1 and off == 0 and restarted == 2 and m.level == vim.log.levels.WARN
      and m.title == "Nv4J" and (m.msg or ""):find("/p/a", 1, true) ~= nil and (m.msg or ""):find("2048", 1, true) ~= nil
      and (m.msg or ""):find(".nv4j", 1, true) ~= nil
    lsp.report(P .. "memwatch_unit", ok,
      ("warnings: below threshold %d (want 0), at it %d (want 1), second sample %d (want 1), threshold 0 added %d (want 0), restarted client %d total (want 2); spring client ignored; text %q")
        :format(below, at, again, off, restarted, m.msg or ""))
  end)
  if not ok_m then lsp.report(P .. "memwatch_unit", false, "error: " .. tostring(e_m)) end
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
    rss and ("jdt.ls pid %s RSS %.0f MB for 3 files in 3 dirs"):format(pid, rss / 1024)
      or ("jdt.ls process or its RSS not found (pid %s)"):format(tostring(pid)))
end)
if not ok_all then lsp.report(P .. "single_client", false, "error: " .. tostring(err)) end
stop_all()

-- ── warn (cap 1: the second loose root is refused), warn_off (cap 0: old behaviour, two clients) ──
local LO = TMP .. "/loose"
write(LO .. "/one/One.java", "public class One {}\n")
write(LO .. "/one/OneB.java", "public class OneB {}\n")
write(LO .. "/two/Two.java", "public class Two {}\n")
write(LO .. "/two/TwoB.java", "public class TwoB {}\n")
local function jdtls_on(buf) return #vim.lsp.get_clients({ name = "jdtls", bufnr = buf }) end
ok_all, err = pcall(function()
  local before = #notes
  local b1, c1 = open_ready(LO .. "/one/One.java")
  local after_first = #notes - before
  local b2 = lsp.open(LO .. "/two/Two.java")
  vim.wait(4000, function() return #notes - before >= 1 end, 100)
  -- Measured: without the cap the second client registers 3 to 4 s after the file opens (load 8), so a refused
  -- start is only believed after waiting for it: up to 15 s (returns at once when a second client shows up).
  vim.wait(15000, function() return #vim.lsp.get_clients({ name = "jdtls" }) >= 2 end, 100)
  local after_second = #notes - before
  local b3 = lsp.open(LO .. "/two/TwoB.java")
  local b4 = lsp.open(LO .. "/one/OneB.java")
  vim.wait(3000)
  local clients = vim.lsp.get_clients({ name = "jdtls" })
  local m = notes[before + 1] or ""
  local one, two = LO .. "/one", LO .. "/two"
  local text_ok = m:find("^Not starting a second jdt.ls") and m:find(two, 1, true) and m:find(one, 1, true)
    and m:find("(" .. LO .. ")", 1, true) and m:find("create an empty .nv4j file", 1, true)
  lsp.report(P .. "warn",
    c1 ~= nil and #clients == 1 and clients[1].config.root_dir == one and after_first == 0 and after_second == 1
      and #notes - before == 1 and jdtls_on(b2) == 0 and jdtls_on(b3) == 0 and jdtls_on(b4) == 1 and text_ok,
    ("%d jdt.ls client(s) (want 1, at %s), jdtls on Two.java %d, TwoB.java %d (want 0), OneB.java %d (want 1); warnings after 1st start %d (want 0), after 2nd %d (want 1), after 2 more files %d (want 1); text %q; log %s")
      :format(#clients, one, jdtls_on(b2), jdtls_on(b3), jdtls_on(b4), after_first, after_second, #notes - before, m, log))
end)
if not ok_all then lsp.report(P .. "warn", false, "error: " .. tostring(err)) end
stop_all()

local LO0 = TMP .. "/loose0"
write(LO0 .. "/one/One.java", "public class One {}\n")
write(LO0 .. "/two/Two.java", "public class Two {}\n")
vim.g.nv4j_loose_max = 0
ok_all, err = pcall(function()
  local before = #notes
  local _, c1 = open_ready(LO0 .. "/one/One.java")
  local _, c2 = open_ready(LO0 .. "/two/Two.java")
  local clients = vim.lsp.get_clients({ name = "jdtls" })
  local m = notes[before + 1] or ""
  lsp.report(P .. "warn_off",
    c1 ~= nil and c2 ~= nil and #clients == 2 and #notes - before == 1 and m:find("^Starting a second jdt.ls") ~= nil,
    ("vim.g.nv4j_loose_max = 0: %d jdt.ls clients (want 2), warnings %d (want 1, 'Starting a second...'): %q; log %s")
      :format(#clients, #notes - before, m, log))
end)
if not ok_all then lsp.report(P .. "warn_off", false, "error: " .. tostring(err)) end
vim.g.nv4j_loose_max = nil
stop_all()
vim.notify = orig_notify

-- ── memwatch_live: the real timer path (needs a real jdt.ls) ───────────────────────────────────
-- Threshold 50 MB and a 1 s period are set before the jdt.ls attaches (the timer is restarted first: an earlier case
-- may have started it with the defaults). Exactly one WARN "jdt.ls for <root> uses N MB", still one 5 s later,
-- and the timer is gone once the client has stopped (the next tick sees no jdt.ls).
local MW = TMP .. "/mw"
write(MW .. "/.nv4j")
write(MW .. "/M.java", "public class M {}\n")
ok_all, err = pcall(function()
  local mw = require("nv4j.memwatch")
  mw.stop()
  local warns = {}
  local nf = vim.notify
  vim.notify = function(msg, level, o)
    if type(msg) == "string" and msg:find("^jdt.ls for ") then warns[#warns + 1] = msg end
    return nf(msg, level, o)
  end
  vim.g.nv4j_jdtls_warn_mb, vim.g.nv4j_memwatch_ms = 50, 1000
  local ok_in, e_in = pcall(function()
    local t0 = vim.uv.now()
    local _, c = open_ready(MW .. "/M.java")
    if not c then return lsp.report(P .. "memwatch_live", false, "jdt.ls not ready (prerequisite)") end
    vim.wait(60000, function() return #warns >= 1 end, 100)
    local first_ms = vim.uv.now() - t0
    local n1 = #warns
    vim.wait(5000, function() return false end, 100)
    local n2 = #warns
    c:stop()
    vim.wait(15000, function() return c:is_stopped() end, 100)
    stop_all()
    vim.wait(4000, function() return false end, 100) -- >= 3 ticks of 1 s with no jdt.ls
    local m1 = warns[1] or ""
    local mb = tonumber(m1:match("uses (%d+) MB"))
    local timer_gone = not mw._timer_active()
    lsp.report(P .. "memwatch_live", n1 == 1 and n2 == 1 and m1:find("jdt.ls for " .. MW, 1, true) == 1 and mb ~= nil and mb >= 50 and timer_gone,
      ("threshold 50 MB, period 1 s: %d warning after %.0f ms from opening the file (want 1), %d after 5 s more (want 1): %q; timer stopped after the client stopped: %s")
        :format(n1, first_ms, n2, m1:sub(1, 80), tostring(timer_gone)))
  end)
  vim.notify = nf
  vim.g.nv4j_jdtls_warn_mb, vim.g.nv4j_memwatch_ms = nil, nil
  mw.stop()
  if not ok_in then error(e_in) end
end)
if not ok_all then lsp.report(P .. "memwatch_live", false, "error: " .. tostring(err)) end
stop_all()

-- cleanup: temp tree and the jdt.ls dirs of the roots this check made (exact names only)
for r in pairs(roots_made) do
  if r:sub(1, #TMP + 1) == TMP .. "/" then
    vim.fn.delete(paths.jdtls_data .. "/" .. project_name(r), "rf")
    vim.fn.delete(paths.jdtls_config .. "/" .. project_name(r), "rf")
  end
end
vim.fn.delete(TMP, "rf")
lsp.finish()
