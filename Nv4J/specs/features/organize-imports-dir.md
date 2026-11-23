# Feature: organize imports for a folder or the project

Priority: P3 leftover (IntelliJ: Optimize Imports on a folder / project). Status: built 2026-11-23. Check: `tests/checks/113_organize_dir.lua` (8 cases, live jdt.ls). Controls: `tests/lib/control_113.sh` (5 patches). Code: `nvim/lua/nv4j/organize.lua` (loaded on the first key press, zero startup cost).

## Keys

`<leader>cI`: the project of the current file; with the cursor in neo-tree, the folder under the cursor (a file: its folder). neo-tree `O`: the same for the node. `<leader>co` stays the single-file action. `<leader>cI` was free (docs/KEYS.md lists the `<leader>c` keys; LazyVim has no `cI`); `O` is not a neo-tree default (`o` is the order menu).

## Mechanism

jdt.ls 1.63.0 command `java.edit.organizeImports` (JDTDelegateCommandHandler -> `OrganizeImportsCommand.organizeImports`, the code-action id `java.action.organizeImports` is the same work behind a code action). The argument is a URI: a project root runs `organizeImportsInProject`, a file `organizeImportsInFile`. The server applies the edit itself with `workspace/applyEdit` (and returns an empty object); the wrapper counts the files that have at least one text edit in that request, then writes the buffers that were not modified before, and notifies "Organized imports in N files under <dir>" (or "already organized", or "(k not saved: they had unsaved changes)").

Finding (2026-11-23, live): a folder URI below the project root returns an EMPTY edit. Likely cause (read in the source, not confirmed by a debugger): the command takes `getFileForLocation(path)` first, and Eclipse's `getFileForLocation` returns a file handle for a path two or more segments deep without checking that it is a file, so `organizeImportsInDirectory` (the branch for folders, ~line 117) is never reached for a package folder (a trailing slash on the URI did not help). The project root has one segment, so it works. Workaround: a sub-folder is one request per `.java` file under it (skips hidden, `target`, `build`, `out`, `node_modules`), one after the other; the project root is one request.

Unsaved buffers: organized in the buffer, not written (the user keeps their undo and decides); the message says how many.

## Test design

Temp Maven project (6 files, 3 packages, one nested, one clean, one with unsaved edits), real jdt.ls. `dir_scope` (package `a`: 2 files changed on disk, files outside byte for byte equal), `message`, `project_scope` (3 more), `dirty_not_saved`, `again_zero`, `no_client` (WARN, no crash), `keys`. Controls: count never kept, clean buffers not saved, dirty buffers saved, a folder sent as one URI (the jdt.ls bug above), the code-action command id.

Not built: a confirmation question before a project-wide run (the edits stay undoable per buffer until saved, but clean files are saved at once, like IntelliJ); an IntelliJ-style options dialog.
