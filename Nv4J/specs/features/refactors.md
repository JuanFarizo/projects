# Feature: Refactors (rename with file move, move, rename package, inline, change signature, safe delete)

Priority: P3. Status: Task 0 done (research, fixture, failing check `62_refactor`); Task 4 builds the missing parts. Decision: D23 in `specs/001-architecture.md`. Spec: `specs/005-p3-tests-scaffold-refactor.md`. Check: `tests/checks/62_refactor.lua`. Product (Task 4): `nvim/lua/nv4j/refactor.lua`, keys in `nvim/lua/config/keymaps.lua`.

## Budget

Each refactor applied <= 2 s on the fixture, all references and imports correct, build clean afterwards (no jdt.ls error in the touched files <= 3 s), every refactor undoable with one `u` per buffer.

## Fixture (Task 0)

`src/main/java/demo/billing/Invoice.java` (class to rename/move), `demo/billing/PriceCalculator.java` (`total(Invoice)`: change signature target, calls private `gross` (inline method) through a local `gross` (inline variable); `legacyTotal` has no usages (safe delete allowed), `total` has 3 (blocked)), `demo/shop/Checkout.java` (call sites and imports in another package; only class of `demo.shop`, so renaming that package moves one file). No `main`, no Spring annotation (P2's main-class and bean counts unchanged).

## IntelliJ behaviour (reference, `intellij-community` at `b633034bb`)

- Rename a class renames its file and updates references and imports (`java/java-impl-refactorings/src/com/intellij/refactoring/rename/`); renaming a package directory updates every `package`/`import` line.
- Move class/package (`.../refactoring/move/moveClassesOrPackages/`, F6): pick a target package, imports fixed, the file moves.
- Inline method/variable/constant (`.../refactoring/inline/`, Ctrl+Alt+N): all or this occurrence.
- Change signature (`.../refactoring/changeSignature/`, Ctrl+F6): a dialog; a new parameter gets a default value used at the call sites.
- Safe delete (`.../refactoring/safeDelete/JavaSafeDeleteProcessor.java`, Alt+Delete): searches usages first; with usages it shows them and asks; without, deletes.
- One undo reverts the whole refactoring (all files).

## jdt.ls mechanism (clone `eclipse.jdt.ls` at `b52e20a`; installed jdt.ls 1.62.0, `org.eclipse.jdt.core.manipulation` 1.26.0)

- Rename: `textDocument/rename` (`handlers/RenameHandler.java`, `RenameSupport` with UPDATE_REFERENCES) returns a WorkspaceEdit; for a type it includes the compilation unit rename as a `RenameFile` document change (Neovim advertises `resourceOperations`). `textDocument/prepareRename` on a `package` declaration answers "Renaming this element is not supported".
- File and folder rename: `workspace/willRenameFiles` (`handlers/FileEventHandler.java` `handleWillRenameFiles`): file rename -> type rename edits; folder rename -> package rename edits (`computePackageRenameEdit`), on the OLD uris; move -> `computeMoveEdit`. The client must apply the edit before moving.
- Move, change signature, extract, inline come as code actions (`text/correction/RefactorProposalUtility.java`, `corrections/RefactorProcessor.java` `getInlineProposal`): kinds `refactor.move` (`JavaCodeActionKind.REFACTOR_MOVE`), `refactor.change.signature`, `refactor.inline`. Move and change signature are commands (`java.action.applyRefactoringCommand` with `moveFile`/`moveType`/`changeSignature`) that the client must implement: nvim-jdtls does (`lua/jdtls.lua`: `move_file` asks the destination with `vim.ui.select` and calls `java/getMoveDestinations` + `java/move`; `change_signature` opens an editable float, parses it on `BufUnload`, then `java/getRefactorEdit`). Inline is plain `java/getRefactorEdit`.
- The refactoring engine itself (`org.eclipse.jdt.internal.corext.refactoring.*`) is in `org.eclipse.jdt.core.manipulation` (eclipse.jdt.ui repo), not in `eclipse.jdt.core`; not cloned (the protocol is what we need; the installed jar is the truth).
- No safe delete in jdt.ls (code actions at a method: "Change signature", "Make Static", "Move ...", "Inline Method", generate/organize entries; nothing deletes).
- LazyVim: `<leader>cr` = `vim.lsp.buf.rename`, `<leader>cR` = `Snacks.rename.rename_file` (willRenameFiles, file only); its neo-tree extra calls `Snacks.rename.on_rename_file(old, new)` on neo-tree's FILE_RENAMED/FILE_MOVED, i.e. AFTER neo-tree moved the file or folder, with a 1 s `request_sync`.

## Baseline (Task 0, measured)

Today's paths, prompts answered by the check. Logs: `/tmp/nv4j/logs/test-20261021-210035.log`, `-210135.log`, and the full run in `005`.

| Case | Path today | Result |
|------|-----------|--------|
| rename class `Invoice` -> `Bill` | `vim.lsp.buf.rename` (`<leader>cr`) | **works**: 440 to 761 ms, file renamed, imports and references updated, build clean; one `u` per buffer restores the text (the file keeps the new name: undo does not rename back) |
| move `Invoice` to `demo.shop` | code action "Move 'Invoice'..." + nvim-jdtls destination `vim.ui.select` | **works**: 663 to 682 ms, file moved, Checkout's import dropped, PriceCalculator imports `demo.shop.Invoice`, build clean |
| rename package `demo.shop` -> `demo.store` | `<leader>cr` on the package line | **fails**: prepareRename "Renaming this element is not supported" |
| same | neo-tree folder rename (LazyVim -> `Snacks.rename.on_rename_file` after the move) | **fails**: folder moved, `package demo.shop;` left in `demo/store/Checkout.java` (error "declared package does not match"): willRenameFiles is asked after the move |
| inline method (call of `gross`) | code action "Inline Method" | works: 101 ms, build clean |
| inline local variable `gross` | code action "Inline local variable" | works: 130 to 144 ms |
| change signature of `total` (+ `int discount` = 0) | code action "Change signature for 'total'", nvim-jdtls float filled with `- int discount 0`, closed | works: 364 to 385 ms, 3 call sites pass 0; interactive only (a float to edit, no arguments) |
| safe delete `total` / `legacyTotal` | none | no action in jdt.ls |
| keys | | `<leader>jm/ji/js/jd/jr` unmapped; `<leader>cr` "Rename" |

## Decision D23 (summary; full text in 001)

Ride on jdt.ls code actions and nvim-jdtls's command handlers (they already meet the 2 s budget), with thin entry functions in `nv4j/refactor.lua` that select the action by kind (`refactor.move`, `refactor.inline`, `refactor.change.signature`) and accept answers as arguments (no prompt in checks). Own code only for the gaps: package rename (willRenameFiles BEFORE the move, apply, write touched buffers, move the folder, re-point buffers; also used for neo-tree folder renames instead of LazyVim's after-the-move hook), safe delete (`textDocument/references`: usages -> quickfix, nothing deleted; none -> delete the declaration range from `documentSymbol`), change signature with arguments (`java/getChangeSignatureInfo` + `java/getRefactorEdit`, the float stays for interactive use), a summary of touched files. Rejected: custom refactor commands built on text edits (re-implements what jdt.ls does correctly).

## Proposed keys (collision check done in Task 0)

`<leader>cr` stays Rename (class rename moves the file: works today), `<leader>cR` stays Rename File. New, in the "Java" group `<leader>j` (unused today, shared with scaffolding `<leader>jn`): `<leader>jm` move, `<leader>ji` inline, `<leader>js` change signature, `<leader>jd` safe delete, `<leader>jr` refactor menu (IntelliJ "Refactor This": all refactor code actions at the cursor), `<leader>jp` rename package (Task 4 may fold it into `<leader>cr` on a package line). The plan's `<leader>cr` group is not used: `<leader>cr` is LazyVim's Rename, and a prefix on it would make rename wait for `timeoutlen`. Checked: `<leader>c*` in use: `ca cA cc cC cd cf cF cl cm co cO cr cR cs cS cP ci cx* cg*`; `<leader>j*`: none.

## Test design (`tests/checks/62_refactor.lua`)

Cases: `api`, `keys`, `rename_class`, `rename_class_undo`, `move_class`, `rename_package`, `inline_method`, `inline_variable`, `change_signature`, `safe_delete_blocked`, `safe_delete_free`, `fixture_restored`. Each case starts from the snapshot and restores it (`tests/lib/fixture.lua`), jdt.ls told, so a rename never leaks into the next case or the next session. "Build clean" waits for a jdt.ls publish after the edit for every touched file (003 P2 lesson: wait for the exact producer).

Negative controls: n62a (Task 0): `vim.lsp.util.apply_workspace_edit` drops every change outside the current buffer -> `rename_class`, `move_class`, `change_signature` FAIL (wrong imports, errors listed), log `/tmp/nv4j/logs/test-20261021-210328.log`. The inline cases are single-file and stay green under n62a: Task 4 adds a control for them (edit dropped entirely -> FAIL). Plan for Task 4: package rename with willRenameFiles after the move (today's hook) -> `rename_package` FAIL; safe delete that deletes despite usages -> `safe_delete_blocked` FAIL; undo split over two steps -> `rename_class_undo` FAIL.

## Trial log

| # | Change | Effect | Kept |
|---|--------|--------|------|
| t0-a | inline method by title `^Inline method` | no match: jdt.ls says "Inline Method" | pattern `^Inline [Mm]ethod` |
| t0-b | rename package through `<leader>cr` only | prepareRename refuses; the case also tries the neo-tree path | kept (both recorded) |
| t0-c | neo-tree path emulated: `fs_rename` then `Snacks.rename.on_rename_file(old, new)` | folder moved, package line not updated | baseline |
| t0-d | `Snacks.rename.on_rename_file(old, new, rename_fn)` (willRenameFiles before the move) | still wrong on disk: the edit lands in the buffer of the OLD path (unsaved), then the folder moves with the old content; the buffer points at a path that no longer exists (Review Focus 2 data-loss shape). Log `/tmp/nv4j/logs/t0-62-trial-willrename-before.out` | evidence for D23 |
| t0-e | raw `workspace/willRenameFiles` for the folder | 32 ms, one edit: `package demo.store` on the old `demo/shop/Checkout.java` uri (log `/tmp/nv4j/logs/test-20261021-210249.log`) | evidence: jdt.ls side works |
| t0-f | n62a negative control (above) | 3 cases FAIL | evidence |
