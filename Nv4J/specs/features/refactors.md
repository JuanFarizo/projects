# Feature: Refactors (rename with file move, move, rename package, inline, change signature, safe delete)

Priority: P3. Status: Task 0 done (research, fixture, failing check `62_refactor`). Task 4 is split in 4a rename class and rename package (**built**, see "Task 4a"), 4b move, 4c inline, 4d change signature, 4e safe delete (not built: their cases still measure today's path or fail). Decision: D23 in `specs/001-architecture.md`. Spec: `specs/005-p3-tests-scaffold-refactor.md`. Check: `tests/checks/62_refactor.lua`. Product (Task 4): `nvim/lua/nv4j/refactor.lua`, keys in `nvim/lua/config/keymaps.lua`.

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

`<leader>cr` stays Rename (class rename moves the file: works today), `<leader>cR` stays Rename File. New, in the "Java" group `<leader>j` (unused today, shared with scaffolding `<leader>jn`): `<leader>jm` move, `<leader>ji` inline, `<leader>js` change signature, `<leader>jd` safe delete, `<leader>jr` refactor menu (IntelliJ "Refactor This": all refactor code actions at the cursor), `<leader>jp` rename package (Task 4 may fold it into `<leader>cr` on a package line). **Task 4a ruling (user):** `<leader>jr` is rename (the class, or the package when the cursor is on the `package` line), `<leader>jp` rename package; a "Refactor This" menu, if wanted, needs another key (4b-4e). The plan's `<leader>cr` group is not used: `<leader>cr` is LazyVim's Rename, and a prefix on it would make rename wait for `timeoutlen`. Checked: `<leader>c*` in use: `ca cA cc cC cd cf cF cl cm co cO cr cR cs cS cP ci cx* cg*`; `<leader>j*`: none.

## Test design (`tests/checks/62_refactor.lua`)

Cases: `api`, `keys`, `rename_class`, `rename_class_undo`, `move_class`, `rename_package`, `inline_method`, `inline_variable`, `change_signature`, `safe_delete_blocked`, `safe_delete_free`, `fixture_restored`. Each case starts from the snapshot and restores it (`tests/lib/fixture.lua`), jdt.ls told, so a rename never leaks into the next case or the next session. "Build clean" waits for a jdt.ls publish after the edit for every touched file (003 P2 lesson: wait for the exact producer).

Negative controls: n62a (Task 0): `vim.lsp.util.apply_workspace_edit` drops every change outside the current buffer -> `rename_class`, `move_class`, `change_signature` FAIL (wrong imports, errors listed), log `/tmp/nv4j/logs/test-20261021-210328.log`. The inline cases are single-file and stay green under n62a: Task 4 adds a control for them (edit dropped entirely -> FAIL). Plan for Task 4: package rename with willRenameFiles after the move (today's hook) -> `rename_package` FAIL; safe delete that deletes despite usages -> `safe_delete_blocked` FAIL; undo split over two steps -> `rename_class_undo` FAIL.

## Task 4a: rename class and rename package (built)

Product: `nvim/lua/nv4j/refactor.lua` (`rename_class`, `rename_package`, `rename` for `<leader>jr`, `rename_paths`, `new_errors`, neo-tree handlers), keys in `nvim/lua/config/keymaps.lua`, neo-tree hooks in `nvim/lua/plugins/neo-tree.lua`.

- **Rename class** (`<leader>jr`, `rename_class({ name })`, prompt when no name): the type under the cursor (a capitalised word), else the file's own type. `textDocument/rename` to jdt.ls; its WorkspaceEdit (reference and import edits plus the `RenameFile`) is applied with `vim.lsp.util.apply_workspace_edit` (the renamed buffer is moved with `:saveas`, undo kept). A conflict (`Bill` exists) is refused by jdt.ls itself ("Compilation unit 'X.java' already exists"), shown, nothing changed.
- **Rename package** (`<leader>jr` on the `package` line, `<leader>jp`, `rename_package({ name })`): jdt.ls refuses `prepareRename` there, so the folder rename is announced with `workspace/willRenameFiles` BEFORE the move (old uris, folder still in place), the edit applied, then the folder moved with `vim.lsp.util.rename` (os.rename plus `:saveas` of every loaded buffer under it: buffers re-pointed, undo kept), then `workspace/didRenameFiles`. The namesake package folders in the project's other source roots (`src/*/java`, e.g. `src/test/java`) move too, one root at a time, `src/main/java` first: jdt.ls renames the package of ONE root and adds imports of the moved types to the namesake files of the other roots; those edits are dropped (that root's own rename follows and puts its files in the same package again, so no same-package imports are left). Refused with a message and nothing changed: target package exists (no merge), into itself, no `package` line, folder not matching the package.
- **neo-tree**: renaming or moving a `.java` file or a folder with Java files inside a jdt.ls project goes through the same `rename_paths` from neo-tree's `before_file_rename`/`before_file_move` events (handled, so neo-tree does not move it again); our `file_renamed`/`file_moved` handlers (registered before LazyVim's) stop LazyVim's after-the-move `Snacks.rename.on_rename_file` for these. Other renames keep LazyVim's path.
- **Buffers**: a touched buffer that had no unsaved changes is written after the edit; one with unsaved changes is edited in place and left unsaved; a renamed/moved file's buffer is written by the move with its unsaved changes. The summary (one notification) names every touched file with its old path and these notes, and "[outside the project]" for files outside the jdt.ls root.
- **Honest results**: a failure part-way (edit error, move error, no answer for a later root) lists what was changed and says to undo with `u` per file. 3 s after the edit (and again at 8 s when the first look found nothing), errors in the touched files or new errors anywhere (a reference jdt.ls did not update, e.g. a file with a syntax error) are shown as a warning; a newer refactor cancels the pending look.
- **Second root**: right after the first root moved, jdt.ls answered the second root's `willRenameFiles` with null on the first try in 3 of 3 check runs (the edit came on the second try 100 ms later). `rename_paths` asks up to 10 times 100 ms apart; if still null it sets the `package` lines itself (subpackages too) and says in the summary that references to those classes from other packages were not updated (twin case `rename_package_fallback`). **First root** (fix round 1): a null answer for a Java file/folder whose source and target are both in a source root is asked again the same way; still null -> refused, "nothing changed" (before the fix the folder moved with the old `package` line and no warning). Chosen over the package-line fallback because nothing has changed yet at that point (case `rename_package_first_null`, jdt.ls stubbed null).
- **Strings and config** (fix round 1, scope ruling: warn only, never rewrite): after a class rename, `stale_refs` scans the project (`.java` string literals, `@Qualifier`/`@Named`/`@Resource`/`@DependsOn` bean names, and `.properties`/`.yml`/`.xml` files; `target`, `build`, `.git` and the like skipped) for the old simple name and fully qualified name; after a package rename (and neo-tree renames) for the old package. Hits make the summary a warning: "NOT rewritten (strings/config still name Invoice, check them): file:line, ...". Measured with a planted JPQL string, a class-name string and an `application.properties` value: all 3 listed, nothing rewritten, no false hit in the renamed code, scan 17 ms on the fixture (`rename_class_strings`).
- **neo-tree package folders** (fix round 1): a folder renamed/moved inside its source root takes its namesake folders (`src/test/java`) along, as `rename_package` does (`neotree_rename_billing`).
- **neo-tree refusal** (fix round 1): neo-tree (`4d55ed3`) cannot cancel from `before_file_rename`/`before_file_move`. Verified in `fs_actions.lua`: with `handled` it skips its own `uv.fs_rename` but still runs `complete` (`rename_buffer` re-points every buffer under the old path to the new, not existing, path and force-deletes the originals; then `file_renamed` and "Renamed X successfully"). Under the old behaviour (n62u) the refused rename lost the Checkout buffer and wrote `demo/store/Checkout.java`. Now, after a refusal, the handler returns NOT handled and makes neo-tree's own rename fail: the destination exists for 1 s as a folder holding a placeholder file (`ENOTEMPTY`/`EISDIR`), neo-tree logs "Could not rename the files", nothing moves, no success toast (`neotree_refused`).
- **Pending refactors** (ruling, fix round 1): a case whose `nv4j.refactor` function is not built (`move_class`, `inline_*`, `change_signature`, `safe_delete_*`) FAILs with "pending: nv4j.refactor.<fn> not built (Task 4x)" (today's path still measured and shown after it), and `api` adds one `pending_<fn>` FAIL line per unbuilt function. `62_refactor` stays red until 4e on purpose.

Measured, 3 consecutive runs of `62_refactor` (21 PASS, 2 FAIL each: `safe_delete_*`, Task 4e), logs `/tmp/nv4j/logs/test-20261026-111555.log`, `-111628.log`, `-111821.log`:

| Case | Applied (budget 2 s) | Notes |
|------|----------------------|-------|
| `rename_class` Invoice -> Bill (5 files) | 634 to 1009 ms | build clean, written, summary; `rename_class_undo` one `u` per buffer |
| `rename_class_unsaved` | 370 to 499 ms | user edits kept; Checkout left unsaved, Bill written |
| `rename_class_boot` GreetingController -> HelloController | 60 to 105 ms | `@RestController`/`@GetMapping` kept, build clean |
| `rename_class_errors` (+ `_twin`) | 310 to 378 ms | jdt.ls skips Checkout's references (syntax error there): warning names Checkout.java |
| `rename_package` demo.shop -> demo.store | 1165 to 1231 ms | 1125 to 1173 ms of it in jdt.ls's `willRenameFiles` (first package rename of the session); edit and write 0 to 1 ms, move 38 to 56 ms |
| `rename_package_imports` demo.billing -> demo.invoicing, main and test | 654 to 806 ms | 2 tries for src/test/java each run |
| `rename_package_fallback` (jdt.ls stubbed null for src/test/java) | 1359 to 1431 ms | 10 tries of 100 ms then the fallback |
| `neotree_rename_package` / `neotree_rename_file` | 113 to 152 ms / 313 to 351 ms | LazyVim's after-the-move hook not called |
| `rename_class_conflict`, `rename_package_conflict` | refused at once | nothing changed, message |

Negative controls (product patched for one run, reverted; patches in the Task 4a report):

| # | Patch | Fails | Log |
|---|-------|-------|-----|
| n62b | edits outside the current buffer dropped | `rename_class`, `rename_class_undo`, `rename_class_unsaved`, `rename_package_imports`, `rename_package_fallback`, `neotree_rename_file` (rename_package/neotree_rename_package only edit the current file: stay green) | `/tmp/nv4j/logs/test-20261026-110528.log` |
| n62o | `new_errors` returns nothing | `rename_class_errors`, `rename_class_errors_twin` | same log; again with the final follow-up: `-111711.log` |
| n62c | folder moved before `willRenameFiles` (LazyVim's order) | `rename_package`, `rename_package_imports`, `rename_package_fallback`, `neotree_rename_package`, `neotree_rename_file` | `-110639.log` |
| n62e | an extra undo step after the edit | `rename_class_undo` | `-110639.log` |
| n62j | follow-up warning not shown | `rename_class_errors` (twin stays green) | `-110639.log`, `-111711.log` |
| n62n | `<leader>jr`/`jp` descriptions wrong | `keys` | `-110639.log` |
| n62d | `os.rename` instead of `vim.lsp.util.rename` (buffers not re-pointed) | `rename_package`, `rename_package_imports`, `rename_package_fallback`, `neotree_rename_package`, `neotree_rename_file` | `-111137.log` (first try `-110752.log` died at `attached`: jdt.ls not ready, unrelated) |
| n62f | conflict checks removed | `rename_package_conflict`; `rename_class_conflict` stayed green: jdt.ls refuses itself (trial t4a-d) | `-111137.log` |
| n62h | unsaved buffers reloaded from disk before the edit (user edits lost) | `rename_class_unsaved`, `rename_package_imports` | `-111137.log` |
| n62k | no package-line fallback | `rename_package_fallback` | `-111137.log` |
| n62p | jdt.ls's refusal not shown | `rename_class_conflict` | `-111258.log` |
| n62g | no summary | `rename_class`, `rename_class_unsaved`, `rename_package`, `rename_package_fallback` | `-111006.log` |
| n62i | neo-tree handlers not registered (LazyVim's path) | `neotree_rename_package`, `neotree_rename_file` (hook called) | `-111006.log` |
| n62l | touched buffers not written | `rename_class` ("written to disk") | `-111006.log` |
| n62m | other source roots not renamed | `rename_package_imports` | `-111006.log` |
| n62q | first-root null answer handled as before the fix (no retry, no refusal, folder moved) | `rename_package_first_null` ("returned true", folder moved), `neotree_refused` | `-113008.log` |
| n62r | `stale_refs` returns nothing | `rename_class_strings` | `-113008.log` |
| n62v | `<leader>jr` always renames the class | `jr_package_line` (prompt "Rename class Checkout") | `-113008.log` |
| n62w | the prompt's answer ignored | `prompt_class` | `-113008.log` |
| n62s | the `RenameFile` part of jdt.ls's edit dropped (control for `rename_class_boot`) | `rename_class_boot` (GreetingController.java not gone, HelloController.java missing), and every class rename case | `-113110.log` |
| n62t | neo-tree folder rename without the namesake folders | `neotree_rename_billing` | `-113110.log` |
| n62u | refusal returns `handled` (the pre-fix neo-tree behaviour) | `neotree_refused` (success toast, Checkout buffer gone, `demo/store/Checkout.java` written) | `-113110.log` |

Open items (4a):
- `<leader>jr` is rename; the planned "Refactor This" menu needs another key (4b-4e).
- neo-tree refusal: neo-tree's own "Could not rename the files" warning follows ours, and a placeholder folder exists for 1 s (fix round 1).
- Strings and config naming a renamed class or package (JPQL, `@Qualifier`, class names in `application.yml`/`.properties`/`.xml`) are not rewritten, only listed in a warning (scope ruling). Bean names that only differ by case outside those annotations, and other file types (`.sql`, `.json`, `.kt`), are not scanned.
- A moved file's buffer with unsaved changes is written by the move (`:saveas`) without asking (named in the summary).
- Only jdt.ls is asked (`willRenameFiles`); LazyVim's path asked every client (the Spring Boot LS is not told before the move).
- Other source roots are found as `<project>/src/*/java` only; another module's namesake package is not renamed (jdt.ls updates its imports).
- A namesake-root file with a fully qualified reference to a moved type loses that edit (dropped with the import edits): the follow-up warning shows the error.
- Not checked: neo-tree move (`before_file_move`, same code as rename), nested/non-public types, Gradle, files outside the root (the summary marks them; no fixture case).

## Trial log

| # | Change | Effect | Kept |
|---|--------|--------|------|
| t0-a | inline method by title `^Inline method` | no match: jdt.ls says "Inline Method" | pattern `^Inline [Mm]ethod` |
| t0-b | rename package through `<leader>cr` only | prepareRename refuses; the case also tries the neo-tree path | kept (both recorded) |
| t0-c | neo-tree path emulated: `fs_rename` then `Snacks.rename.on_rename_file(old, new)` | folder moved, package line not updated | baseline |
| t0-d | `Snacks.rename.on_rename_file(old, new, rename_fn)` (willRenameFiles before the move) | still wrong on disk: the edit lands in the buffer of the OLD path (unsaved), then the folder moves with the old content; the buffer points at a path that no longer exists (Review Focus 2 data-loss shape). Log `/tmp/nv4j/logs/t0-62-trial-willrename-before.out` | evidence for D23 |
| t0-e | raw `workspace/willRenameFiles` for the folder | 32 ms, one edit: `package demo.store` on the old `demo/shop/Checkout.java` uri (log `/tmp/nv4j/logs/test-20261021-210249.log`) | evidence: jdt.ls side works |
| t0-f | n62a negative control (above) | 3 cases FAIL | evidence |
| t4a-a | neo-tree rename in a headless check | our handlers never ran: neo-tree defers its setup (event subscription) until the tree is first shown | the check calls `require("neo-tree").ensure_config()` (a user renaming in the tree has it open) |
| t4a-b | all roots' `willRenameFiles` asked before any change | the second root's edit, computed on the original state, adds `import demo.billing.*` to the test files; jdt.ls renames one root only and adds imports to the namesake files | one root at a time, `src/main/java` first, edits for later roots' files dropped |
| t4a-c | second root asked right after the first move | jdt.ls answers null (3 of 3 check runs, not in a lone debug run) | retry 10 x 100 ms (2 tries each run), then package-line fallback with a NOTE (`rename_package_fallback`) |
| t4a-d | rename_class pre-check "target file exists" | never decides: jdt.ls refuses on its own (n62f) | removed; n62p covers the message |
| t4a-e | syntax error in a referencing file | jdt.ls renames but skips that file; its new errors came after the 3 s look in one run (`-111341.log`) | warning at 3 s, second look at 8 s when nothing was found |
| t4a-f | follow-up of the previous case fired during the next one (`-111006.log`) | errors blamed on the wrong refactor | a newer refactor cancels the pending follow-up |
| t4a-g | `vim.lsp.util.rename` on a folder | os.rename + `:saveas` of each loaded buffer under it: re-pointed, undo kept, unsaved text written (t0-d used `Snacks.rename._rename`, which deletes the buffers) | kept |
| t4a-h | profile `rename_package` 1.2 s | 1.1 s is jdt.ls's first `willRenameFiles` of the session; the same folder rename in neo-tree later in the run 113-152 ms | kept (budget met) |
| t4a-i | fix round 1: first-root null answer | before: folder moved with the old `package` line, no warning | retry, then refused with "nothing changed" |
| t4a-j | fix round 1: neo-tree refusal with `handled` | neo-tree's `complete` re-points and deletes the buffers, logs success (n62u) | not handled + neo-tree's rename made to fail (placeholder folder, 1 s) |
