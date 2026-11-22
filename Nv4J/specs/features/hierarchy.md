# Type and call hierarchy picker

`<leader>cS` subtypes, `<leader>cP` supertypes, `<leader>ci` incoming calls, `<leader>cO` outgoing calls (same keys as before). Code: `nvim/lua/nv4j/hierarchy.lua` (loaded on first key press, zero startup cost), keys in `nvim/lua/config/keymaps.lua`. Check: `tests/checks/98_hierarchy.lua` (23 cases, 5 live; controls `tests/lib/control_98.sh`, 13).

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
- Not exercised live: several clients, multiple prepare results, the 15 s timeout (stub only), `<CR>` on a library row is now exercised (see above).
- Library rows show no preview text (empty by design: no extra request).
