# Feature: Test runner

Priority: P3. Status: Task 0 done (research, fixture, failing check `60_tests_runner`); Task 2 builds it. Decision: D21 in `specs/001-architecture.md`. Spec: `specs/005-p3-tests-scaffold-refactor.md`. Check: `tests/checks/60_tests_runner.lua`. Product (Task 2): `nvim/lua/nv4j/tests.lua`, keys in `nvim/lua/config/keymaps.lua`.

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

`<leader>tr` nearest (LazyVim's name kept), `<leader>tt` class, `<leader>tp` project (replaces the `mvn test` terminal), `<leader>tf` failed, `<leader>tl` last, `<leader>to` results, `<leader>td` debug nearest, `<leader>tT` pick (LazyVim). The plan's `<leader>tn` for nearest collides with Nv4J's global "New terminal in a tab" (`config/keymaps.lua`), so nearest stays `<leader>tr`. LazyVim core and the enabled extras map no other `<leader>t*` key (the `test.core` extra is not enabled; its names agree: `tr` nearest, `tt` file, `tl` last, `to` output, `td` debug nearest).

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
