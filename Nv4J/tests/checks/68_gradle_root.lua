-- P4 Gradle T3: project root rule (G7 nearest build file, G2/D29 nearest settings.gradle(.kts) above a sub-project).
-- Run via tests/run.sh (gated like 67: needs the Gradle fixture's wrapper for the live case). Spec: specs/006-p4-gradle.md.
-- Unit cases on temp trees under /tmp/nv4j/gradle-root-<pid> (removed at the end); root.project is pure, no jdt.ls.
--  prio_pom_above / prio_gradle_above / prio_pom_below / prio_mixed_depth (G7): the NEAREST build file wins whatever its
--                      kind: pom.xml two levels above a build.gradle.kts, build.gradle above a build.gradle.kts, build.gradle above a
--                      pom.xml, build.xml above a pom (equal priority, not list order).
--  settings_two        (G2 twin of one_jdtls): settings.gradle.kts above app (kts) and lib (groovy): both files -> the SAME root (the
--                      settings dir), kind "build", has_marker true; a sub-project two levels down too.
--  settings_nearest    a build-logic dir with its own settings stays its own root; app next to it goes to the outer settings.
--  settings_own        a dir with settings AND build is itself; a standalone Gradle project (no settings above) is unchanged.
--  maven_unchanged     pom.xml sub-project under a settings.gradle dir stays its own root (Gradle rule never applies to Maven);
--                      multi-module Maven with git root (64_project_marker's g/m) still the git root.
--  bound_git / bound_nv4j / bound_home : the settings search never goes above the git root, above a `.nv4j` dir (override;
--                      a `.nv4j` WITH settings beside it is kind nv4j), or to $HOME and above (stubbed under the tree).
--  boot_under_settings roots.is_boot(settings dir) finds the Boot sub-project (boot_dirs goes 2 levels down).
--  loose_unchanged / cap_kinds : a file with no marker is still "loose"; warn_loose (cap) does not count a client at a Gradle
--                      settings root as a loose root (stub clients: the loose file next to it is not refused, nor warned), while
--                      a client at a real loose root still blocks (control inside the case).
--  one_jdtls (live)    throwaway multi-project build (settings.gradle + app + lib, app depends on project(':lib')) under
--                      /tmp/nv4j/gradle-root-<pid>/live: opening a file of app, then one of lib -> exactly ONE jdtls client,
--                      root_dir the settings dir, java.project.getAll lists both projects, no error in app's use of lib.
--                      NV4J_68_LIVE=0 skips it (used only for unit-control runs).
-- Controls (patch nvim/lua/nv4j/root.lua, run, restore, cmp against a backup): see specs/006 T3 and the report.
local lsp = require("lsp")
local P = "68_gradle_root."
local log = vim.env.NV4J_LOG or "(no NV4J_LOG)"

local TMP = "/tmp/nv4j/gradle-root-" .. vim.fn.getpid()
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

local root = require("nv4j.root")

local function case(name, file, want_root, want_kind)
  local r, m, k = root.project(TMP .. "/" .. file)
  local want = want_root == "" and TMP or (TMP .. "/" .. want_root)
  lsp.report(P .. name, r == want and m == (want_kind ~= "loose") and k == want_kind,
    ("%s -> %s, %s, %s (want %s, %s, %s); log %s"):format(file, short(r), tostring(m), tostring(k), short(want),
      tostring(want_kind ~= "loose"), want_kind, log))
end

-- ── G7: nearest build file ────────────────────────────────────────────────────────────────────
write(TMP .. "/p1/pom.xml", "<project/>")
write(TMP .. "/p1/mid/sub/build.gradle.kts", "")
write(TMP .. "/p2/build.gradle", "")
write(TMP .. "/p2/k/build.gradle.kts", "")
write(TMP .. "/p3/build.gradle", "")
write(TMP .. "/p3/m/pom.xml", "<project/>")
write(TMP .. "/p4/pom.xml", "<project/>")
write(TMP .. "/p4/a/b/build.xml", "<project/>")
case("prio_pom_above", "p1/mid/sub/src/main/java/X.java", "p1/mid/sub", "build")
case("prio_gradle_above", "p2/k/src/X.java", "p2/k", "build")
case("prio_pom_below", "p3/m/src/X.java", "p3/m", "build")
case("prio_mixed_depth", "p4/a/b/src/X.java", "p4/a/b", "build")

-- ── G2 / D29: nearest settings.gradle(.kts) above a sub-project ───────────────────────────────
local BOOT_KTS = 'plugins { id("org.springframework.boot") version "3.5.0" }\n'
write(TMP .. "/g1/settings.gradle.kts", 'include("app", "lib", "deep:x")\n')
write(TMP .. "/g1/build.gradle.kts", "")
write(TMP .. "/g1/app/build.gradle.kts", BOOT_KTS)
write(TMP .. "/g1/lib/build.gradle", "plugins { id 'java' }\n")
write(TMP .. "/g1/deep/x/build.gradle", "")
write(TMP .. "/g1/app/src/main/java/A.java", "class A {}")
write(TMP .. "/g1/lib/src/main/java/L.java", "class L {}")
write(TMP .. "/g1/deep/x/src/D.java", "class D {}")
do
  local a, am, ak = root.project(TMP .. "/g1/app/src/main/java/A.java")
  local l, lm, lk = root.project(TMP .. "/g1/lib/src/main/java/L.java")
  local d = root.project(TMP .. "/g1/deep/x/src/D.java")
  lsp.report(P .. "settings_two", a == TMP .. "/g1" and l == a and d == a and am and lm and ak == "build" and lk == "build",
    ("app -> %s (%s, %s), lib -> %s (%s, %s), deep/x -> %s (want all TMP/g1, true, build); log %s"):format(
      short(a), tostring(am), ak, short(l), tostring(lm), lk, short(d), log))
end
lsp.report(P .. "boot_under_settings", root.is_boot(TMP .. "/g1") == true and root.boot_dirs(TMP .. "/g1")[1] == TMP .. "/g1/app",
  ("is_boot(TMP/g1) %s, boot_dirs[1] %s (want true, TMP/g1/app); log %s"):format(tostring(root.is_boot(TMP .. "/g1")),
    short(root.boot_dirs(TMP .. "/g1")[1]), log))

write(TMP .. "/g2/settings.gradle", "")
write(TMP .. "/g2/app/build.gradle", "")
write(TMP .. "/g2/build-logic/settings.gradle.kts", "")
write(TMP .. "/g2/build-logic/build.gradle.kts", "")
write(TMP .. "/g2/build-logic/conv/build.gradle.kts", "")
local bl = root.project(TMP .. "/g2/build-logic/conv/src/X.java")
local ap = root.project(TMP .. "/g2/app/src/X.java")
lsp.report(P .. "settings_nearest", bl == TMP .. "/g2/build-logic" and ap == TMP .. "/g2",
  ("build-logic/conv -> %s (want TMP/g2/build-logic, its own settings), app -> %s (want TMP/g2); log %s"):format(short(bl), short(ap), log))

write(TMP .. "/g3/settings.gradle", "")
write(TMP .. "/g3/build.gradle", "")
write(TMP .. "/g3/sub/build.gradle", "")
write(TMP .. "/s/build.gradle.kts", "")
local own = root.project(TMP .. "/g3/src/X.java")
local sub = root.project(TMP .. "/g3/sub/src/X.java")
local solo, solom, solok = root.project(TMP .. "/s/src/X.java")
lsp.report(P .. "settings_own", own == TMP .. "/g3" and sub == TMP .. "/g3" and solo == TMP .. "/s" and solom and solok == "build",
  ("g3 -> %s, g3/sub -> %s (want TMP/g3), standalone s -> %s %s %s (want TMP/s, true, build); log %s"):format(
    short(own), short(sub), short(solo), tostring(solom), solok, log))

write(TMP .. "/m1/settings.gradle", "")
write(TMP .. "/m1/mod/pom.xml", "<project/>")
write(TMP .. "/m1/dual/pom.xml", "<project/>")
write(TMP .. "/m1/dual/build.gradle", "")
write(TMP .. "/m2/pom.xml", "<project/>")
write(TMP .. "/m2/.git/HEAD", "")
write(TMP .. "/m2/m/pom.xml", "<project/>")
local mm = root.project(TMP .. "/m1/mod/src/X.java")
local gm = root.project(TMP .. "/m2/m/src/X.java")
local dual = root.project(TMP .. "/m1/dual/src/X.java")
lsp.report(P .. "maven_unchanged", mm == TMP .. "/m1/mod" and gm == TMP .. "/m2" and dual == TMP .. "/m1/dual",
  ("pom under a settings dir -> %s (want TMP/m1/mod), multi-module Maven with git root -> %s (want TMP/m2), pom+build.gradle dir -> %s (want TMP/m1/dual); log %s"):format(short(mm), short(gm), short(dual), log))

-- bounds
write(TMP .. "/b1/settings.gradle", "")
write(TMP .. "/b1/repo/.git/HEAD", "")
write(TMP .. "/b1/repo/app/build.gradle", "")
case("bound_git", "b1/repo/app/src/X.java", "b1/repo/app", "build")
write(TMP .. "/b2/settings.gradle", "")
write(TMP .. "/b2/proj/.nv4j", "")
write(TMP .. "/b2/proj/app/build.gradle", "")
write(TMP .. "/b3/.nv4j", "")
write(TMP .. "/b3/settings.gradle", "")
write(TMP .. "/b3/a/build.gradle", "")
do
  local r1 = root.project(TMP .. "/b2/proj/app/src/X.java")
  local r2, m2, k2 = root.project(TMP .. "/b3/a/src/X.java")
  lsp.report(P .. "bound_nv4j", r1 == TMP .. "/b2/proj/app" and r2 == TMP .. "/b3" and m2 and k2 == "nv4j",
    ("settings above a .nv4j dir not used: %s (want TMP/b2/proj/app); .nv4j beside settings: %s %s %s (want TMP/b3, true, nv4j); log %s"):format(
      short(r1), short(r2), tostring(m2), k2, log))
end
write(TMP .. "/hm/settings.gradle", "")
write(TMP .. "/hm/p/build.gradle", "")
write(TMP .. "/hm/p/q/r/build.gradle", "")
do
  local orig_home = root.home
  root.home = function() return TMP .. "/hm" end
  local r1 = root.project(TMP .. "/hm/p/src/X.java")
  local r2 = root.project(TMP .. "/hm/p/q/r/src/X.java")
  root.home = orig_home
  lsp.report(P .. "bound_home", r1 == TMP .. "/hm/p" and r2 == TMP .. "/hm/p/q/r",
    ("$HOME = TMP/hm holding settings.gradle: p -> %s, p/q/r -> %s (want themselves, never $HOME); log %s"):format(short(r1), short(r2), log))
end

-- loose files and the loose-file cap
write(TMP .. "/lo/X.java", "class X {}")
case("loose_unchanged", "lo/X.java", "lo", "loose")
do
  local function stub(r) return { config = { root_dir = r }, is_stopped = function() return false end, is_stopping = function() return false end } end
  local notes = {}
  local orig_notify = vim.notify
  vim.notify = function(m) notes[#notes + 1] = m end
  root.clear_refused()
  -- a running client at the Gradle settings root: not loose, so a loose root next to it is neither warned nor refused
  local msg1, ref1 = root.warn_loose(TMP .. "/lo", { stub(TMP .. "/g1") })
  root.clear_refused()
  -- control inside the case: a client at a real loose root DOES refuse (cap 1)
  local msg2, ref2 = root.warn_loose(TMP .. "/lo", { stub(TMP .. "/lo2") })
  vim.notify = orig_notify
  root.clear_refused()
  lsp.report(P .. "cap_kinds", msg1 == nil and ref1 == false and #notes == 1 and msg2 ~= nil and ref2 == true,
    ("client at settings root: msg %s refused %s (want nil, false); client at a loose root: refused %s, warnings %d total (want true, 1); log %s")
      :format(tostring(msg1), tostring(ref1), tostring(ref2), #notes, log))
end

-- ── one_jdtls (live) ─────────────────────────────────────────────────────────────────────────
local paths = require("nv4j.paths")
local function project_name(r) return vim.fs.basename(r) .. "-" .. vim.fn.sha256(r):sub(1, 8) end
local LIVE = TMP .. "/live"
if vim.env.NV4J_68_LIVE ~= "0" then
  local ok, err = pcall(function()
    local fixture = vim.env.NV4J_GRADLE_FIXTURE
    if not fixture or vim.fn.isdirectory(fixture) == 0 then
      return lsp.report(P .. "one_jdtls", false, "NV4J_GRADLE_FIXTURE not set (run through tests/run.sh)")
    end
    vim.fn.mkdir(LIVE, "p")
    vim.fn.system({ "cp", "-R", fixture .. "/gradle", fixture .. "/gradlew", LIVE .. "/" })
    write(LIVE .. "/settings.gradle", "rootProject.name = 'multi'\ninclude 'app', 'lib'\n")
    write(LIVE .. "/build.gradle", "")
    write(LIVE .. "/lib/build.gradle", "plugins { id 'java-library' }\nrepositories { mavenCentral() }\n")
    write(LIVE .. "/app/build.gradle", "plugins { id 'java' }\nrepositories { mavenCentral() }\ndependencies { implementation project(':lib') }\n")
    write(LIVE .. "/lib/src/main/java/lib/Lib.java", "package lib;\n\npublic class Lib {\n  public static int one() { return 1; }\n}\n")
    write(LIVE .. "/app/src/main/java/app/App.java", "package app;\n\nimport lib.Lib;\n\npublic class App {\n  int x() { return Lib.one(); }\n}\n")
    local live_root = vim.uv.fs_realpath(LIVE)
    local ba = lsp.open(live_root .. "/app/src/main/java/app/App.java")
    local ca = lsp.wait_ready(ba, 300000)
    local bl = lsp.open(live_root .. "/lib/src/main/java/lib/Lib.java")
    local cl = lsp.wait_ready(bl, 300000)
    local clients = vim.lsp.get_clients({ name = "jdtls" })
    local rs = vim.tbl_map(function(c) return c.config.root_dir end, clients)
    local errs = {}
    vim.wait(15000, function()
      errs = vim.tbl_filter(function(d) return d.severity == vim.diagnostic.severity.ERROR end, vim.diagnostic.get(ba))
      return false
    end, 500)
    lsp.report(P .. "one_jdtls",
      ca ~= nil and cl ~= nil and #clients == 1 and clients[1].config.root_dir == live_root and #errs == 0,
      ("app ready %s, lib ready %s, %d jdt.ls client(s) [%s] (want 1 at %s), errors in App.java %d (want 0: lib resolves); log %s")
        :format(tostring(ca ~= nil), tostring(cl ~= nil), #clients, table.concat(rs, ", "), live_root, #errs, log))
  end)
  if not ok then lsp.report(P .. "one_jdtls", false, "error: " .. tostring(err)) end
  -- stop every jdtls this check started, then remove its data dirs (exact names) and the throwaway project
  for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do c:stop() end
  vim.wait(15000, function() return #vim.lsp.get_clients({ name = "jdtls" }) == 0 end, 200)
  for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do c:stop(true) end
  for _, r in ipairs({ LIVE, LIVE .. "/app", LIVE .. "/lib" }) do
    local rr = vim.uv.fs_realpath(r) or r
    vim.fn.delete(paths.jdtls_data .. "/" .. project_name(rr), "rf")
    vim.fn.delete(paths.jdtls_config .. "/" .. project_name(rr), "rf")
  end
end

vim.fn.delete(TMP, "rf")
lsp.finish()
