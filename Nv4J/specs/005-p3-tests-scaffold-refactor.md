# 005 - P3: tests runner, scaffolding, refactors, async import

Status: Task 0 done (research, fixture, decisions D21 to D24, four failing checks). Task 1 done (async import, frecency vs project ranking, dirty-fixture guard; `63_async_import` passes, see "Task 1"). Task 2 done (test runner; `60_tests_runner` passes, see "Task 2"). Task 3 done (scaffolding; `61_scaffold` passes, see "Task 3"). Task 4 split by the user into 4a-4e: 4a done (rename class and rename package, `specs/features/refactors.md` "Task 4a"; `62_refactor` 26 PASS, 10 FAIL after fix round 2: the FAILs are the pending-by-design lines and cases of move, inline, change signature, safe delete, Tasks 4b-4e); 4b-4e and Task 5 not started. Plan: `docs/superpowers/plans/2026-10-21-nv4j-p3-tests-scaffold-refactor.md`. Does not contradict `001-architecture.md`; decisions D21 and later live in its decisions table.

## Goal

A daily workflow close to IntelliJ for tests (nearest, class, project, failed, results in the editor), scaffolding (package, class kinds, Spring stereotypes, test class for a class) and refactors (rename with file move, move, rename package, inline, change signature, safe delete), plus the P1 follow-ups: asynchronous import on accept and project ranking above blink's frecency.

## Budgets (set at plan start, not to be weakened)

| Metric | Budget | Check |
|--------|--------|-------|
| Accept a completion: item text inserted | <= 100 ms | `63_async_import` `accept_first`, `accept_second`, `stub_slow` |
| Its import present after the accept, never lost or duplicated | <= 1.5 s | same |
| Run nearest test, result visible (warm) | <= 10 s | `60_tests_runner` `nearest_warm` |
| Scaffold: file on disk, opened, right `package` line | <= 300 ms | `61_scaffold` `kind_*`, `nested_name`, `test_for` |
| Rename/move/inline/change signature applied, references and imports right, build clean (jdt.ls, 3 s) | <= 2 s | `62_refactor` |
| Every refactor undoable with one `u` per buffer | yes | `62_refactor` `rename_class_undo` (Task 4 adds the others) |
| P1/P2 budgets | unchanged (`001`) | checks 00 to 52 |

## Decisions

- D21 (test results UI), D22 (scaffolding entry), D23 (refactor surface), D24 (async import mechanism): `001` decisions table, with the reasons; details and trials in the feature specs below.

## Reference repos (read only, `~/.cache/nv4j/`, pinned)

| Repo | Commit | Sparse set extended in Task 0 |
|------|--------|-------------------------------|
| `intellij-community` | `b633034bb` | `java/java-impl/src/com/intellij/ide/actions/`, `java/java-impl/resources/fileTemplates/`, `java/java-impl/src/com/intellij/testIntegration/`, `java/java-impl-refactorings/src/com/intellij/refactoring/{rename,move,inline,changeSignature,safeDelete}/`, `plugins/junit/src/com/intellij/execution/junit/`, `platform/smRunner/src/com/intellij/execution/testframework/sm/runner/` |
| `eclipse.jdt.ls` | `b52e20a` | `org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/text/`, `.../internal/corext/` (handlers and corrections were already there) |
| `eclipse.jdt.core` | `cd40048` | none: the refactoring engine (`org.eclipse.jdt.internal.corext.refactoring`) is in `org.eclipse.jdt.core.manipulation` (eclipse.jdt.ui repo); the installed jar `org.eclipse.jdt.core.manipulation_1.26.0` is what runs |
| installed | jdt.ls 1.62.0, java-test bundle 0.43.1 (Mason), nvim-jdtls `6e9d953`, blink.cmp v1.10.2 `78336bc`, which-key `3aab214` | |

Nothing copied from any of them.

## Fixture (extended in Task 0)

`tests/fixtures/demo`, still `mvn -q compile` green on JDK 25 (run.sh) and `mvn test` green (7 run, 1 skipped, BUILD SUCCESS, measured offline):

- `src/main/java/demo/billing/Invoice.java`, `PriceCalculator.java` (`total`, private `gross`, unused `legacyTotal`), `src/main/java/demo/shop/Checkout.java` (call sites and imports in another package): refactor targets, `specs/features/refactors.md`. No `main` method, no Spring annotation, so `40_debug` `configs` (3 main classes) and `52_spring_nav` `picker` (17 entries) are unchanged.
- `src/test/java/demo/billing/PriceCalculatorTest.java`: plain, `@ParameterizedTest` (3 invocations), `@Nested`, `@Disabled` (5 passing runs, 1 skipped).
- `src/test/java/demo/billing/PriceCalculatorFailingTest.java`: 1 pass, 1 failure on purpose, `@Tag("nv4j-failing")`. Kept out of the normal build: run.sh compiles main only (`mvn -q compile`), and `pom.xml` sets surefire `<excludedGroups>nv4j-failing</excludedGroups>` so `mvn test` stays green. The editor runner (java-test bundle) ignores surefire configuration and runs it, as IntelliJ would: that is the failure `60_tests_runner` needs. No other check runs tests except `40_debug` (one method of `GreetingPropertiesTest`).
- `tests/lib/fixture.lua` (new helper): snapshot/restore of `src/` for checks that change files on disk (61, 62), with jdt.ls told (`didChangeWatchedFiles`, refresh, build) so a rename never survives into the next session.
- `tests/lib/edit.lua` `E.keymap`: a mapping as a user session has it (which-key's queued buffer keys included; which-key sets up at `VimEnter`, never reached by a headless check).

## Baseline (Task 0, measured; details per feature)

| Feature | Today | Spec |
|---------|-------|------|
| Tests | nearest via nvim-jdtls (LazyVim `<leader>tr`) 0.80 to 1.0 s warm, 1.5 to 3.2 s first; class run counts `@Disabled` as passed (6 instead of 5/0/1); failing assertion shown in quickfix and diagnostics; no project (only `mvn test` in a terminal), no failed-only, no last/results keys | `specs/features/tests-runner.md` |
| Scaffolding | BufNewFile template fills a buffer in 26 to 61 ms but only an empty file is on disk (nvim-jdtls writes new buffers on attach); no annotation, package, dotted name or test-for-class; no `<leader>jn` | `specs/features/scaffolding.md` |
| Refactors | rename class 440 to 761 ms, move 663 to 682 ms, inline 101 to 144 ms, change signature 364 to 385 ms (interactive float) all work and build clean; package rename fails (`<leader>cr` refused, neo-tree folder rename leaves the old `package` line); no safe delete | `specs/features/refactors.md` |
| Async import | text inserted after 786 to 802 ms (first `List`), 405 to 438 ms (`HashMap`), 875 to 891 ms (800 ms stubbed resolve); imports never lost | `specs/features/async-import.md` |

Also measured: `<leader>tT` is nvim-jdtls's `pick_test` (a `vim.ui.select` of the file's tests, same runner, same result layer).

## Keys (proposed in Task 0, collision check done)

| Key | Meaning | Collision check |
|-----|---------|-----------------|
| `<leader>tr` / `tt` / `tp` / `tf` / `tl` / `to` / `td` / `tT` | test nearest / class / project / failed / last / results / debug nearest / pick | `tr`, `tt`, `tT` are LazyVim's java extra (kept names); `tp` is Nv4J's `mvn test` terminal (replaced); `tf`, `tl`, `to`, `td` free; the plan's `<leader>tn` for nearest collides with Nv4J's global "New terminal in a tab", so nearest stays `tr` |
| `<leader>jn` (`jt`) | new Java file/package (test for this class) | `<leader>j` unused (LazyVim core, enabled extras, Nv4J; `61_scaffold` `key` lists none) |
| `<leader>jm` / `ji` / `js` / `jd` / `jr` (`jp`) | move / inline / change signature / safe delete / refactor menu (rename package) | same group, unused; `<leader>cr` stays Rename and `<leader>cR` Rename File (LazyVim); a `<leader>cr` prefix would delay rename |

## Rulings in Task 0 (cost if wrong)

- Nearest stays `<leader>tr` (not the plan's `<leader>tn`, taken by "New terminal in a tab"). Cost: none known; the user's terminal key is kept.
- Refactor keys live under `<leader>j` instead of a `<leader>cr` group. Cost: one more group to learn; rename itself unchanged.
- The failing test class lives in the main fixture, tagged out of `mvn test` by surefire, instead of a separate fixture dir. Cost: a user running `mvn test` on the fixture does not see it; the editor runner always runs it (project counts 7/1/1).
- `60_tests_runner` project counts expect the tagged class to run (IntelliJ ignores `excludedGroups` too). Cost: if Task 2 chose to honour surefire tags, the expected counts change (decide there, not silently).
- Checks 60 to 63 report today's paths through the same cases until the `nv4j.*` modules exist, so the baseline numbers are measured; passing baseline cases (nearest warm, failure shown, rename class, move, inline, change signature, compiles) are honest: today's tool already meets those budgets.

## Task 0 full run

Full `tests/run.sh` before the Task 0 commit, log `/tmp/nv4j/logs/test-20261021-210814.log` (exit 1, only from the four new checks):

- P1/P2 unchanged, 223 PASS 0 FAIL: `DONE 00_boot 11 0`, `01_jdtls_ready 2 0`, `10_completion_latency 17 0`, `11_completion_ranking 26 0`, `12_usage_index 7 0`, `20_java25 10 0`, `30_diagnostics 24 0`, `31_imports 10 0`, `32_code_actions 28 0`, `40_debug 16 0`, `41_run 27 0`, `50_spring_ls 13 0`, `51_spring_completion 20 0`, `52_spring_nav 12 0`. The new fixture classes did not move `@` `RestController` (rank 1) or the debug main-class count.
- `DONE 60_tests_runner 3 5`: FAIL `api`, `keys`, `class_counts` (6 passed, `@Disabled` counted as passed), `project_counts`, `failed_only` (no in-editor run). PASS `nearest_warm` (804 ms warm, 3131 ms first), `failure_shown` (982 ms).
- `DONE 61_scaffold 3 14`: FAIL `api`, `key`, 8 template kinds (25 to 67 ms but only an empty file on disk), `kind_annotation`, `package`, `nested_name`, `test_for` (not offered). PASS `compiles`, `fixture_restored`.
- `DONE 62_refactor 8 5`: FAIL `api`, `keys`, `rename_package` (old package line left), `safe_delete_blocked`, `safe_delete_free` (no action). PASS `rename_class` 415 ms, `rename_class_undo`, `move_class` 734 ms, `inline_method` 140 ms, `inline_variable` 128 ms, `change_signature` 375 ms, `fixture_restored`.
- `DONE 63_async_import 1 3`: FAIL `accept_first` (text after 715 ms), `accept_second` (373 ms), `stub_slow` (878 ms). Imports present each time.

Fixture left unchanged on disk after the run (`git status` clean for `tests/fixtures`).

Negative controls run in Task 0 (product or behaviour stubbed for one run, reverted): n1 (`63`, `resolve_timeout_ms = 50`, imports lost -> FAIL, `/tmp/nv4j/logs/test-20261021-205435.log`), n60a (`60`, results kept out of quickfix/diagnostics -> `failure_shown` FAIL, `-210751.log`), n62a (`62`, workspace edits limited to the current buffer -> rename/move/change signature FAIL, `-210328.log`). The template baseline is the control for `61`'s "saved" condition.

## Task 1 (async import, frecency vs project ranking, dirty-fixture guard)

Details, cases, negative controls n2 to n12 and trials t1-a to t1-l: `specs/features/async-import.md`. Three consecutive `63_async_import` runs: `DONE 63_async_import 16 0` each (`/tmp/nv4j/logs/test-20261021-215442.log`, `-215506.log`, `-215531.log`); text in 45 to 51 ms, import 317 to 871 ms, `@` `RestController` 1 with a polluted frecency database (blink's own order 27).

Full `tests/run.sh` before the Task 1 commit, log `/tmp/nv4j/logs/test-20261021-215600.log` (exit 1, only from 60, 61, 62, which Tasks 2 to 4 build):

- P1/P2 unchanged, 223 PASS 0 FAIL: `DONE 00_boot 11 0`, `01_jdtls_ready 2 0`, `10_completion_latency 17 0`, `11_completion_ranking 26 0`, `12_usage_index 7 0`, `20_java25 10 0`, `30_diagnostics 24 0`, `31_imports 10 0`, `32_code_actions 28 0`, `40_debug 16 0`, `41_run 27 0`, `50_spring_ls 13 0`, `51_spring_completion 20 0`, `52_spring_nav 12 0`. Budgets: cold first 46 ms (400), worst warm p95 50 ms (150).
- `DONE 63_async_import 16 0` (text 47/50/50 ms, import 736/347/936 ms).
- Still failing as expected, same cases as Task 0: `DONE 60_tests_runner 3 5`, `DONE 61_scaffold 3 14`, `DONE 62_refactor 8 5`.

Dirty-fixture guard: `tests/lib/fixture_guard.sh`, called from `run.sh` before the build (`NV4J_FIXTURE_DIRTY=fail|restore|allow`); tests in `/tmp/nv4j/guard-test.log` (scratch git copy) and `/tmp/nv4j/guard-runsh.log` (real fixture, untracked probe: exit 3 before any build).

### Task 1 fix round 1 (review B1, M1)

jdt.ls's import ranges are never applied any more (only the statement, placed by Nv4J in its importOrder group); details, 12 new cases, controls r2 to r19 and the 50-run real-resolve loop (50/50, lossy jdt.ls edit seen in 36 of 50) in `specs/features/async-import.md`. `63_async_import` now 28 cases: three consecutive runs 28/0 (`/tmp/nv4j/logs/test-20261021-222940.log`, `-223017.log`, `-223053.log`).

Full `tests/run.sh` after the fix, log `/tmp/nv4j/logs/test-20261021-224104.log` (exit 1, only from 60, 61, 62): P1/P2 223 PASS 0 FAIL (same per-check counts as above), cold first 42 ms, worst warm p95 42 ms; `DONE 63_async_import 28 0`; `60_tests_runner 3 5`, `61_scaffold 3 14`, `62_refactor 8 5` as before. The full run just before it (`-223221.log`) had `20_java25 6 1`: `attached` failed after Neovim reported `LSP[jdtls]: Error INVALID_SERVER_JSON: "Expected colon but found invalid token at character 65537"` (a transport glitch at the 64 KiB boundary, not in completion code); `20` alone passed 10/0 right after (`-224040.log`), then the full rerun above.

## Task 2 (test runner)

Details, mechanism (D21 with one deviation: java-test commands called directly, not through `jdtls.dap.experimental.run`), 20 cases, negative controls n60b to n60o and trials t2-a to t2-m: `specs/features/tests-runner.md`. Verified: java-test 0.43.1 refuses project and package `testLevel` (`/tmp/nv4j/logs/t2-probe1.log`), so project = one JVM per Java project and test kind with every test class (`-testNameFile`). Keys as ruled in Task 0: `<leader>tr`/`tt`/`tp`/`tf`/`tl`/`to`/`td`; `<leader>tp` no longer runs `mvn test` in a terminal.

Three consecutive `60_tests_runner` runs: `DONE 60_tests_runner 20 0` each (`/tmp/nv4j/logs/test-20261022-092842.log`, `-092935.log`, `-093026.log`): nearest warm 690/854/891 ms (budget 10 s), first 2753/2189/2212 ms, class 898/913/892 ms, failure shown 714/711/614 ms, project 754/965/2118 ms, failed only 628/836/921 ms, debug with a breakpoint 897/1100/1267 ms, non-compiling class 1980/1710/1995 ms.

Full `tests/run.sh` before the Task 2 commit, log `/tmp/nv4j/logs/test-20261022-093117.log` (exit 1, only from 61 and 62, which Tasks 3 and 4 build):

- P1/P2 unchanged, 223 PASS 0 FAIL: `00_boot 11 0`, `01_jdtls_ready 2 0`, `10_completion_latency 17 0`, `11_completion_ranking 26 0`, `12_usage_index 7 0`, `20_java25 10 0`, `30_diagnostics 24 0`, `31_imports 10 0`, `32_code_actions 28 0`, `40_debug 16 0`, `41_run 27 0`, `50_spring_ls 13 0`, `51_spring_completion 20 0`, `52_spring_nav 12 0`.
- `60_tests_runner 20 0` (nearest warm 912 ms, first 3072 ms, project 1045 ms, debug 1185 ms), `63_async_import 28 0`.
- Still failing as expected: `61_scaffold 3 14` (same cases as Task 0). `62_refactor 7 6`: the expected 5 plus `change_signature` ("build NOT clean": Checkout.java still reported the old `total(Invoice)` errors after the 3 call sites were rewritten). `62_refactor` alone right after: `8 5`, `change_signature` PASS build clean (`/tmp/nv4j/logs/test-20261022-093834.log`). Task 2 changed nothing in the refactor path (its `nv4j/debug.lua` change is a build-message label); recorded as a flake for Task 4 to look at (the build-clean wait after a change signature).

## Task 3 (scaffolding)

Details, templates, 27 cases, negative controls n61a to n61r and trials t3-a to t3-g: `specs/features/scaffolding.md`. Built as D22: `nvim/lua/nv4j/scaffold.lua` is the one template source (`util/java_scaffold.lua` removed; `:e Foo.java` BufNewFile and neo-tree `file_added` call it and now also leave the template on disk). Keys `<leader>jn` (new) and `<leader>jt` (test of this class), group `<leader>j` "java". `compiles` (Task 0 case) was too weak: it passed with a wrong package line (n61a, trial t3-c); it now waits for an explicit build and reads the error count after it.

Three consecutive `61_scaffold` runs: `DONE 61_scaffold 27 0` each (`/tmp/nv4j/logs/test-20261026-093126.log`, `-093142.log`, `-093158.log`): type kinds 28 to 112 ms (budget 300 ms), other created files 28 to 72 ms, package 1 to 3 ms, slowest file's jdt.ls error state 1.0 to 1.1 s (budget 3 s).

Full `tests/run.sh` before the Task 3 commit, log `/tmp/nv4j/logs/test-20261026-092355.log` (exit 1, only from 62, which Task 4 builds): `00_boot 11 0`, `01_jdtls_ready 2 0`, `10_completion_latency 17 0`, `11_completion_ranking 26 0`, `12_usage_index 7 0`, `20_java25 10 0`, `30_diagnostics 24 0`, `31_imports 10 0`, `32_code_actions 28 0`, `40_debug 16 0`, `41_run 27 0`, `50_spring_ls 13 0`, `51_spring_completion 20 0`, `52_spring_nav 12 0`, `60_tests_runner 20 0`, `61_scaffold 27 0`, `62_refactor 8 5` (the expected Task 0 failures), `63_async_import 28 0`. That run measured `compiles*` with the earlier "last publish" timing (2.0 s, trial t3-e); the check was changed after it and run 3 times alone.

