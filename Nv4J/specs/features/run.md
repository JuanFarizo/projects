# Feature: Run Spring Boot

Priority: P2. Status: done (Task 2): `DONE 41_run 18 0` in 3 of 3 consecutive runs; review fix round 1: `DONE 41_run 22 0` in 3 of 3. Final review fix wave: `DONE 41_run 27 0` in 3 of 3. Code: `nvim/lua/nv4j/run.lua`, keys in `nvim/lua/config/keymaps.lua`, one helper exported from `nvim/lua/nv4j/debug.lua` (`refresh_and_build`). Tests: `tests/checks/41_run.lua`. Spec: `specs/004-p2-spring-run-debug.md`. Debug path it builds on: `specs/features/debug-run.md`.

## What it does

- API: `require("nv4j.run").spring_boot({ debug = boolean, profile = string|nil, env = table|nil, vm_args = string[]|nil, args = string[]|nil })`. `vm_args` and `args` are extras (the check uses `vm_args` for its process marker).
- Keys: `<leader>rs` run, `<leader>rd` debug, `<leader>rp` pick a profile (the `application-<p>.properties|yml|yaml` files found under `src/main/resources` of the project and of the current module, or "Other..." to type one) and run, `<leader>rS` run through the build tool, `<leader>rx` stop every run. P1's `<leader>rj` (plain main class, plain `java`) is unchanged. No collision: LazyVim's `<leader>r*` keys come only from the `editor.refactoring` extra, which is not enabled; `<leader>rn` (rename) stays. Enabling LazyVim's `editor.refactoring` extra would collide: it maps `<leader>rs` (select refactor) and `<leader>rp` among others. which-key group `<leader>r` = "run".
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

## Review fix round 1

1. **Build tool opt-in (D15 trade-off).** `vim.g.nv4j_run_tool = "maven"` (Maven first) or `"gradle"` (Gradle first), or `spring_boot({ tool = ... })`, runs `build_tool_command` even with jdt.ls attached; key `<leader>rS` ("Run Spring Boot (build tool)") does it for one run. Debug always goes through jdt.ls (an INFO says so when the option is set). README Known limitations lists what `<leader>rs` skips: the `spring-boot-maven-plugin` `<configuration>` (`jvmArguments`, `environmentVariables`, `profiles`, `mainClass`, `arguments`), a pom-profile `spring.profiles.active`, plugins bound to `process-classes`, the plugin's `-XX:TieredStopAtLevel=1`.
   - Resource filtering probe (scratch script, fixture restored after): `demo.version=@project.version@` appended to `application.properties`, `target/classes/application.properties` deleted, jdt.ls started, `refresh_and_build`: the copied file had `demo.version=0.0.1`. m2e inside jdt.ls filters resources (Boot parent's `@...@` delimiter) on the `<leader>rs` path. One run. Annotation processors were not verified (the fixture has none).
2. **jdt.ls client lookup.** `M.client_for_path(path)`: the jdt.ls client whose `root_dir` is the path or its deepest ancestor. `M.project_root()`: the buffer's own client, else the client containing the buffer's file (`application.yml`, a module's `pom.xml`), else (a buffer with no file, e.g. a run terminal) the only client, else build markers and no client. Without a client an INFO notice says "jdt.ls is not attached for <root>: running with the build tool".
3. **Process group kill.** `jobstart(term)` makes the job the leader of its own session and process group. `kill_tree` sends SIGTERM to the group (only when its pgid equals the job's pid and is not Neovim's group) and to every descendant from the recursive `pgrep -P` snapshot (it also reaches a child that left the group). After the grace time it sends SIGKILL to the group if it still has members, and to the snapshot pids that are still alive with the same `ps lstart` (a reused pid is never signalled). `VimLeavePre` uses the same handles (`done()`, `force()`).
4. **Stop gated on the job, not the state.** `M.is_alive(s)` = `jobwait({job}, 0)[1] == -1`, or a debug session not yet started and not final. `M.running`, `M.stop`, `stop_all`, BufWipeout and VimLeavePre use it, so a JVM that printed Boot's failure analysis ("failed") and did not exit can still be stopped.
5. `rd` env is now asserted (`debug_env`: `System.getenv("SERVER_PORT")` = "0" at the stop).

New cases: `failed_alive` (stand-in: `sh` prints the failure block, then `exec sleep 6043`; state failed + ERROR notice, still listed as running, `<C-c>` ends it), `force_tool` (`vim.g.nv4j_run_tool = "maven"` with jdt.ls attached gives `mvn spring-boot:run -Dspring-boot.run.jvmArguments=...`, stopped at once), `client_lookup`, `debug_env`; `keymaps` includes `<leader>rS`. `tree_kill` adds a perl child that leaves the group (`setpgrp`) and ignores TERM/HUP/INT.

| # | Change | Result | Kept |
|---|--------|--------|------|
| r1 | first run of the new cases (log `/tmp/nv4j/logs/test-20261021-120929.log`) | 21 of 22: `client_lookup` compared `/tmp/...` with the `/private/tmp/...` root from `vim.fs.root` | check compares real paths |
| r2 | 3 consecutive runs (logs `test-20261021-121014.log`, `-121043`, `-121110`) | `DONE 41_run 22 0` 3 of 3; tree gone in 2053, 2004, 1943 ms; started 4838, 4391, 4528 ms (info) | kept |
| r3 | control `NV4J_41_KILL_MODE=root` (only the root pid; log `-121146`) | `tree_kill` FAIL: sh, both sleeps and the perl child left after 10 s | control |
| r4 | control `nosnapshot` (group kill only; log `-121226`) | `tree_kill` FAIL: the perl child that left the group survives | snapshot needed |
| r5 | control `nogroup` (snapshot only; log `-121304`) | PASS: the snapshot also covers the in-group children. The group kill is the guard for children forked after the snapshot; that case is not tested | group kill kept as a guard |

Harness note: while r2 to r5 ran, the check's cleanup used `pkill -9 -f 6042`, which would match any process with "6042" anywhere in its command line. The patterns are now anchored (`^perl .*6042`, `^sleep 604[13]`).

Fix round full `tests/run.sh` (log `/tmp/nv4j/logs/test-20261021-121503.log`, anchored cleanup patterns): P1 135 PASS 0 FAIL, `DONE 40_debug 16 0`, `DONE 41_run 22 0`, `DONE 50_spring_ls 0 5` (Task 3).

## Final review fix wave

1. **One detector (D17).** `M.is_boot` = `root.is_boot` (memoized `boot_project`: root plus modules 2 levels down), the same call the Spring LS makes (`spring.is_boot` now delegates to it). Without jdt.ls the project is the outermost dir with a build file above the buffer (`outer_root`: `root.project`, then up while the parent has a `pom.xml`/`build.gradle*`/`settings.gradle*`), so an aggregator outside git is found from `common/`. For a buffer with no file, the current directory is used the same way before falling back to the only jdt.ls client.
2. **Build-tool cwd.** `root.boot_module(root, module)`: the buffer's module when its own build file is Boot and it is not an aggregator (`<modules>` or a settings.gradle), else the first non-aggregator Boot dir from the scan, else the first Boot dir. `build_tool_command(module, opts, project)` looks for `mvnw`/`gradlew` in the module and its parents up to the project. Maven needs the sibling modules installed.
3. **Shared client lookup.** `root.client_for_path(path, clients?)` (deepest jdt.ls root that is `path` or an ancestor). `debug.lua`'s `jdtls_client` uses it (no more exact match / `clients[1]` fallback); `run.client_for_path` delegates to it.
4. `launch_debug` calls `setup_autocmds()`, so VimLeavePre also stops a `<leader>rd` app.
5. `dap.run` runs under `pcall`. On error: session `failed`, removed from pending, ERROR notification.
6. **Debug terminal scan (found by `leave_stops_debug`).** The incremental row scan missed "Started" in a second debug session: nvim-dap pools its terminal buffer (content reset by the new terminal, so the saved row index was past the end), and a hidden or pooled terminal is 80 columns or less whatever the window width, so the wrap heuristic (row as wide as the window) joined nothing. Trials: t1 incremental scan, failed 1 of 3 runs (state "starting", text contained Started); t2 debounced full rescan with the window-width join, failed 3 of 3; t3 instrumented: `scan_rows` without a join and with width 129 both found nothing while the "" join did, so the rows are narrower than the window. Fix: start and port matched on all rows joined with "", the failure block parsed row by row (parts end at blank rows, wrapped rows joined with " ", so a word split by the wrap shows a stray space). Case `dap_scan` covers 37- and 80-column rows. After the fix: 3 of 3.

Control (log `/tmp/nv4j/logs/test-20261021-160849.log`): the old detector (`boot_build` on the root and the buffer's module) and cwd = project root: `multi_module` FAIL "Not a Spring Boot project" from common/, the aggregator and the no-file buffer.

`tests/run.sh`: `ensure_mason` returns 1 instead of exiting. jdtls missing stays FATAL. vscode-spring-boot-tools missing prints a WARN and `SKIP <check>: vscode-spring-boot-tools not installed` for 50, 51 and 52; the other checks run. Proved with a temporary copy of run.sh whose probe pointed at a missing file (NV4J_CHECKS `0*`: 00 and 01 ran; `5*`: three SKIP lines, exit 0). The copy was removed.

Numbers: 3 consecutive `DONE 41_run 27 0` (logs `test-20261021-162740.log`, `-162812`, `-162842`). Full run `test-20261021-163714.log`: exit 0, 223 PASS 0 FAIL (41: 27). A first full run (`-163048`) lost `50_spring_ls` to a jdt.ls RPC stream error (INVALID_SERVER_JSON at about 64 KB, before any Spring step). 50 alone then passed 3 of 3.
