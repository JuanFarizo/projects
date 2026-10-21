# Feature: Run Spring Boot

Priority: P2. Status: done (Task 2): `DONE 41_run 18 0` in 3 of 3 consecutive runs. Code: `nvim/lua/nv4j/run.lua`, keys in `nvim/lua/config/keymaps.lua`, one helper exported from `nvim/lua/nv4j/debug.lua` (`refresh_and_build`). Tests: `tests/checks/41_run.lua`. Spec: `specs/004-p2-spring-run-debug.md`. Debug path it builds on: `specs/features/debug-run.md`.

## What it does

- API: `require("nv4j.run").spring_boot({ debug = boolean, profile = string|nil, env = table|nil, vm_args = string[]|nil, args = string[]|nil })`. `vm_args` and `args` are extras (the check uses `vm_args` for its process marker).
- Keys: `<leader>rs` run, `<leader>rd` debug, `<leader>rp` pick a profile (the `application-<p>.properties|yml|yaml` files found under `src/main/resources` of the project and of the current module, or "Other..." to type one) and run, `<leader>rx` stop every run. P1's `<leader>rj` (plain main class, plain `java`) is unchanged. No collision: LazyVim's `<leader>r*` keys come only from the `editor.refactoring` extra, which is not enabled; `<leader>rn` (rename) stays. which-key group `<leader>r` = "run".
- Boot detection (`M.is_boot(root)`): Maven first, `<groupId>org.springframework.boot</groupId>` anywhere in `pom.xml` with comments removed (parent, plugin, starter, BOM import); then `org.springframework.boot` in `build.gradle` / `build.gradle.kts` (the plugin id). Checked on the project root and on the module of the current buffer. The main class must carry `@SpringBootApplication` (file from jdt.ls's `vscode.java.resolveMainClass`); several: `vim.ui.select`.
- Run (with jdt.ls): the launch config of that main class from nvim-jdtls's `fetch_main_configs` (the same as `<leader>dc`, through Task 1's serialized gate), then `nv4j.debug.refresh_and_build(root, ..., "run")` ("Building before run...", same warnings as debug), then `<JAVA_HOME>/bin/java [vmArgs] [-Dspring.profiles.active=<p>] [vm_args] [--module-path ...] -cp <classpath> <main> [args]` in a terminal split. `JAVA_HOME` = the default runtime of `nv4j.jdk.runtimes(root)` (project JDK per `.sdkmanrc`/pom), never `PATH`; `JAVA_HOME` is also put in the app's environment, next to `env`.
- Debug: the same config through `dap.run` (Task 1's wrapped adapter builds before launch and stops the debuggee's terminal job when the session closes), with `javaExec` from `nv4j.jdk`, the profile as `-Dspring.profiles.active`, `env` and `vm_args`. nvim-dap's terminal buffer is scanned for the same Boot lines.
- Run without jdt.ls (no client for the project): build-tool fallback, Maven first: `<root>/mvnw` (or `mvn`) `spring-boot:run -Dspring-boot.run.profiles=<p> -Dspring-boot.run.jvmArguments=<vm_args>`; Gradle: `<root>/gradlew` (or `gradle`) `bootRun`, profile through `SPRING_PROFILES_ACTIVE`. `PATH` gets `$JAVA_HOME/bin` first. Debug needs jdt.ls (a warning says so).
- Output: `botright 15split`, a scratch buffer named `nv4j-run://<Main>[ [profile]]#<n>`, `jobstart(cmd, { term = true })`; focus goes back to the window you were in. Buffer keys (normal mode): `<C-c>` stops, `q` stops and wipes the buffer. Typing `<C-c>` in terminal mode sends SIGINT to the app as usual (Boot shuts down; exit code 130 counts as stopped).
- Notifications (title "Spring Boot"): `"<Main> started on port N in X s"` from Boot's `Started ... in X seconds` plus `... started on port N`; on `APPLICATION FAILED TO START`, the failure analysis Description and Action as an ERROR (e.g. "Web server failed to start. Port 8080 was already in use."); a non-zero exit without that block as an ERROR with the last exception/ERROR line; "stopped" / "exited" otherwise. Output is scanned from the raw pty stream (ANSI codes and CR removed, partial lines kept between chunks).
- Session records in `M.sessions` (`state` starting, running, failed, exited, stopped; `port`, `pid`, `job`, `buf`); `M.running()`, `M.stop(s)`, `M.stop_all()`.
- Stop = whole process tree: the descendants of the job's pid are collected first (`pgrep -P`, recursive: once a parent dies its children are re-parented and cannot be found), all get SIGTERM, survivors SIGKILL after `KILL_GRACE_MS` (5 s). Wiping a run buffer stops its app; `VimLeavePre` stops every running tree (TERM, up to 3 s, then KILL).

## Trials: Maven `spring-boot:run` or main class with the classpath

Measured on the fixture (Boot 3.5.13, Java 25), JDK 25 as `JAVA_HOME` for Maven, `--server.port=0`, time from the command to the `Started DemoApplication` line in its output (shell loop polling the log every 50 to 100 ms). Logs `/tmp/nv4j/logs/trial-*.log`.

| # | Change | Result | Kept |
|---|--------|--------|------|
| m1 | `mvn -q spring-boot:run` (plain) | never started: 2 runs gave no output for 78 s each (stopped by the trial loop), a third was stopped earlier. Without `-q`: Maven resolves the plugin prefix by loading every plugin of the pom's `pluginManagement` (Boot's parent) and hung downloading `maven-failsafe-plugin-3.5.5.pom` from the user's company mirror (`k12-plugin`, unreachable here); `spring-boot-maven-plugin:3.5.13` itself is not in `~/.m2` either | rejected as the default: depends on the network and on Maven settings |
| m2a | `mvn -o org.springframework.boot:spring-boot-maven-plugin:3.5.16:run` (offline, fully qualified) | BUILD FAILURE in 3 to 4 s: the plugin's dependencies (`spring-boot-loader-tools`, `spring-boot-buildpack-platform` 3.5.16) were never downloaded | evidence |
| m2 | same with 3.5.14 (complete in `~/.m2`), 3 runs | Started after 6.8, 5.0, 5.9 s (Boot itself 1.8 to 2.0 s); app on Java 25.0.4 (fork uses Maven's `JAVA_HOME`); Boot's plugin adds `-XX:TieredStopAtLevel=1`; SIGTERM to `mvn` also ended the forked JVM (the plugin's shutdown hook) | evidence (Maven costs about 3 to 4 s) |
| j1 | `java -cp target/classes:<runtime classpath> demo.DemoApplication`, JDK 25, 3 runs | Started after 2.45, 2.60, 2.59 s | chosen |
| j2 | j1 + `-XX:TieredStopAtLevel=1` (what Boot's plugin adds), 3 runs | 2.51, 2.60, 2.36 s: no clear gain, and the flag lowers the app's peak speed | rejected |
| p1 | two j1 runs on the same `SERVER_PORT` | second exits with code 1 after about 3 s, prints `APPLICATION FAILED TO START` / Description "Web server failed to start. Port 18099 was already in use." / Action ...: the lines the notification parses | evidence |

Decision: main class with the classpath from jdt.ls (j1), after the jdt.ls build. Faster (about 2.5 s against 5 to 7 s with every plugin already local), no network, same JDK rule as debug (project JDK from `nv4j.jdk`), and the same path for Maven and Gradle projects (jdt.ls resolves both). The classpath is the one jdt.ls already resolved for debug, so `rs` and `rd` run exactly the same program. Cost: the run uses jdt.ls's compiled classes (`target/classes`, shared with Maven) instead of a Maven build; resource filtering or plugins bound to `process-classes` are not run. The build-tool command remains the fallback without jdt.ls.

## Test design (`tests/checks/41_run.lua`)

jdt.ls is started on `DemoApplication.java` (hostile run.sh env: JDK 21 first on `PATH`, `JAVA_HOME` unset); every app gets `-Dnv4j.check=41_run` through `vm_args` so the check can count and always kill its JVMs. `vim.o.columns = 300` so Boot's log lines are not wrapped in the terminal buffer. Cases (see the file header): `started` (info timing, logged as `run_started`), `started_notice`, `java25`, `env` (`DEMO_GREETING_TEXT`), `terminal`, `port_in_use` and `no_hung` (Review Focus 4: the second run uses the first run's port through env `SERVER_PORT`; the first run uses `SERVER_PORT=0`, so the fixture's 8080 never clashes with anything on the machine), `stop_no_orphan` (the buffer's `<C-c>` mapping), `close` (`q`), `profile` (`dev`: `application-dev.yml` says "Hello dev"), `tree_kill`, `debug_stop` / `debug_profile` / `debug_no_orphan` (breakpoint in `StartupRunner.run`, `started` evaluated at the stop, logged as `run_debug_breakpoint_hit`), `detect`, `build_tool_cmd`, `keymaps`.

`tree_kill` stands in for `mvn` and its forked JVM, which cannot run here (m1): `sh -c "trap '' TERM HUP INT; sleep 6041 & sleep 6041 & wait"` started with `start_terminal`; every process ignores SIGTERM and SIGHUP, so only the tree walk plus the SIGKILL escalation ends them (`KILL_GRACE_MS` 1.5 s in the check).

### Check trials

| # | Change | Result | Kept |
|---|--------|--------|------|
| c1 | baseline before `run.lua` (log `/tmp/nv4j/logs/test-20261021-115258.log`) | `DONE 41_run 1 17` (`nv4j.run` not loadable) | failing first |
| c2 | first implementation (log `test-20261021-115449.log`) | 17 of 18; `tree_kill` "tree up false": `pgrep -f "sleep 6041"` also matched the `sh -c` line (3 processes, not 2) | check fixed: `^sleep 6041` |
| c3 | fixed check | `DONE 41_run 18 0`, tree gone in 1717 ms (1.5 s grace + KILL) | kept |
| c4 | control: `kill_tree` signals only the root pid (log `test-20261021-115600.log`) | `tree_kill` FAIL: both `sleep 6041` children alive 10 s after stop; `stop_no_orphan` still passes (a single JVM has no children) | descendant walk confirmed |

### Final numbers (Task 2)

3 consecutive `NV4J_CHECKS=41_run tests/run.sh` (logs `/tmp/nv4j/logs/test-20261021-115641.log`, `-115725`, `-115817`): `DONE 41_run 18 0` in 3 of 3. `started` 5188, 7654, 4640 ms from the call to "Started" (info: includes resolveMainClass, the classpath fetch, the refresh and two incremental builds and the JVM; Boot's own start 2.2 to 2.3 s). `tree_kill` 1735, 1936, 1722 ms. `debug_stop` 4897, 4405, 2729 ms (budget 20 s).

Full `tests/run.sh` (log `/tmp/nv4j/logs/test-20261021-115929.log`): P1 135 PASS 0 FAIL, `DONE 40_debug 16 0`, `DONE 41_run 18 0`, `DONE 50_spring_ls 0 5` (Task 3, expected).
