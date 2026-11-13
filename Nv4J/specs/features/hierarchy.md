# Type and call hierarchy picker

`<leader>cS` subtypes, `<leader>cP` supertypes, `<leader>ci` incoming calls, `<leader>cO` outgoing calls (same keys as before). Code: `nvim/lua/nv4j/hierarchy.lua` (loaded on first key press, zero startup cost), keys in `nvim/lua/config/keymaps.lua`. Check: `tests/checks/98_hierarchy.lua` (15 cases, 3 live; controls `tests/lib/control_98.sh`, 8).

## Why

Neovim 0.12's `vim.lsp.buf.typehierarchy`, `incoming_calls` and `outgoing_calls` all end the same way (read from `runtime/lua/vim/lsp/buf.lua`): prepare, then the default handler fills the quickfix list and opens it, one line per item as `full/path|line col| Name detail`. The path comes first, the name last, and several prepare results go through a `vim.ui.select` first. Not a tree, not readable for a long path.

## What it does

- Prepare (`textDocument/prepareTypeHierarchy` or `prepareCallHierarchy`) to every attached client that supports it (jdt.ls in practice), then ONE request per prepared item (`typeHierarchy/subtypes|supertypes`, `callHierarchy/incomingCalls|outgoingCalls`). Nothing per row, no extra levels (the results are the direct ones the LSP returns). Several prepared items or clients are merged into one list.
- Telescope picker (the config's picker), rows `<icon> Name  package  relative/path:line` sorted by name (case-insensitive), then package, path. Name in the function colour, the rest dimmed. Type rows: `Circle  demo.shapes  src/main/java/demo/shapes/Circle.java:4`. Call rows: `Class#method` (parameters of jdt.ls's `method(Type)` dropped), the container's package, `xN` when the LSP sent more than one call site. Library classes show `jar/package/Class.java` (from the jdt:// URI) and have an empty preview (no extra LSP request).
- Preview: the target in a grep preview (line highlighted). `<CR>` jumps with `vim.lsp.util.show_document` (offset encoding of the client). `<C-q>`, `<Tab>`, filtering: the default Telescope keys (entries carry filename/lnum/col/text).
- Jump target: the item's `selectionRange` (the name in the declaration), else `range`. Incoming calls: the FIRST call site (smallest position of `fromRanges`, which lie in the caller's file). Outgoing calls: the callee's declaration (its call sites are in the origin file and are only counted).
- Messages: no attached client supporting the method, "No subtypes of X" (same for supertypes, callers, callees; INFO), an LSP error (WARN), no answer within 15 s (WARN, requests cancelled). A new hierarchy command cancels the request in flight; an answer of a superseded run is dropped.

## Verified

Live check 98 on a 6-file Maven project: subtypes of an interface = its 3 implementors (one in another package) in 68 to 1300 ms (jdt.ls warm), rows name first, jump to the class line; incoming calls of a method: `Main#go`, `Report#run`, jump on the call line. In a real tmux session (private server): `<leader>cS` draws the picker with preview, `<CR>` lands on `Circle.java` 4:13; `<leader>ci` lists the callers and `<CR>` on the second lands on the call in `Report.java` 11:11; `<leader>cP` opens (Circle: 2 supertypes).

## Bug fixed (2026-11-13, user report)

`<leader>cO` raised `E5108 ... path: expected string, got table` when the selection moved over a library row. Cause: the entry of a non-file (jdt://) row had `path` and `filename` nil, so Telescope's `from_entry.path` fell back to `entry.value`, our row table, and the grep previewer crashed. Now every entry has a string path: the file path, else the jdt:// URI (the previewer's readable check fails, so the preview is empty; `<C-q>` gets a filename that `:cc` opens through jdt.ls's BufReadCmd, checked), else "". Regression cases `entry_safe` (pure) and `live_outgoing_library` (real picker, selection moved over all rows, v:errmsg and :messages clean); control `nilpath` makes both fail.

## Verified in tmux after the fix

`<leader>cO` on `Out#hi`: 3 rows, `Shape#area  demo.shapes  .../Shape.java:4`, `PrintStream#println  java.io  java.base/java.io/PrintStream.java:1130`, `List#of  java.util  java.base/java.util/List.java:936`; moving over all of them: no error, library previews empty. `<leader>cP` on Circle: `Shape  demo.shapes  .../Shape.java:3` and `Object  java.lang  java.base/java.lang/Object.java:39`.

## Not done / limits

- No tree: one level at a time (select a row and press the key again on the target).
- Not exercised live: several clients, multiple prepare results, the 15 s timeout (stub only), `<CR>` on a library row (the jump to a jdt:// target through `show_document` was not tried; `:cc` on a quickfix entry was).
- Library rows show no preview text (empty by design: no extra request).
