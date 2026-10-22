# Feature: Scaffolding (new package, class, test class)

Priority: P3. Status: Task 0 done (research, failing check `61_scaffold`); Task 3 builds it. Decision: D22 in `specs/001-architecture.md`. Spec: `specs/005-p3-tests-scaffold-refactor.md`. Check: `tests/checks/61_scaffold.lua`. Product (Task 3): `nvim/lua/nv4j/scaffold.lua`; today's template: `nvim/lua/util/java_scaffold.lua` (used by `config/autocmds.lua` BufNewFile and `plugins/neo-tree.lua` `file_added`).

## Budget

File created on disk, opened, with the right `package` line <= 300 ms. Then jdt.ls reports no error for it <= 3 s.

## IntelliJ behaviour (reference, `intellij-community` at `b633034bb`)

- New > Java Class (`java/java-impl/src/com/intellij/ide/actions/CreateClassAction.java`, `JavaCreateTemplateInPackageAction.java`): one name field plus a kind list: Class, Interface, Record (language level >= 16), Enum, Annotation, Exception, plus user templates. A dotted name (`foo.Bar`) creates the packages. Offered only inside a source root; the package comes from the directory.
- Templates (`java/java-impl/resources/fileTemplates/internal/*.java.ft`): `package ${PACKAGE_NAME};` (omitted in the default package), a blank line, the File Header include (empty by default), `public class ${NAME} {` / `}`; record `public record ${NAME}() {`. No comments by default.
- New > Package: creates the directory (no `package-info.java`).
- Create Test (`java/java-impl/src/com/intellij/testIntegration/createTest/CreateTestAction.java`, `CreateTestDialog.java` `suggestTestClassName`: prefix + class name + suffix, default suffix `Test`; `JavaTestGenerator.java`): same package in the test source root, JUnit 5 picked from the classpath.
- Spring stereotypes are not Community templates; Ultimate offers Spring components through the same New menu. Our presets (controller, service, repository, entity) follow what a user would type.

## Today (baseline, Task 0, measured)

`:e Foo.java` (or neo-tree `a`) fires BufNewFile, a `vim.ui.select` of 8 kinds (class, interface, record, enum, controller, service, repository, entity) fills the buffer (`util/java_scaffold.lua`). Measured by `61_scaffold` with the select answered by the check (logs `/tmp/nv4j/logs/test-20261021-205836.log` and the full run in `005`):

| What | Result |
|------|--------|
| template kinds (8) | buffer filled in 26 to 61 ms with the right package line, declaration and stereotype annotation/import |
| on disk | **only an empty file**: nvim-jdtls writes every new Java buffer to disk on attach (`lua/jdtls/setup.lua`, `vim.cmd('w')` when the file does not exist), before the template fills the buffer; the content is on disk only after `:w` |
| annotation kind, package, dotted name (`deep.Thing`), test class for the current class | not offered |
| `<leader>jn` | unmapped; no `<leader>j*` key exists (LazyVim core, enabled extras, Nv4J) |
| compiles | the template class buffer: 0 jdt.ls errors, 92 ms after its publish |
| neo-tree `a` | `scaffold_file` writes the file after the prompt (not measured headless: neo-tree UI) |

## Decision D22 (summary; full text in 001)

Own command `require("nv4j.scaffold").new({ kind, name, dir })` with `vim.ui.select`/`vim.ui.input` prompts when arguments are missing, global key `<leader>jn` (works from a Java buffer, any file of the project, or neo-tree's node via its `file_added`/a neo-tree command calling the same function). The file is written to disk with its content before it is opened (no empty file, no unsaved template). Templates as IntelliJ's (no header comment) plus the Spring presets; `test` kind derives `src/test/java/<pkg>/<Name>Test.java` from the current class. The BufNewFile template stays for `:e Foo.java` but uses the same template table (one source, no duplicate). Rejected as the main entry: a neo-tree add hook only (needs the tree open; neo-tree creates the file before we know the kind).

## Proposed keys (collision check done in Task 0)

`<leader>jn` new (kind picker; "Java" which-key group `<leader>j`), and the "test for this class" kind reachable from the same picker (Task 3 may add `<leader>jt`). `<leader>j` is unused by LazyVim core, the enabled extras and Nv4J (checked with `nvim_get_keymap` in `61_scaffold` `key`: "other <leader>j keys: none"). The refactor keys share the group (`specs/features/refactors.md`).

## Test design (`tests/checks/61_scaffold.lua`)

Cases: `api`, `key`, `kind_<k>` for 9 kinds, `package`, `nested_name`, `test_for`, `compiles`, `fixture_restored` (details in the check header). The check snapshots `src/` and restores it after (`tests/lib/fixture.lua`: files back byte for byte, added files and their class files removed, buffers wiped, jdt.ls told with `didChangeWatchedFiles` + refresh + build).

Negative controls: the baseline itself is the control for "saved": the template path fills the buffer but leaves an empty file, and every template case FAILs with "on disk WITHOUT the package line (0 lines)". Plan for Task 3: write the file without the package line -> `kind_*` FAIL; open nothing -> "current buffer NO"; `test` kind into `src/main/java` -> `test_for` FAIL; an annotation import dropped -> stereotype case FAIL. `compiles` passes today on the template buffer: Task 3 adds a control where the generated class has a syntax error (case must FAIL).

## Trial log

| # | Change | Effect | Kept |
|---|--------|--------|------|
| t0-a | first check: "on disk" = file exists | template cases passed as "on disk yes": the file existed, empty (nvim-jdtls's write) | replaced |
| t0-b | "on disk" = the file on disk has the package line | template cases FAIL with "(0 lines)" | kept |
| t0-c | where the empty file comes from: `eventignore` FileType or BufNewFile -> no file; Lua `io.open`/`uv.fs_open` traced -> not Lua I/O; message `[New] 0L, 0B` = a `:write` | `nvim-jdtls/lua/jdtls/setup.lua:100` `vim.cmd('w')` for a buffer whose file does not exist | finding |
| t0-d | `config.autocmds` loaded by the check (`require`, so LazyVim's later load is a no-op) | BufNewFile template active headless | kept |
