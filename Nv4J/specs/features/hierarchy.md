# Type and call hierarchy picker

`<leader>cS` subtypes, `<leader>cP` supertypes, `<leader>ci` incoming calls, `<leader>cO` outgoing calls (same keys as before). Code: `nvim/lua/nv4j/hierarchy.lua` (loaded on first key press, zero startup cost), keys in `nvim/lua/config/keymaps.lua`. Check: `tests/checks/98_hierarchy.lua` (37 cases, 13 live; controls `tests/lib/control_98.sh`, 25).

## Why

Neovim 0.12's `vim.lsp.buf.typehierarchy`, `incoming_calls` and `outgoing_calls` all end the same way (read from `runtime/lua/vim/lsp/buf.lua`): prepare, then the default handler fills the quickfix list and opens it, one line per item as `full/path|line col| Name detail`. The path comes first, the name last, and several prepare results go through a `vim.ui.select` first. Not a tree, not readable for a long path.

## What it does

- Prepare (`textDocument/prepareTypeHierarchy` or `prepareCallHierarchy`) to every attached client that supports it (jdt.ls in practice), then ONE request per prepared item (`typeHierarchy/subtypes|supertypes`, `callHierarchy/incomingCalls|outgoingCalls`). Nothing per row, no extra levels (the results are the direct ones the LSP returns). Several prepared items or clients are merged into one list.
- Telescope picker (the config's picker), rows `<icon> Name  package  relative/path:line` sorted by name (case-insensitive), then package, path. Name in the function colour, the rest dimmed. Type rows: `Circle  demo.shapes  src/main/java/demo/shapes/Circle.java:4`. Call rows: `Class#method` (parameters of jdt.ls's `method(Type)` dropped), the container's package, `xN` when the LSP sent more than one call site. Library classes show `jar/package/Class.java` (from the jdt:// URI) and have an empty preview (no extra LSP request).
- Preview: the target in a grep preview (line highlighted). `<CR>` jumps with `vim.lsp.util.show_document` (offset encoding of the client). `<C-q>`, `<Tab>`, filtering: the default Telescope keys (entries carry filename/lnum/col/text).
- Jump target: the item's `selectionRange` (the name in the declaration), else `range`. Incoming calls: the FIRST call site (smallest position of `fromRanges`, which lie in the caller's file). Outgoing calls: the callee's declaration (its call sites are in the origin file and are only counted).
- Messages: no attached client supporting the method, "No subtypes of X" (same for supertypes, callers, callees; INFO), an LSP error (WARN), no answer within 15 s (WARN, requests cancelled). A new hierarchy command cancels the request in flight; an answer of a superseded run is dropped.

## Level-1 cache (2026-11-21)

Reference: `TypeHierarchyHandler.java:162-163` (jdt.ls builds a workspace hierarchy for subtypes: the slow request, 68 to 1300 ms). Two caches in `hierarchy.lua`, one LRU of `M.CACHE_MAX` = 64 entries: the prepare answer per (method, buffer, changedtick, cursor position, client), and the rows per prepared item (method + uri + name + selection range). A repeat press finds both and sends no request at all: `finish` runs inside `M.run`, the picker opens at once. Supertypes right after subtypes at the same cursor reuse the prepare answer and send only `typeHierarchy/supertypes`.

Emptied (`M.invalidate`) by: `LspNotify` of `textDocument/didChange`, `textDocument/didSave`, `workspace/didChangeWatchedFiles`; `LspProgress` end of a jdt.ls job whose title has Build, Updat, Import, Initializ or Refresh; `LspAttach`/`LspDetach`. NOT by the end of "Validate documents" / "Publish Diagnostics": measured live, those end after every buffer switch and an edit, which made the first version of the cache empty itself between two presses (the edit already reports through didChange). An answer that was in flight when an invalidation happened is shown but not stored (epoch counter); an LSP error is not stored. The hooks are created on the first key press, not at startup.

Checked: pure `cache_hit`, `cache_other_kind`, `cache_invalidate` (each event, plus the three that must NOT empty it), `cache_inflight`, `cache_error`, `cache_lru` (stub client, requests counted); live `live_cache` (first press 2 requests and 2 entries; repeat press 0 requests; after an edit the cache is empty and the next press sends 2 requests; same rows each time). On the 6-file project jdt.ls answers in 17 to 44 ms warm, so the measured gain there is 17-44 ms to 0; the 68 to 1300 ms of the earlier measurement is what a repeat press saves on a larger workspace (not re-measured). Controls: `nocache`, `noinval`, `noepoch`, `nolru`, `badprog` each make their case fail.

## `<CR>` on a library row (2026-11-21)

Tried live (`live_enter_library`): outgoing calls of `Out#hi`, selection moved to `List#of  java.util  java.base/java.util/List.java:936`, `<CR>`: the picker closes, the current window shows the `jdt://contents/java.base/java.util/List.java?=...` buffer (1196 lines, read-only, content from jdt.ls), cursor on line 936 (the row's line), 47 ms. `show_document` already behaves sensibly for a `jdt://` target (nvim-jdtls's BufReadCmd fills it), so no code change was needed. One message appears in `v:errmsg` when any Java buffer's filetype loads in the check's headless session: `E216: No such group or event: java_spotbugs_post User <buffer>`, raised by Neovim's own `runtime/ftplugin/java.vim`, not by Nv4J; the case ignores that one string.

## Verified

Live check 98 on a 6-file Maven project: subtypes of an interface = its 3 implementors (one in another package) in 68 to 1300 ms (jdt.ls warm), rows name first, jump to the class line; incoming calls of a method: `Main#go`, `Report#run`, jump on the call line. In a real tmux session (private server): `<leader>cS` draws the picker with preview, `<CR>` lands on `Circle.java` 4:13; `<leader>ci` lists the callers and `<CR>` on the second lands on the call in `Report.java` 11:11; `<leader>cP` opens (Circle: 2 supertypes).

## Bug fixed (2026-11-13, user report)

`<leader>cO` raised `E5108 ... path: expected string, got table` when the selection moved over a library row. Cause: the entry of a non-file (jdt://) row had `path` and `filename` nil, so Telescope's `from_entry.path` fell back to `entry.value`, our row table, and the grep previewer crashed. Now every entry has a string path: the file path, else the jdt:// URI (the previewer's readable check fails, so the preview is empty; `<C-q>` gets a filename that `:cc` opens through jdt.ls's BufReadCmd, checked), else "". Regression cases `entry_safe` (pure) and `live_outgoing_library` (real picker, selection moved over all rows, v:errmsg and :messages clean); control `nilpath` makes both fail.

## Verified in tmux after the fix

`<leader>cO` on `Out#hi`: 3 rows, `Shape#area  demo.shapes  .../Shape.java:4`, `PrintStream#println  java.io  java.base/java.io/PrintStream.java:1130`, `List#of  java.util  java.base/java.util/List.java:936`; moving over all of them: no error, library previews empty. `<leader>cP` on Circle: `Shape  demo.shapes  .../Shape.java:3` and `Object  java.lang  java.base/java.lang/Object.java:39`.

## Not done / limits

- No tree: one level at a time (select a row and press the key again on the target).
- Exercised live now (2026-11-23): several clients (a second in-process server), the timeout, outgoing calls, `<CR>` on a library row. Not exercised: several prepare results from ONE server (jdt.ls sends one).
- Library rows show no preview text (empty by design: no extra request).

## Speed round (2026-11-23)

Measured with a real jdt.ls 1.63 (private config dir whose `nv4j` is a symlink to this worktree's `nvim`, proved by `stdpath("config")` realpath). Biggest fixture: `tests/fixtures/demo` (Spring Boot, 20 Java files, Spring Data on the classpath): too small to show the cost, so a copy of it with 1000 more classes was measured too (40 packages x 25 classes: 321 implementors of an interface, 360 subclasses of an abstract class; copy in /tmp, not committed). Medians, ms, `warm` = 5 repeats after the first request:

| request | demo (20 files) cold / warm | 1000-class copy cold / warm |
|---|---|---|
| prepare (type or method) | 3-29 / 2-8 | 4-30 / 3-6 |
| supertypes | 31 / 10 (1 result) | 20 / 9 |
| subtypes, 0-3 results | 15-27 / 11-18 | 28 / 22 (library type, 2 results) |
| subtypes, 321 results | - | 470-780 / 277 (later runs 80) |
| subtypes, 360 results | - | 186-209 / 61-105 |
| incoming calls (7 callers) | 135 / 70 | 51 / 26 (0 callers) |
| outgoing calls | 34 / 17 | 41 / 9 |
| H.run end to end, cache empty | 9-82 | 10-241 |

The first request after import can be much slower (4135 ms for the first typeHierarchy request of one session, 4815 ms in check 98 on the 6-file project): jdt.ls builds its index then. Sizes: only subtypes grow with the workspace (supertypes, calls do not).

Tried one at a time:

1. KEPT: picker with a loading row. When the answer is not there `M.LOADING_MS` = 120 ms after the key press, the picker opens at once with one `loading ...` row (title `Subtypes of X  (loading ...)`); the rows replace it in the same picker (`M.fill`, prompt text kept) when they arrive. A fast answer (cache hit, small workspace) opens the final picker directly, no flicker. Closing the picker cancels the requests (`BufWipeout` of the prompt buffer); `<CR>` on the placeholder does nothing; an empty answer, an error or the timeout closes it with the message. Live: picker visible after 109-115 ms for an answer delayed to 600 ms (rows in the same picker after 640 ms), instead of nothing for the whole wait.
2. NOT KEPT (not built): prepare + supertypes + subtypes in parallel. The two hierarchy requests need the item the prepare answers (jdt.ls resolves it by the item's data), so they cannot start before it; prepare to several clients is already parallel. Sending supertypes and subtypes together once the item is there was measured on the 1000-class copy: subtypes 74 ms together vs 80 ms alone, supertypes 5 ms in both: nothing to gain, so no extra request.
3. KEPT: prefetch of subtypes on `CursorHold` (`updatetime` 700 ms) when the word under the cursor starts with a capital letter, normal mode, Java buffer, no hierarchy run in flight, no prefetch in flight (slot freed by the answer or after 20 s), jdt.ls not reporting a Build / Import / Refresh / Initializ / Starting job, `vim.g.nv4j_hierarchy_prefetch ~= false`. It fills the level-1 cache (prepare answer + subtypes rows, same keys as a press, epoch-guarded), so the next `<leader>cS` is a cache hit. Cost measured: main thread 0.1 to 1.1 ms per prefetch (including building 360 rows in the callback), one prepare and one subtypes request per symbol and buffer state (the cache answers a repeat CursorHold), nothing while typing (CursorHold does not fire). jdt.ls: completion sent right after a subtypes request 31 ms vs 29 ms alone (max 55), hover 3 vs 2 ms, so a prefetch does not hold up completion. Result on the 1000-class copy: press after prefetch 0.6 ms (0.8 ms for 360 rows) instead of 108 to 290 ms. The module loads on the first CursorHold in a Java buffer (the autocmd is in `config/keymaps.lua`), not at startup.
4. KEPT (behaviour checked, 15 s unchanged): no answer within `M.TIMEOUT_MS` = 15000 ms: one WARN `no answer to typeHierarchy/subtypes within 15 s`, the requests cancelled, the loading picker closed, a late answer ignored. Live with 500 ms: WARN after 501 ms, picker closed, `cancel_request` sent. The message now prints the seconds with `%.4g` (it said `0 s` for a short timeout).

Bug found by the several-clients case and fixed: the level-1 cache key per item had no client, so a second server answering the same item (same uri, name, range) was served the first server's rows. The key now includes the client id (`nokeyclient` control).

Exercised live now: outgoing calls (`live_outgoing`: `List#of,PrintStream#println,Shape#area`, jump = the callee's declaration `Shape.java:4`), several clients (`live_two_clients`: jdt.ls plus an in-process Lua server attached to the same buffer; rows merged and sorted; each asked once per request kind).

New cases (all in 98, every one has a control): pure `loading_slow`, `loading_fast`, `loading_cancel`, `timeout_slow`, `several_stub`, `prefetch_stub`, `prefetch_gates`, `prefetch_epoch`; live `live_loading`, `live_loading_close`, `live_timeout`, `live_outgoing`, `live_two_clients`, `live_prefetch`. Controls: `noload`, `nocancel`, `noclosecancel`, `notimeout`, `nokeyclient`, `oneclient`, `nopf`, `noword`, `noslot`, `nobusy`, `nopfepoch`, `noaucmd`.

Not done / limits of this round: no tree; the loading picker is not shown when jdt.ls answers in under 120 ms; the 1000-class numbers come from a synthetic copy (no real big project was available offline); a prefetch and a key press at the same moment send the same request twice (rare: needs the press within the subtypes time of the CursorHold).
