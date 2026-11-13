# Type and call hierarchy picker

`<leader>cS` subtypes, `<leader>cP` supertypes, `<leader>ci` incoming calls, `<leader>cO` outgoing calls (same keys as before). Code: `nvim/lua/nv4j/hierarchy.lua` (loaded on first key press, zero startup cost), keys in `nvim/lua/config/keymaps.lua`. Check: `tests/checks/98_hierarchy.lua` (13 cases, 1 live; controls `tests/lib/control_98.sh`, 7).

## Why

Neovim 0.12's `vim.lsp.buf.typehierarchy`, `incoming_calls` and `outgoing_calls` all end the same way (read from `runtime/lua/vim/lsp/buf.lua`): prepare, then the default handler fills the quickfix list and opens it, one line per item as `full/path|line col| Name detail`. The path comes first, the name last, and several prepare results go through a `vim.ui.select` first. Not a tree, not readable for a long path.

## What it does

- Prepare (`textDocument/prepareTypeHierarchy` or `prepareCallHierarchy`) to every attached client that supports it (jdt.ls in practice), then ONE request per prepared item (`typeHierarchy/subtypes|supertypes`, `callHierarchy/incomingCalls|outgoingCalls`). Nothing per row, no extra levels (the results are the direct ones the LSP returns). Several prepared items or clients are merged into one list.
- Telescope picker (the config's picker), rows `<icon> Name  package  relative/path:line` sorted by name (case-insensitive), then package, path. Name in the function colour, the rest dimmed. Type rows: `Circle  demo.shapes  src/main/java/demo/shapes/Circle.java:4`. Call rows: `Class#method` (parameters of jdt.ls's `method(Type)` dropped), the container's package, `xN` when the LSP sent more than one call site. Library classes show `jar/package/Class.class` (the jdt:// URI) and have no file preview.
- Preview: the target in a grep preview (line highlighted). `<CR>` jumps with `vim.lsp.util.show_document` (offset encoding of the client). `<C-q>`, `<Tab>`, filtering: the default Telescope keys (entries carry filename/lnum/col/text).
- Jump target: the item's `selectionRange` (the name in the declaration), else `range`. Incoming calls: the FIRST call site (smallest position of `fromRanges`, which lie in the caller's file). Outgoing calls: the callee's declaration (its call sites are in the origin file and are only counted).
- Messages: no attached client supporting the method, "No subtypes of X" (same for supertypes, callers, callees; INFO), an LSP error (WARN), no answer within 15 s (WARN, requests cancelled). A new hierarchy command cancels the request in flight; an answer of a superseded run is dropped.

## Verified

Live check 98 on a 6-file Maven project: subtypes of an interface = its 3 implementors (one in another package) in 68 to 1300 ms (jdt.ls warm), rows name first, jump to the class line; incoming calls of a method: `Main#go`, `Report#run`, jump on the call line. In a real tmux session (private server): `<leader>cS` draws the picker with preview, `<CR>` lands on `Circle.java` 4:13; `<leader>ci` lists the callers and `<CR>` on the second lands on the call in `Report.java` 11:11; `<leader>cP` opens (Circle: 2 supertypes).

## Not done / limits

- No tree: one level at a time (select a row and press the key again on the target).
- Not exercised live: `<leader>cO` (outgoing), several clients, multiple prepare results, the 15 s timeout (stub only), the library-class rows with a real jdt:// target (pure case only).
- Rows from a jdt:// URI show no file preview.
