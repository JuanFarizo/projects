-- P4 T4 (G3, D30): the project JDK major is also read from Gradle build files. Run via tests/run.sh (gated like 67,
-- so it is skipped together with it when the fixture cannot resolve; the unit cases themselves need no network,
-- no Gradle, no jdt.ls: temp projects under /tmp/nv4j/gradle-jdk-<pid>, removed afterwards). Spec: specs/006-p4-gradle.md
-- (G3, T4), specs/001-architecture.md D30. Code: nvim/lua/nv4j/jdk.lua (`project_majors`, text rules, nothing evaluated).
--  toolchain_groovy  : `languageVersion = JavaLanguageVersion.of(21)` in build.gradle -> { 21 }; `.set(...)`, `.convention(...)`.
--  toolchain_kts     : `languageVersion.set(JavaLanguageVersion.of(17))` and `= JavaLanguageVersion.of(21)` in build.gradle.kts.
--  jvm_toolchain     : `kotlin { jvmToolchain(21) }` (kts) and `jvmToolchain(17)` (Groovy) -> that major.
--  compat_forms      : sourceCompatibility/targetCompatibility as JavaVersion.VERSION_21, VERSION_1_8, toVersion("17"), '21', "17",
--                      21, 1.8, `java.sourceCompatibility = ...`, Groovy without `=` (`sourceCompatibility '11'`).
--  order             : toolchain first, then jvmToolchain, then sourceCompatibility, then targetCompatibility.
--  dedupe            : the same major from several settings is listed once.
--  both_dsl          : build.gradle then build.gradle.kts when both exist.
--  comments          : `//`, block comments and a `//` inside a URL string do not hide or invent settings.
--  strings           : a setting spelled inside a string literal (println, triple quotes) is not a setting.
--  not_literal       : a variable, `libs.versions...get()`, `JavaVersion.VERSION_HIGHER` are skipped, never guessed.
--  no_version        : a build file with no version, no build file, nil root -> {}.
--  sdkmanrc_wins     : `.sdkmanrc java=17` stays first, before a Gradle toolchain 21; the pom's majors stay before Gradle's and
--                      a pom-only project is unchanged.
--  multi_project     : settings.gradle(.kts) `include`s (':app', ':libs:core', several per line, trailing comma): the sub-project
--                      build files are read after the root's; includeBuild and unknown dirs are not.
--  runtime_default   : jdk.runtimes with fake JDK 8/17/21/25 (NV4J_JDK_ROOT): toolchain 17 -> default JavaSE-17; .sdkmanrc 21
--                      beats toolchain 17; no version -> the newest (25); a toolchain nobody installed -> the newest.
--  live_rs           : <leader>rs on a throwaway Boot Gradle project (toolchain N, N != the default major) with a stub gradlew
--                      (jdt.ls not attached: the build-tool path of run.lua, the same nv4j.jdk project runtime as the jdt.ls
--                      path) launches with JAVA_HOME = a JDK of major N that nv4j.jdk finds, and `java -version` there says N.
--                      SKIP when no other JDK is installed.
--  catalog_version   : (G3 rest) `jvmToolchain(libs.versions.jdk.get().toInt())`, `JavaLanguageVersion.of(libs.versions.java.get())`,
--                      `JavaVersion.toVersion(libs.versions.java.get())`, key `java-version` = `libs.versions.java.version` with
--                      gradle/libs.versions.toml [versions] -> that major.
--  catalog_not       : entry missing, not a number ("latest"), no catalog, a commented entry -> {} (nothing guessed).
--  props_version     : `javaVersion=21` in gradle.properties read through JavaVersion.toVersion(javaVersion), findProperty, property,
--                      providers.gradleProperty(..).get().toInt(), `val javaVersion: String by project`, JavaLanguageVersion.of(javaVersion);
--                      the sub-project's gradle.properties beats the root's.
--  props_not         : key absent, value `abc`, a commented key, `findProperty("x") ?: 17`, and a build that defines a local
--                      `def/val javaVersion` or `ext.javaVersion` itself (the property would be the wrong value) -> {}.
--  convention_plugin : (G3 rest) the module applies `id 'acme.java-conventions'`, buildSrc/src/main/groovy/acme.java-conventions.gradle
--                      has the toolchain -> that major; build-logic (kts) the same; a convention applying another one; the
--                      convention's catalog/property lookups; a convention nobody applies is not read; the module's own setting
--                      comes first; .sdkmanrc still wins.
-- Out of scope (documented, not read): values computed by code (`?:`, `if`), binary convention plugins (a class), a plugin from a
-- repository, the user's ~/.gradle/gradle.properties and -P / environment overrides, `options.release`.
-- Controls: tests/lib/control_69.sh patches nvim/lua/nv4j/jdk.lua under the run.sh lock, runs this check, restores the file
-- and cmp's it against a backup (see the header of that script for the patch list and the cases each must fail).
vim.o.confirm = false
vim.o.columns = 300 -- terminal rows as wide as possible: a long JAVA_HOME is not wrapped in the buffer
local lsp = require("lsp")
local P = "69_gradle_jdk."
local J = require("nv4j.jdk")
local TMP = "/tmp/nv4j/gradle-jdk-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
local n_proj = 0

local function project(files)
  n_proj = n_proj + 1
  local d = TMP .. "/p" .. n_proj
  vim.fn.mkdir(d, "p")
  for f, body in pairs(files) do
    vim.fn.mkdir(vim.fs.dirname(d .. "/" .. f), "p")
    vim.fn.writefile(vim.split(body, "\n"), d .. "/" .. f)
  end
  return d
end
local function show(t) return "{" .. table.concat(t, ", ") .. "}" end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
local function expect(name, files, want)
  local got = J.project_majors(project(files))
  lsp.report(P .. name, same(got, want), ("got %s, want %s"):format(show(got), show(want)))
end
-- Several projects in one case: every row {files, want, label}.
local function expect_all(name, rows)
  local bad = {}
  for _, r in ipairs(rows) do
    local got = J.project_majors(project(r[1]))
    if not same(got, r[2]) then bad[#bad + 1] = ("%s: got %s want %s"):format(r[3], show(got), show(r[2])) end
  end
  lsp.report(P .. name, #bad == 0, #bad == 0 and (#rows .. " projects") or table.concat(bad, "; "))
end

local ok_all, err = pcall(function()
  expect_all("toolchain_groovy", {
    { { ["build.gradle"] = "plugins { id 'java' }\njava {\n  toolchain {\n    languageVersion = JavaLanguageVersion.of(21)\n  }\n}" }, { 21 }, "assign" },
    { { ["build.gradle"] = "java { toolchain { languageVersion.set(JavaLanguageVersion.of(17)) } }" }, { 17 }, "set" },
    { { ["build.gradle"] = "java.toolchain.languageVersion.convention(JavaLanguageVersion.of(11))" }, { 11 }, "convention" },
    { { ["build.gradle"] = "java {\n toolchain {\n  languageVersion = JavaLanguageVersion.of(\n   8)\n }\n}" }, { 8 }, "wrapped" },
  })
  expect_all("toolchain_kts", {
    { { ["build.gradle.kts"] = "java {\n  toolchain {\n    languageVersion.set(JavaLanguageVersion.of(17))\n  }\n}" }, { 17 }, "set" },
    { { ["build.gradle.kts"] = "java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }" }, { 21 }, "assign" },
  })
  expect_all("jvm_toolchain", {
    { { ["build.gradle.kts"] = "plugins { kotlin(\"jvm\") }\nkotlin {\n  jvmToolchain(21)\n}" }, { 21 }, "kts" },
    { { ["build.gradle"] = "kotlin {\n  jvmToolchain(17)\n}" }, { 17 }, "groovy" },
    { { ["build.gradle.kts"] = "kotlin { jvmToolchain { languageVersion.set(JavaLanguageVersion.of(11)) } }" }, { 11 }, "block form" },
  })
  expect_all("compat_forms", {
    { { ["build.gradle"] = "sourceCompatibility = JavaVersion.VERSION_21" }, { 21 }, "VERSION_21" },
    { { ["build.gradle"] = "sourceCompatibility = JavaVersion.VERSION_1_8" }, { 8 }, "VERSION_1_8" },
    { { ["build.gradle"] = "targetCompatibility = JavaVersion.toVersion(\"17\")" }, { 17 }, "toVersion" },
    { { ["build.gradle"] = "sourceCompatibility = '21'" }, { 21 }, "'21'" },
    { { ["build.gradle"] = "sourceCompatibility = \"17\"" }, { 17 }, "\"17\"" },
    { { ["build.gradle"] = "sourceCompatibility = 21" }, { 21 }, "21" },
    { { ["build.gradle"] = "sourceCompatibility = 1.8" }, { 8 }, "1.8" },
    { { ["build.gradle"] = "sourceCompatibility '11'" }, { 11 }, "no equals" },
    { { ["build.gradle.kts"] = "java.sourceCompatibility = JavaVersion.VERSION_17" }, { 17 }, "java. prefix kts" },
    { { ["build.gradle.kts"] = "java {\n  sourceCompatibility = JavaVersion.VERSION_21\n  targetCompatibility = JavaVersion.VERSION_21\n}" }, { 21 }, "kts block" },
  })
  expect("order", { ["build.gradle"] = "targetCompatibility = 8\nsourceCompatibility = 17\nkotlin { jvmToolchain(25) }\n"
    .. "java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }" }, { 21, 25, 17, 8 })
  expect("dedupe", { ["build.gradle"] = "java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }\n"
    .. "sourceCompatibility = '21'\ntargetCompatibility = JavaVersion.VERSION_21\nkotlin { jvmToolchain(21) }" }, { 21 })
  expect("both_dsl", { ["build.gradle"] = "sourceCompatibility = 17", ["build.gradle.kts"] = "kotlin { jvmToolchain(21) }" }, { 17, 21 })
  expect("comments", { ["build.gradle"] = table.concat({
    "// sourceCompatibility = 8",
    "/* java { toolchain { languageVersion = JavaLanguageVersion.of(11) } }",
    "   kotlin { jvmToolchain(11) } */",
    "def home = 'https://example.com/a//b' // trailing: targetCompatibility = 8",
    "java { toolchain { languageVersion = JavaLanguageVersion.of(21) } } /* of(7) */",
    "// kotlin { jvmToolchain(9) }",
  }, "\n") }, { 21 })
  expect("strings", { ["build.gradle"] = table.concat({
    "println 'sourceCompatibility = 8'",
    "println \"languageVersion = JavaLanguageVersion.of(11)\"",
    "def doc = '''",
    "kotlin { jvmToolchain(9) }",
    "'''",
    "tasks.register('x') { doLast { println \"targetCompatibility = 7 \\\" quote\" } }",
    "sourceCompatibility = '17'",
  }, "\n") }, { 17 })
  expect_all("not_literal", {
    { { ["build.gradle"] = "sourceCompatibility = javaVersion17\ntargetCompatibility = rootProject.ext.jdk21" }, {}, "variables" },
    { { ["build.gradle.kts"] = "java { toolchain { languageVersion.set(JavaLanguageVersion.of(libs.versions.java17.get().toInt())) } }" }, {}, "catalog (no catalog file)" },
    { { ["build.gradle.kts"] = "java { sourceCompatibility = JavaVersion.VERSION_HIGHER }\nkotlin { jvmToolchain(javaVer) }" }, {}, "VERSION_HIGHER" },
    { { ["build.gradle"] = "ext.mySourceCompatibility = 8\nmyjvmToolchain(11)\nsourceCompatibility_x = 9" }, {}, "longer identifiers" },
  })
  local TOML = "[versions]\njdk = \"21\"\njava = \"17\"\njava-version = \"11\"\nlatest = \"latest\"\n# old = \"8\"\nboot = \"3.5.13\"\n"
  expect_all("catalog_version", {
    { { ["gradle/libs.versions.toml"] = TOML, ["build.gradle.kts"] = "kotlin {\n  jvmToolchain(libs.versions.jdk.get().toInt())\n}" }, { 21 }, "jvmToolchain kts" },
    { { ["gradle/libs.versions.toml"] = TOML, ["build.gradle"] = "java { toolchain { languageVersion = JavaLanguageVersion.of(libs.versions.java.get()) } }" }, { 17 }, "of(libs...get()) groovy" },
    { { ["gradle/libs.versions.toml"] = TOML, ["build.gradle.kts"] = "java { toolchain { languageVersion.set(JavaLanguageVersion.of(libs.versions.java.get().toInt())) } }" }, { 17 }, "of(...toInt()) kts" },
    { { ["gradle/libs.versions.toml"] = TOML, ["build.gradle"] = "sourceCompatibility = JavaVersion.toVersion(libs.versions.java.get())" }, { 17 }, "toVersion" },
    { { ["gradle/libs.versions.toml"] = TOML, ["build.gradle"] = "java.toolchain.languageVersion = JavaLanguageVersion.of(libs.versions.java.version.get().toInteger())" }, { 11 }, "java-version key" },
    { { ["gradle/libs.versions.toml"] = TOML, ["settings.gradle"] = "include 'app'", ["app/build.gradle"] = "kotlin { jvmToolchain(libs.versions.jdk.get().toInt()) }" }, { 21 }, "sub-project, catalog at the root" },
  })
  expect_all("catalog_not", {
    { { ["gradle/libs.versions.toml"] = TOML, ["build.gradle.kts"] = "kotlin { jvmToolchain(libs.versions.nothere.get().toInt()) }" }, {}, "entry missing" },
    { { ["gradle/libs.versions.toml"] = TOML, ["build.gradle.kts"] = "kotlin { jvmToolchain(libs.versions.latest.get().toInt()) }" }, {}, "not a number" },
    { { ["gradle/libs.versions.toml"] = TOML, ["build.gradle.kts"] = "kotlin { jvmToolchain(libs.versions.old.get().toInt()) }" }, {}, "commented entry" },
    { { ["gradle/libs.versions.toml"] = TOML, ["build.gradle.kts"] = "kotlin { jvmToolchain(libs.versions.jdk.get().toInt() + 4) }" }, {}, "arithmetic" },
    { { ["gradle/libs.versions.toml"] = TOML, ["build.gradle.kts"] = "kotlin { jvmToolchain(libs.plugins.jdk.get().toInt()) }" }, {}, "libs.plugins is not a version" },
  })
  local PROPS = "# javaVersion=11\norg.gradle.jvmargs=-Dfile.encoding=UTF-8\njavaVersion=21\nother = 17\nbad=abc\n"
  expect_all("props_version", {
    { { ["gradle.properties"] = PROPS, ["build.gradle"] = "sourceCompatibility = JavaVersion.toVersion(javaVersion)" }, { 21 }, "toVersion(javaVersion)" },
    { { ["gradle.properties"] = PROPS, ["build.gradle"] = "sourceCompatibility = JavaVersion.toVersion(findProperty('javaVersion'))" }, { 21 }, "findProperty" },
    { { ["gradle.properties"] = PROPS, ["build.gradle.kts"] = "java { sourceCompatibility = JavaVersion.toVersion(property(\"javaVersion\") as String) }" }, { 21 }, "property as String" },
    { { ["gradle.properties"] = PROPS, ["build.gradle.kts"] = "kotlin { jvmToolchain(providers.gradleProperty(\"javaVersion\").get().toInt()) }" }, { 21 }, "providers.gradleProperty" },
    { { ["gradle.properties"] = PROPS, ["build.gradle.kts"] = "val javaVersion: String by project\nkotlin { jvmToolchain(javaVersion.toInt()) }" }, { 21 }, "by project" },
    { { ["gradle.properties"] = PROPS, ["build.gradle"] = "java { toolchain { languageVersion = JavaLanguageVersion.of(javaVersion) } }" }, { 21 }, "of(javaVersion)" },
    { { ["gradle.properties"] = PROPS, ["build.gradle"] = "java { toolchain { languageVersion = JavaLanguageVersion.of(project.property('other').toInteger()) } }" }, { 17 }, "project.property, spaces around =" },
    { { ["gradle.properties"] = "javaVersion=21", ["settings.gradle"] = "include 'app'", ["app/gradle.properties"] = "javaVersion=17",
        ["app/build.gradle"] = "sourceCompatibility = JavaVersion.toVersion(javaVersion)" }, { 17 }, "sub-project properties win" },
    { { ["gradle.properties"] = "javaVersion=21", ["settings.gradle"] = "include 'app'",
        ["app/build.gradle"] = "sourceCompatibility = JavaVersion.toVersion(javaVersion)" }, { 21 }, "root properties for the sub-project" },
  })
  expect_all("props_not", {
    { { ["gradle.properties"] = PROPS, ["build.gradle"] = "sourceCompatibility = JavaVersion.toVersion(nothere)" }, {}, "key absent" },
    { { ["gradle.properties"] = PROPS, ["build.gradle"] = "sourceCompatibility = JavaVersion.toVersion(findProperty('bad'))" }, {}, "value abc" },
    { { ["gradle.properties"] = "# javaVersion=11\n", ["build.gradle"] = "sourceCompatibility = JavaVersion.toVersion(javaVersion)" }, {}, "commented key" },
    { { ["gradle.properties"] = PROPS, ["build.gradle"] = "sourceCompatibility = JavaVersion.toVersion(findProperty('javaVersion') ?: 17)" }, {}, "elvis default" },
    { { ["gradle.properties"] = PROPS, ["build.gradle"] = "def javaVersion = 8\nsourceCompatibility = JavaVersion.toVersion(javaVersion)" }, {}, "local def" },
    { { ["gradle.properties"] = PROPS, ["build.gradle.kts"] = "val javaVersion = 11\nkotlin { jvmToolchain(javaVersion) }" }, {}, "local val" },
    { { ["gradle.properties"] = PROPS, ["build.gradle"] = "ext.javaVersion = 8\nsourceCompatibility = JavaVersion.toVersion(javaVersion)" }, {}, "ext assignment" },
    { { ["gradle.properties"] = PROPS, ["build.gradle"] = "ext { javaVersion = 8 }\nsourceCompatibility = javaVersion" }, {}, "ext block" },
    { { ["build.gradle"] = "sourceCompatibility = JavaVersion.toVersion(javaVersion)" }, {}, "no gradle.properties" },
  })
  local CONV_G = "plugins { id 'java' }\njava {\n  toolchain {\n    languageVersion = JavaLanguageVersion.of(21)\n  }\n}"
  local c1 = project({ ["settings.gradle"] = "include 'app', 'lib'", ["build.gradle"] = "",
    ["buildSrc/build.gradle"] = "plugins { id 'groovy-gradle-plugin' }\nsourceCompatibility = 8", ["buildSrc/src/main/groovy/acme.java-conventions.gradle"] = CONV_G,
    ["buildSrc/src/main/groovy/acme.unused.gradle"] = "java { toolchain { languageVersion = JavaLanguageVersion.of(25) } }",
    ["app/build.gradle"] = "plugins { id 'acme.java-conventions' }\nsourceCompatibility = 17",
    ["lib/build.gradle"] = "plugins { id 'java' }" })
  local c2 = project({ ["settings.gradle.kts"] = "pluginManagement { includeBuild(\"build-logic\") }\ninclude(\"app\")",
    ["build-logic/settings.gradle.kts"] = "include(\"conventions\")",
    ["build-logic/conventions/src/main/kotlin/acme.jvm.gradle.kts"] = "plugins { id(\"acme.base\") }\nkotlin { jvmToolchain(libs.versions.jdk.get().toInt()) }",
    ["build-logic/conventions/src/main/kotlin/acme.base.gradle.kts"] = "plugins { java }\njava { sourceCompatibility = JavaVersion.toVersion(javaVersion) }",
    ["gradle/libs.versions.toml"] = TOML, ["gradle.properties"] = "javaVersion=11",
    ["app/build.gradle.kts"] = "plugins { id(\"acme.jvm\") }" })
  local c3 = project({ ["build.gradle"] = "plugins { id 'acme.java-conventions' }",
    ["buildSrc/src/main/groovy/acme.java-conventions.gradle"] = CONV_G, [".sdkmanrc"] = "java=17.0.9-tem" })
  local c4 = project({ ["build.gradle"] = "plugins { id 'com.other.plugin' version '1.0' }",
    ["buildSrc/src/main/groovy/acme.java-conventions.gradle"] = CONV_G })
  local c5 = project({ ["settings.gradle"] = "include 'app'", ["app/build.gradle"] = "plugins { id 'acme.a' }",
    ["buildSrc/src/main/groovy/acme.a.gradle"] = "plugins { id 'acme.b' }\nsourceCompatibility = 8",
    ["buildSrc/src/main/groovy/acme.b.gradle"] = "plugins { id 'acme.a' }\nsourceCompatibility = 11" })
  local g2, g3, g4, g5 = J.project_majors(c2), J.project_majors(c3), J.project_majors(c4), J.project_majors(c5)
  local g1root = J.project_majors(c1)
  lsp.report(P .. "convention_plugin", same(g1root, { 17, 21 }) and same(g2, { 21, 11 }) and same(g3, { 17, 21 }) and same(g4, {}) and same(g5, { 8, 11 }),
    ("root c1 (app: own 17 then the convention's 21; buildSrc build file says 8, never read; acme.unused not applied) %s want {17, 21}; build-logic c2 (the app's `acme.jvm` -> catalog jdk 21, then the `acme.base` it applies -> property 11; root has no build file) %s want {21, 11}; "
      .. "sdkmanrc 17 + convention 21: %s want {17, 21}; plugin from a repository, unapplied convention: %s want {}; a convention applying itself in a cycle: %s want {8, 11}")
    :format(show(g1root), show(g2), show(g3), show(g4), show(g5)))
  local c1app = J.project_majors(project({ ["settings.gradle"] = "include 'app'", ["app/build.gradle"] = "plugins { id 'acme.java-conventions' }\nsourceCompatibility = 17",
    ["buildSrc/src/main/groovy/acme.java-conventions.gradle"] = CONV_G }))
  lsp.report(P .. "convention_order", same(c1app, { 17, 21 }),
    ("the module's own sourceCompatibility 17 comes before the convention's toolchain 21: %s want {17, 21}"):format(show(c1app)))
  expect_all("no_version", {
    { { ["build.gradle"] = "plugins { id 'java' }\nrepositories { mavenCentral() }" }, {}, "build file without version" },
    { { ["README"] = "x" }, {}, "no build file" },
    { { ["build.gradle"] = "" }, {}, "empty build file" },
    { { ["build.gradle"] = "/* unclosed comment\nsourceCompatibility = 8" }, {}, "unclosed comment" },
    { { ["build.gradle"] = "def s = 'unclosed\nsourceCompatibility = 17" }, { 17 }, "unclosed string ends at the line" },
  })
  lsp.report(P .. "no_root", #J.project_majors(nil) == 0, "project_majors(nil) = " .. show(J.project_majors(nil)))
  expect_all("sdkmanrc_wins", {
    { { [".sdkmanrc"] = "java=17.0.9-tem", ["build.gradle"] = "java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }" },
      { 17, 21 }, "sdkmanrc 17 before toolchain 21" },
    { { [".sdkmanrc"] = "# sdk\njava=21.0.1-tem\ngradle=8.5", ["build.gradle.kts"] = "kotlin { jvmToolchain(17) }" }, { 21, 17 }, "sdkmanrc 21" },
    { { ["pom.xml"] = "<project><properties><maven.compiler.release>21</maven.compiler.release></properties></project>" }, { 21 }, "pom only" },
    { { ["pom.xml"] = "<project><properties><java.version>21</java.version></properties></project>", ["build.gradle"] = "sourceCompatibility = 17" },
      { 21, 17 }, "pom before gradle" },
    { { [".sdkmanrc"] = "java=11.0.1", ["pom.xml"] = "<project><properties><java.version>21</java.version></properties></project>",
        ["build.gradle"] = "sourceCompatibility = 17" }, { 11, 21, 17 }, "sdkmanrc, pom, gradle" },
  })
  local inc = project({
    ["settings.gradle"] = "rootProject.name = 'multi'\n// include 'ghost'\ninclude ':app', ':libs:core'\n  include(\"lib2\",\n    \"nodir\")\n"
      .. "includeBuild '../other'\ninclude 'ghost'",
    ["build.gradle"] = "sourceCompatibility = 21",
    ["app/build.gradle.kts"] = "kotlin { jvmToolchain(17) }",
    ["libs/core/build.gradle"] = "sourceCompatibility = 11",
    ["lib2/build.gradle"] = "sourceCompatibility = 8",
    ["other/build.gradle"] = "sourceCompatibility = 9",
  })
  local got = J.project_majors(inc)
  local kts = project({ ["settings.gradle.kts"] = "include(\"app\")", ["app/build.gradle.kts"] = "java { toolchain { languageVersion = JavaLanguageVersion.of(17) } }" })
  local got_kts = J.project_majors(kts)
  lsp.report(P .. "multi_project", same(got, { 21, 17, 11, 8 }) and same(got_kts, { 17 }),
    ("groovy settings %s (want {21, 17, 11, 8}: root, app, libs/core, lib2; not includeBuild/ghost/comment), kts settings, root without build file %s (want {17})")
    :format(show(got), show(got_kts)))

  -- jdk.runtimes with fake JDKs: the default runtime follows the Gradle toolchain
  local jroot = TMP .. "/jdks"
  for _, v in ipairs({ "8.0.452", "17.0.9", "21.0.7", "25.0.1" }) do
    local h = jroot .. "/jdk-" .. v
    vim.fn.mkdir(h .. "/bin", "p")
    vim.fn.writefile({ "" }, h .. "/bin/java")
    vim.fn.writefile({ 'JAVA_VERSION="' .. v .. '"' }, h .. "/release")
  end
  local saved_root, saved_jh = vim.env.NV4J_JDK_ROOT, vim.env.JAVA_HOME
  vim.env.NV4J_JDK_ROOT, vim.env.JAVA_HOME = jroot, nil
  local function default_of(files)
    local rts, def = J.runtimes(project(files))
    local name
    for _, r in ipairs(rts) do if r.default then name = r.name end end
    return name, def
  end
  local a = default_of({ ["build.gradle"] = "java { toolchain { languageVersion = JavaLanguageVersion.of(17) } }" })
  local b = default_of({ [".sdkmanrc"] = "java=21.0.7", ["build.gradle"] = "java { toolchain { languageVersion = JavaLanguageVersion.of(17) } }" })
  local c = default_of({ ["build.gradle"] = "plugins { id 'java' }" })
  local d = default_of({ ["build.gradle"] = "java { toolchain { languageVersion = JavaLanguageVersion.of(99) } }\nsourceCompatibility = 8" })
  local e = default_of({ ["build.gradle.kts"] = "java { toolchain { languageVersion = JavaLanguageVersion.of(99) } }" })
  vim.env.NV4J_JDK_ROOT, vim.env.JAVA_HOME = saved_root, saved_jh
  lsp.report(P .. "runtime_default", a == "JavaSE-17" and b == "JavaSE-21" and c == "JavaSE-25" and d == "JavaSE-1.8" and e == "JavaSE-25",
    ("toolchain 17 -> %s; sdkmanrc 21 + toolchain 17 -> %s; no version -> %s; toolchain 99 (not installed) then source 8 -> %s; toolchain 99 only -> %s")
    :format(tostring(a), tostring(b), tostring(c), tostring(d), tostring(e)))
end)
if not ok_all then lsp.report(P .. "unit_error", false, tostring(err):gsub("\n.*", "")) end

-- ── live: <leader>rs picks the toolchain JDK ──────────────────────────────────────────────────
local function live()
  local all = J.discover()
  local _, default = J.runtimes(nil)
  local target
  for _, want in ipairs({ 21, 17, 8, 25 }) do
    for _, d in ipairs(all) do
      if d.major == want and not d.ea and want ~= default then target = want; break end
    end
    if target then break end
  end
  if not target then
    print("SKIP " .. P .. "live_rs no installed JDK differs from the default major " .. tostring(default) .. " (nv4j.jdk found " .. #all .. ")")
    return
  end
  local d = project({
    ["build.gradle"] = ("plugins {\n  id 'java'\n  id 'org.springframework.boot' version '3.5.13'\n}\njava {\n  toolchain {\n    languageVersion = JavaLanguageVersion.of(%d)\n  }\n}"):format(target),
    ["gradlew"] = '#!/bin/sh\necho "STUB_JAVA_HOME=$JAVA_HOME"\necho "STUB_JAVA_VERSION=$("$JAVA_HOME/bin/java" -version 2>&1 | head -1)"\n',
  })
  vim.fn.setfperm(d .. "/gradlew", "rwxr-xr-x")
  vim.cmd("edit " .. vim.fn.fnameescape(d .. "/build.gradle"))
  local R = require("nv4j.run")
  local n = #R.sessions
  local map = vim.fn.maparg("<leader>rs", "n", false, true)
  if type(map.callback) == "function" then map.callback() else R.spring_boot({}) end
  vim.wait(10000, function() return #R.sessions > n end, 20)
  local s = R.sessions[n + 1]
  if s then vim.wait(15000, function() return not R.is_alive(s) end, 50) end
  local txt = (s and vim.api.nvim_buf_is_valid(s.buf)) and table.concat(vim.api.nvim_buf_get_lines(s.buf, 0, -1, false), "\n") or ""
  local jh = txt:match("STUB_JAVA_HOME=(%S+)")
  local ver = txt:match("STUB_JAVA_VERSION=[^\n]-\"([%d%._]+)")
  local found
  for _, j in ipairs(all) do if jh and j.real == (vim.uv.fs_realpath(jh) or jh) then found = j end end
  local vmajor = ver and ver:match("^1%.(%d+)") or (ver and ver:match("^(%d+)"))
  lsp.report(P .. "live_rs", found ~= nil and found.major == target and tonumber(vmajor) == target,
    ("toolchain %d (default major %s): <leader>rs launched with JAVA_HOME=%s (nv4j.jdk major %s), java -version %s; terminal: %s")
    :format(target, tostring(default), tostring(jh), tostring(found and found.major), tostring(ver), txt:gsub("%s+", " "):sub(1, 200)))
  if s and vim.api.nvim_buf_is_valid(s.buf) then pcall(vim.api.nvim_buf_delete, s.buf, { force = true }) end
end
local ok_live, err_live = pcall(live)
if not ok_live then lsp.report(P .. "live_rs", false, "error: " .. tostring(err_live):gsub("\n.*", "")) end

vim.fn.delete(TMP, "rf")
lsp.finish()
