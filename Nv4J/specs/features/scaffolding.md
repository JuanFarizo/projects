# Feature: Scaffolding (new package, class, test class)

Priority: P3. Status: built in Task 3 (`61_scaffold` 27 of 27 PASS). Decision: D22 in `specs/001-architecture.md`. Spec: `specs/005-p3-tests-scaffold-refactor.md`. Check: `tests/checks/61_scaffold.lua`. Product: `nvim/lua/nv4j/scaffold.lua`, the one template source, also used by `config/autocmds.lua` (BufNewFile) and `plugins/neo-tree.lua` (`file_added`); `nvim/lua/util/java_scaffold.lua` is gone.

## Budget

File created on disk, opened, with the right `package` line <= 300 ms. Then jdt.ls reports no error for it <= 3 s.

## IntelliJ behaviour (reference, `intellij-community` at `b633034bb`)

- New > Java Class (`java/java-impl/src/com/intellij/ide/actions/CreateClassAction.java`, `JavaCreateTemplateInPackageAction.java`): one name field plus a kind list: Class, Interface, Record (language level >= 16), Enum, Annotation, Exception, plus user templates. A dotted name (`foo.Bar`) creates the packages. Offered only inside a source root; the package comes from the directory.
- Templates (`java/java-impl/resources/fileTemplates/internal/*.java.ft`): `package ${PACKAGE_NAME};` (omitted in the default package), a blank line, the File Header include (empty by default), `public class ${NAME} {` / `}`; record `public record ${NAME}() {`. No comments by default.
- New > Package: creates the directory (no `package-info.java`).
- Create Test (`java/java-impl/src/com/intellij/testIntegration/createTest/CreateTestAction.java`, `CreateTestDialog.java` `suggestTestClassName`: prefix + class name + suffix, default suffix `Test`; `JavaTestGenerator.java`): same package in the test source root, JUnit 5 picked from the classpath.
- Spring stereotypes are not Community templates; Ultimate offers Spring components through the same New menu. Our presets (controller, service, repository, entity) follow what a user would type.

## Baseline (Task 0, measured, before Task 3)

`:e Foo.java` (or neo-tree `a`) fires BufNewFile, a `vim.ui.select` of 8 kinds (class, interface, record, enum, controller, service, repository, entity) fills the buffer (`util/java_scaffold.lua`). Measured by `61_scaffold` with the select answered by the check (logs `/tmp/nv4j/logs/test-20261021-205836.log` and the full run in `005`):

| What | Result |
|------|--------|
| template kinds (8) | buffer filled in 26 to 61 ms with the right package line, declaration and stereotype annotation/import |
| on disk | **only an empty file**: nvim-jdtls writes every new Java buffer to disk on attach (`lua/jdtls/setup.lua`, `vim.cmd('w')` when the file does not exist), before the template fills the buffer; the content is on disk only after `:w` |
| annotation kind, package, dotted name (`deep.Thing`), test class for the current class | not offered |
| `<leader>jn` | unmapped; no `<leader>j*` key exists (LazyVim core, enabled extras, Nv4J) |
| compiles | the template class buffer: 0 jdt.ls errors, 92 ms after its publish |
| neo-tree `a` | `scaffold_file` writes the file after the prompt (not measured headless: neo-tree UI) |

## Built (Task 3)

`require("nv4j.scaffold").new({ kind, name, dir, insert })`:

- Kinds: `class`, `interface`, `record`, `enum`, `annotation`, `controller`, `service`, `repository`, `entity`, `package`, `test`. Missing kind: `vim.ui.select` of the 11; missing name: `vim.ui.input` ("New service in demo.p3scaffold:"). Directory: neo-tree's node under the cursor (its directory for a file), else the current file's directory, else cwd.
- Package from the directory under `src/<set>/java` (`main`, `test`, any set). A dotted name `deep.Thing` creates `deep/` and `package <pkg>.deep;`. A source root itself = default package (no package line). A directory outside `src/<set>/java` is refused with a message when a build file is above it; without one (a loose-file directory, as jdt.ls treats it) the default package is used.
- Names: every dotted part must be a Java identifier, not a keyword or literal (`1Bad`, `class`, `a..B`, `Foo-Bar`, empty: refused with a message).
- The file is written (`fs_open` with `wx`: never overwrites) BEFORE it is opened, so nvim-jdtls's write-on-attach finds it and the empty file of the baseline is gone. An existing file is not touched: a message, and it is opened.
- Templates (IntelliJ's, no header comment): `package x;`, blank, (stereotype: import, blank, annotation), `public class X {` / blank / `}`; record `public record X() {` / `}`; annotation `public @interface X {`. `test`: `<Class>Test` in the same package under `src/test/java`, `import org.junit.jupiter.api.Test;`, package-private class with one `@Test void test()` (JUnit 4 `org.junit.Test`/`public` when the build names only `junit:junit`). Refused from a test source (message). `package`: the directory (no `package-info.java`), relative to `dir`.
- With a UI and `insert = true` (the keys): cursor in the body, insert mode (`S` on the body line, so the indent comes from the indent expression; inside the record's parentheses). Headless callers get no insert mode (no `S` left in the typeahead).
- Keys (`config/keymaps.lua`, global): `<leader>jn` new (kind, then name), `<leader>jt` the test class of the current class (opened when it exists, else created). which-key group `<leader>j` = "java".
- `:e Foo.java` (BufNewFile, `fill_buf`): the kind picker of the 9 type kinds, buffer filled from the same templates, then written. neo-tree `a` (`file_added`, `fill_file`): neo-tree made an empty file, the template is written into it (a non-empty file is left alone).

### Results (`61_scaffold`)

Three consecutive runs 27/0 (`/tmp/nv4j/logs/test-20261026-093126.log`, `-093142.log`, `-093158.log`) and the full run (`-092355.log`, 27/0):

| Case | Result (budget) |
|------|-----------------|
| `kind_*` (9 kinds): on disk with the package line, current buffer, declaration, stereotype import + annotation | 28 to 112 ms (300 ms; the first file of a run is the slowest) |
| `prompts` (kind and name asked), `nested_name`, `test_for`, `default_package`, `test_dir_class` | 28 to 72 ms (300 ms) |
| `package` | 1 to 6 ms |
| `edit_template` (`:e`, on disk), `neotree_fill` | 52 to 79 ms, 6 to 9 ms |
| `exists`, `invalid_name`, `outside_root`, `test_from_test` | refused with a message, nothing written |
| `compiles` / `compiles_all` (15 files): error state settled, zero errors after an explicit build | slowest file 1.0 to 1.1 s in the 3 runs (3 s); the full run used the earlier "last publish" timing: 2.0 s (t3-e) |

### Negative controls (product mutated, check run, mutation reverted)

| # | Mutation | Cases that FAIL | Log |
|---|----------|-----------------|-----|
| n61a | no package line in the template | 9 `kind_*`, `prompts`, `nested_name`, `test_for`, `test_dir_class`, `edit_template`, `neotree_fill`, `compiles` and `compiles_all` (jdt.ls: declared package "" does not match) | `/tmp/nv4j/logs/test-20261026-093244.log` (first run before the `compiles` fix: `-092026.log`, `compiles` PASSED there, see t3-c) |
| n61b+g+h | file not opened (b), no identifier check (g), outside-root accepted (h) | every created-file case "current buffer NO", `exists` (opened NO), `compiles*` (b); `invalid_name` (g); `outside_root` (h) | `-092220.log` |
| n61c+d+f+i+j | test into `src/main/java` (c), stereotype import dropped (d), overwrite allowed (f), `package ;` in the default package (i), test from a test source allowed (j) | `test_for` (c); 4 stereotypes + `compiles_all` "cannot be resolved to a type" (d); `exists` (f); `test_from_test` (j) | `-092235.log`; f and i again with the stronger cases (t3-d): `exists` "disk CHANGED", `default_package` "WRONG: package ;" + `compiles_all` syntax error, `-092326.log` |
| n61e+k+l | class template missing `}` (e), `<leader>jn` not mapped (k), refusals without a message (l) | `compiles`, `compiles_all` (e); `key` (k); `exists`, `invalid_name`, `outside_root`, `test_from_test` (l) | `-092252.log` |
| n61p+q+r | prompted name created in cwd (p), BufNewFile template not written (q), neo-tree handler writes nothing (r) | `prompts` (p); `edit_template` "(0 lines)", the Task 0 baseline (q); `neotree_fill` "EMPTY" (r) | `-093227.log` |

Deterministic twin for the race-prone `compiles*`: after the timing wait, `nv4j.debug.refresh_and_build` then 500 ms without a publish; the error count is read after that build, not from whichever publish came first.

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
| t3-a | `nv4j/scaffold.lua`: write with content, then `:edit`; `util/java_scaffold.lua` removed, BufNewFile and neo-tree call the same `M.lines` | 14 target cases pass, 28 to 119 ms | kept |
| t3-b | review cases added (`exists`, `invalid_name`, `outside_root`, `default_package`, `test_dir_class`, `test_from_test`, `compiles_all`) | pass | kept |
| t3-c | n61a: `compiles` (Task 0 case: wait for a publish and zero errors) PASSED with a wrong package: jdt.ls publishes a clean list on open, the build's error about 2 s later | `compiles*` now: error state settled <= 3 s, zero errors after an explicit build; n61a FAILs both | kept |
| t3-d | n61i passed `default_package` (`"package " .. "" .. ";"` matched the expected line) and n61f passed "disk unchanged" (same template rewritten) | default package = no package line at all; `exists` first appends a user edit on disk | kept |
| t3-e | `compiles_all` timing on "last publish": 2.0 s in the full run because every new file makes jdt.ls republish the open ones (clean, unchanged) | timing = the publish that last changed the error count: slowest file 1.0 to 1.1 s | kept |
| t3-f | insert mode via `feedkeys("S")` in headless checks would leave `S` in the typeahead | insert only with a UI (`nvim_list_uis`) | kept |
| t3-g | `prompts`, `edit_template`, `neotree_fill` added (the prompt path, `:e`, neo-tree handler) | pass; n61p/q/r FAIL them | kept |

## Open items

- neo-tree `a` is checked through its `file_added` handler, not by driving neo-tree's UI; `<leader>jn` with the cursor on a neo-tree node (directory from the node) is not covered by a check.
- Insert mode after `<leader>jn`/`<leader>jt` (cursor in the body, `S` for the indent) only runs with a UI: checked by hand, not by `61_scaffold`.
- JUnit 4 template (`junit:junit` only) and Gradle builds are not covered by a fixture.
- `package` kind takes the name relative to `dir` (from a source root it is the full name); IntelliJ prefills the current package instead. No `package-info.java`.
- No "Exception" kind and no user templates (IntelliJ has both).

