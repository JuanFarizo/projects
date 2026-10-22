# Feature: Asynchronous import on completion accept (P1 follow-up)

Priority: P3 (P1 follow-up). Status: Task 0 done (research, failing check `63_async_import`); Task 1 builds it. Decision: D24 in `specs/001-architecture.md`. Spec: `specs/005-p3-tests-scaffold-refactor.md`. Check: `tests/checks/63_async_import.lua` (`31_imports` and `11_completion_ranking` must stay green). Product (Task 1): `nvim/lua/nv4j/completion.lua`, `nvim/lua/plugins/blink.lua`.

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
