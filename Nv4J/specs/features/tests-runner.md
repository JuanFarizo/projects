# Feature: Test runner

Priority: P3. Status: built in Task 2 (`60_tests_runner` 20 cases pass, 3 of 3 runs, see "Task 2"); Task 2 review fixes (t2-n to t2-r): 27 cases. Decision: D21 in `specs/001-architecture.md`. Spec: `specs/005-p3-tests-scaffold-refactor.md`. Check: `tests/checks/60_tests_runner.lua`. Product: `nvim/lua/nv4j/tests.lua`, keys in `nvim/lua/config/keymaps.lua` (global) and `nvim/lua/plugins/java.lua` (per Java buffer, on attach).

## Budget

Run nearest test: result visible <= 10 s from the key press, warm (second run of the session). Pass/fail/skip counts must match the fixture; a failing assertion shows its message and jumps to the line.

## IntelliJ behaviour (reference, `intellij-community` at `b633034bb`)

- JUnit run configurations are produced from the context: method, class, package, directory, "all in module" (`plugins/junit/src/com/intellij/execution/junit/JUnitConfigurationProducer.java`, `AllInPackageConfigurationProducer.java`, `AbstractAllInDirectoryConfigurationProducer.java`).
- `@Disabled` tests are reported as ignored, not passed (`plugins/junit/src/com/intellij/execution/junit/DisabledConditionUtil.java`); parameterized invocations and `@Nested` classes are tree nodes under their method/class.
- Results stream into the SM test runner tree (`platform/smRunner/src/com/intellij/execution/testframework/sm/runner/SMTestProxy.java`, `GeneralToSMTRunnerEventsConvertor.java`): pass/fail/ignored counts, failure message, stack trace with links to lines (`SMTestLocator`). "Rerun failed tests" reruns exactly the failed leaves.
- The runner ignores surefire's `excludedGroups`: a tagged-out class still runs from the editor.

## jdt.ls / java-test mechanism (installed: jdt.ls 1.62.0, java-test bundle 0.43.1 in Mason, nvim-jdtls `6e9d953`)

- Test discovery: `vscode.java.test.findTestTypesAndMethods` (or the older `vscode.java.test.search.codelens`) on a file URI returns a tree of test items (`fullName`, `testLevel` Class 5 / Method 6, `testKind`, `jdtHandler`, `range`, `children` for methods, nested classes as items).
- Launch arguments: `vscode.java.test.junit.argument` with `{ projectName, testLevel, testKind, testNames }` returns `mainClass` (JDT's `RemoteTestRunner`), `classpath`, `programArguments` with `-port <n>`. nvim-jdtls adds the test-scope classpath from `java.project.getClasspaths`.
- Run: nvim-jdtls (`lua/jdtls/dap.lua` `run`) opens a TCP server, rewrites `-port`, launches through `dap.run` (so P2's build-before-launch, JDK and JUnit-launcher fixes in `nv4j/debug.lua` apply), reads the Eclipse RemoteTestRunner stream (`%TESTS`, `%TESTE`, `%FAILED`, `%ERROR`, `%TRACES`/`%TRACEE`; ignored tests carry an `@Ignore: ` prefix in the `%TESTS` line), then `lua/jdtls/junit.lua` `show`: `vim.diagnostic.set` (namespace `junit`) on the failing line, `✓`/`✗` extmarks, quickfix list `jdtls-tests`, results in dap-repl, `after_test(items, tests)`.
- API it exposes: `test_class`, `test_nearest_method`, `pick_test`, and `M.experimental = { run, fetch_lenses, fetch_launch_args, make_context, make_config }`. No project, package or "failed only" scope.
- Gaps measured (below): `@Disabled` is counted as passed (the parser matches the `@Ignore: ` prefix but drops it); no counts per state; results go to the current buffer only; no rerun of failures.

## Baseline (Task 0, measured)

Through nvim-jdtls's functions (what LazyVim's `<leader>tr`/`<leader>tt` call), result read from `after_test`. Logs: `/tmp/nv4j/logs/test-20261021-210501.log`, `-210721.log`, full run `-210814.log`.

| Case | Today | Result |
|------|-------|--------|
| nearest `totalMultiplies`, first run | 1.5 to 3.2 s | 1 passed (correct) |
| nearest, warm (second run) | 0.80 to 1.0 s | 1 passed; inside the 10 s budget already |
| class `PriceCalculatorTest` | 0.86 to 1.1 s | **6 passed, skipped not counted**: the `@Disabled` `notYet` counted as passed (want 5/0/1); the 3 parameterized invocations and the nested test are reported |
| class `PriceCalculatorFailingTest` | 0.89 to 0.95 s | 1 passed 1 failed; quickfix entry at line 22 with `AssertionFailedError: P3 fixture: fails on purpose`, diagnostic on line 22 (works) |
| project | none | `<leader>tp` runs `mvn test` in a terminal: no results in the editor |
| failed only | none | no API |
| keys | | `<leader>tr` "Run Nearest Test", `<leader>tt` "Run All Test" (runs the class), `<leader>tT` "Run Test" (pick), `<leader>tp` "Run all tests (project build tool)"; `<leader>tf/tl/to/td` unmapped; `<leader>tn` is Nv4J's "New terminal in a tab" (global) |

LazyVim adds the test keys through which-key on `LspAttach`; which-key sets up at `VimEnter`, which a headless check never reaches, so the check reads which-key's queue (`tests/lib/edit.lua` `E.keymap`).

## Decision D21 (summary; full text in 001)

Keep nvim-jdtls's launch path (java-test bundle, `jdtls.dap.experimental`: fetch lenses, launch args, `dap.run` with P2's fixes) and add a thin own result layer in `nv4j/tests.lua`: parse the RemoteTestRunner stream (counts incl. ignored, nested and parameterized names), show failures as `vim.diagnostic` + quickfix (message and frames that jump to the line), a summary notification, `<leader>to` opens the quickfix list. Scopes nearest/class from lenses; failed = rerun the failed method items (one launch, method-level `testNames`); project = one launch per test class found, or one project-level request if `testLevel` 3 works on 0.43.1 (to verify in Task 2). Rejected: a view over surefire XML (`mvn test`): Maven start alone is seconds, it depends on plugin resolution that failed offline in P2 (`specs/features/run.md` m1), it honours `excludedGroups` (the failing class would never run from the editor) and it is Maven only.

## Proposed keys (collision check done in Task 0)

`<leader>tr` nearest (LazyVim's name kept), `<leader>tt` class, `<leader>tp` project (replaces the `mvn test` terminal), `<leader>tf` failed, `<leader>tl` last, `<leader>to` results, `<leader>td` debug nearest, `<leader>tT` pick (LazyVim; since the Task 2 fixes bound by Nv4J, see t2-n). The plan's `<leader>tn` for nearest collides with Nv4J's global "New terminal in a tab" (`config/keymaps.lua`), so nearest stays `<leader>tr`. LazyVim core and the enabled extras map no other `<leader>t*` key (the `test.core` extra is not enabled; its names agree: `tr` nearest, `tt` file, `tl` last, `to` output, `td` debug nearest).

## Test design (`tests/checks/60_tests_runner.lua`)

Cases: `api`, `keys`, `nearest_warm`, `class_counts`, `failure_shown`, `project_counts`, `failed_only` (details in the check header). Expected fixture counts: class 5/0/1, failing class 1/1, project 7/1/1 (the tagged class runs from the editor, as in IntelliJ), failed only 0/1. Until `nv4j.tests` exists the timed cases run through nvim-jdtls so the baseline numbers are measured, not guessed.

Negative controls: n60a (Task 0) drops the `jdtls-tests` quickfix list and the `junit` diagnostics: `failure_shown` FAILs ("quickfix NO entry at line 22 ... diagnostic MISSING"), log `/tmp/nv4j/logs/test-20261021-210751.log`. Plan for Task 2: count `@Disabled` as passed again (parser change reverted) -> `class_counts` FAILs; break the failed-only selection (rerun the whole class) -> `failed_only` FAILs (2 tests); no `on_done` within the timeout -> no result.

## Trial log

| # | Change | Effect | Kept |
|---|--------|--------|------|
| t0-a | Key case with `maparg` only | `<leader>tr`/`<leader>tt` "unmapped" although LazyVim adds them: which-key never set up headless (it waits for `VimEnter`) | replaced |
| t0-b | `require("lazy").load({ plugins = { "which-key.nvim" } })` in the check | still queued (which-key's `setup` defers its load to `VimEnter` when `vim_did_enter == 0`) | reverted |
| t0-c | `E.keymap`: `maparg`, else the which-key queue (buffer or global spec) | `<leader>tr` "Run Nearest Test", `<leader>tt` "Run All Test" found | kept |
| t0-d | n60a negative control (above) | `failure_shown` FAIL | evidence |
| t0-e | surefire alternative for D21: `mvn -o -q test -Dtest='PriceCalculatorTest#totalMultiplies'` (JDK 25, offline, warm `~/.m2`), 2 runs | 4.5 s, 3.1 s, rc 0 (nearest through the bundle: 0.80 to 1.0 s warm); logs `/tmp/nv4j/logs/t0-surefire-{1,2}.log` | evidence: surefire rejected |
| t2-a | java-test commands probed (`/tmp/nv4j/logs/t2-probe1.log`): `vscode.java.test.junit.argument` with `testLevel` 3 (project, `testNames` `{ "demo" }` or `{}`) and 4 (package) | both answer `errorMessage` "The input type of the launch configuration does not exist": project/package level does not work on 0.43.1 (the open item of Task 0, now verified). `testLevel` 5 with 2 class names and 6 with 2 method handlers answer `-testNameFile`: one JVM for a list. `findJavaProjects` + `findTestPackagesAndTypes` list a project's test classes (nested ones as children) | project = one launch per Java project and test kind with every top-level class |
| t2-b | First `nv4j/tests.lua` (`t2-probe2.log`) | nearest 2.4 s first / 0.8 s warm, class 5/0/1 with the 3 invocations (`%TSTTREE` display `[1] quantity=1`) and the nested test, failing class 1/1 with quickfix line 22, project 7/1/1. Wrong: failed-only reran the whole class (1/1): a project run indexes classes only, so no method item was found; the build message said "Building before debug" for a plain run | fixed (t2-c, t2-d) |
| t2-c | Failed-only fetches the method items of the failing files first (`findTestTypesAndMethods`) | 0/1, only `failsOnPurpose` (`t2-probe3.log`) | kept |
| t2-d | `config.nv4j_what` read by P2's adapter wrapper (`nv4j/debug.lua`) for the build message | "Building before test run..." / "test debug"; `40_debug` `build_guard` still sees "Building before debug" (its configs have no label) | kept |
| t2-e | `t2-probe3.log`: debug with a breakpoint, `dap.continue()` straight from the `stopped` listener | the JVM never resumed (nvim-dap had not taken the stop yet), the run hit the 120 s product timeout, and the started-but-unended test was counted as passed | product: an unended test is not counted any more; check: continue once `session.stopped_thread_id` is set (as `40_debug` does). Without a breakpoint the debug run ends in 1.3 s (`t2-probe4.log`, `-probe5.log`) |
| t2-f | Non-compiling test class (`BrokenTest`, `int x = "text"`) and a Maven project without JUnit (`t2-probe3.log`) | build warns "has compile errors; launching anyway", the run reports 0/1 with `java.lang.Error: Unresolved compilation problem` at line 8 in about 1 s; no-JUnit project: "No tests found in PlainTest.java ..." and "No JUnit tests found in nojunit ..." at once (its jdt.ls import took 9 s) | kept |
| t2-g | Check run 1 (`/tmp/nv4j/logs/test-20261022-090506.log`) | debug case timed out (t2-e); `F.restore` wipes the fixture buffers, the next case used a dead buffer | check reopens the buffer after the restore |
| t2-h | Check run 2 (`-090941.log`) | timeout case got "cancelled" instead of "no result within": the timer cancelled the launch first and the launch's own error finished the run | timer finishes the run first, then cancels |
| t2-i | Keys: rebinding at VimEnter (first design) | wrong for a real session: which-key loads at VeryLazy (after VimEnter, `vim_did_enter == 1`), so a VimEnter rebind runs before which-key creates LazyVim's queued keys | replaced by t2-j |
| t2-j | Keys: on attach, LazyVim's queued `<leader>tr`/`<leader>tt` for that buffer are removed from which-key's queue (`_queue`, which-key `3aab214` pinned), then Nv4J's are bound per buffer; when which-key is already loaded its `add()` created LazyVim's keys synchronously and the bind replaces them | `keys_after_whichkey` (which-key loaded, VimEnter fired, queue processed) passes; control n60g fails it | kept |
| t2-k | Check run 3 (`-091135.log`) | which-key's queue processing died on "Invalid buffer id: 1" (specs queued for a buffer the check wiped), so its load never finished | check prunes queued specs of invalid buffers before loading which-key (a headless artifact, see the check comment) |
| t2-l | Check run 4 (`-091309.log`) | 20 of 20 PASS | kept |
| t2-m | Key desc check by pattern only | n60g showed LazyVim's "Run Nearest Test" matches `[Nn]earest`: only `<leader>tt` was reported as overridden | the desc must equal Nv4J's (`nv4j.tests.keys`); n60g then reports both |
| t2-n | Task 2 review fixes (2026-10-27). Keys: `opts.test = false` on LazyVim's java extra (no `<leader>tr/tt/tT` from it, so which-key shows Nv4J's descs) and `<leader>tT` = nvim-jdtls's `pick_test` in `nv4j.tests.keys`; `opts.test = false` also drops the java-test jars from the extra's bundle list, so `opts.jdtls` adds `$MASON/share/java-test/*.jar` back. The which-key `_queue` strip (t2-j) and `M._strip_queued` are removed | `keys`, `keys_after_whichkey`, `test_bundle`, `pick_key` pass; n60g, n60u, n60v fail them. n60u (bundle not added) fails only `test_bundle` and `no_junit_project`: the test runs still pass, jdt.ls keeps the bundle installed in its `-configuration` cache, so `test_bundle` is the case that catches it | kept (replaces t2-j) |
| t2-o | Stream handles: `finish` closed the accepted luv sockets with `s:disconnect` (no such method on a TCP handle, hidden by `pcall`): each stayed open until the JVM's EOF. Now `read_stop` + `close`; `bind`, `listen`, `accept` and `getsockname` results checked, a failure ends the launch with "test stream server: ..." | `stream_closed` (at `on_done` the server and the accepted socket are closed), `stream_bind_error` pass; n60p, n60q fail them | kept |
| t2-p | Lock: taken at the top of `run()` (a discovery lock, replaced by the run in `start()`), released by every refusal (`refuse` with the run's own lock), by an error in a discovery callback (`guard`) and by `finish_run` | `lock_quick_press`: two back-to-back calls, the second refused, one launch; n60r (lock in `start()` only) launches twice | kept |
| t2-q | Discovery bound: `findTestTypesAndMethods`, `findJavaProjects`, `findTestPackagesAndTypes` time out after `M.discovery_timeout_ms` = 15 s (`vim.g.nv4j_test_discovery_timeout_ms`), the request is cancelled, the run ends with "Test discovery failed: no answer from jdt.ls within 15 s (command)" and the lock is released. Not a D13 budget but a bound: measured answers 5 ms to 1.5 s (`no_tests_file`, `no_junit_project` on a project jdt.ls just imported), 15 s leaves room for a busy jdt.ls | `discovery_timeout` (stubbed `client.request` never answers, bound 500 ms: nearest and project end in about 0.5 s with the message, next real run works); n60s (no bound) holds the lock forever | kept |
| t2-r | Raw stream: `p.raw` keeps at most 2 x `M.raw_max` (500) lines (trimmed to the last 500 when it passes 1000), `M._last_raw` the last 500; the whole stream with `vim.g.nv4j_tests_debug = true` | `raw_cap`, `timeout_bounded` (`_last_raw` <= 500); n60t fails `raw_cap` | kept |

## Task 2

Mechanism (D21, one deviation): the java-test bundle commands nvim-jdtls uses (`findTestTypesAndMethods`, `findJavaProjects`, `findTestPackagesAndTypes`, `vscode.java.test.junit.argument`, `java.project.getClasspaths` test scope) are called directly from `nv4j/tests.lua`, and `dap.run` is called with Nv4J's own TCP server and parser. `jdtls.dap.experimental.run` was not reused: it always runs nvim-jdtls's result layer (`junit` namespace, its quickfix list, `print`) besides any callback, which would show two result sets. P2's path still applies to every launch: the `dap.adapters.java` wrapper (refresh + build, message "Building before test run/debug..."), the JUnit launcher swap (`on_config`), the JDT launching gate (client `request` wrapper). The JDK is `javaExec` = the default runtime of `nv4j.jdk.runtimes(root)` (the same rule as `nv4j.run`). Console `internalConsole` (output in the dap-repl, no terminal split per run); `noDebug = true` for runs, `false` for `debug = true`.

Results: `%TSTTREE`/`%TESTS`/`%TESTE`/`%FAILED`/`%ERROR`/`%TRACES` by test id; `@Ignore: ` and `@AssumptionFailure: ` count as skipped; parameterized invocations are separate leaves (display `[n] ...`); a test that started but never ended is not counted. Failures: `vim.diagnostic` (namespace `nv4j_tests`) at the first stack frame in the test's class, quickfix list "Nv4J tests: <counts> (<label>)" with the message entry then one entry per stack frame that is a project file (`src/*/java` of the root or one module level down), skipped tests as `W` entries; sign extmarks `✓`/`✗`/`○` on the method lines of loaded buffers (after a project run they come a moment later, the method lines are fetched then); a summary notification. The whole run is bounded (`vim.g.nv4j_test_timeout_ms`, default 120 s): then the session is disconnected and "no result within ..." is shown. A second run while one is running is refused with a message. The JVM's dap session is disconnected 3 s after its results if still alive.

Keys (D21/005): `<leader>tr` nearest, `<leader>tt` class, `<leader>tp` project (replaces the `mvn test` terminal), `<leader>tf` failed, `<leader>tl` last, `<leader>to` results (quickfix), `<leader>td` debug nearest; global from `config/keymaps.lua`, per Java buffer from `plugins/java.lua` on attach (t2-j). `<leader>tT` stays LazyVim's (nvim-jdtls's pick, its own result layer).

### Cases (`60_tests_runner`, 29)

`attached`, `api`, `keys` (8 keys bound in the buffer with Nv4J's desc, no LazyVim test key in the buffer or globally; `<leader>tn` still the terminal), `test_bundle`, `pick_key`, `raw_cap`, `nearest_warm`, `stream_closed`, `lock_quick_press`, `stream_bind_error`, `discovery_timeout`, `class_counts`, `file_scope`, `nearest_param`, `nearest_nested`, `failure_shown`, `project_counts`, `failed_only`, `last_again`, `results_panel`, `debug_nearest`, `broken_class`, `no_tests_file`, `no_junit_project`, `timeout_bounded`, `keys_after_whichkey`, `fixture_restored` (details in the check header). Every run case asserts, besides the counts, a RemoteTestRunner launch seen by nvim-dap's `on_config` during the run and Nv4J's quickfix title with the same counts (carried review item a): a stub cannot pass them.

### Negative controls (product changed for one run, reverted; `cmp` with the saved file after each)

| # | Change | Cases that FAIL | Log |
|---|--------|-----------------|-----|
| n60b | `run` replaced by a stub that calls `on_done` with the expected counts, nothing launched | all 15 run cases (launches 0, no Nv4J quickfix) | `/tmp/nv4j/logs/test-20261022-091448.log` |
| n60c | `run` delegates to nvim-jdtls (`test_nearest_method`/`test_class`, counts from `after_test`) | all 15 run cases (`class_counts` 6/0/0, no Nv4J title, no `nv4j_tests` diagnostic, no ✓ sign; no-tests cases wait 150 s with no message) | `-091534.log` |
| n60d+e+g+j+k+m+o | one run: `@Ignore:` not recognised (d), failed-only reruns classes (e), no queue strip (g), timer x1000 (j), `refuse` silent (k), `results()` without `copen` (m), `last` refused (o) | `class_counts`, `file_scope`, `project_counts` (d: 6/0/0, 8/1/0); `failed_only` (e: 1/1); `keys_after_whichkey` (g); `timeout_bounded` (j); `no_tests_file`, `no_junit_project` (k: message MISSING); `results_panel` (m); `last_again` (o) | `-092405.log` |
| n60h+l+n | one run: no finish on `%RUNTIME` (h), failure message dropped (l), nearest always the class (n) | `nearest_warm`, `nearest_param`, `nearest_nested`, `debug_nearest`, `timeout_bounded` (n: 5/0/1); `failure_shown`, `broken_class` (l). h alone breaks no case: finishing on `%RUNTIME` is defensive (EOF follows) | `-092457.log` |
| n60g | no queue strip (after t2-m) | `keys_after_whichkey`: `<leader>tr=Run Nearest Test, <leader>tt=Run All Test` | `-092630.log` |
| n60f | `bind` a no-op | `keys` (5 unmapped, tr/tt queued LazyVim keys), `keys_after_whichkey` | `-092743.log` |
| n60p+q+t+v | one run (t2-n..r): sockets closed with `disconnect` again (p), `bind` result ignored (q), no raw cap (t), `<leader>tT` left out of `nv4j.tests.keys` (v) | `stream_closed` (p: "1 still open"); `stream_bind_error` (q: the error is "no port after bind", not the bind); `raw_cap` (t: 5005 of 5005 kept); `keys`, `pick_key`, `keys_after_whichkey` (v: `<leader>tT` not bound) | `/tmp/nv4j/logs/test-20261027-203445.log` |
| n60r | lock set in `start()` only (not in `run()`) | `lock_quick_press`: second press not refused, launches 2 | `-203602.log` |
| n60s | discovery bound ignored | `discovery_timeout` (no result in 5 s, lock held) and every later run case ("A test run is in progress (finding the tests)"): the bug itself | `-203701.log` |
| n60g (t2-n) | `opts.test = false` removed (LazyVim's test keys back) | `keys_after_whichkey`: `<leader>tr=Run Nearest Test`, `<leader>tt=Run All Test`, `<leader>tT=Run Test` (the headless `keys` case runs before which-key creates its queued keys) | `-203755.log` |
| n60u | java-test jars not added back in `opts.jdtls` | `test_bundle` (0 java-test jars), `no_junit_project` | `-203855.log` |
| n60w (fix wave S-I1) | dap session name per run again (`#<run>`), not per launch (`#<run>.<n>`) | `launch_names` (both sessions named `... #6`; launch 2 DISCONNECTED by launch 1's reap, as the reviewer described) | `/tmp/nv4j/logs/test-20261029-095300.log` |
| n60x (fix wave S-M3) | the run timeout backstop's body without `pcall` | `timeout_handler_error` (lock HELD, no result) and every later run case ("A test run is in progress"): the bug itself | `-095300.log` |

Deterministic twins: `stream_closed` reads the handles inside `on_done`, which runs in the same callback that read `%RUNTIME` (before the JVM's EOF can be read); `lock_quick_press` makes both calls synchronously, so the second always lands while the first is in its asynchronous discovery; `stream_bind_error` and `discovery_timeout` stub the failure (`vim.uv.new_tcp`, `client.request`) instead of waiting for a real one. `timeout_bounded` forces the bound with a 300 ms product timeout (instead of a stuck JVM); `keys_after_whichkey` replays the which-key load order headless (lazy load + VimEnter) instead of waiting for a real VeryLazy.

Fix wave after the final review (2026-10-29): (S-I1) the dap session of a launch is named `Nv4J tests: <label> #<run>.<n>` (n = the launch's index in the run); the reap of launch n (3 s after its stream ended) matches that exact name, the run timeout handler matches `#<run>.<digits>`. Before, every launch of a run (a project run with several Java projects or test kinds, a failed rerun with a method and a class group) had the same name, and the reap of launch n could terminate launch n+1's test JVM if its session had registered by then. Case `launch_names`: one run with two launches (`dap.run` and `dap.sessions` stubbed, a fake JVM connecting to the stream server; launch 2's stream is held open past launch 1's reap): names differ, launch 1 reaped, launch 2 still connected 3.8 s after launch 1's results. (S-M3) the run timeout callback runs its body under `pcall`: on an error the run ends with "run timeout handler failed: ..." (on_done still called, also when `finish_run` itself throws part-way: `run.on_done_called`), `running` is cleared, an ERROR notification names it. Case `timeout_handler_error` (collect made to throw by putting a number in the run's parsers; timeout 700 ms).

### Final runs

Three consecutive runs 20/0 (`/tmp/nv4j/logs/test-20261022-092842.log`, `-092935.log`, `-093026.log`) and the full run 20/0 (`-093117.log`); numbers in `specs/005-p3-tests-scaffold-refactor.md` "Task 2" and the README (Capabilities: Tests).

### Open items

- TestNG is not run by Nv4J's runner (a message points to `<leader>tT`, nvim-jdtls). JUnit 4 goes through the same path (test kind 1) but no fixture covers it.
- Project scope runs one JVM per jdt.ls Java project and test kind; a multi-module project was not measured. Gradle not tested.
- Frames are resolved to files under `src/*/java` of the root and one module level down; deeper modules show the message entry without frames.
- Stdout of the tests goes to the dap-repl only (`internalConsole`), not into the results.
- (fixed, t2-n) The which-key queue strip is gone: LazyVim's test keys are off (`opts.test = false`). The check still prunes queued which-key specs of wiped buffers before loading which-key (t2-k, a headless artifact for LazyVim's extract keys).
- `<leader>to` is the quickfix list (failures and skipped tests), not a tree of every test as IntelliJ's panel.
