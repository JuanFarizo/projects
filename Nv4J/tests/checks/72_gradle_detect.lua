-- P4 Gradle T7 (G8 Boot detection, G9 scaffold JUnit flavour). Pure unit cases on temp trees under /tmp/nv4j/gradle72-<pid>
-- (removed at the end): no jdt.ls, no Gradle, no network, so not gated in tests/run.sh. Spec: specs/006-p4-gradle.md "T7".
-- G8, nv4j.root.boot_build / boot_module:
--  boot_apply_plugin   `apply plugin: 'org.springframework.boot'` (Groovy) and `id("org.springframework.boot")` (Kotlin DSL) -> Boot.
--  boot_catalog_alias  multi-project, catalog at the settings root: [plugins] `boot = { id = "org.springframework.boot" ... }`, app
--                      applies `alias(libs.plugins.boot)` (a name the old fixed `libs.plugins.spring.boot` text rule misses) -> app
--                      is Boot and boot_module is app (not the settings root).
--  boot_catalog_lib    app has no Boot plugin but `implementation libs.web` with `web = { module = "org.springframework.boot:spring-
--                      boot-starter-web" }` -> Boot.
--  boot_catalog_not    app applies `alias(libs.plugins.kotlin.jvm)` only (same catalog naming Boot) -> app NOT Boot; prefix guard:
--                      `libs.plugins.bootx` is not `libs.plugins.boot`.
--  boot_buildsrc       convention plugin buildSrc/src/main/groovy/acme.boot-conventions.gradle names the Boot plugin, app applies
--                      `id 'acme.boot-conventions'`, lib applies `id 'acme.java-conventions'` (plain) -> app Boot, lib not,
--                      boot_module(root) = app (buildSrc, whose build.gradle names spring-boot-gradle-plugin, is never chosen).
--  boot_build_logic    included build build-logic (own settings) with conventions/src/main/kotlin/acme.spring-boot.gradle.kts
--                      applying id("org.springframework.boot"); app/build.gradle.kts `id("acme.spring-boot")` -> Boot.
-- G9, nv4j.scaffold.junit (the flavour of a new test class):
--  junit_catalog4      `testImplementation libs.junit` with `junit = "junit:junit:4.13.2"` -> 4.
--  junit_catalog5      app: `testImplementation libs.junit.jupiter` (`junit-jupiter = { module = "org.junit.jupiter:junit-jupiter" }`)
--                      while the root `subprojects {}` names junit:junit -> 5 (the module's own build file decides first).
--  junit_subproject4   multi-project (root = settings dir since D29), root build.gradle empty, app/build.gradle names junit:junit -> 4.
--  junit_root_block4   root build.gradle `subprojects { dependencies { testImplementation 'junit:junit:4.13.2' } }`, app silent -> 4.
-- Controls (NV4J_72_CONTROL=<comma list>): oldroot (HEAD nvim/lua/nv4j/root.lua), oldscaffold (HEAD nvim/lua/nv4j/scaffold.lua's
-- junit), noboot (root.boot_build always false: the cases HEAD already passed), noroot (scaffold reads only the module's file),
-- anyalias (any Boot entry in the catalog counts, whatever alias the build file uses: boot_catalog_not).
local lsp = require("lsp")
local P = "72_gradle_detect."
local log = vim.env.NV4J_LOG or "(no NV4J_LOG)"
local CONTROL = vim.env.NV4J_72_CONTROL or ""
local function has(c) return ("," .. CONTROL .. ","):find("," .. c .. ",", 1, true) ~= nil end
local HERE = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize((debug.getinfo(1, "S").source:gsub("^@", ""))))) -- tests/
local NV = vim.fs.dirname(HERE)

local TMP = "/tmp/nv4j/gradle72-" .. vim.fn.getpid()
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
local function head_file(rel)
  local out = TMP .. "/head-" .. vim.fs.basename(rel)
  local git_root = vim.fn.systemlist({ "git", "-C", NV, "rev-parse", "--show-toplevel" })[1]
  local prefix = vim.fn.systemlist({ "git", "-C", NV, "rev-parse", "--show-prefix" })[1] or ""
  vim.fn.system({ "sh", "-c", ('git -C "%s" show "HEAD:%s%s" > "%s"'):format(git_root, prefix, rel, out) })
  return out
end
if has("oldroot") then package.loaded["nv4j.root"] = dofile(head_file("nvim/lua/nv4j/root.lua")) end
if has("oldscaffold") then -- HEAD's local junit(), exported for the case
  local f = head_file("nvim/lua/nv4j/scaffold.lua")
  local src = table.concat(vim.fn.readfile(f), "\n"):gsub("\nreturn M%s*$", "\nM.junit = M.junit or junit\nreturn M\n")
  vim.fn.writefile(vim.split(src, "\n"), f)
  package.loaded["nv4j.scaffold"] = dofile(f)
end
if CONTROL ~= "" then io.stdout:write("\nCONTROL " .. CONTROL .. " active\n") end
local root = require("nv4j.root")
local scaffold = require("nv4j.scaffold")
if has("noboot") then root.boot_build = function() return false end end
if has("anyalias") then -- "the catalog names Boot" taken as "this build uses Boot", whatever alias the build file uses
  root.catalog_uses = function(_, cat, section, pred)
    for _, v in pairs(cat and cat[section] or {}) do if pred(v) then return true end end
    return false
  end
end
if has("noroot") then -- scaffold sees only the module's own build file (no project-root fallback)
  local orig = root.project
  root.project = function(p) return vim.fs.root(p, { { "build.gradle", "build.gradle.kts", "pom.xml" } }) or orig(p) end
end
local function boot(dir) return (root.boot_build(TMP .. "/" .. dir)) == true end

-- ── G8 ─────────────────────────────────────────────────────────────────────────────────────────
write(TMP .. "/ap/build.gradle", "apply plugin: 'java'\napply plugin: 'org.springframework.boot'\n")
write(TMP .. "/ak/build.gradle.kts", 'plugins {\n    java\n    id("org.springframework.boot") version "3.5.13"\n}\n')
lsp.report(P .. "boot_apply_plugin", boot("ap") and boot("ak"),
  ("apply plugin: -> %s, id(\"...\") kts -> %s (want true, true); log %s"):format(tostring(boot("ap")), tostring(boot("ak")), log))

local TOML = [[
[versions]
boot = "3.5.13"   # the Boot version

[libraries]
web = { module = "org.springframework.boot:spring-boot-starter-web" }
junit = "junit:junit:4.13.2"

[plugins]
boot = { id = "org.springframework.boot", version.ref = "boot" }
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version = "2.1.0" }
]]
write(TMP .. "/c1/settings.gradle", "include 'app', 'web', 'kt', 'px'\n")
write(TMP .. "/c1/build.gradle", "")
write(TMP .. "/c1/gradle/libs.versions.toml", TOML)
write(TMP .. "/c1/app/build.gradle", "plugins {\n    id 'java'\n    alias(libs.plugins.boot)\n}\n")
write(TMP .. "/c1/web/build.gradle", "plugins { id 'java' }\ndependencies {\n    implementation libs.web\n}\n")
write(TMP .. "/c1/kt/build.gradle.kts", "plugins {\n    alias(libs.plugins.kotlin.jvm)\n}\n")
write(TMP .. "/c1/px/build.gradle", "plugins {\n    alias(libs.plugins.bootx)\n}\n")
do
  local mod = root.boot_module(TMP .. "/c1", TMP .. "/c1/app")
  lsp.report(P .. "boot_catalog_alias", boot("c1/app") and mod == TMP .. "/c1/app",
    ("alias(libs.plugins.boot) in app: %s, boot_module %s (want true, TMP/c1/app); log %s"):format(tostring(boot("c1/app")), short(mod), log))
end
lsp.report(P .. "boot_catalog_lib", boot("c1/web"),
  ("implementation libs.web (spring-boot-starter-web): %s (want true); log %s"):format(tostring(boot("c1/web")), log))
lsp.report(P .. "boot_catalog_not", not boot("c1/kt") and not boot("c1/px"),
  ("alias(libs.plugins.kotlin.jvm): %s, alias(libs.plugins.bootx): %s (want false, false); log %s"):format(
    tostring(boot("c1/kt")), tostring(boot("c1/px")), log))

write(TMP .. "/b1/settings.gradle", "include 'app', 'lib'\n")
write(TMP .. "/b1/build.gradle", "")
write(TMP .. "/b1/buildSrc/build.gradle",
  "plugins { id 'groovy-gradle-plugin' }\nrepositories { gradlePluginPortal() }\ndependencies {\n    implementation 'org.springframework.boot:spring-boot-gradle-plugin:3.5.13'\n}\n")
write(TMP .. "/b1/buildSrc/src/main/groovy/acme.boot-conventions.gradle",
  "plugins {\n    id 'java'\n    id 'org.springframework.boot'\n}\n")
write(TMP .. "/b1/buildSrc/src/main/groovy/acme.java-conventions.gradle", "plugins { id 'java' }\n")
write(TMP .. "/b1/app/build.gradle", "plugins { id 'acme.boot-conventions' }\n")
write(TMP .. "/b1/lib/build.gradle", "plugins { id 'acme.java-conventions' }\n")
do
  local mod = root.boot_module(TMP .. "/b1", nil)
  lsp.report(P .. "boot_buildsrc", boot("b1/app") and not boot("b1/lib") and mod == TMP .. "/b1/app",
    ("app (acme.boot-conventions): %s, lib (acme.java-conventions): %s, boot_module(root) %s (want true, false, TMP/b1/app); log %s")
      :format(tostring(boot("b1/app")), tostring(boot("b1/lib")), short(mod), log))
end

write(TMP .. "/l1/settings.gradle.kts", 'pluginManagement { includeBuild("build-logic") }\ninclude("app")\n')
write(TMP .. "/l1/build-logic/settings.gradle.kts", 'include("conventions")\n')
write(TMP .. "/l1/build-logic/conventions/build.gradle.kts", "plugins { `kotlin-dsl` }\n")
write(TMP .. "/l1/build-logic/conventions/src/main/kotlin/acme.spring-boot.gradle.kts",
  'plugins {\n    java\n    id("org.springframework.boot")\n}\n')
write(TMP .. "/l1/app/build.gradle.kts", 'plugins {\n    id("acme.spring-boot")\n}\n')
lsp.report(P .. "boot_build_logic", boot("l1/app"),
  ("app applying acme.spring-boot from build-logic: %s (want true); log %s"):format(tostring(boot("l1/app")), log))

-- ── G9 ─────────────────────────────────────────────────────────────────────────────────────────
local function flavour(path)
  local ok, r = pcall(function() return scaffold.junit(path) end)
  return ok and r or ("error: " .. tostring(r))
end
write(TMP .. "/j1/settings.gradle", "")
write(TMP .. "/j1/gradle/libs.versions.toml", TOML)
write(TMP .. "/j1/build.gradle", "plugins { id 'java' }\ndependencies {\n    testImplementation libs.junit\n}\n")
local f4 = flavour(TMP .. "/j1/src/test/java/a/ATest.java")
lsp.report(P .. "junit_catalog4", f4 == 4, ("testImplementation libs.junit (junit:junit): %s (want 4); log %s"):format(tostring(f4), log))

write(TMP .. "/j2/settings.gradle", "include 'app'\n")
write(TMP .. "/j2/gradle/libs.versions.toml",
  '[libraries]\njunit-jupiter = { module = "org.junit.jupiter:junit-jupiter", version = "5.12.2" }\njunit4 = "junit:junit:4.13.2"\n')
write(TMP .. "/j2/build.gradle", "subprojects {\n    dependencies { testImplementation 'junit:junit:4.13.2' }\n}\n")
write(TMP .. "/j2/app/build.gradle", "plugins { id 'java' }\ndependencies {\n    testImplementation libs.junit.jupiter\n}\n")
local f5 = flavour(TMP .. "/j2/app/src/test/java/a/ATest.java")
lsp.report(P .. "junit_catalog5", f5 == 5,
  ("app: testImplementation libs.junit.jupiter, root subprojects {} names junit:junit (the module wins): %s (want 5); log %s"):format(tostring(f5), log))

write(TMP .. "/j3/settings.gradle", "include 'app'\n")
write(TMP .. "/j3/build.gradle", "")
write(TMP .. "/j3/app/build.gradle", "plugins { id 'java' }\ndependencies {\n    testImplementation 'junit:junit:4.13.2'\n}\n")
local fs = flavour(TMP .. "/j3/app/src/test/java/a/ATest.java")
lsp.report(P .. "junit_subproject4", fs == 4,
  ("sub-project app names junit:junit, root build.gradle empty (root %s): %s (want 4); log %s"):format(
    short(root.project(TMP .. "/j3/app/src/test/java/a/ATest.java")), tostring(fs), log))

write(TMP .. "/j4/settings.gradle", "include 'app'\n")
write(TMP .. "/j4/build.gradle", "subprojects {\n    apply plugin: 'java'\n    dependencies {\n        testImplementation 'junit:junit:4.13.2'\n    }\n}\n")
write(TMP .. "/j4/app/build.gradle", "")
local fr = flavour(TMP .. "/j4/app/src/test/java/a/ATest.java")
lsp.report(P .. "junit_root_block4", fr == 4,
  ("root subprojects {} block names junit:junit, app silent: %s (want 4); log %s"):format(tostring(fr), log))

vim.fn.delete(TMP, "rf")
lsp.finish()
