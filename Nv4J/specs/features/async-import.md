# Feature: Asynchronous import on completion accept (P1 follow-up)

Priority: P3 (P1 follow-up). Status: built in Task 1 (`63_async_import` 28 cases pass, fix round 1 included; Task 0: research and the failing check). Decision: D24 in `specs/001-architecture.md`. Spec: `specs/005-p3-tests-scaffold-refactor.md`. Check: `tests/checks/63_async_import.lua` (`31_imports` and `11_completion_ranking` must stay green). Product (Task 1): `nvim/lua/nv4j/completion.lua`, `nvim/lua/plugins/blink.lua`.

## Budget

Accepting a completion returns control with the item text inserted <= 100 ms; the import is in the buffer <= 1.5 s after the accept, never lost, never duplicated.

## IntelliJ behaviour (reference, `intellij-community` at `b633034bb`)

The import is added synchronously by the insert handler (`java/java-impl/src/com/intellij/codeInsight/completion/JavaClassNameInsertHandler.java`: `PsiTypeLookupItem.addImportForItem`) because the PSI is in-process; javadoc for the popup is computed separately and lazily. Insert and import are one undoable command.

## jdt.ls / blink mechanism (installed: jdt.ls 1.62.0; blink.cmp v1.10.2 `78336bc`)

- jdt.ls sends the import (`additionalTextEdits`) only in `completionItem/resolve`, the same request that renders the javadoc: 0.4 to 0.8 s for well documented types (P1, `specs/features/diagnostics-imports-actions.md`).
- blink's accept (`lua/blink/cmp/completion/accept/init.lua`): `sources.resolve(ctx, item):timeout(resolve_timeout_ms):catch(return item)`, then `apply_item` (text edit + additionalTextEdits together), then `sources.execute` and only then the callback. Nv4J sets `resolve_timeout_ms = 1500` (`plugins/blink.lua`), so the text waits for resolve.
- The timeout does not cancel the resolve: `task:timeout` only rejects the outer task (`lua/blink/cmp/lib/async.lua`); the provider's cached resolve task (`sources/lib/provider/init.lua` `resolve_cache`, per context id) keeps running and completes later with the edits. That late result is the hook for D24.
- `lsp:execute` (`sources/lsp/init.lua`) runs the item's `command` (jdt.ls: `java.completion.onDidSelect`) through `client:exec_cmd` and calls back after the server answers; jdt.ls answers it after the pending resolve, so blink's accept callback (menu/signature re-show) waits about 0.4 to 0.6 s even when the text is already in (measured, n1 below). It does not block typing.

## Baseline (Task 0, measured)

`63_async_import`, accept through blink's own accept as in `31_imports`, the typed prefix polled every 1 ms (logs `/tmp/nv4j/logs/test-20261021-205415.log` and the full run in `005`):

| Case | Text inserted | Import | blink callback |
|------|---------------|--------|----------------|
| `accept_first` (`Lis` -> `List`, first accept of the session) | 786 to 802 ms | with the text | 776 to 802 ms |
| `accept_second` (`HashMa` -> `HashMap`, right after) | 405 to 438 ms | with the text | 400 to 438 ms |
| `stub_slow` (every resolve answer held 800 ms) | 875 to 891 ms | with the text, once | 876 to 891 ms |

All three FAIL the 100 ms budget; imports are never lost today (that is what the 1.5 s wait buys).

## Decision D24 (summary; full text in 001)

Accept no longer waits: `resolve_timeout_ms` drops to a value that keeps the insert under 100 ms (about 50 ms: measured 46 to 51 ms insert in n1), and Nv4J applies the import itself when the item's resolve, which blink keeps running, completes after the accept. Hook: a wrapper around blink's accept function (`package.loaded["blink.cmp.completion.accept"]`, used by `list.accept` and by the checks) that, for Java `jdtls` items applied without `additionalTextEdits`, takes the provider's cached resolve task and on completion applies its `additionalTextEdits` once with `vim.lsp.util.apply_text_edits`, guarded: buffer still valid and loaded, the import not already present, the edit range inside the import block and its text unchanged; otherwise drop it (never corrupt). Joined to the accept's undo block when no other change happened in between (`undojoin`), so one `u` removes both. No second resolve request (jdt.ls work not doubled). Rejected: keep the 1.5 s wait (fails the budget); `java.completion.lazyResolveTextEdit` (P1 trial: no effect on this cost); our own completion source (rewrites blink's LSP source for one field).

## Test design (`tests/checks/63_async_import.lua`)

Cases: `attached`, `accept_first`, `accept_second` (no pause after the first; the first statement is finished as a user would, else `List HashMa` parses as a declaration and jdt.ls offers variable names), `stub_slow` (deterministic twin: resolve answers held 800 ms, fails on every run while accept waits for resolve, 003 P2 lesson). The first accept is pinned 1 s after ServiceReady (D13). Review Focus 1 cases (buffer edited, cursor moved, buffer closed, undo between accept and late resolve) are Task 1's, on the stubbed resolve.

Negative control n1 (Task 0): `resolve_timeout_ms = 50` without any late apply (product file edited for one run, reverted, `git diff` clean): text in 46 to 51 ms but every case FAILs with "import MISSING", including `stub_slow` (callback 75 ms). Log `/tmp/nv4j/logs/test-20261021-205435.log` (earlier variant of the check: `-205210.log`). So the check fails both for a slow insert and for a lost import.

## Trial log

| # | Change | Effect | Kept |
|---|--------|--------|------|
| t0-a | first check measured blink's accept callback | n1 showed callback 788 ms with timeout 50 ms: the callback also waits for `java.completion.onDidSelect`, not what the user sees | replaced |
| t0-b | measure the moment the typed prefix becomes the item text (1 ms polling) | insert time separated from callback time | kept |
| t0-c | typed `List` (prefix = item text) | no visible change to detect | typed `Lis` |
| t0-d | read the typed line by its index | the import lands above it in the same apply: line moved, never seen | extmark on the typed line |
| t0-e | `List` line left unfinished before the `HashMa` accept | `HashMa` menu offered `hashMaList` (variable name of `List HashMa`) | first statement completed (`List<String> a = null;`) |
| t0-f | n1 negative control (above) | imports lost -> FAIL | evidence |

## Task 1: what was built

- `nvim/lua/plugins/blink.lua`: `completion.accept.resolve_timeout_ms` 1500 -> 50; `init` calls `require("nv4j.completion").install_async_import()`, which installs a `package.preload` for `blink.cmp.completion.accept` (blink's `list.accept` and the checks require it at call time) that loads blink's file and returns `M.wrap_accept(original)`.
- `nvim/lua/nv4j/completion.lua` `wrap_accept` (design after fix round 1, see below): for a Java buffer and a jdt.ls item without (mixed) `additionalTextEdits` it records the accepted row, an extmark spanning the accepted line (left gravity start, right gravity end) and, through `nvim_buf_attach` `on_lines`, the changedtick right after blink's own edit of that line; calls blink's accept; then takes `require("blink.cmp.sources.lib").resolve(ctx, item)` (same context and item: blink's cached task, no second request) and, when it completes, runs `late_import` scheduled. A watchdog (`ASYNC_WAIT_MS`, 10 s) drops a resolve that never answers; every path clears the extmark.
- `M.take_imports` (called from `transform_lsp`, which blink also runs on the resolved item): import-only `additionalTextEdits` of a jdt.ls item move to `nv4j_imports`, so **blink never applies jdt.ls's import ranges**, not even when the resolve came in time (doc popup). Mixed edits stay for blink, as in P1.
- `late_import` guards, in order: resolve carries import edits (else `none`); buffer valid and loaded (else `dropped`, "buffer closed"); not `module-info.java`; every edit's non-blank text is `import ...;` (else `dropped`); only the import **statements** are taken; those already among the header's imports (comment-aware scan: import text in `//` or `/* */` comments does not count) are skipped (`present`: never a duplicate); the extmark region still contains the accepted word (else `dropped`: the accept was undone); then each statement is inserted by `place_import` at a place computed from the **current** buffer: `java.completion.importOrder` group (read from the jdtls client settings, defined once as `M.IMPORT_ORDER` and sent by `plugins/java.lua`), sorted within the group, a blank line between groups, statics last, after `package` when there are no imports, at the top of the code below any leading license comment when there is no package; `import module` lines are left alone. `undojoin` when the changedtick is still the one after blink's edit (one `u` removes item and import, also across the undo boundary <Esc> makes; otherwise the import is its own undo step). Outcomes: `async_log` (last 20) / `async_count`; outcomes other than applied/present also go to `vim.notify` at DEBUG level.
- Changes against D24 as written in Task 0: jdt.ls's ranges are never applied (first version: applied when unchanged, else placed; review B1), and a changed region no longer drops the import. D24 in 001 updated.
- Bug fixed on the way: a resolve answering after its buffer was wiped threw "Invalid buffer id" from `transform_lsp` (`is_java`) (P1 code, reached now because resolves outlive the accept); `is_java` and `snippets_should_show` check the buffer first.

### Frecency vs project ranking (P1 follow-up, same task)

Root cause measured (trial t1-e): blink v1.10.2's Rust `fuzzy` (`fuzzy/rust/lib.rs`, `fuzzy.rs`) adds the frecency bonus (up to +6, keyed by label + kind + source) whenever the database is open; the `use_frecency` option (false for an empty keyword in `fuzzy/init.lua`) is parsed and never read, and setting `fuzzy.frecency.enabled = false` after the database is open changes nothing. After 20 accepts of `java.util.List` every `List` container annotation (`AssertFalse.List`, ...) gets score 6 on `@` against 0 for the rest, so blink's `score` sort put 23 of them above `RestController` (rank 24).

Fix: `M.sorts()` returns `java_sort_empty` for Java when no keyword character is typed before the cursor: score_offset (deprecated -2, postfix -6, snippet, project-key offsets) first, then jdt.ls relevance and project usage as in `java_sort`, then blink's `score` (with nothing typed, that is exactly the frecency bonus: a tie breaker), then jdt.ls order. With a typed prefix the fuzzy match dominates and the order is unchanged (`score`, `java_sort`); cmdline completion with a Java buffer current gets blink's default sort (its items are not Java items). Clean database: identical order to before (score = score_offset there), confirmed by 10/11 unchanged. Trade-off: on an empty-prefix list frecency now only breaks ties (it can no longer lift an item over higher jdt.ls relevance or project usage), which is the point; in `java.util.` member lists, where relevance is flat, it still orders.

## Task 1 check (`63_async_import`, first version: 16 cases; 28 after fix round 1, below)

| Case | What | Result (3 consecutive final runs) |
|------|------|-----------------------------------|
| `accept_first` | first accept of the session (`Lis` -> `List`) | text in 45 to 46 ms (budget 100), import 659 to 787 ms (1500) |
| `accept_second` | `HashMa` right after | text in 51 ms, import 317 to 372 ms, `List` import still there once |
| `stub_slow` | resolve answers held 800 ms | text in 50 to 51 ms, import 867 to 871 ms, exactly once |
| `rf_edit_below` | line typed below between accept and resolve | applied once, text intact |
| `rf_cursor_moved` | cursor moved to `main`'s line, col 18 | applied, cursor still on its text and column |
| `rf_import_typed` | user typed the same import | `present`, count 1 |
| `rf_region_changed` | `import java.util.Map;` typed right below `package` (inside jdt.ls's stale range) | `placed` before `Map`, nothing deleted |
| `rf_removing_edit` | the held answer's edit rewritten to replace the existing `import java.util.List;` line (twin of t1-l) | `placed`, both imports kept |
| `rf_undo` | `u` undoes the accept | `dropped`, buffer = before the accept |
| `rf_undo_one` | undo boundary (<Esc>) only | applied, joined: one `u` removes item and import |
| `rf_second` | `HashMap` accepted before `ArrayList`'s resolve answered | `applied` + `placed`, both once, sorted |
| `rf_closed` | buffer wiped | `dropped` ("buffer closed"), no error, file on disk unchanged |
| `frecency_polluted` | 20 accepts of `List` with blink's real frecency write, scratch db `/tmp/nv4j/frecency-63/<pid>/` | db written (64 bytes) |
| `frecency_at` | `@` in CustomerController, polluted db | `RestController` 1 (top 5); `List` items carry bonus 6; blink's plain score order 27 |
| `frecency_http` | `http.` in SecurityConfig, polluted db | `authorizeHttpRequests` 2 (top 3) |

The Review Focus cases are deterministic: every `completionItem/resolve` answer of the jdtls client is held by a gate until the case releases it, so the action always happens between accept and late resolve. Two test-side rules (deviations from a plain replay, documented here): (1) before each `rf_*` accept the check clears the buffer's diagnostics, resets the text and waits (<= 10 s) for jdt.ls's "ArrayLis cannot be resolved" publish, because right after a case that ended with the import in place jdt.ls's resolve sometimes still saw the import and sent no `additionalTextEdits` (trial t1-h; a jdt.ls staleness, not Nv4J's; it means "no import", as P1 behaved with any missing edit); (2) an undo boundary (`let &undolevels = &undolevels`) is made before the accept, as the user's own typing makes one: blink skips its undo point for jdt.ls items (they are snippet-format), and headless API edits are otherwise one undo block.

### Negative controls, first version (verbatim path, superseded by fix round 1; product or check mutated for one run, restored byte for byte, `cmp` identical)

| # | Mutation | Fails | Log |
|---|----------|-------|-----|
| n2 | `install_async_import` does nothing (blink at 50 ms, no late apply) | `accept_first`, `accept_second`, `stub_slow` ("import MISSING") and all 8 `rf_*` | `/tmp/nv4j/logs/test-20261021-214334.log` |
| n3 | "already present" guard off | `rf_import_typed` (duplicate) | `-213801.log` |
| n4 | accepted-text (undo) guard off | `rf_undo` (import added after the undo) | `-213827.log` |
| n5 | region check off (jdt.ls ranges always applied) | `rf_region_changed` (`import java.util.Map;` deleted), `rf_second` (order/blank lines wrong) | `-214254.log` |
| n6 | no `undojoin` | `rf_undo_one` (one `u` left the item) | `-214151.log` |
| n7 | cursor saved and restored by position around the apply (a common plugin pattern) | `rf_cursor_moved` (cursor on the blank line above) | `-213943.log` |
| n8 | buffer-valid guards off (`late_import`, `is_java`) | `rf_closed` ("Invalid buffer id") | `-214008.log` |
| n12 | additive-only check off | `rf_removing_edit` (`import java.util.List;` replaced) | `-215412.log` |
| n9 | Java sort back to `{ "score", java_sort }` | `frecency_at` (rank 24) | `-214033.log` |
| n10 | Java sort off (blink default for Java) | `frecency_at` (29), `frecency_http` (9) | `-214448.log` |
| n11 | check: frecency write stubbed during the 20 accepts | `frecency_polluted` (db 0 bytes), `frecency_at` (bonus 0) | `-214512.log` |

n1 (Task 0, timeout 50 without late apply) is the same as n2 for the first three cases. Mutation script: the trial runner in the Task 1 report.

## Fix round 1 (review: B1 blocking, M1)

**B1.** The first version applied jdt.ls's ranges when the lines they touch were unchanged since the accept, but jdt.ls computes them on its own snapshot, which may predate an earlier late import or user edit: a stale pure insertion passed every guard. Measured with the new 50-run loop (below, first run before the fix to `take_imports`): jdt.ls's `HashMap` edit was `2:0-2:22 "import java.util.HashMap;"` in 22 of 50 runs, a replacement of the existing `import java.util.List;` line (28 runs: `2:0-2:0 "import java.util.HashMap;\n"`). That is the t1-a/t1-l flake. Now jdt.ls's ranges are never applied: `take_imports` moves import-only edits off the resolved item (blink's in-time path cannot apply them either) and `place_import` inserts the statements at a place computed from the current buffer.

**M1.** `place_import` follows `java.completion.importOrder` (one definition, `M.IMPORT_ORDER`, sent by `plugins/java.lua`, read back from the client settings), see the design bullets above.

Resolve errors and missing answers: an error answer gives `none`; no answer within `ASYNC_WAIT_MS` (10 s) gives `dropped`; both are logged (`async_log`, `vim.notify` DEBUG) and clear the extmark.

Spring-client items (the Spring Boot LS on Java buffers) go through blink's plain accept: with the 50 ms timeout, a resolve-only edit arriving later would be lost. None exist today (its `@Value`/`@Profile` items carry their edits in the completion answer), `51_spring_completion` passes.

New cases (12): `rf_stale_insert` (jdt.ls's pure insertion at (2,22) while line 2 now holds a longer import: added before it, sorted, no split line), `rf_in_time_lossy` (resolved before the accept with the lossy 2:0-2:22 edit: blink does not apply it, `List` kept), `rf_resolve_error`, `rf_no_answer` (extmark cleared, outcome logged), `place_other_first`, `place_group_between` (jakarta between other and java with blank lines), `place_sorted_in_group`, `place_before_static`, `place_static_last`, `place_no_package_license` (below the license comment, at the top of the code), `place_comment_not_import` (a bare `import java.util.ArrayList;` line inside `/* */` and one after `//` do not count as present), `place_module_import_kept`. Placement cases compare every line, blank lines included. `rf_region_changed`, `rf_removing_edit`, `rf_second` now expect `applied` (one path). Case count: 28 (attached, 3 accept cases, 21 `rf_*`/`place_*`, 3 frecency).

Real-resolve loop: `NV4J_63_REPEAT=50 NV4J_CHECKS=63_async_import tests/run.sh` accepts `List` then `HashMap` 50 times against the real resolve (no gate; each run waits for jdt.ls to settle), prints `REPEAT i ok|BAD; outcomes: ... [jdt.ls: <edits>]; head: <first 4 lines>` per run and one `repeat_real` case with the counts. Final code (`/tmp/nv4j/logs/test-20261021-223129.log`): **50/50** runs with both imports once and every line as expected; import missing 0, duplicated 0, other line wrong 0, `none` 0; 100 of 100 outcomes `applied` (blink applied none in time); jdt.ls's `HashMap` edit was the lossy `2:0-2:22 "import java.util.HashMap;"` in 36 of 50 runs (14: `2:0-2:0 "import java.util.HashMap;\n"`), `List` always `0:13-2:0 "\n\nimport java.util.List;\n\n"`. First loop run (place_import already in, `take_imports` not yet): also 50/50, lossy edit 22 of 50 (`-221420.log`).

Three consecutive runs after the fix: `DONE 63_async_import 28 0` (`-222940.log`, `-223017.log`, `-223053.log`): text 43 to 51 ms, import `List` 658 to 790 ms, `HashMap` 461 to 479 ms, stubbed 871 to 877 ms.

### Negative controls, fix round 1 (one mutation per run, restored, `cmp` identical; runner `negctl2.py` in the Task 1 report)

| # | Mutation | Fails | Log |
|---|----------|-------|-----|
| r2 | wrapper not installed | every accept, `rf_*` and `place_*` case (24) | `/tmp/nv4j/logs/test-20261021-221816.log` |
| r3 | present guard off | `rf_import_typed` | `-222010.log` |
| r4 | undo guard off | `rf_undo` | `-222047.log` |
| r5 | jdt.ls ranges applied as sent (verbatim) | `rf_region_changed`, `rf_removing_edit`, `rf_stale_insert`, `rf_in_time_lossy`, `rf_second`, all 8 `place_*` (13) | `-222124.log` |
| r6 | no undojoin | `rf_undo_one` | `-222201.log` |
| r7 | cursor saved/restored around the insertion | `rf_cursor_moved` | `-222238.log` |
| r8 | buffer-valid guards off | `rf_closed` | `-222315.log` |
| r9 | old Java sort | `frecency_at` (24) | `-222351.log` |
| r10 | no Java sort | `frecency_at` (29), `frecency_http` (9) | `-222429.log` |
| r11 | check: frecency write stubbed | `frecency_polluted`, `frecency_at` | `-222509.log` |
| r14 | one group for everything | `place_other_first`, `place_group_between`, `place_before_static`, `place_static_last` | `-222546.log` |
| r15 | naive present test (any trimmed line) | `place_comment_not_import` (`present`, import lost) | `-222623.log` |
| r16 | `import module` not recognized | `place_module_import_kept` | `-222659.log` |
| r17 | no package: insert at line 0 | `place_no_package_license` (above the license) | `-222736.log` |
| r18 | no watchdog | `rf_no_answer` (extmark left, no outcome) | `-222849.log` |
| r19 | `take_imports` off (blink applies import edits) | `rf_in_time_lossy` (`List` import replaced) | `-222812.log` |

`place_sorted_in_group` fails under r5 only (sorting has no separate control: r14 keeps one group sorted).

## Dirty-fixture guard (carried item)

`tests/lib/fixture_guard.sh <fixture> [fail|restore|allow]`, called by `tests/run.sh` before the fixture build: `git status --porcelain --untracked-files=all -- src pom.xml` inside `tests/fixtures/demo`; dirty -> FATAL with the list and the exact recovery command (`git -C '<fixture>' checkout -- src pom.xml && git -C '<fixture>' clean -fd -- src`), exit 3; `NV4J_FIXTURE_DIRTY=restore` runs exactly that and prints what it restored; `=allow` warns and runs. Nothing outside the fixture's `src` and `pom.xml` is read or touched. Tested on a scratch git copy (`/tmp/nv4j/guardtest`: modified `App.java` and `pom.xml`, an untracked `junk/New.java`, plus a dirty file outside the fixture and an untracked file in the fixture root): clean -> 0; fail -> 3 with the list and the command; allow -> 0; restore -> 0, `Removing src/main/java/demo/junk/`, afterwards only the two files outside `src`/`pom.xml` are still dirty (log `/tmp/nv4j/guard-test.log`). Through `run.sh` on the real fixture with an untracked probe file: FATAL, exit 3 before any build, probe removed by hand afterwards (log `/tmp/nv4j/guard-runsh.log`).

## Task 1 trial log

| # | Change | Effect | Kept |
|---|--------|--------|------|
| t1-a | timeout 50 + wrapper applying the late edits verbatim, guards: closed, imports only, present, accepted line, region unchanged else drop | `accept_*`, `stub_slow` pass (text 42 to 51 ms, import 708 to 891 ms); one run of four had `accept_second` with the `List` import count 0, not reproduced in 5 more runs with the edits logged (`/tmp/nv4j/logs/test-20261021-212144.log`); the outcome log (`async_log` with edits) was added to diagnose any recurrence | kept |
| t1-b | Review Focus cases with a resolve gate | `rf_second` lost the second import (drop on changed region); `rf_undo`/`rf_undo_one` undid back to the file (headless edits one undo block); `rf_closed` threw "Invalid buffer id" in `is_java` (`-212652.log`) | led to t1-c..f |
| t1-c | changed region -> place the import lines (sorted) instead of dropping | `rf_second`, `rf_region_changed` pass | kept |
| t1-d | extmark spanning the accepted line instead of a point mark at col 0 (a line replaced by two lines moved the point mark to the next line, so the guard dropped a valid import) | `rf_second` first import applied | kept |
| t1-e | frecency: why does `@` show 23 `List` items first? Debug ranks with `fuzzy.frecency.enabled` toggled | same rank 24 either way; score 6 on `List` items with nothing typed: blink's Rust ignores `use_frecency` (debug run `/tmp/nv4j/logs/test-20261021-213054.log`) | root cause |
| t1-f | `java_sort_empty` for an empty keyword | `frecency_at` 24 -> 1, `frecency_http` 2 | kept |
| t1-g | undo join on "seq == seq before + 1" | never true for jdt.ls items (no blink undo point) and wrong in insert mode; replaced by the changedtick right after blink's edit (`on_lines`) | replaced |
| t1-h | `rf_import_typed`/`rf_undo` sometimes `none`: jdt.ls's resolve carried no edit right after a case that ended with the import (gate debug: `ate=nil`); a wait on stale diagnostics returned in 0.1 ms | reset diagnostics + wait for this text's publish before each `rf_*` (test-side, above) | kept |
| t1-i | `rf_region_changed` with a blank line before the new import, `rf_undo_one` without an undo boundary | n5 and n6 did not fail (stale ranges happened to give the same non-blank lines; headless edits joined anyway); the cases were made strict (import right below `package`; undo boundary) and then both controls fail | kept |
| t1-j | `frecency_at_typed` (`@Re`) | rank 1 with any sort (no control can fail it): removed | removed |
| t1-l | 8-run repeat of `63`: one run had `accept_second` with the `List` import gone after a verbatim apply (`/tmp/nv4j/logs/test-20261021-215052.log`, same symptom as t1-a): jdt.ls's late `HashMap` edit replaced the `List` import line (edits were not yet printed then; the only verbatim path that can remove that line). Guard 5 (additive only: an edit that would remove a non-blank line is placed instead) + deterministic twin `rf_removing_edit` (n12 fails without the guard); the case output now prints the late edits | kept |
| t1-m | review B1/M1: verbatim path removed, `take_imports`, `place_import` with importOrder, watchdog; 12 new cases, controls r2 to r19 | all pass; every control fails its cases | kept |
| t1-k | cmdline completion with a Java buffer current | Java sorts would have applied to cmdline items (pre-existing); now blink's default there | kept |
