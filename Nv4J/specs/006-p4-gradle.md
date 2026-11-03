# 006 - P4: Gradle as a first-class build tool

Status: Task 0 (research and spec) done 2026-11-03; **T1 and T2 built 2026-11-03** (see "Status of T1 and T2" after the task list); T3 to T7 open. Facts below are measured unless marked "unverified". Does not contradict `001-architecture.md` (D2: "Maven first-class, Gradle second, untested (P4)"); the decisions proposed here are D28 and later (D27 is taken: saved run defaults). D28 to D32 are recorded in the `001` decision table as "proposed, Claude, user can overturn" (the user did not object).

## Goal

A Spring Boot developer on Gradle gets the same daily workflow as on Maven: open the project, one jdt.ls for the whole build, Spring LS, run/debug (`<leader>rs`, `rd`, `rp`, `rS`), tests (`<leader>tr/tt/tp/tf`), scaffolding, refactors, with checks that prove it and fail when the code is removed. "First-class" is defined in decision D28 below.

## Summary of what works today (nothing was built for it)

Because Nv4J drives everything through jdt.ls (D15, D21), most features already work on Gradle. Measured with throwaway projects (below): import of single, multi-project, Spring Boot (Groovy and Kotlin DSL) builds; the Spring LS (mapping `@/hello`, bean, `server.port` completion); `<leader>rs` (java -cp, started in 1.0 to 2.7 s); `<leader>rS` (`./gradlew bootRun`); `<leader>rd` starts under DAP; JUnit 5 nearest/class/project; failure shown in quickfix at the right line; the "Build file" notification for an unresolved dependency.

What does not work or is unproven: a silent `0 passed, 0 failed` test run on a typical Gradle 8 project (G1), two jdt.ls for one multi-project build (G2), the project JDK ignoring the Gradle build file (G3), bootRun details (G4), a hang I could not explain on a build.gradle with a syntax error (G6). Zero of the 21 checks run Gradle.

## Budgets (proposed for P4, same numbers as Maven unless noted; measured Gradle values in "Experiments")

| Metric | Budget | Check (proposed) |
|--------|--------|------------------|
| Gradle Boot project: jdt.ls ready (warm Gradle daemon, new jdt.ls workspace) | info only; measured 25.9 s (Maven twin 13.3 s). Ceiling to decide in D28 | `67_gradle` `import_*` |
| Same, second start of the same root | <= 15 s (measured 7.2 to 9.3 s; Maven twin 4.7 s) | `67_gradle` `import_warm` |
| Nearest test, result visible, Gradle project, warm | <= 10 s (P3 budget; measured 0.8 to 1.3 s) | `67_gradle` `test_nearest` |
| `<leader>rs` Gradle Boot app "started" | <= 20 s (measured 1.0 to 1.5 s after the key) | `67_gradle` `run_cp` |
| `<leader>rS` (`gradlew bootRun`) "started" | <= 60 s (measured 4.2 to 6.4 s with the daemon warm) | `67_gradle` `run_bootrun` |
| One jdt.ls per Gradle build, whatever sub-project file is opened first | exactly 1 client | `67_gradle` `one_jdtls` (G2) |
| P1 to P3 budgets and checks 00 to 66 | unchanged | whole suite |

## Facts: where the code touches Gradle

Method: `grep -rn -i gradle nvim/lua tests` plus reading each module. "Works" = measured on Gradle in this spec; "Maven-only" = the code assumes a pom; "unknown" = not exercised.

| Place | What it does for Gradle | Status |
|-------|-------------------------|--------|
| `nv4j/root.lua:5-14` `build_markers` | `pom.xml, build.gradle, build.gradle.kts, settings.gradle, settings.gradle.kts, mvnw, gradlew, build.xml` | Works for one project; see G2, G7 |
| `nv4j/root.lua:73-101` `project()` | `vim.fs.root(path, M.build_markers)` (`:75`) with a FLAT list: the list order is a PRIORITY, not nearness (a marker earlier in the list found anywhere above beats a nearer later marker). Measured: `pom.xml` two levels above a `build.gradle.kts` wins (`/tmp/nv4j/gradle-probe-prio/a`); a `build.gradle.kts` project under a dir holding a `build.gradle` got the parent as root (probe `bootkts`, log `gradle-probe-bootkts.log`, root was the probe parent dir). Multi-project without git: root is the sub-project (`multi/app`), NOT the dir with `settings.gradle` (G2). With a `.git` at a dir that has `settings.gradle`, the git root wins (rule 2) and works | Bug (G7), design gap (G2) |
| `nv4j/root.lua:233-274` `boot_build` | Gradle: `org.springframework.boot` text, `spring-boot-starter`, catalog aliases, `gradle/libs.versions.toml`; comments stripped. Plugin only in `buildSrc`/convention plugins is not seen | Works (probes: Groovy, Kotlin DSL, `apply false` at root + plugin in `app`); convention plugins unverified (G8) |
| `nv4j/root.lua:276` `SKIP_DIRS` | contains `build`, `gradle`, `bin`, `src`: a sub-project named `build`/`gradle`/`bin` is never scanned | Works; edge case unverified |
| `nv4j/root.lua:312-330` `aggregator`, `boot_module` | `settings.gradle(.kts)` marks an aggregator; `bootRun` runs in the first non-aggregator Boot dir | Works (probe `bootmulti`: `cmd = {bootmulti/gradlew, bootRun}`, task `:app:bootRun`) |
| `nv4j/run.lua:37` `BUILD_MARKERS`, `:419` `OUTER_MARKERS` | module and outer-root lookup, includes `settings.gradle*` | Works |
| `nv4j/run.lua:57-90` `build_tool_command` | Gradle branch (`:82-87`): `gradlew` (found only when executable, searched upward to the project root) else bare `gradle`; profile -> env `SPRING_PROFILES_ACTIVE`; args -> `--args=`; `vm_args` ignored (Maven passes `-Dspring-boot.run.jvmArguments`) | Works with a wrapper; G4 |
| `nv4j/run.lua:547-` `spring_boot` | `<leader>rs` is tool independent (jdt.ls classpath, D15). Message "No pom.xml or build.gradle above this buffer" | Works (probes `boot`, `bootmulti`, `bootkts`) |
| `config/keymaps.lua:283-287` `<leader>rS` | calls `spring_boot({ tool = "maven" })`; for a Gradle-only project `build_tool_command` falls to Gradle | Works; the name is misleading, unverified for a project with both files |
| `nv4j/debug.lua:189-230` `junit_launcher` | swaps JDT's bundled `junit-platform-launcher` for the engine's own, found with the Maven repo layout `.../junit-platform-engine/<ver>/junit-platform-engine-<ver>.jar` (`:215`). The Gradle cache layout has a hash directory between version and jar, so it never matches; the code even says "Gradle is not handled" (`:221`) | BROKEN for a Gradle project that does not declare the launcher (G1) |
| `nv4j/tests.lua:767` | project scope = `vscode.java.test.findJavaProjects(root URI)`: only the Java projects under the jdt.ls root | Works; sees only what the root covers (G2) |
| `nv4j/refactor.lua:86-100` `module_root` | nearest folder with `pom.xml`, `build.gradle` or `build.gradle.kts` (`vim.fs.find`, nearest wins); `settings.gradle*` not a module marker (right) | Works (check 62 `multi_module_roots` has a `g/build.gradle.kts` module and a mixed pom/kts nesting) |
| `nv4j/scaffold.lua:78-92` `junit()` | looks for `junit-jupiter`/`spring-boot-starter-test` (5) or `junit:junit` (4) in the project's `pom.xml`, `build.gradle`, `build.gradle.kts`; default 5 | Works for literal coordinates; catalog aliases (`libs.junit`) and a root `subprojects {}` block default to 5 (G9) |
| `nv4j/scaffold.lua` package/dir layout | `src/<set>/java` regex; Gradle uses the same layout | Works |
| `nv4j/jdk.lua:113-137` `project_majors` | reads `.sdkmanrc` and the pom only; nothing from Gradle. Measured: `toolchain languageVersion = 21` project -> default major 25 (the JAVA_HOME/newest JDK); with `.sdkmanrc java=17` -> 17 | Gap (G3) |
| `nv4j/buildfile.lua:8-14` | notifies on jdt.ls errors on `build.gradle(.kts)`, `settings.gradle(.kts)` | Works for an unresolved dependency (probe `bad1`); syntax error case G6 |
| `nv4j/spring.lua:24` | the five extension jars include `sts-gradle-tooling.jar`; root is the jdt.ls root | Works (probes: Spring LS client up with 0 ms wait, mapping, bean, completion, on Groovy, Kotlin and multi-project) |
| `nv4j/usage.lua:31` | markers include gradle files, `gradlew`, `settings.gradle*` | Works, scan root follows `root.project` (G2) |
| `plugins/java.lua:15,70` | `root_dir` = `root.project`; `updateBuildConfiguration = "automatic"` (Maven/Gradle build file changes applied without asking) | Works; automatic reimport on a `build.gradle` edit unverified |
| `config/autocmds.lua:86` | Darcula theme for `build.gradle*` in cwd | Works |
| `tests/` | `41_run:394-474` (fake `build.gradle.kts` + fake `gradlew`, command string only), `50_spring_ls` `detect` (text only), `62_refactor` `multi_module_roots` (an empty `g/build.gradle.kts`), `64`, `12`. No check imports a Gradle project, runs Gradle or starts a Gradle app | No coverage (G10) |

## Experiments

Setup: throwaway projects under `/tmp/nv4j/gradle-probe-77700/` (deleted afterwards, with their jdt.ls workspaces under `~/.cache/nv4j/jdtls-data`/`jdtls-config`). Driver: a headless nvim as in `tests/run.sh` (`NVIM_APPNAME=nv4j`, `JAVA_HOME` unset, JDK 21 first on `PATH`, `tests/lib/lsp.lua` helpers) calling the real `nv4j.tests.run` and `nv4j.run.spring_boot`; driver not kept in the repo. Logs kept: `/tmp/nv4j/logs/gradle-probe-<name>.log`. They ran after the other session's `tests/run.sh` released `/tmp/nv4j/run.lock` (11:19); load average stayed 8 to 16, so timings are noisy (read them as upper bounds).

### (a) Gradle on this machine

- `gradle` is not on a PATH Neovim sees: the shell function `gradle` is a lazy SDKMAN loader; `vim.fn.executable("gradle")` is 0 and `mvn` is 1 (nvim headless, same env). SDKMAN has Gradle 9.7.0 (`~/.sdkman/candidates/gradle/current`, Kotlin 2.4.0, Groovy 4.0.32). Wrapper distributions cached in `~/.gradle/wrapper/dists`: 8.8, 8.9, 8.14.2, 9.7.1.
- JDK for the Gradle CLI: found with `nvim -l tests/lib/jdk_home.lua 25` (= `~/.sdkman/candidates/java/25.0.4-amzn`), set as `JAVA_HOME` for that command only; nothing hardcoded in the product.
- `Gradle 8.8` wrapper on JDK 25: `Unsupported class file major version 69` (CLI). Inside jdt.ls the same project imported fine: its Gradle 8.8 daemon ran on `~/.sdkman/candidates/java/21.0.7-amzn` (`ps` of the daemons), so jdt.ls picks a compatible JDK for Gradle itself (log `gradle-probe-old8.log`).
- Network was reachable (Maven Central, plugins.gradle.org, services.gradle.org answered 200; the "company mirror unreachable" of P2 is another host). `--offline` works once the cache holds the dependencies: single and multi-project JUnit builds ran offline (`BUILD SUCCESSFUL in 2s`). The Boot build failed offline first: `Plugin [id: 'io.spring.dependency-management', version: '1.1.7'] was not found` (plugin marker not cached; cache held Boot 3.3.x starters and only the 3.5.13 Gradle plugin, no `spring-boot-starter-web`), then built online in 18 s and offline from then on. `~/.gradle` grew from 2.1 GB to 2.2 GB. A Gradle fixture therefore needs the network once on a fresh machine.
- Gradle daemons are separate long-lived JVMs: 5 `GradleDaemon` processes were running at the end (3 on JDK 25, 2 on JDK 21), idle ones expire by Gradle's own timeout. They are not children of Neovim and not covered by `memwatch` or the stop logic. Not touched.

### (b) jdt.ls import (new jdt.ls workspace, Gradle daemon warm, ready = `lsp.wait_ready`)

| Project | Root chosen by Nv4J | jdt.ls projects | Import |
|---------|---------------------|-----------------|--------|
| single (`java`, JUnit 5, toolchain 21) | `single` | 1 | 18.8 s whole process cold (`gradle-probe-single-cold.log`), 7.5 s warm (`-single-warm`) |
| multi (`settings.gradle` include lib, app; no git) | `multi/app` (sub-project, not `multi`) | app AND lib (jdt.ls found the build through `settings.gradle`) | 19.2 s whole process (`multi-app-cold`) |
| same, opened `app/Main.java` then `lib/Greeter.java` | client 1 `multi/app`, client 2 `multi/lib` | same two projects in both | 9.7 s then +13.2 s: TWO jdt.ls for one build (`multi-two`) |
| same tree with a `.git` dir | `gitmulti` (git root has `settings.gradle`) | app, lib | 20.0 s whole process; `<leader>tp`: 2 passed (`gitmulti`) |
| Spring Boot 3.5.13, Groovy (`org.springframework.boot` plugin, starter-web) | `boot` | 1 | 25.9 s cold, 9.3 s and 7.2 s warm (`boot-cold`, `boot-warm`, `boot-warm2`) |
| Spring Boot, Kotlin DSL (`build.gradle.kts`, `settings.gradle.kts`) | `bootkts` | 1 | 11.2 s (`bootkts2`; the first run `bootkts` was invalid, see G7) |
| Spring Boot multi-project (`app` Boot + `lib`, root `apply false`, `.git`) | `bootmulti` | app, lib | 14.2 s (`bootmulti-cold`) |
| Maven twin of `boot` (parent 3.5.13, same app), for comparison | `mvnboot` | 1 | 13.3 s cold, 4.7 s warm (`mvnboot-1`, `-2`) |

Classpath for Spring LS and run (`java.project.getClasspaths`): runtime scope 36 entries incl. `spring-boot-starter-web-3.5.13.jar`, `spring-webmvc-6.2.17.jar` from `~/.gradle/caches/modules-2/files-2.1/...`; test scope 66. Project output folder is `bin/main` (jdt.ls's, with `application.properties` copied; no Gradle `processResources` filtering). In `bootmulti` the java -cp has a bogus entry `/lib/bin/default` (harmless, jdt.ls). jdt.ls writes `.project`, `.classpath`, `.settings`, `bin/` into the Gradle project (as for Maven).
Spring LS (all three Boot probes): client initialized immediately after jdt.ls ready; `workspace/symbol` `@/` = `@/hello -- GET` (`@/hi -- GET` in `bootmulti`), `@+` 1 bean; completion of `server.po` = 75 items, first `server.port`.

### (c) Tests (`nv4j.tests.run`, JUnit 5)

- single, warm: nearest 1210 ms, class 600 ms, project 536 ms, 1 passed each (`single-warm`). Failing test: `class` and `project` = 1 failed 1 passed, quickfix `CalcTest.java:6 CalcTest.failsOnPurpose: AssertionFailedError: expected: <7> but ...` (`single-fail`): frames resolve to the right line on Gradle.
- multi without git (root `multi/app`): nearest 802 ms, class 550 ms, project 631 ms, but "all tests in app: 1 passed": `lib`'s `GreeterTest` is not run (`multi-app-cold`). With git root `gitmulti`: project = 2 passed (1110 ms).
- boot: nearest 1258 ms, class 705 ms, project 756 ms (`boot-warm`).
- **Silent wrong result (G1).** Project `old8b` = Gradle 8.8 wrapper, `testImplementation 'org.junit.jupiter:junit-jupiter'` and `useJUnitPlatform()` but no `testRuntimeOnly 'org.junit.platform:junit-platform-launcher'` (the default for Gradle 8 projects): nearest, class and project all report `0 passed, 0 failed, 0 skipped`, no error, while the JVM died. The dap-repl holds `java.lang.NoClassDefFoundError: org/junit/platform/engine/OutputDirectoryCreator` (`gradle-probe-old8b-raw2.log`); the only trace is the `junit_launcher` warning "no junit-platform-engine jar from a Maven repository ... (Gradle is not handled)". The same project with the launcher declared passes (`old8`, `single`, `boot`).

### (d) Run

- `<leader>rs`, `boot`: `java -cp .../boot/bin/main:~/.gradle/caches/...` on `~/.sdkman/candidates/java/25.0.4-amzn/bin/java`, running 1545 ms after the key, notice "BootApp started on port 65407 in 0.93 s", stopped cleanly. `bootmulti` 1225 ms, `bootkts` 2722 ms. The project asked for toolchain 21 and ran on 25 (G3).
- `<leader>rS` = `{ <root>/gradlew, "bootRun" }` (wrapper preferred: yes, `exe("gradlew","gradle")` finds it, also from the sub-project cwd `bootmulti/app` with the wrapper at the root): state running 4172 ms (`boot`), 5305 ms (`bootmulti`, task `:app:bootRun`), 6350 ms (`bootkts`); stop left no `BootApp` process. `bootRun` runs the app on the Gradle toolchain JDK (log line `Starting BootApp using Java 21.0.12`), not on `nv4j.jdk`'s default. By hand: `JAVA_TOOL_OPTIONS=-Dnv4j.probe=1 SERVER_PORT=0 SPRING_PROFILES_ACTIVE=dev ./gradlew bootRun --args=--demo.greeting=foo` reached the app (profile `dev` active, "Picked up JAVA_TOOL_OPTIONS" printed twice) in 4 s.
- `<leader>rd` (`boot`): "Building before debug...", then "started on port 49439 in 1.037 s" under nvim-dap. Breakpoint hit on Gradle: unverified.
- `build_tool_command(boot, {profile="dev", vm_args={"-Dx=1"}, args={"--a=b"}})` = `{gradlew, "bootRun", "--args=--a=b"}`, env `SPRING_PROFILES_ACTIVE=dev`: `-Dx=1` is dropped without a message. Without a wrapper it returns `{"gradle","bootRun"}`, which cannot start here (item (a)).

### (e) Build file errors

- `bad1` (`implementation 'com.example.nonexistent:nothing:9.9.9'`): jdt.ls ready, diagnostic on `build.gradle` "Unresolved dependency: com.example.nonexistent:nothing:9.9.9", notification `Build file: bad1/build.gradle: 1 build error(s), the project classpath may be stale` (`bad1` run, output in the session; same module `nv4j/buildfile.lua`). Java file itself 0 diagnostics.
- `bad2` (unclosed `dependencies {` in `build.gradle`): jdt.ls log "Java Model Exception ... bad2 does not exist" and `/tmp/nv4j/logs/lsp.log` grew to 175 MB; the headless Neovim then stayed at 95 to 97% CPU, with `lsp.wait_ready(buf, 60000)` not returning in 100 s and 9 minutes the first time (`sample` showed nested `nlua_wait`). Unverified whether this is `tests/lib/lsp.lua`'s `wait_ready` (harness) or product behaviour; not reproduced with `bad1`. Probes killed.

## Gap list (ranked by value to a Spring Boot developer on Gradle)

| # | Gap | Proposed fix | Cost | How a check proves it (deterministic, with control) |
|---|-----|--------------|------|------------------------------------------------------|
| G1 | JUnit run on a Gradle project without an explicit launcher dependency reports 0/0/0 silently (the standard Gradle 8 setup) | (1) `debug.lua junit_launcher`: also match the Gradle cache layout (`.../org.junit.platform/junit-platform-engine/<ver>/<hash>/junit-platform-engine-<ver>.jar` -> glob `.../junit-platform-launcher/<ver>/*/junit-platform-launcher-<ver>.jar`), falling back to the existing warning; (2) the runner must turn "no result stream and the JVM wrote a `NoClassDefFoundError`/`ClassNotFoundException`" into an error, never 0/0/0 | S + S | Unit: `junit_launcher` with a fake classPaths in Gradle layout and a tmp cache -> swapped; control: pattern reverted -> FAIL. Live: Gradle fixture without the launcher dependency -> `nearest` 1 passed and `failsOnPurpose` shown; control: fix (1) off -> error message present, not 0/0/0 |
| G2 | Multi-project Gradle without git or `.nv4j`: root = sub-project; opening files of two sub-projects starts two jdt.ls for one build (+13 s, 2x memory); `<leader>tp`, usage counts, refactor scans cover only the sub-project | In `root.project`, a dir with `settings.gradle(.kts)` above the nearest Gradle build file (and not above the git root or `$HOME`) is the root; nearest `settings.gradle*` wins (so `buildSrc`/`build-logic` with their own settings stay their own root, as in Gradle) | M | Pure: tmp trees (settings above two sub-projects -> same root for both; settings in `build-logic` -> its own; no settings -> unchanged; Maven tree unchanged); control: rule off -> two roots. Live: `67_gradle` `one_jdtls`: open `app` then `lib` file, exactly 1 jdtls client; control: 2 |
| G3 | Project JDK ignores Gradle: `toolchain { languageVersion = N }`, `sourceCompatibility`, `JavaVersion.VERSION_N`, `jvmToolchain(N)` are not read, so `<leader>rs`/`rd` run on the default JDK (25 here) instead of the project's 21/17; a Boot 2.x or older-library project can fail there | Extend `jdk.project_majors` (root's `build.gradle(.kts)`, then the module's) with these four forms | S | Pure `project_majors` cases per form, Groovy and Kotlin; control: unchanged function -> `{}`. Live: java.version printed by the app equals the toolchain major |
| G4 | `<leader>rS` details: `vm_args` (also from `.nv4j` D27) silently dropped; bare `gradle` not found when only SDKMAN's lazy function exists; `gradlew` found only if executable | vm_args -> env `JAVA_TOOL_OPTIONS` (verified to reach the app); fallback `gradle` search: `$GRADLE_HOME/bin`, `~/.sdkman/candidates/gradle/current/bin`; a `gradlew` without the exec bit is run as `sh gradlew` or warned | S | Extend `41_run` `build_tool_cmd` (string level) + a live `run_bootrun` case; control: vm_args not mapped -> FAIL; live check reads the property in the app |
| G5 | Gradle import is about 2x Maven (25.9 vs 13.3 s cold, 7 to 9 vs 4.7 s warm) and Gradle daemons outlive Neovim | No code; document, and state in D28 that `memwatch` covers only jdt.ls | none | `67_gradle` `import_warm` budget (info + ceiling) |
| G6 | Build file errors: unresolved dependency is shown; a syntax error in `build.gradle` led to a spinning Neovim in my probe (cause unknown) | Reproduce under a hard timeout in the check harness; if product: bound the wait and say "Gradle import failed" (jdt.ls reports it where? unverified) | M, unknown | `67_gradle` `build_file_error` (unresolved dep -> notification, already works) and `build_file_syntax` (no hang, a message); control: notification module stubbed |
| G7 | `root.project` uses marker priority, not nearest (`vim.fs.root` flat list): a pom above a nearer `build.gradle.kts`, or a `build.gradle` above a `.kts` sub-project, wins. Affects Maven mixes too | Equal-priority list: `vim.fs.root(path, { M.build_markers })` (nested), keep rule 2 (git root) | S | Pure cases (the two trees above), `64_project_marker` and `62_refactor` rerun; control: flat list -> FAIL |
| G8 | Boot detector reads only the project's own build file: plugin applied by a convention plugin (`buildSrc`, `build-logic`, `id 'org.company.boot-conventions'`) is not detected, so no Spring LS and `<leader>rs` refuses (unverified, by code reading) | Detect `buildSrc`/`build-logic`/`included build` files naming Boot; or document `.nv4j` run settings as the override (a `boot: true` key, D27's file) | M | Pure `boot_build` on a tmp tree; control: old rule -> false |
| G9 | Scaffold JUnit flavour: version-catalog aliases and root `subprojects {}` blocks default to 5 | Read `gradle/libs.versions.toml` for `junit:junit` and the root build file; low value | S | `61_scaffold` junit cases |
| G10 | No Gradle fixture or check; every statement above is a one-off probe | Fixture `tests/fixtures/gradle-boot` (Groovy, Boot 3.5.13, starter-web, JUnit 5 with and without launcher as two variants) + `67_gradle.lua`; `run.sh` resolves it once (`./gradlew --offline` first, online if allowed) and prints SKIP lines when Gradle cannot resolve (same pattern as the Spring package) | M | the checks themselves; control per case in the style of 60 to 66 |

Not a gap (measured fine): Kotlin DSL import and run, Spring LS on Gradle, JUnit failure frames, sub-project cwd for `bootRun`, `rs` stop without orphans.

## Task order (small, each shippable, one commit and one check run each)

1. **T1 fixture and baseline check (G10).** `tests/fixtures/gradle-boot`, `run.sh` resolution step with SKIP, `67_gradle` cases that pass today: `import`, `spring_ls` (mapping, property completion), `run_cp`, `run_bootrun`, `test_nearest/class/project`, `failure_shown`, `debug_started`. Controls: each case against a stub as in 60. Ships a safety net for everything below.
2. **T2 G1** (launcher on Gradle + never 0/0/0). Highest user value: it breaks the test key silently.
3. **T3 G7 + G2** (root rule: nearest, `settings.gradle` wins). One jdt.ls per Gradle build, `<leader>tp` over all sub-projects.
4. **T4 G3** (project JDK from Gradle files).
5. **T5 G4** (bootRun polish).
6. **T6 G6** (build file errors; first reproduce).
7. **T7 G8/G9 if wanted, then docs**: README Gradle line (`README.md:17`, `:242`), `docs/KEYS.md:44`, `001` D2 text ("untested" -> status), `docs/TODO.md`, handoff.

## Status of T1 and T2 (2026-11-03)

**T1 done.** Fixture `tests/fixtures/gradle-boot` (Groovy DSL, Spring Boot 3.5.13, `starter-web`, JUnit 5; `GreetingController` with `@GetMapping("/hello")`, a `Calculator` bean, `CalculatorTest` 2 passing, `CalculatorFailingTest` 1 pass + 1 failure on purpose tagged `nv4j-failing` and excluded from `./gradlew test`, like the demo's `PriceCalculatorFailingTest`; `server.port=0`). Wrapper: **committed** (`gradlew`, `gradle/wrapper/gradle-wrapper.{jar,properties}`, Gradle 9.7.1), because Neovim does not see SDKMAN's `gradle`, the wrapper needs no CLI, and it runs offline once its distribution and the fixture's dependencies are in `~/.gradle` (verified: `./gradlew --offline test` 6 s). Gradle 9.7.1 (not the 8.14.2 also cached) because 8.x does not run on JDK 25, which `nv4j.jdk` picks for `<leader>rS`. `.gitignore` in the fixture: `.gradle/ build/ bin/ .project .classpath .settings/`. Guard: `tests/lib/fixture_guard.sh` takes the watched paths after the mode (`src build.gradle settings.gradle` for this fixture). `tests/run.sh`, only when a selected check is `67_*`: guard, then `./gradlew --offline -q testClasses` on the JDK 21 found by `nv4j.jdk` discovery (JAVA_HOME for that command only), then the same online; if both fail `SKIP 67_gradle.lua: ...` and a WARN (same pattern as 50-52 for the Spring package). Until the fixture is committed the guard reports it as uncommitted: run with `NV4J_FIXTURE_DIRTY=allow`. Check `67_gradle`: 18 cases (list in the file header and `README.md`). Gradle daemons started by the runs are left to Gradle's own idle timeout (`./gradlew --stop` in the fixture stops this version's daemons).

Measured (three consecutive green runs, `DONE 67_gradle 18 0`: `/tmp/nv4j/logs/test-20261103-124824.log`, `-125740.log`, `-125855.log`; load average 4 to 12 from other work, so read them as upper bounds):

| What | Measured | Budget (this spec) |
|------|----------|--------------------|
| jdt.ls ready after open: first run, new jdt.ls workspace for the fixture | 16.9 s (`test-20261103-115811.log`) | info |
| same, workspace and daemon warm | 6.8 to 8.3 s (5 runs) | info (proposed <= 15 s) |
| `<leader>tr` nearest, warm / first | 0.50 to 0.68 s / 0.73 to 1.09 s | <= 10 s |
| `<leader>tt` class / `<leader>tp` project (3 passed, 1 failed, 1 launch) | 0.46 to 0.77 s / 0.58 to 0.64 s | info |
| `<leader>rs` "Started GradleBootApplication" after the key | 1.27 to 1.55 s | <= 20 s |
| `<leader>rS` (`./gradlew bootRun`, daemon warm) | 3.3 to 4.3 s | <= 60 s |

The import time is information only (a ceiling is decided when T3 exists); the other budgets are the proposals of the Budgets table, now measured three times.

**T2 done (G1).** Reproduced first (`/tmp/nv4j/logs/test-20261103-120114.log`): a plain Gradle project (`junit-jupiter:5.12.2`, `useJUnitPlatform()`, no launcher dependency) gave `0 passed, 0 failed, 0 skipped` at INFO with the JVM dead. Two findings that differ from the Task 0 probe: (1) it reproduces on the Gradle 9.7.1 wrapper too (the jdt.ls classpath, not Gradle's own test task, decides); (2) the Boot fixture without its `testRuntimeOnly junit-platform-launcher` line still got the launcher on the jdt.ls test classpath, so the Boot plugin or its BOM supplies it (not investigated), and the case uses a plain project. Fix (a) `nvim/lua/nv4j/debug.lua` `junit_launcher` matches the Gradle cache layout (hash folder between version and jar) and globs the launcher of the same version; fix (b) `nvim/lua/nv4j/tests.lua` `launch_one`: a stream that ends without `%RUNTIME` is an error with the last Exception/Error line of the JVM console (nvim-dap `event_output`), never 0/0/0; details, cases and controls: `specs/features/tests-runner.md` "Gradle and the silent false green". Limit: fix (a) needs the launcher of the engine's exact version in the Gradle cache; otherwise a WARN naming `testRuntimeOnly 'org.junit.platform:junit-platform-launcher'` and fix (b)'s error.

Check 67 controls (`NV4J_67_CONTROL=<comma list>` in the check; a run with a control must FAIL; logs in `tests-runner.md`): `stubtests` (nv4j.tests.run fabricates a result: test_nearest/class/project/failure_shown), `stubrun` (spring_boot does nothing: run_cp, run_bootrun, debug_started), `nowrapper` (gradlew not executable for nv4j.run: run_bootrun), `markers` (Gradle markers removed from nv4j.root: root_dir), `NV4J_SPRING=0` (spring_ls); the T2 controls n67a to n67c put the HEAD `debug.lua`/`tests.lua` back.

## Decisions (proposed, for the user; numbering continues `001`, D27 is run defaults)

| # | Question | Recommendation | Cost if wrong |
|---|----------|----------------|---------------|
| D28 | What is "first-class" for Gradle? (a) the same jdt.ls-driven features as Maven, proven by `67_gradle` on a Gradle fixture, no Gradle-driven test runner; or (b) also run tests through `gradle test` | (a) | (b) is a second runner to build and check (L); with (a) Gradle-only test config (filters, `test { systemProperty }`) is not applied, as for Maven today |
| D29 | Multi-project root: `settings.gradle(.kts)` above a sub-project's build file wins over the nearest build file (G2) | yes, nearest `settings.gradle*` | A standalone sub-project inside a bigger tree with a settings file it does not belong to opens the bigger build (more projects imported); `.nv4j` is the override (D25) |
| D30 | Read the project JDK from Gradle build files (toolchain, `sourceCompatibility`) like `.sdkmanrc`/pom (G3) | yes | `<leader>rs` picks a different JDK than today for those projects; set `.sdkmanrc` to override |
| D31 | Gradle fixture needs the network once (about 100 MB into `~/.gradle`); `67_gradle` SKIPs when Gradle cannot resolve | accept | CI or a fresh machine offline skips the Gradle check instead of failing; a vendored offline repo would cost about 100 MB in the repo (not recommended) |
| D32 | `vm_args`/`.nv4j` run settings reach `bootRun` through `JAVA_TOOL_OPTIONS` (G4) | yes | The JVM prints "Picked up JAVA_TOOL_OPTIONS" twice in the run terminal; the Gradle daemon JVM sees the option too (not measured further) |

## Unverified / not done

- Offline import in jdt.ls (`java.import.gradle.offline.enabled`), automatic reimport after editing `build.gradle` (`updateBuildConfiguration = automatic`), breakpoint hit in a Gradle Boot app, a Gradle test failure for a `@Nested`/parameterized class, Boot 2.x on Gradle, composite builds (`includeBuild`), `buildSrc` in jdt.ls, Gradle catalog fixtures through jdt.ls (only through the detector's text rule), Windows, Linux.
- The G6 hang cause; the 175 MB `/tmp/nv4j/logs/lsp.log` (grows with jdt.ls errors; not investigated).
- Timings: load average 8 to 16, one sample each; budgets above are proposals until a check measures three runs.
