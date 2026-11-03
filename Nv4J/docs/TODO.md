# Nv4J: pending work

One list of what is open. Update it when you finish or add something. Newest decisions are in `specs/001-architecture.md`; how to resume is in `docs/HANDOFF-p3.md`. Last update: 2026-11-03.

## Waiting for your decision

| Item | What to decide | Cost if wrong |
|------|----------------|---------------|
| D23 move via `workspace/willRenameFiles` | Keep it, or go back to the code action | Move class may behave differently from IntelliJ in edge cases |
| Command or key that creates `.nv4j` | Build it (for example `:Nv4jInit` in the project's top folder), or keep `touch .nv4j` | None |

## Open work

- [x] jdt.ls flakes investigated 2026-11-02 (details in `docs/HANDOFF-p3.md`, Flakes). B fixed twice (`rename_class` revalidates every open Java file, case `rename_class_revalidates`; the cold first rename that left dependents on the old name is retried once and warned, cases `rename_class_cold_*`). A (`INVALID_SERVER_JSON`) narrowed: not Neovim's parser, the message is jdt.ls's `sts.java.classpath` data over 64 KB; the raw-bytes capture now exists (`vim.g.nv4j_lsp_capture`, see below); open: wait for the next hit. C (stall) not found: old log gone, load was 11 to 49; `run.sh` now logs the load before each check.
- [ ] `two_boot_index` flake (about 1 in 4 at load 4-5): 8 instrumented runs were all green, cause not captured; two real defects fixed (`file:/` projectUri routing, retry of a rejected `addClasspathListener`, see spring-language-server.md s2). If it fails again, look at the `addClasspathListener rejected` lines in `/tmp/nv4j/logs/spring-route.log` and keep `spring-boot-ls.log`.
- [x] Flake A capture: `vim.g.nv4j_lsp_capture = true` (or env `NV4J_LSP_CAPTURE=1`) keeps the last 128 KB of raw stdout of jdt.ls and the Spring LS and writes `/tmp/nv4j/logs/lsp-capture-<client>-<time>.bin` with a WARN on `INVALID_SERVER_JSON` or an abnormal server exit (`nvim/lua/nv4j/lspcapture.lua`, check 64 `capture_*`). Still open: turn it on when working with a big Spring project; when it fires, look at the bytes around character 65512 of the dump and see whether two messages interleave.
- [ ] Flake C: stall: look at the new `load: ..., java processes` lines in `tests/run.sh` output next time a check is slow.
- [ ] Linux: run Nv4J on Ubuntu once. `<A-/>` comment, `<A-Left>` / `<A-Right>`, `<A-]>` / `<A-[>` were tested only through the key map, not in a Linux terminal.
- [ ] AI agents: Claude and Cursor were never run for real; check 65 stubs `ClaudeCodeOpen`.
- [ ] First start with Mason on a new machine: prettier, marksman, markdownlint-cli2 and markdown-toc install (needs Node).
- [x] Cap minors (2026-11-02): a buffer the loose-file cap refused starts its jdt.ls by itself when a jdt.ls exits and the cap allows it (`root.release_refused`, cases `cap_release`, `cap_release_live`); the `start_or_attach` guard is re-applied before every start (`root.guard_start`, case `guard_reload`); `warn_loose` compares roots with `root.canon` (case `cap_canon`).
- [x] Tests not covered (2026-11-03): JUnit 4 (`60_tests_runner` `junit4_runs`), TestNG refusal and the mixed or TestNG-only project (`testng_refused`, `testng_project_mixed`, `testng_project_only`), a multi-module Maven project run from the parent root (`multi_module`), the Mason `is_installing` guard (`50_spring_ls` `ensure_package_installing`), the three `spring-route.log` lines (`50_spring_ls` `route_log_nomatch`, `route_log_nobuf`, `route_log_rejected`). No product bug found. Still open: a real TestNG run (the runner refuses it by design; `<leader>tT` is not checked on a TestNG file), a multi-module project whose parent is not the jdt.ls root.
- [ ] Case-folding branch of the project path match runs only on a case-sensitive file system (this Mac is case-insensitive).

Settled, no longer asked: the 5 s ceiling for change signature on a method with implementations stays (it only sets how long the check waits); smear-cursor and mini.animate are not ported (user ruling D26).

## Later (priorities from the plan)

- [ ] P4: Gradle as a first-class build tool, JPA, TestNG polish. Gradle research and task order: `specs/006-p4-gradle.md` (gap list G1 to G10, decisions D28 to D32 proposed by Claude, the user can overturn). Done: T1 (fixture `tests/fixtures/gradle-boot`, check `67_gradle`, `run.sh` resolve step with SKIP) and T2 (G1: no silent 0/0/0, launcher in the Gradle cache). Next: T3 (G7 + G2, root rule and one jdt.ls per Gradle build), T4 (project JDK from Gradle files), T5 (`vm_args` for `bootRun`), T6 (build file errors, first reproduce the G6 hang), T7 (G8/G9, docs).
- [ ] Commit the Gradle fixture and T1/T2 (nothing is committed yet): until the fixture is committed `tests/run.sh` needs `NV4J_FIXTURE_DIRTY=allow` for check 67 (the guard sees the new fixture as uncommitted).
- [ ] JDT index save (only if a start on the second day is slow).
- [ ] `-Xms` / `-Xmx` stay out (your rule).

## Done recently

- 2026-11-03: P4 T1/T2: Gradle Spring Boot fixture and `67_gradle` (18 cases, three green runs; controls n67a to n67c and the stub/markers/wrapper controls in `specs/features/tests-runner.md`); a test JVM that dies is an error naming the cause, never `0 passed, 0 failed, 0 skipped`; the JUnit launcher is found in the Gradle cache. Decisions D28 to D32 recorded as proposed.
- 2026-11-03: test coverage for JUnit 4, TestNG, multi-module Maven, the Mason `is_installing` guard and the spring-route.log lines: `60_tests_runner` 34 cases, `50_spring_ls` 28 cases, controls in `tests-runner.md` and `spring-language-server.md` (n60y, n60z, n50a, n50b).
- 2026-11-02: debug-only raw stdout capture for flake A and the three cap minors (see Open work); `64_project_marker` has 36 cases. Controls n64g: all eight new real or unit cases FAIL when the capture, the release, the canon compare or the guard re-application is removed (`/tmp/nv4j/logs/test-20261102-224619.log`).
- 2026-11-02: `61_scaffold` `compiles_all` / `edit_template` flake fixed: the Spring LS held the new file's template twice (nvim sends a pending didChange to a client that attached after the edit); `fill_buf` flushes pending changes, case `edit_template_sync` with control. The same race can hit any edit made within 150 ms before a second LS attaches (not fixed outside the scaffold).
- 2026-11-02: cold first class rename no longer leaves dependents on the old name silently: references compared with the edit, one retry, WARN if still missing (check 62 `rename_class_cold_*`). Docs name jdt.ls 1.63.0 (installed plugin 1.63.0.202610191322).
- 2026-11-02: Spring LS with two projects: checked with a real run, it does index the second project (request mapping, bean, configuration key) although it gets only the first folder; no fix needed. Check 50 `two_boot_index`. Memory warning timer path smoke-tested with a real jdt.ls: check 64 `memwatch_live`.
- 2026-11-02: jdt.ls memory: no budget and no limit; a warning once a jdt.ls reaches 2 GB RSS (`vim.g.nv4j_jdtls_warn_mb`, `nv4j/memwatch.lua`, check 64 `memwatch_unit`).
- 2026-11-02: cap on loose-file jdt.ls (`vim.g.nv4j_loose_max`, default 1), two Spring Boot apps in one Neovim, three full runs green (21 checks).
- 2026-10-30: Cmd keys on Mac, Alt keys on Linux (comment, jump, terminal tabs).
- 2026-10-29: dotfiles merge (D26), P3 pushed.
