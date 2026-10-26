# Feature: Refactors (rename with file move, move, rename package, inline, change signature, safe delete)

Priority: P3. Status: Task 0 done (research, fixture, failing check `62_refactor`). Task 4 is split in 4a rename class and rename package (**built**, see "Task 4a"), 4b move a class to another package (**built**, see "Task 4b"), 4c inline, 4d change signature, 4e safe delete (not built: their cases FAIL "pending" and still show today's path). Decision: D23 in `specs/001-architecture.md`. Spec: `specs/005-p3-tests-scaffold-refactor.md`. Check: `tests/checks/62_refactor.lua`. Product (Task 4): `nvim/lua/nv4j/refactor.lua`, keys in `nvim/lua/config/keymaps.lua`.

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
- **Second root**: right after the first root moved, jdt.ls answered the second root's `willRenameFiles` with null on the first try in 3 of 3 check runs (the edit came on the second try 100 ms later). `rename_paths` asks up to 10 times 100 ms apart; if still null it sets the `package` lines itself (subpackages too) and says in the summary that references to those classes from other packages were not updated (twin case `rename_package_fallback`). **First root** (fix round 1): a null answer for a Java file/folder whose source and target are both in a source root is asked again the same way; still null -> refused, "nothing changed" (before the fix the folder moved with the old `package` line and no warning), but only when the moved file(s) declare a top-level type named like their file (fix round 2): that is where an edit is due. An empty or broken file, `package-info.java` or a file without its own type gets null legitimately: it moves with the package lines set by text and a NOTE, like a later root (cases `rename_package_first_null`, `rename_package_no_type`, jdt.ls stubbed null).
- **Strings and config** (fix round 1, scope ruling: warn only, never rewrite): after a class rename, `stale_refs` scans the project (`.java` string literals, `@Qualifier`/`@Named`/`@Resource`/`@DependsOn` bean names, and `.properties`/`.yml`/`.xml` files; `target`, `build`, `.git` and the like skipped) for the old simple name and fully qualified name, plus `import` lines of the old name in any Java file (a reference jdt.ls skipped, found from the text even when jdt.ls never reports the error; fix round 2); after a package rename (and neo-tree renames) for the old package. Hits make the summary a warning: "NOT rewritten (strings/config still name Invoice, check them): file:line, ...". Measured with a planted JPQL string, a class-name string and an `application.properties` value: all 3 listed, nothing rewritten, no false hit in the renamed code, scan 17 ms on the fixture (`rename_class_strings`).
- **neo-tree package folders** (fix round 1): a folder renamed/moved inside its source root takes its namesake folders (`src/test/java`) along, as `rename_package` does (`neotree_rename_billing`).
- **neo-tree refusal** (fix round 1): neo-tree (`4d55ed3`) cannot cancel from `before_file_rename`/`before_file_move`. Verified in `fs_actions.lua`: with `handled` it skips its own `uv.fs_rename` but still runs `complete` (`rename_buffer` re-points every buffer under the old path to the new, not existing, path and force-deletes the originals; then `file_renamed` and "Renamed X successfully"). Under the old behaviour (n62u) the refused rename lost the Checkout buffer and wrote `demo/store/Checkout.java`. Now, after a refusal, the handler returns NOT handled and makes neo-tree's own rename fail with a placeholder at the destination (fix round 2: nothing is written into any folder): a file renamed onto an empty placeholder folder (`EISDIR`), a folder onto an empty placeholder file (`ENOTDIR`). neo-tree logs "Could not rename the files", nothing moves, no success toast (`neotree_refused`). The placeholder and the parents made for it go 1 s after the last refusal for that destination (a second refusal keeps it; the first timer does not remove it), at `VimLeavePre` at the latest. An existing destination is never used (neo-tree refuses existing destinations before firing the event, `rename_is_safe`/`get_unused_name`); if it exists or the placeholder cannot be made, the handler answers `handled` (neo-tree's move cannot happen; its `complete` re-points the buffers) with a warning (`neotree_placeholder`). A hard crash (kill -9) inside that second can still leave the placeholder.
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
| n62x | first-root refusal for any null answer (round 1 rule) | `rename_package_no_type` (refused, nothing moved) | `/tmp/nv4j/logs/test-20261026-114457.log` |
| n62y | placeholder timer ignores a later refusal | `neotree_placeholder` (gone 0.6 s after the 2nd refusal) | `-114457.log` |
| n62B | scan cap never reported | `stale_scan_truncated` | `-114457.log` |
| n62z | no `VimLeavePre` cleanup | `neotree_placeholder` (error: no such group) | `-114615.log` |
| n62A | an existing destination folder used (marker written into it) | `neotree_placeholder` | `-114615.log` |
| n62q | (again after round 2) first-root null handled as before round 1 | `rename_package_first_null`, `neotree_refused`, `rename_package_no_type` | `-114615.log` |
| n62C | stale `import` lines not looked for | `rename_class_errors` (summary misses Checkout.java:3) | `-114856.log` |
| n62o | (again) `new_errors` returns nothing | `rename_class_errors_twin` | `-114856.log` |
| n62D | `follow_up` does nothing (fix round 3) | `follow_up_warning` (no warning) | `/tmp/nv4j/logs/test-20261026-120519.log` |
| n62E | a newer refactor no longer cancels the pending follow-up | `follow_up_warning` (A's warning shown, and a stale Invoice -> Bill warning from an earlier case 451 ms after B started) | `-115853.log` |

Open items (4a):
- `<leader>jr` is rename; the planned "Refactor This" menu needs another key (4b-4e).
- neo-tree refusal: neo-tree's own "Could not rename the files" warning follows ours, and a placeholder (empty file or folder at the destination) exists for 1 s; removed at `VimLeavePre`, not after a hard crash.
- **Open investigation (not explained):** after the rename with a syntax error in Checkout, jdt.ls never published Checkout's new errors in 2 of 11 runs (15 s, `/tmp/nv4j/logs/test-20261026-114229.log`, `-114457.log`). The follow-up warning then stays silent; the summary still names the stale `import`, but a same-package reference (no import) in such a file is not found. Cause unknown (jdt.ls build scheduling? the skipped file being unsaved?).
- One full `62_refactor` run (`-120005.log`) had jdt.ls stalling: `willRenameFiles` timed out after 3 s (refused, "nothing changed"), a class rename took 19.7 s; not seen in the runs before or the 2 right after (`-121019.log`, `-121124.log`). Not investigated.
- `follow_up` is asserted by `follow_up_warning` only with errors planted in a check namespace (fix round 3); with jdt.ls's own errors it is shown, not required (`rename_class_errors`).
- Strings and config naming a renamed class or package (JPQL, `@Qualifier`, class names in `application.yml`/`.properties`/`.xml`) are not rewritten, only listed in a warning (scope ruling). Bean names that only differ by case outside those annotations, and other file types (`.sql`, `.json`, `.kt`), are not scanned. The scan stops after 5000 scannable files (`require("nv4j.refactor").scan_max_files`) and the warning says so.
- A moved file's buffer with unsaved changes is written by the move (`:saveas`) without asking (named in the summary).
- Only jdt.ls is asked (`willRenameFiles`); LazyVim's path asked every client (the Spring Boot LS is not told before the move).
- Other source roots are found as `<project>/src/*/java` only; another module's namesake package is not renamed (jdt.ls updates its imports).
- A namesake-root file with a fully qualified reference to a moved type loses that edit (dropped with the import edits): the follow-up warning shows the error.
- Not checked: neo-tree move (`before_file_move`, same code as rename), nested/non-public types, Gradle, files outside the root (the summary marks them; no fixture case).

## Task 4b: move a class to another package (built)

Product: `require("nv4j.refactor").move({ package })` in `nvim/lua/nv4j/refactor.lua`, key `<leader>jm` ("Refactor: move class to another package") in `nvim/lua/config/keymaps.lua`.

- **Mechanism (deviation from D23's "code action" wording, same jdt.ls engine):** the move goes through `rename_paths`, the package-rename path of 4a, with one file: `workspace/willRenameFiles` for `demo/billing/Invoice.java -> demo/shop/Invoice.java` BEFORE the move. jdt.ls's `FileEventHandler.computeMoveEdit` calls `MoveHandler.move` with the target package, the same call as the "Move 'Invoice'..." code action's `java/move` (measured: identical edits, 206 to 247 ms against 221 to 400 ms, trial t4b-a). The client moves the file, so 4a's buffer handling, summary, strings/config scan, retry/refusal on a null answer and the 3 s follow-up are reused unchanged; `java/move` would also need `java/getMoveDestinations`, which lists only packages that exist.
- **Which class:** the file's own top-level type (named like the file), when the cursor is inside it or outside every type (package/import lines). Found with `textDocument/documentSymbol` (2 s timeout; without hierarchical symbols, the text decides). Refused with the reason and nothing changed: cursor in a nested type ("only top-level types move"), cursor in a second top-level type of the file (jdt.ls moves whole files), no type named like the file. IntelliJ's F6 on a reference moves the referenced class; here the cursor's enclosing type decides.
- **Target:** `opts.package`, else `vim.ui.select` of the project's packages (folders with a `.java` file in any `src/*/java`, the current package left out) plus "New package...", which asks with `vim.ui.input`. The file always stays in its own source root (`src/main/java` class -> `src/main/java/<target>`).
- **Refusals (nothing changed):** invalid package name (each part a Java identifier, no keyword: `demo.1x`, `demo.class`); same package (INFO "already in package X; nothing to do"); a `<target>/<Name>.java` in ANY source root of the project (`src/test/java/demo/shop/Invoice.java` too: two `demo.shop.Invoice` would shadow each other), "nothing overwritten"; jdt.ls gives no edit after 10 tries over 1 s (4a's refusal); cursor rules above.
- **Missing target package:** the folder (and parents) is created and jdt.ls told with `workspace/didChangeWatchedFiles` (created); the summary says "created package folder ...". If the move is refused or fails, the folders made for it are removed when empty and jdt.ls told (deleted). jdt.ls answers null for a target folder that does not exist (trial t4b-b).
- **Test class:** jdt.ls moves only the class's file. A `<Name>Test`/`<Name>Tests`/`<Name>IT` in the old package of another source root stays there (jdt.ls adds the import of the moved class to it, like to every other referencing file); the summary says "src/test/java/demo/billing/InvoiceTest.java stays in package demo.billing (only Invoice moves; move it too with <leader>jm ...)". Not moved automatically (IntelliJ does not either, unless asked).
- **Spring Boot:** annotations stay as they are (moving a controller is a plain file move with the package line changed). A class with a stereotype (`@RestController`, `@Controller`, `@Service`, `@Component`, `@Repository`, `@Configuration`, `@ControllerAdvice`, `@RestControllerAdvice`) moved outside every `@SpringBootApplication` class's package (found in `src/main/java`, scan capped like the strings scan) gets a warning: component scanning will not find it unless `@ComponentScan`/`scanBasePackages` names the target (those are not read).
- **Strings and config:** only the old fully qualified name is stale after a move (`demo.billing.Invoice` in strings, `.properties`/`.yml`/`.xml`, `import demo.billing.Invoice;` lines left behind); the simple name is still right and is not searched (it was for class renames). neo-tree moves of a file to another folder now use the same patterns (before: the simple-name patterns of a rename, false hits on `"Invoice"`).
- **Unsaved buffers, undo, files outside the root, errors elsewhere:** as in 4a (rename_paths): a referencing buffer with unsaved edits is edited in place and left unsaved; the moved file's buffer is written by the move with its unsaved edits (named in the summary); one `u` per buffer gives its text back (the file stays in the new folder); files outside the jdt.ls root are marked in the summary; the 3 s/8 s follow-up reports errors in touched files or new ones. With a syntax error in Checkout, jdt.ls still updated its import on a move (unlike a class rename, which skips that file; measured every run); when an import is left (stubbed twin), the summary names it (`Checkout.java:3`).
- **neo-tree** `m` (move a `.java` file to another folder) already went through `rename_paths` since 4a (label "Moved class X to package Y"); it does not get the 4b-only checks (other-root conflict, test note, Spring warning, created-folder cleanup). Not checked by a case.

Measured, 3 consecutive runs of `62_refactor` after the last code change (each `DONE 62_refactor 44 8`, the 8 FAILs = the pending inline/change signature/safe delete lines), logs `/tmp/nv4j/logs/test-20261026-160629.log`, `-160755.log`, `-160919.log` (60/61 regression after it: `DONE 60_tests_runner 20 0`, `DONE 61_scaffold 27 0`, `-161043.log`):

| Case | Applied (budget 2 s) | Notes |
|------|----------------------|-------|
| `move_class` Invoice -> demo.shop (5 files) | 382 to 461 ms | willRenameFiles 134 to 189 ms, edit+write about 200 ms; build clean; `move_class_undo` one `u` per buffer |
| `move_class_unsaved` | 390 to 457 ms | Checkout left unsaved with its edit, moved file written with its edit |
| `move_class_new_package` demo.invoicing | 426 to 517 ms | folder created; once 1.5 to 1.7 s in NC runs (jdt.ls busy, open items) |
| `move_prompt` / `move_key_new_package` | 361 to 505 ms / 456 to 1684 ms | select of packages; `<leader>jm` + "New package..." |
| `move_class_boot` (demo.web) / `_boot_scan` (web) | 155 to 1184 ms / 94 to 122 ms | annotations kept, build clean; warning outside `demo` |
| `move_class_test_stays`, `move_class_stale` | 373 to 403 ms, 421 to 497 ms | InvoiceTest stays (import added, summary says so); properties line listed, no simple-name hit |
| `move_class_errors`, `_skipped_twin` | 315 to 428 ms, 358 to 452 ms | jdt.ls updated Checkout despite the syntax error (3 of 3); twin: warning names Checkout.java:3 |
| `move_new_package_refused` | refused after 964 to 1003 ms | 10 null answers, created folder removed |
| `move_invalid`, `move_same_package`, `move_conflict`, `move_not_top_level` | at once | nothing changed, reason shown |

Negative controls (product patched for one run, reverted; patcher with exact-text patches, as in 4a):

| # | Patch | Fails | Log |
|---|-------|-------|-----|
| n62F | `move` moves the file without jdt.ls (`vim.lsp.util.rename` only) | `move_class`, `_undo`, `_unsaved`, `_new_package`, `move_new_package_refused`, `move_prompt`, `move_key_new_package`, `move_class_boot`, `_boot_scan`, `_test_stays`, `_stale`, `_errors`, `_skipped_twin` | `/tmp/nv4j/logs/test-20261026-160113.log` |
| n62U | an extra undo step on the moved buffer after the move | `move_class_undo` (Invoice.java) | `-155915.log` |
| n62R | buffers with unsaved edits reloaded from disk before the move | `move_class_unsaved`, `move_class_errors` | `-155915.log` |
| n62V | the target folder not created | `move_class_new_package`, `move_key_new_package`, `move_class_boot`, `move_class_boot_scan` | `-160349.log` |
| n62P | created folder not removed after a refusal | `move_new_package_refused` (demo/invoicing left behind) | `-155741.log` |
| n62H | package name not validated | `move_invalid` | `-155741.log` |
| n62I | same-package check removed | `move_same_package` (the move path's "already exists" error instead of the INFO) | `-155741.log` |
| n62J | target class not looked for in the source roots | `move_conflict` (the src/test/java sub-case moved Invoice) | `-155741.log` |
| n62K | cursor rule removed (always the file's type) | `move_not_top_level` (Order moved) | `-155741.log` |
| n62L | the picked package ignored | `move_prompt` | `-155915.log` |
| n62M | no Spring component-scan warning | `move_class_boot_scan` | `-155741.log` |
| n62N | no test-stays note | `move_class_test_stays` | `-155741.log` |
| n62O | class-rename patterns (simple name) for a move | `move_class_stale` (false hit on InvoiceLabels.java) | `-155915.log` |
| n62Q | old-name `import` lines not looked for after a move | `move_class_skipped_twin` | `-155741.log` |
| n62G | jdt.ls not told about the created folder (`didChangeWatchedFiles` skipped) | nothing: `move_class_new_package` still passed with 2 tries instead of 1 (Neovim's own file watcher told jdt.ls); kept for clients without that watcher, n62V is its control | `-155915.log` |

Open items (4b):
- Moving several classes at once, a whole package into another (jdt.ls: "upstream JDT supports only moving Java files"), moving a nested type to the top level, moving to another module/source root: not supported.
- The test class is not moved along (said in the summary); the old package folder is left when it becomes empty.
- Spring warning: `@ComponentScan`/`scanBasePackages`/`@Import` not read (could be a false warning); `@SpringBootApplication` looked for only in `src/main/java`.
- Single slow moves: `move_key_new_package` 1684 ms (`-160919.log`), `move_class_boot` 1184 ms (`-160629.log`), and `move_class_new_package` once took 1.5 to 1.7 s (jdt.ls's `willRenameFiles` 1163 ms in `-155741.log`, `documentSymbol` 1171 ms in `-155915.log`, both right after the previous case's restore and build); usually about 0.4 s. Within the 2 s budget, close to it when jdt.ls is still busy.
- Default package: moving out of it is allowed (jdt.ls adds the `package` line; not checked); moving into it is not offered (an empty name cancels).
- Gradle, multi-module, files outside the root: not checked (the summary marks files outside the root).

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
| t4a-k | fix round 2: `rename_class_errors` and its twin waited for jdt.ls's errors on Checkout | in 2 of 11 runs jdt.ls never published them (15 s; `-114229.log`, `-114457.log`): the follow-up had nothing to show | the stale `import` is found from the text (summary warning, deterministic); the twin plants the error in a check namespace; the follow-up is reported, not required |
| t4a-j | fix round 1: neo-tree refusal with `handled` | neo-tree's `complete` re-points and deletes the buffers, logs success (n62u) | not handled + neo-tree's rename made to fail (placeholder folder, 1 s) |
| t4b-a | `willRenameFiles` (file move) against `java/getMoveDestinations` + `java/move` (scratch check, `/tmp/nv4j/logs/test-20261026-154744.log`) | identical edits (Checkout import dropped, PriceCalculator and the 2 billing tests import `demo.shop.Invoice`, package line); `willRenameFiles` 400/228/221 ms, `java/move` 218/247/206 ms; the first `willRenameFiles` right after jdt.ls was ready took 2175 ms (`-154704.log`) | `willRenameFiles` through `rename_paths` (4a's path reused) |
| t4b-b | target folder missing / created but jdt.ls not told / created and told (same log) | null at once (2 to 4 ms) / null / edit (362 ms) | create the folder, tell jdt.ls, then ask (retries of rename_paths cover the rest) |
| t4b-c | `move_class_errors` written like `rename_class_errors` (expecting Checkout's import left) | jdt.ls updated Checkout's import despite the syntax error (`-155335.log`) | the case accepts either honest result; a stubbed twin drops Checkout's edit and asserts the warning |
| t4b-d | n62G: no `didChangeWatchedFiles` for the created folder | still moved (2 tries): Neovim's watcher tells jdt.ls on macOS | notify kept (cheap; Neovim's watcher is off on some systems), n62V is the control |
