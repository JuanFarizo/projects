# 005 - P3: tests runner, scaffolding, refactors, async import

Status: Task 0 done (research, fixture, decisions D21 to D24, four failing checks). Tasks 1 to 5 not started. Plan: `docs/superpowers/plans/2026-10-21-nv4j-p3-tests-scaffold-refactor.md`. Does not contradict `001-architecture.md`; decisions D21 and later live in its decisions table.

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
