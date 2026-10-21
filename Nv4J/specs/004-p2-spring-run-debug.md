# 004 - P2: run, debug and Spring awareness

Status: Task 0 done (research, fixture, failing baselines); Task 1 done (debug works: `DONE 40_debug 13 0`, 5 of 5 consecutive runs; review fix round: `DONE 40_debug 16 0`, 3 of 3)); Task 2 done (run Spring Boot: `DONE 41_run 18 0`, 3 of 3; review fix round 1: `DONE 41_run 22 0`, 3 of 3); Task 3 done (Spring Boot language server: `DONE 50_spring_ls 11 0`, 3 of 3). Plan: `docs/superpowers/plans/2026-10-21-nv4j-p2-spring-run-debug.md`. Does not contradict `001-architecture.md`; decisions D14 and later live in its decisions table.

## Goal

Run and debug a Spring Boot app from Neovim (profiles, env, breakpoints that hit), and Spring awareness: `application.properties`/`yml` key completion and hover, `@Value`/`@Profile` completion, beans and request mappings navigation, all inside the P1 budgets.

## Budgets (set at plan start, not to be weakened)

| Metric | Budget | Check |
|--------|--------|-------|
| Breakpoint hit, from `dap.run` | <= 20 s | `40_debug` `breakpoint_hit` |
| Debuggee gone after terminate | <= 10 s (no orphan JVM) | `40_debug` `no_orphan` |
| Spring LS ready after jdt.ls ready | <= 10 s (info on first install) | `50_spring_ls` `attached` |
| `application.properties` first completion (1.0 s after the Spring client is initialized, as D13) | <= 400 ms | `50_spring_ls` `props_first` |
| `application.properties` warm completion p95 | <= 150 ms | `50_spring_ls` `props_warm` |
| Hover | <= 500 ms | `50_spring_ls` `props_hover` |
| Extra RSS of the Spring LS | <= 1 GB (info), hard limit 1.5 GB | `50_spring_ls` `rss` |
| P1 budgets with the Spring LS running | unchanged (warm p95 <= 150 ms, cold first <= 400 ms, `@` RestController top 5, diagnostics <= 3 s) | checks 10, 11, 30 |

## Decisions

- D14 (Spring LS wiring): `JavaHello/spring-boot.nvim` pinned at `9880be4` + Mason `vscode-spring-boot-tools` 2.2.0, configured by nv4j. Reason and trials: `001` D14, `specs/features/spring-language-server.md`. Built in Task 3.

## Rulings in Task 0 (cost if wrong)

- `props_first` is sent 1.0 s after the Spring client is initialized (same pin as P1 `cold_first`). A request in the same millisecond got 0 items (positive control pc1). Cost: a user typing within the first second after the server comes up may see an empty list.
- `40_debug` plants two new classes (`LateRunner<N>`, `LateGreeting<N>`, new N per run) before jdt.ls starts, to reproduce "files added while Neovim was closed". Cost: each run leaves a deleted-file entry in the jdt.ls workspace history (harmless; the check removes the files and their class files).
- `40_debug` `classpath_first` measures a timing race: before the fix it failed in 3 of 3 runs with 4 parallel `fetch_main_configs`, but a lucky run can pass. `breakpoint_hit` and `no_orphan` carry the deterministic baseline.
- `no_orphan` was added to `40_debug` now (Review Focus 5, owner Task 1) because the baseline already shows the orphan JVM.

## Fixture (extended in Task 0)

`tests/fixtures/demo` (Spring Boot 3.5.13, Java 25) gained, keeping `mvn -q compile` green:

- `src/main/resources/application.properties` (`spring.application.name`, `server.port=8080`, `spring.jpa.open-in-view`, `demo.greeting.text`, `demo.greeting.times`) and `application-dev.yml` (`server.port`, `demo.greeting.text`, `logging.level.demo`).
- `GreetingProperties` (`@ConfigurationProperties(prefix = "demo.greeting")` record), `GreetingConfig` (`@EnableConfigurationProperties`, a `@Profile("dev")` `@Bean`), `GreetingController` (`@Value("${demo.greeting.text:Hello}")`, `@GetMapping("/hello")`), `StartupRunner` (`ApplicationRunner`, a stable breakpoint target).

## Baseline (Task 0)

`50_spring_ls`: `DONE 50_spring_ls 0 5` (no `spring-boot` client: "no 'spring-boot' client on application.properties after 30741 ms (filetype jproperties, clients: none)"). Log `/tmp/nv4j/logs/test-20261021-100352.log`.

`40_debug`, 3 runs (logs `/tmp/nv4j/logs/test-20261021-100947.log`, `-101122.log`, `-101216.log`): `classpath_first` FAIL 3/3 (the m2e provider race), `configs` FAIL 3/3 (nvim-jdtls drops main classes or never calls back), `breakpoint_hit` FAIL 3/3 (planted classes not built at launch), `no_orphan` FAIL 2/3 (the third run passed only because the app had died by itself; with the full run below, 2 of 4 runs passed that way, which is why Task 1 made the case require the JVM alive before terminate).

Root causes and the full trial logs: `specs/features/debug-run.md`, `specs/features/spring-language-server.md`.

Full `tests/run.sh` after the fixture change: see "Task 0 full run" below.

## Task 1 (debug)

Fixes in `nvim/lua/nv4j/debug.lua` (no helper API; `require("nv4j.debug").junit_launcher(config)` is exported for the check): first JDT launching calls one at a time until a classpath resolved, source-folder refresh + two incremental builds before every Java launch, terminal job stopped when a Java launch session closes, no jdt.ls for unnamed buffers, JDT's bundled JUnit launcher replaced by the engine-matching one. Details, controls and the trial log (f1 to f15): `specs/features/debug-run.md`.

Fixture: `src/test/java/demo/GreetingPropertiesTest.java` (plain JUnit 5, no Spring context) for the JUnit case.

`40_debug` now has 13 cases (Task 0's 5 plus `variable`, `debuggee_jdk`, `one_jdtls`, `test_breakpoint_hit`, `test_variable`, `test_debuggee_jdk`, `test_finished`, `junit_launcher`; the review fix round added `junit_launcher_missing`, `gate_robust`, `build_guard`, 16 in all). 5 consecutive runs: `DONE 40_debug 13 0` 5 of 5, breakpoint hit 2941 to 3095 ms and test breakpoint 715 to 894 ms (budget 20 s), debuggee `java.version` 25.0.4 with JDK 21 first on PATH and `JAVA_HOME` unset, debuggee gone after terminate.

Full `tests/run.sh` (log `/tmp/nv4j/logs/test-20261021-112341.log`): P1 unchanged at 135 PASS (00: 11, 01: 2, 10: 17, 11: 26, 12: 7, 20: 10, 30: 24, 31: 10, 32: 28, all 0 FAIL), `DONE 40_debug 13 0`, `DONE 50_spring_ls 0 5` (no `spring-boot` client yet, Task 3). 148 PASS, exit 1 only because of `50_spring_ls`.

Review fix round full run (log `/tmp/nv4j/logs/test-20261021-113449.log`): P1 135 PASS 0 FAIL (same per-check counts), `DONE 40_debug 16 0`, `DONE 50_spring_ls 0 5`. 151 PASS, exit 1 only because of `50_spring_ls`.

Ruling: a build before launch that ends with compile errors only warns and launches (VS Code asks). Cost if wrong: a launch on stale classes after a warning the user may miss.

## Task 2 (run Spring Boot)

`nvim/lua/nv4j/run.lua`: `require("nv4j.run").spring_boot({ debug, profile, env })`, keys `<leader>rs` / `<leader>rd` / `<leader>rp` / `<leader>rx` (P1's `<leader>rj` unchanged). Runs the `@SpringBootApplication` main class with `java -cp <jdt.ls classpath>` on the project JDK after jdt.ls's refresh + build (decision D15 in `001`; `mvn spring-boot:run` was slower and hung on plugin resolution, trials m1 to j2), debug through Task 1's nvim-dap path; build-tool fallback (Maven first, then Gradle) without jdt.ls. Terminal split, `<C-c>` stops, `q` stops and closes, stop kills the whole process tree. Boot's start line and failure analysis (port in use) become notifications. Details and trial log: `specs/features/run.md`.

`41_run` (18 cases): baseline `DONE 41_run 1 17` (log `/tmp/nv4j/logs/test-20261021-115258.log`); 3 consecutive runs `DONE 41_run 18 0` (logs `test-20261021-115641.log`, `-115725`, `-115817`).

Full `tests/run.sh` (log `/tmp/nv4j/logs/test-20261021-115929.log`): P1 135 PASS 0 FAIL (00: 11, 01: 2, 10: 17, 11: 26, 12: 7, 20: 10, 30: 24, 31: 10, 32: 28), `DONE 40_debug 16 0`, `DONE 41_run 18 0`, `DONE 50_spring_ls 0 5` (Task 3). 169 PASS, exit 1 only because of `50_spring_ls`.

Review fix round 1: build-tool opt-in (`<leader>rS`, `vim.g.nv4j_run_tool`), the jdt.ls client looked up by ancestor root (INFO notice when there is none), stop through the process group plus the descendant snapshot (SIGKILL only to the same process, by start time), stop gated on the job being alive instead of the state, `rd` env asserted. 3 consecutive runs `DONE 41_run 22 0`; full run (log `/tmp/nv4j/logs/test-20261021-121503.log`): P1 135 PASS, `DONE 40_debug 16 0`, `DONE 41_run 22 0`, `DONE 50_spring_ls 0 5`. Details: `specs/features/run.md`, "Review fix round 1".

Rulings: run uses jdt.ls's classes and classpath, not a Maven build (cost if wrong: the plugin `<configuration>`, pom profiles and `process-classes` plugins are skipped for `<leader>rs`; `<leader>rS` / `vim.g.nv4j_run_tool` switch to the build tool. Resource filtering does run, through m2e in jdt.ls); `<leader>rs` runs without a profile and `<leader>rp` asks each time (no saved run configurations); `q` stops the app before closing (cost: no way to hide the output and keep the app running other than switching buffers).

## Task 3 (Spring Boot language server)

`nvim/lua/plugins/spring.lua` (plugin pinned by commit, lazy on `java`/`yaml`/`jproperties`; Mason `ensure_installed`), `nvim/lua/nv4j/spring.lua` (`require("nv4j.spring").setup()`: server jar and jdt.ls bundles from the Mason package without versions, `java_cmd` from `nv4j.jdk.server_home()`, own `root_dir` = the jdt.ls root and only for Spring Boot projects, `vim.g.nv4j_spring = false` off switch), `nvim/lua/nv4j/root.lua` (jdt.ls root logic moved out of `plugins/java.lua`, shared), `plugins/java.lua` appends the five extension jars to LazyVim's bundles for Spring Boot roots only. `tests/run.sh` installs `vscode-spring-boot-tools` like jdtls. Details, gating cases and trials (t1 to t7, control c1): `specs/features/spring-language-server.md`.

`50_spring_ls` grew from 5 to 11 cases (Review Focus 1: `plain_maven` with a release-21 Maven project and an `application.properties`, `loose_file`, `disabled`; Review Focus 2: `server_jvm` with JDK 21 first on `PATH`; plus `yml_java_attached`, `bundles`). Negative control without the gating: `disabled`, `plain_maven`, `loose_file` FAIL (2 and 3 Spring LS processes). 3 consecutive runs `DONE 50_spring_ls 11 0`: ready 37 to 330 ms after jdt.ls (10 s), first completion 19 to 90 ms (400), warm p95 3.8 to 4.9 ms (150), hover 5 to 7 ms (500), RSS 415 to 439 MB (1 GB).

P1 with the Spring client on every fixture Java buffer (capabilities not restricted, nothing to fix): worst warm p95 50 to 55 ms (Task 2: 42 ms), cold first 43 to 49 ms, `@` RestController rank 1, diagnostics 457 to 474 ms. The first full run had `40_debug` `build_guard` FAIL once (a 1 s `vim.defer_fn` fired after 671 ms: libuv's cached loop time was stale when the timer was armed); `40_debug` alone passed twice; fixed with `vim.uv.update_time()` before arming in `nv4j/debug.lua` `M.build`, after which the case measured 1000 ms.

Final full `tests/run.sh` (log `/tmp/nv4j/logs/test-20261021-141316.log`), exit 0: P1 135 PASS 0 FAIL (00: 11, 01: 2, 10: 17, 11: 26, 12: 7, 20: 10, 30: 24, 31: 10, 32: 28), `DONE 40_debug 16 0`, `DONE 41_run 22 0`, `DONE 50_spring_ls 11 0`. 184 PASS.

Rulings: the `spring-boot` client stays on Java buffers with full capabilities (Task 4 needs `@Value`/`@Profile`; cost if wrong: Java completion merges a second source, measured no regression); Boot detection is a text match for `spring-boot`/`org.springframework.boot` in build files, memoized per session (cost: a pom that only mentions it, e.g. in a non-Boot property, starts the server; adding Boot needs a restart); bundles only for Boot roots (cost: none for plain projects; a project that becomes Boot needs a jdt.ls restart).

## Task 0 full run

`tests/run.sh`, log `/tmp/nv4j/logs/test-20261021-101339.log`: every P1 check still passes, 135 PASS (00: 11, 01: 2, 10: 17, 11: 26, 12: 7, 20: 10, 30: 24, 31: 10, 32: 28), same count as the end of P1. New checks fail for the expected reasons: `DONE 40_debug 2 3` (`classpath_first` 2 m2e provider errors, `configs` "2!, 3, no callback", `breakpoint_hit` "Unresolved compilation problems: LateGreeting<N> cannot be resolved to a type"; `attached` and `no_orphan` pass, the app died by itself) and `DONE 50_spring_ls 0 5` (no `spring-boot` client). 137 PASS in total, exit 1 only because of the two new checks.
