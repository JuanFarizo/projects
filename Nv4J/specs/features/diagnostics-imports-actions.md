# Feature: diagnostics, imports, code actions

Priority: P1. Status: implemented (Task 6). Final numbers and the trial log are at the end.

Pass/fail tests (run by `tests/run.sh`):

| Check | Covers |
|-------|--------|
| `tests/checks/30_diagnostics.lua` | unused code warnings, errors, no duplicates, one renderer, typing burst settles, fix clears, Java 25 without false diagnostics, bad/fixed pom.xml (visible notification, automatic reload, no notice on wipe), missing artifact, unused imports while the file has errors (nv4j pass: javadoc/annotation/static uses not flagged, cleared on removal, no duplicate without errors, 3000-line cost) |
| `tests/checks/31_imports.lua` | auto-import on the first accepted completion of a session and on a second documented type (through blink.cmp's accept), Spring import lands in its group, `<leader>co` removes unused imports and orders groups (also with a compile error), `<leader>co` only means Organize Imports, `<leader>cO` outgoing calls |
| `tests/checks/32_code_actions.lua` | create method (same class, other class), create variable/field, create class, import type, implement methods, remove unused import/local, generate getters/setters, constructor, toString, equals/hashCode, extract variable/constant/method, Lombok members resolve |

Planted sources: `tests/fixtures/planted/*.java.txt` (they declare `public class App` and replace the App.java buffer in memory, never on disk; the brief named `demo/src/main/java/demo/Broken.java.txt`, moved out of the Maven source tree so the fixture stays a clean project). Temp Maven projects: `/tmp/nv4j/pomcase` (check 30), `/tmp/nv4j/lombokcase` (check 32). Timings: `/tmp/nv4j/logs/latency.jsonl` (`diag_*`, `pom_*`, `import_accept_*`, `organize`, `code_action_*`).

## Sources read

| Repo | Local copy (read only) | Commit | Paths added to the sparse checkout for this task |
|------|------------------------|--------|-----------------------------------------------|
| intellij-community | `~/.cache/nv4j/intellij-community` | `b633034bb` | `java/java-impl/src/com/intellij/codeInsight/daemon/impl/quickfix/`, `.../codeInsight/generation/`, `java/java-analysis-impl/src/com/intellij/codeInsight/daemon/impl/analysis/`, `.../codeInspection/unusedImport/`, `.../unusedSymbol/`, `java/java-frontback-impl/src/com/intellij/psi/codeStyle/`, `platform/analysis-impl/src/com/intellij/codeInsight/{CodeInsightSettings.java,daemon/}`, `java/java-impl/src/org/jetbrains/java/generate/GenerateToStringActionHandlerImpl.java` |
| eclipse.jdt.ls | `~/.cache/nv4j/eclipse.jdt.ls` | `b52e20a` | `org.eclipse.jdt.ls.core/src/org/eclipse/jdt/ls/core/internal/{handlers,corrections,text/correction}/` |
| eclipse.jdt.core | `~/.cache/nv4j/eclipse.jdt.core` | `cd40048` | `org.eclipse.jdt.core.compiler.batch/src/org/eclipse/jdt/internal/compiler/{ast/CompilationUnitDeclaration.java,ast/AbstractMethodDeclaration.java,lookup/CompilationUnitScope.java}` |
| nvim-jdtls | `~/.local/share/nv4j/lazy/nvim-jdtls` | `6e9d953` | (plugin install) |
| blink.cmp v1.10.2 | `~/.local/share/nv4j/lazy/blink.cmp` | | (plugin install) |

Installed server: jdt.ls 1.62.0, jdt.core 3.48.0, m2e 2.8.0 (Mason). The clones are `master`, so line numbers can differ slightly from what runs. No code copied.

Not in the sparse clones (so not checked, only user-visible behaviour is cited): IntelliJ's `ShowAutoImportPass`/`ImportHelper` internals beyond the code-style table, the IntelliJ Maven sync UI (closed `maven` plugin parts), jdt.core's `ImportRewriteAnalyzer` (import grouping was measured instead of read).

## 1. Diagnostics

### IntelliJ

- Re-highlights `AUTOREPARSE_DELAY_DEFAULT = 300` ms after the last change (`platform/analysis-impl/src/com/intellij/codeInsight/daemon/DaemonCodeAnalyzerSettings.java`).
- Unused imports: `UnusedImportsVisitor` (`java/java-analysis-impl/src/com/intellij/codeInsight/daemon/impl/analysis/UnusedImportsVisitor.java`) marks each import by its own reference count, also when the file has other errors (only an import with a parse error itself is skipped, `PsiUtilCore.hasErrorElementChild`). It also flags mis-sorted imports (`MissortedImportsInspection`).
- Unused locals/fields/methods: `UnusedSymbolLocalInspection`, `UnusedDeclarationInspection`.
- Maven: a failed sync is shown in the Build tool window plus a balloon (closed source, user-visible behaviour).

### JDT / jdt.ls

- Debounce on the server: validation `DOCUMENT_LIFECYCLE_MAX_DEBOUNCE = 400` ms and publish `400..2000` ms adaptive (`handlers/BaseDocumentLifeCycleHandler.java`). The old comment in `java.lua` ("jdtls has no debounce of its own") was wrong and is corrected.
- Severity: ECJ warnings become LSP Warning, unused/unnecessary problems get `DiagnosticTag.Unnecessary` (`handlers/BaseDiagnosticsHandler.java`, `getDiagnosticTag`, `convertSeverity`), which Neovim draws faded (`_tags.unnecessary`).
- **Gap: unused warnings disappear while the file has errors.** ECJ checks unused imports only `if (!this.compilationResult.hasMandatoryErrors())` (`CompilationUnitDeclaration.java:664`), and a method with an error gets `ignoreFurtherInvestigation`, so its unused locals are not reported either. Measured: the same unused import + unused local, with and without one type error in the file: 4 warnings vs 0 (explore run, see trial T0). Unused private fields/methods elsewhere in the file are still reported. IntelliJ shows them in both cases. Not configurable in jdt.ls. **User decision (fix round 1): unused imports must show anyway** -> `nv4j/unused_imports.lua` (below). Unused locals in a method with an error stay a JDT gap.
- Per-file cap: `maxProblemsPerUnit` 100 (measured 100 diagnostics for a file with 150 errors).
- Maven: m2e puts build-file problems as markers on `pom.xml` (`Project build error: Non-readable POM ...`, `Missing artifact g:a:jar:v`) and on the project (`The container 'Maven Dependencies' references non existing library ...`). With `updateBuildConfiguration = interactive` (jdt.ls default, `Preferences.java`) an Information diagnostic "The build file has been changed and may need reload to make it effective." stays on `pom.xml`.

### Neovim side

- `vim.diagnostic.config`: LazyVim defaults (`update_in_insert = false`, `severity_sort = true`), built-in `virtual_text = false` because tiny-inline-diagnostic draws inline (`plugins/diagnostics.lua`). Decision: keep `update_in_insert = false`: errors refresh on InsertLeave, so the half-typed line does not flicker red while typing. The checks run in normal mode.
- `flags.debounce_text_changes`: 500 vs 200 ms measured the same edit-to-screen time (460-690 ms), because Neovim's semantic-token request flushes pending didChange after about 200 ms and jdt.ls's own 400 ms publish debounce dominates. 500 stays.
- tiny-inline-diagnostic cost: `vim.diagnostic.set` with all DiagnosticChanged handlers (tiny-inline, nv4j.buildfile) takes 3-6 ms for 100 diagnostics, 0.4 ms to clear (headless; drawing itself cannot be measured headless).

### Design

- Config only, plus `nvim/lua/nv4j/buildfile.lua` (small Lua, config cannot do it): on `DiagnosticChanged` for `pom.xml`/`build.gradle(.kts)`/`settings.gradle(.kts)`, one `vim.notify` (ERROR, title "Build file") per distinct set of jdt.ls errors, and an INFO "build errors fixed" when they are gone. Without it the user sees only unresolved types in Java files and no reason.
- `java.configuration.updateBuildConfiguration = "automatic"`.
- `nvim/lua/nv4j/unused_imports.lua` (user decision A, fix round 1): unused-import warnings while the file has compile errors. Treesitter only, no LSP request. Imports come from the tree (static ones by member name, wildcards skipped); for each simple name a plain text search over the body, and each hit is accepted when the tree says it is an `identifier`/`type_identifier` (types, calls, annotations, scoped references) or sits in a `/** */` comment after `{@link`, `{@linkplain`, `{@value`, `@see`, `@throws`, `@exception` (javadoc counts as a use, like JDT and IntelliJ). It publishes only while jdt.ls reports at least one ERROR in the buffer: then ECJ reports no unused import itself, so there is never a duplicate, and in a file without errors jdt.ls owns the warning. Same message and range as jdt.ls ("The import a.b.C is never used", Warning, Unnecessary tag), namespace `nv4j.unused_imports`. Runs on every jdt.ls DiagnosticChanged and 400 ms after the last text change, never in the completion or keystroke path. Cost on a 3000-line file: p50 1.4 ms, p95 2.4 ms per pass including the incremental reparse (check `unused_pass_perf`). Known limits: a fully qualified use (`java.util.Map` in the body) or a name only in a string counts as used only when the tree says identifier; a qualified reference therefore marks the import used (JDT would flag it).

## 2. Imports

### IntelliJ

- Import layout default (`java/java-frontback-impl/src/com/intellij/psi/codeStyle/JavaCodeStyleSettings.java`, lines ~421-427): module imports, all other, blank, `javax.*`, `java.*`, blank, static. Wildcards at `CLASS_COUNT_TO_USE_IMPORT_ON_DEMAND = 5`, `NAMES_COUNT_TO_USE_IMPORT_ON_DEMAND = 3`.
- Completion inserts the import synchronously in the insert handler (`java/java-impl/src/com/intellij/codeInsight/completion/JavaClassNameInsertHandler.java:117`, `PsiTypeLookupItem.addImportForItem`).
- `OPTIMIZE_IMPORTS_ON_THE_FLY` and `ADD_UNAMBIGIOUS_IMPORTS_ON_THE_FLY` default false (`platform/analysis-impl/src/com/intellij/codeInsight/CodeInsightSettings.java:172-174`); optimize on save is an opt-in "Actions on Save" item.
- Import quick fix candidates are sorted by proximity (`ImportClassFixBase`, `CodeInsightUtil.sortIdenticalShortNamedMembers`).

### JDT / jdt.ls

- `java.completion.importOrder` (default `java, javax, org, com`, `Preferences.java:815`) feeds `ImportRewrite.setImportOrder` (`contentassist/TypeProposalUtils.java:167`) and organize imports (`CodeStyleConfiguration.ORGIMPORTS_IMPORTORDER`). `""` matches every package no other entry matches, `#` is the static group (measured, see the order below). jdt.ls default places static imports first and `jakarta` after `com`.
- Star thresholds `java.sources.organizeImports.starThreshold`/`staticStarThreshold`, default 99.
- **The auto-import arrives only in `completionItem/resolve`** when the client advertises `additionalTextEdits` in `resolveSupport` (`contentassist/CompletionProposalReplacementProvider.java:199`); blink.cmp does. The same resolve renders the javadoc (`handlers/CompletionResolveHandler.java`). Measured resolve cost per type (Spring fixture, after warm-up): `ArrayList` 474 ms, `List` 384, `HashMap` 400, `ObjectMapper` 709, `HttpStatus` 46, `LinkedList` 29: cost follows javadoc size, it is not a one-time warm-up cost.
- blink.cmp waits on accept for resolve only `completion.accept.resolve_timeout_ms` (default 100 ms, `blink/cmp/completion/accept/init.lua`), then inserts the item as is. **Root cause of "completing a type does not add the import"**: measured, the first accepted `List` of a session was inserted without `import java.util.List;` (accept 591-778 ms, import missing), a second accept of an already resolved type worked.
- Organize imports (`java/organizeImports`, `handlers/OrganizeImportsHandler.java`) takes the AST before waiting for the document jobs; a request sent in the same instant as the first edit of a session returned `null` (no edit) in 3/3 tries; with 200 ms or more between edit and request it worked 100% (14/14). A user cannot press `<leader>co` that fast, so only noted.
- `java.saveActions.organizeImports` (default false) runs organize on willSaveWaitUntil.

### Design

- `importOrder = { "", "javax", "jakarta", "java", "#" }` (user's choice: all other, javax/jakarta, java, static). Result of organize on `tests/fixtures/planted/imports.java.txt`:

  ```java
  import com.fasterxml.jackson.databind.ObjectMapper;
  import org.springframework.http.ResponseEntity;

  import javax.sql.DataSource;

  import jakarta.validation.Valid;

  import java.util.ArrayList;
  import java.util.List;

  import static java.util.Objects.requireNonNull;
  import static org.springframework.http.HttpStatus.OK;
  ```

  Gap: Eclipse puts a blank line between every group; IntelliJ has none between `javax` and `java`. Cosmetic, not configurable per group.
- Star thresholds 99 (no wildcard imports; Spring's own code style forbids them; IntelliJ would fold at 5).
- blink `completion.accept.resolve_timeout_ms = 1500` (`plugins/blink.lua`). Accept waits only as long as resolve really takes (measured 438-783 ms for documented JDK types, 15-20 ms for constructors and project types); the import is then always added. Gap to IntelliJ: accepting a well documented type that the doc popup has not resolved yet stalls up to about 0.8 s once per type. A warm-up resolve at ServiceReady was tried and did not help (trial T2), because the cost is per type.
- Organize on save: **off** (IntelliJ default). It would remove an import added just before its first use, and it adds a synchronous request to every save. To turn it on: `java.saveActions.organizeImports = true` in `plugins/java.lua` settings.
- Keys (user decision B, fix round 1):

  | Key | Where | Action |
  |-----|-------|--------|
  | `<leader>co` | Java buffers (LazyVim jdtls extra, buffer-local) | Organize Imports: removes unused imports and orders the groups, also when the file has compile errors (check `organize_with_compile_error`) |
  | `<leader>cO` | everywhere (`config/keymaps.lua`) | Outgoing calls (the old global `<leader>co` alias was dropped, each key means one thing) |
  | `<leader>ci` | everywhere | Incoming calls |
  | `<leader>ca` | everywhere (LazyVim) | Code actions, including "Organize imports", "Remove unused import", generate, extract |
  | `<leader>cxv` / `<leader>cxc` / `<leader>cxm` (visual) | Java buffers (LazyVim jdtls extra) | Extract variable / constant / method |

  Organize on save stays off (user decision B).

## 3. Code actions

### IntelliJ

Quick fixes in `java/java-impl/src/com/intellij/codeInsight/daemon/impl/quickfix/` (e.g. `CreateMethodFromUsageFix.java`, `ImplementMethodsFix.java`, `ImportClassFix.java`), generators in `java/java-impl/src/com/intellij/codeInsight/generation/` (`GenerateConstructorHandler`, `GenerateEqualsHandler`) and `org/jetbrains/java/generate/GenerateToStringActionHandlerImpl.java`. Field preselection: toString selects every field of the class (`getPreselection`), constructor selects the final fields (`GenerateConstructorHandler.preselect`). Default toString template: `App{name='x', age=1}`.

### jdt.ls

Everything the user asked for is offered (titles measured in check 32):

| Situation | jdt.ls action |
|-----------|---------------|
| undefined method, same class | `Create method 'twice(int)'` |
| undefined method, other class | `Create method 'doesNotExist()' in type 'Repo'` |
| undefined variable | `Create local variable` / `Create field` / `Create parameter` |
| undefined class | `Create class/interface/enum/record 'Undef'` |
| type not imported | `Import 'List' (java.util)` first, then other packages; `Add all missing imports` |
| missing interface method | `Add unimplemented methods` |
| unused import | `Remove unused import`, `Remove all unused imports` |
| unused local | `Remove 'unused' and all assignments` |
| generate | `Generate Getters and Setters`, `Generate Constructors...`, `Generate toString()...`, `Generate hashCode() and equals()...`, `Generate Delegate Methods...`, `Override/Implement Methods...` |
| extract (selection) | `Extract to local variable`, `... (replace all occurrences)`, `Extract to constant`, `Extract to field`, `Extract to method`, `Introduce Parameter...` |

Actions with `data` are resolved by Neovim (`codeAction/resolve`); the `...` ones are client commands nvim-jdtls implements (`java.action.generateToStringPrompt`, `hashCodeEqualsPrompt`, `generateConstructorsPrompt`, `applyRefactoringCommand`, `overrideMethodsPrompt`), registered in `vim.lsp.commands`. Round trip 9-120 ms.

Gaps found:

- nvim-jdtls's field picker (`jdtls/ui.lua` `pick_many`, a `vim.fn.input` loop) starts with nothing selected for toString and equals/hashCode: pressing Enter generated `toString()` over zero fields. Fixed by `nvim/lua/nv4j/codegen.lua` (preselect every item with jdt.ls's `isField`; methods/getters stay off). Constructors keep jdt.ls's preselection (the field under the cursor; IntelliJ: final fields).
- toString template: jdt.ls cannot quote only strings, so the closest to IntelliJ is `App{name=x, age=1}` (template `${object.className}{${member.name()}=${member.value}, ${otherMembers}}`). Default was `App [name=..., getName()=..., getClass()=..., hashCode()=...]`.
- equals/hashCode: with `useJava7Objects` JDT writes `Objects.hash(name, Integer.valueOf(age))` (explicit boxing; IntelliJ `Objects.hash(name, age)`). Not configurable.
- The picker is a numbered `input()` prompt, not a checkbox list as in IntelliJ. Works, ugly; left as a P3 UX item.

### Lombok

- jdt.ls has no `java.jdt.ls.lombokSupport.enabled` server preference (grep of `Preferences.java`: no lombok key); that is a vscode-java client setting that adds the agent. Here LazyVim's java extra adds `--jvm-arg=-javaagent:$MASON/share/jdtls/lombok.jar` (Mason ships the current lombok.jar). Check 32 asserts the running jdtls has that agent and the jar exists.
- The demo fixture has no Lombok (adding it would change the `@` completion list that check 11 ranks). Check 32 builds `/tmp/nv4j/lombokcase` (lombok 1.18.46 `provided`, release 25): `@Getter @RequiredArgsConstructor` class, a user class calling `new Item("pen", 2).getName()`/`getCount()` -> 0 diagnostics, and `item.` completion lists `getName`.

### Design (codeGeneration settings)

`useBlocks = true`, `generateComments = false`, `hashCodeEquals = { useJava7Objects = true, useInstanceof = false }`, `toString = { template = ..., codeStyle = "STRING_CONCATENATION" }`.

## Planned follow-ups

- **Async import apply** (removes the accept stall, gap 2): accept with a short resolve timeout (about 150 ms) and, when the late `completionItem/resolve` returns, apply its `additionalTextEdits` if they do not overlap edits made since. Needs a small blink.cmp accept hook or a wrapper around the lsp source; to be done with the P3 plan. The README (Task 7) lists it under known gaps.
- **Frecency vs project ranking**: see `specs/002-p1-completion.md`, follow-ups.

## Harness findings (fixed in Task 6)

- blink.cmp's frecency database (`stdpath('state')/blink/cmp/frecency.dat`) boosts every item with a label the user accepted, even for an empty prefix. Accepting `List` a few times (explorations, check 31) pushed the nested `@...List` container annotations to the top of `@` and check 11 dropped `RestController` from rank 4 to 27. Check 31 stubs `blink.cmp.fuzzy.access`; `run.sh` sets `XDG_STATE_HOME=/tmp/nv4j/state` so the user's own frecency never moves ranks in the checks and the checks never write into it. The polluted file in `~/.local/state/nv4j/blink/cmp/` was reset (backup `/tmp/nv4j/backup/frecency.dat.bak`).
- An aborted manual exploration ended on `qa`, hit "Save changes?" with stdin at EOF and saved in-memory edits into `App.java`/`Person.java` (restored with `git checkout`). `run.sh` now ends each check with `qa!` and `</dev/null`.
- blink's accept writes the `.` register through an insert-mode `vim.fn.complete`, impossible headless; check 31 stubs only that (`write_to_dot_repeat`). The rename prompt after an extract and nvim-jdtls's field `input()` are stubbed (cancel / Enter).

## Trial log

One change per trial; numbers from `NV4J_CHECKS='3*' tests/run.sh` unless noted.

| # | Change | Result | Kept |
|---|--------|--------|------|
| T0 | Baseline (Task 5 config), first run of checks 30-32 (log `test-20261020-210744.log`) | diagnostics 469-689 ms; FAIL: `auto_import_first` (accept 769 ms, import MISSING), `organize_order` (static first, jakarta last), `maven_malformed/fixed/missing` (no notification, "may need reload" leftover, fixed pom never clean within 30 s), `apply_tostring` (`App [name=..., getName()=..., getClass()=...]`), `apply_equals_hashcode`, `outgoing_calls_key`; explore: unused import + local reported 4/4 without errors, 0/4 with one error | n/a |
| T1 | blink `completion.accept.resolve_timeout_ms` 100 -> 1500 | `auto_import_first` import added, accept 578-783 ms; `auto_import_second` (HashMap) 438-449 ms | kept |
| T2 | Warm-up `completionItem/resolve` at ServiceReady (`nv4j/warmup.lua`), with the 100 ms timeout | resolve of the warm-up item 14-18 ms (project constructor), first accept still 591-646 ms, import MISSING: cost is per documented type | reverted |
| T3 | `importOrder = { "", "javax", "jakarta", "java", "#" }`, star thresholds 99 | `organize_order` PASS (order above), organize 161-201 ms; `auto_import_group` still PASS | kept |
| T4 | `updateBuildConfiguration = "automatic"` | fixed pom clean in 356-600 ms (was > 30 s with a leftover Information diagnostic) | kept |
| T5 | `nv4j/buildfile.lua` notifier | malformed pom: error 208-318 ms + notification; missing artifact 688-997 ms + notification | kept |
| T6 | `codeGeneration.*` + `nv4j/codegen.lua` field preselection | toString `"App{name=" + name + ", age=" + age + "}"`; equals/hashCode with `Objects.hash`/`Objects.equals` and braces | kept |
| T7 | `<leader>cO` = outgoing calls | PASS | kept |
| T8 | Harness: frecency isolation (check 31 stub, `XDG_STATE_HOME`), reset of the polluted database | check 11 `@` rank back from 27 to 4 | kept |
| T9 | `debounce_text_changes` 500 -> 200 (checks 10 and 30, 2 runs) | errors 471/461 ms vs 468/457/469 ms; unused 686/672 vs 694/669/657; completion p95 unchanged | reverted (no gain), comment corrected |
| T10 | Typing case made strict: the burst ends in code with exactly one warning, so settling needs a fresh publish | settles 633-719 ms after the last keystroke, 1 intermediate state shown on the way | kept (test) |
| F1 | Fix round 1: `nv4j/unused_imports.lua` (user decision A), `<leader>co` only Organize Imports (decision B), organize with a compile error asserted, Lombok check requires 2 s stability, buildfile prunes on wipe | unused import with errors shown 473-506 ms, cleared on removal 474-497 ms, javadoc/annotation/static uses not flagged, no duplicate without errors; pass cost on 3000 lines p50 1.1-1.3 ms, p95 2.3-3.4 ms (first version with a treesitter identifier query: p50 9.9, p95 17.3 ms; then text search + node check without javadoc gmatch); 3 full runs 129 PASS (logs `test-20261020-220403/-220645/-220930.log`); cold_first 51-55 ms, `@` p95 40-45 ms, rank 4 | kept |

## Final

Three consecutive full `tests/run.sh` runs after the last change (commit `a6777a6` + checks), PATH java 21, JAVA_HOME unset: 120 PASS, 0 FAIL each. Logs `/tmp/nv4j/logs/test-20261020-214321.log`, `-214555.log`, `-214828.log`.

| Measure | Run 1 | Run 2 | Run 3 | Budget |
|---------|-------|-------|-------|--------|
| unused warnings shown (ms after edit) | 674 | 684 | 681 | 3000 |
| errors shown | 469 | 476 | 462 | 3000 |
| fix clears | 497 | 471 | 511 | 3000 |
| typing burst settles | 633 | 683 | 646 | 3000 |
| Java 25 file: 0 diagnostics | 490 | 521 | 520 | 3000 |
| malformed pom error (+ notification) | 211 | 208 | 196 | info |
| fixed pom clean | 482 | 586 | 364 | info |
| missing artifact error (+ notification) | 665 | 688 | 638 | info |
| first accept with import (`List`) | 685 | 691 | 746 | 1500 |
| second documented type (`HashMap`) | 439 | 427 | 379 | 1500 |
| organize imports via `<leader>co` | 167 | 183 | 137 | info |
| codeAction round trips | 9-120 ms | | | 1000 |

Completion unchanged: `cold_first` 52/51/53 ms, `@` p95 38/39/41 ms, `@` rank 4 in all runs; open to ready 6084-6257 ms.

## For the user to decide

1. Decided (fix round 1): unused imports show while the file has errors (`nv4j/unused_imports.lua`). Unused locals in a method with an error remain a JDT gap.
2. **Accept stall up to ~0.8 s** on well documented types not yet resolved by the doc popup (the price of always getting the import). Alternative would need a jdt.ls change (imports without javadoc in resolve).
3. Organize on save is off (IntelliJ default); say if you want it on.
4. Decided (fix round 1): `<leader>co` = Organize Imports, `<leader>cO` = outgoing calls only; organize on save off.
5. Cosmetic gaps: blank line between every import group, `Objects.hash(name, Integer.valueOf(age))`, toString without quotes around strings, numbered `input()` field picker.
