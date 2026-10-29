# Nv4J

A fast, lightweight Neovim setup for Java and Spring development. It is built on LazyVim and runs next to your normal Neovim: your own `~/.config/nvim` is never touched. IntelliJ is the feature reference. Every feature has a priority and a pass/fail number, and the numbers are re-measured by a headless test suite you can run yourself.

Status: **P1 and P2 are built and passing** (P1: completion, diagnostics, imports, code actions, JDK handling). P2: debugging a main class or a JUnit test works and is checked (`40_debug`), running a Spring Boot app with profile and env works and is checked (`41_run`), and the Spring Boot language server runs for Spring Boot projects with `application.properties`/`yml` key completion and hover (`50_spring_ls`), `@Value`/`@Profile` completion (`51_spring_completion`), go to definition from `@Value` and a beans/request-mappings picker (`52_spring_nav`). P3 is built: asynchronous import (`63_async_import`), the test runner (`60_tests_runner`) and scaffolding (`61_scaffold`) are built and checked; the refactors (rename class, rename package, move class, inline, change signature, safe delete) are all built and checked (`62_refactor`). P4 and P5 are planned, not built. The "Not yet" list below is honest about that.

## Priorities

| Priority | Scope | Status |
|----------|-------|--------|
| P1 | Completion speed and ranking, diagnostics, imports, code actions, Java 25 and JDK handling | Done (this README, Capabilities) |
| P2 | Spring awareness (annotations, attributes, `application.properties`/`yml`), run and debug Spring Boot | Done (Capabilities: Debug, Run Spring Boot, Spring Boot language server, Spring completion and navigation); leftovers in Not yet |
| P3 | Tests runner polish, scaffolding (package/class creation), refactors beyond what jdt.ls already offers | Done: async import, test runner, scaffolding, all refactors (rename class/package, move class, inline, change signature, safe delete) and the `.nv4j` project marker (Capabilities: Tests, Scaffolding, Refactors); final runs and whole-branch review recorded in `specs/005` |
| P4 | Gradle, Spring navigation, JPA checks | Spring navigation (beans, request mappings, `@Value` definition) done early with P2 Task 4; Gradle and JPA checks not yet |
| P5 | Everything else | Not yet |

Maven is first class. Gradle is second and is not tested yet. Source of truth for decisions and numbers: `specs/001-architecture.md`, `specs/002-p1-completion.md`, `specs/features/*.md`.

## Capabilities (P1, shipped)

Each row says what you get, the measured result (ranges come from the three consecutive full runs recorded in the specs. Later full runs, the Task 7 run (129 PASS) and the two final-review runs (135 PASS each, 0 FAIL), stayed inside these ranges give or take about 10 to 20 percent per single timing; where the three final P2 runs, with the Spring server running, widened a range the row says so; all their numbers are in `specs/001-architecture.md`), and the check that proves it. All numbers come from `tests/run.sh` on a Spring Boot 3.5 fixture project (`tests/fixtures/demo`: web, data-jpa, security, validation; Java 25), Neovim 0.12, jdt.ls 1.62, on the author's Mac. Your machine and a bigger project will differ. The logs of the runs behind the numbers are in `specs/002-p1-completion.md` and `specs/features/diagnostics-imports-actions.md`.

### Completion speed and ranking

| What you get | Measured (budget) | Check |
|--------------|-------------------|-------|
| Completion answers fast once warm | worst case p95 38 to 45 ms over the P1 runs, 41 to 54 ms in the three final P2 runs with the Spring server running (150 ms) for 14 cases: `@`, `@Table(`, `http.`, `repository.`, `System.`, `new Person(`, identifiers | `10_completion_latency` |
| The sorted list ready for the menu | menu p95 worst about 40 ms (150 ms) | `10_completion_latency` |
| First completion after jdt.ls is ready is not slow (warm-up on start) | 51 to 55 ms (400 ms); 48 to 61 ms in the final P2 runs. Before the warm-up it was 740 to 827 ms | `10_completion_latency` (`cold_first`, sent 1.0 s after ServiceReady) |
| Expected item near the top | `@` gives `RestController` at 1 since P2 (4 at the end of P1, jdt.ls order 6), `http.` gives `authorizeHttpRequests` at 2 (was 19), `repository.` gives `save` at 1 (was 42). `@Auto`, `@Rest`, `@Table(`, `@Column(` first or in the short list. Local variables and fields beat JDK types | `11_completion_ranking` |
| Postfix templates (`http.cast`, `sysout`...) come after real members, `http.va` still finds `var` | rule checked | `11_completion_ranking` |
| What you accepted before (blink's frecency) no longer buries the expected item on a list with nothing typed: after accepting `List` 20 times, `@` still gives `RestController` at 1 (blink's own order: 27) and `http.` `authorizeHttpRequests` at 2; frecency only breaks ties there (P3) | top 5 / top 3 | `63_async_import` `frecency_*` |
| Members you use most in the project rank higher (IntelliJ style "most used"), counted with ripgrep | rule checked, rg failing or timing out keeps old counts; a loose `.java` file with no build marker (`pom.xml`, `build.gradle*`, `settings.gradle*`, `.git`) is not counted, so `rg` never scans e.g. your home folder | `11_completion_ranking`, `12_usage_index` |
| Less JDK noise: internal packages, `com.apple.*`, AspectJ internals, `java.awt.List` hidden, so `List` completes to `java.util.List` | `no_noise` cases a, s, m, List | `11_completion_ranking` |

Why it is fast: measured, not guessed. What helped: postfix templates matched on their key and put last, project usage as a tie breaker after jdt.ls relevance, no `java.*` relevance bonus, fewer flooding items, a warm-up completion when jdt.ls is ready. What did not help is recorded too (ParallelGC, AppCDS, `maxResults` 50/1000, `lazyResolveTextEdit`), see the trial log in `specs/002-p1-completion.md`.

Time from opening a file until jdt.ls is ready: about 6.1 to 6.4 s on a warm workspace (6.1 to 6.9 s in the final P2 runs), about 15 s for the very first import of the Spring fixture (info, not budgeted).

### Diagnostics

| What you get | Measured (budget 3 s) | Check |
|--------------|-----------------------|-------|
| Errors appear after an edit | 462 to 476 ms (final P2 runs 443 to 455 ms) | `30_diagnostics` |
| Unused import, local, private field, private method as faded warnings | 674 to 684 ms (final P2 runs 590 to 656 ms) | `30_diagnostics` |
| Fixing the code clears them | 471 to 511 ms | `30_diagnostics` |
| A typing burst settles with no stale error | 633 to 683 ms | `30_diagnostics` |
| Java 25 code (module imports, flexible constructors, `_`, record patterns, Markdown doc comments) has zero diagnostics | 490 to 521 ms | `30_diagnostics`, `20_java25` |
| Unused-import warnings still show while the file has compile errors (jdt.ls drops them, IntelliJ does not) | shown 473 to 506 ms, pass cost on a 3000-line file p50 about 0.9 ms, p95 1.6 to 1.9 ms (100 passes, 5 runs; 1.3 to 2.1 ms in the final P2 runs; a `import module` line is never flagged) | `30_diagnostics` (`unused_pass_perf` and the unused-with-errors cases) |
| A broken `pom.xml` (malformed, missing artifact) shows its error and a visible notification; after the fix its diagnostics clear on their own (the check asserts the diagnostics, not a "fixed" notice) | error plus notice in 196 to 211 ms (malformed), 638 to 688 ms (missing artifact), diagnostics cleared after the fix in 364 to 586 ms | `30_diagnostics` |

Inline diagnostics are drawn by tiny-inline-diagnostic. They refresh when you leave insert mode (`update_in_insert = false`), so a half typed line does not flicker red.

### Imports

| What you get | Measured (budget 1.5 s) | Check |
|--------------|-------------------------|-------|
| Accepting a completion adds its import, also the very first one of a session | first `List` 685 to 746 ms, second documented type (`HashMap`) 379 to 439 ms (final P2 runs 676 to 749 ms and 307 to 466 ms) | `31_imports` |
| Accepting does not wait for the import (P3): the item text is in at once, the import follows when jdt.ls has it, once, placed by Nv4J in its importOrder group (other, `javax`, `jakarta`, `java`, static; sorted, blank line between groups), never by applying jdt.ls's ranges (they can be stale, and jdt.ls sometimes sends one that replaces an existing import line). Edits, cursor moves, an undo or a closed buffer in between never duplicate or corrupt anything (an undone accept drops its import). One `u` removes item and import when nothing changed since the accept; otherwise the import is its own undo step and a second `u` removes it | text 43 to 51 ms (100 ms, before P3: 405 to 802 ms); import first `List` 658 to 790 ms, `HashMap` 461 to 479 ms, with an 800 ms stubbed resolve 871 to 877 ms (1.5 s); 50 of 50 `List` + `HashMap` accepts against the real resolve with both imports once and no other line changed | `63_async_import` |
| Imports land in IntelliJ-like groups: everything else, `javax`, `jakarta`, `java`, then static | checked on a planted file | `31_imports` |
| `<leader>co` organizes: removes unused imports, orders groups, also when the file has a compile error | 137 to 183 ms | `31_imports` |
| No wildcard imports (star threshold 99) | config | none |

Organize on save is off, like IntelliJ's default. The cost of always getting the import is a short wait on accept, see Known limitations.

### Code actions (`<leader>ca`)

Offered by jdt.ls, applied through Neovim's own code action UI. Round trip 9 to 120 ms (budget 1 s; worst 114 to 144 ms in the final P2 runs). Proven by `32_code_actions`:

- Quick fixes: create method (same class or another class), create variable/field/parameter, create class, import type, add unimplemented methods, remove unused import, remove unused local.
- Generate: getters and setters, constructors, `toString()` (`App{name=x, age=1}` style), `equals`/`hashCode` (`java.util.Objects`, braces). The field pickers start with all fields selected (a fix in `nvim/lua/nv4j/codegen.lua`).
- Extract: local variable, constant, method.
- Lombok: `@Getter`, `@RequiredArgsConstructor` members resolve with no errors (Mason's lombok agent).

### JDK handling and Java 25

Nothing is pinned to one JDK. `nvim/lua/nv4j/jdk.lua` finds JDKs in SDKMAN (`~/.sdkman/candidates/java`), `~/Library/Java/JavaVirtualMachines` and `/Library/Java/JavaVirtualMachines`, reading each JDK's `release` file.

- jdt.ls itself runs on `$JAVA_HOME` if that is a JDK 21 or newer, else the newest JDK 21+ it finds, else you get a clear error.
- Every JDK found is registered with jdt.ls. The one used to compile a project follows the build file: `.sdkmanrc`, then the pom's `maven.compiler.release`, `java.version` or `maven.compiler.source`, then `$JAVA_HOME`, then the newest.
- Proven by `20_java25` with a hostile setup (`JAVA_HOME` unset, a JDK 21 first on `PATH`): the Java 25 fixture reports release 25 and a JDK 25 location with zero errors, jdt.ls does not run on `PATH`'s Java 21, and a second Maven project with release 21 gets a JDK 21 runtime.

### Debug (P2, main class and JUnit test)

Breakpoints hit, also in files added while Neovim was closed (a `git pull`), and the debugged program runs on the project's JDK. Fixes in `nvim/lua/nv4j/debug.lua`, details in `specs/features/debug-run.md`. Numbers from 5 consecutive runs of `40_debug` (all cases PASS each; 16 cases since the review fix round, 3 of 3 runs) and the three final full runs (16 of 16 each):

| What you get | Measured (budget) | Check |
|--------------|-------------------|-------|
| Debug a Spring Boot main class (`<leader>dc`, pick the class): stops at the breakpoint, frame and variables readable | stop 2.9 to 3.6 s after launch, including a refresh and build of the project (20 s) | `40_debug` `breakpoint_hit`, `variable` |
| Debug a JUnit 5 test: stops at the breakpoint, then the test finishes and passes (the P2 path; since P3 the key is `<leader>td`, Tests below) | stop 0.7 to 0.9 s (20 s) | `40_debug` `test_breakpoint_hit`, `test_variable`, `test_finished` |
| No "Could not resolve classpath ... m2e.launchconfig.classpathProvider" at start, every main class gets a debug config | 0 errors, 3 of 3 main classes, in 69 of 69 runs (before: failed 4 of 4) | `40_debug` `classpath_first`, `configs` |
| The debugged JVM runs on the project's JDK, not on `PATH`'s (JDK 21 first on `PATH`, `JAVA_HOME` unset) | `java.version` 25.0.4 for the main class and the test | `40_debug` `debuggee_jdk`, `test_debuggee_jdk` |
| Terminate leaves no JVM behind | gone within 10 s (10 s) | `40_debug` `no_orphan`, `test_finished` |
| A debug launch starts no second jdt.ls | 0 extra starts | `40_debug` `one_jdtls` |

Before each launch the project's source folders are refreshed and built (VS Code builds too, you see "Building before debug..."). If the build has compile errors, fails or takes more than 60 s you get a warning and the launch goes ahead. If a JUnit run needs a `junit-platform-launcher` jar that is not in your Maven repository, a warning names it and the `mvn dependency:get` command that fetches it.

### Tests (P3)

Run JUnit tests from the editor and see the results in the file, as in IntelliJ: `<leader>tr` the test at the cursor, `<leader>tt` the class, `<leader>tp` every test of the project, `<leader>tf` the tests that failed last time, `<leader>tl` the last run again, `<leader>td` debug the test at the cursor (breakpoints stop), `<leader>to` the results. Before each run the project is refreshed and built ("Building before test run..."), the test JVM runs on the project's JDK. A failing assertion gets an error diagnostic on its line, the method lines get `✓`/`✗`/`○` signs, the quickfix list ("Nv4J tests: 7 passed, 1 failed, 1 skipped") holds each failure message followed by the stack frames that are files of the project (each jumps to its line) and the skipped tests, and a notification sums it up. `@Disabled` counts as skipped, each parameterized invocation and `@Nested` test counts on its own. The editor runs a class that surefire's `excludedGroups` keeps out of `mvn test`, as IntelliJ does. Code: `nvim/lua/nv4j/tests.lua`, details in `specs/features/tests-runner.md` (decision D21). Numbers from 3 consecutive runs of `60_tests_runner` (20 of 20 PASS each; 29 cases since the Task 2 review fixes and the final review: socket close, run lock, discovery bound, stream cap, `opts.test = false`, one dap session name per launch):

| What you get | Measured (budget) | Check |
|--------------|-------------------|-------|
| Nearest test, result visible, warm (second run of the session) | 0.69 to 0.91 s (10 s); first run 2.2 to 3.1 s | `60_tests_runner` `nearest_warm` |
| Class with a plain, 3 parameterized, 1 nested and 1 `@Disabled` test: 5 passed, 1 skipped | 0.89 to 0.91 s | `class_counts`, `file_scope`, `nearest_param`, `nearest_nested` |
| Failing assertion: quickfix entry and diagnostic on the `assertEquals` line with the message | 0.61 to 0.71 s | `failure_shown` |
| Whole project (3 classes, one JVM): 7 passed, 1 failed, 1 skipped | 0.75 to 2.1 s | `project_counts` |
| Failed tests only, then the last run again: only the failing test, 0 passed 1 failed | 0.63 to 0.92 s, 0.83 to 1.03 s | `failed_only`, `last_again` |
| Debug the nearest test: stops at the breakpoint, then passes | 0.90 to 1.27 s | `debug_nearest` |
| A test class that does not compile: a failure "Unresolved compilation problem" (after the build warning), no hang | 1.7 to 2.0 s | `broken_class` |
| No tests in the file, or a project without JUnit: a clear message, nothing launched | 12 to 19 ms; 0.13 to 1.7 s | `no_tests_file`, `no_junit_project` |
| A run never hangs: it stops after 120 s at most (`vim.g.nv4j_test_timeout_ms`) with a message | stopped at 0.33 to 0.36 s with the bound set to 0.3 s | `timeout_bounded` |
| The keys are Nv4J's, also after which-key created LazyVim's java test keys | 7 of 7 | `keys`, `keys_after_whichkey` |

### Scaffolding (P3)

New Java files as in IntelliJ's New menu: `<leader>jn` asks the kind (class, interface, record, enum, annotation, Spring controller/service/repository/entity, package, test) and the name, and creates the file in the directory you are in (the neo-tree node under the cursor, else the current file's directory). The package comes from the directory under `src/<set>/java`; `deep.Thing` creates the package `deep` too. The file is written with its content, then opened with the cursor in the body (no empty file on disk, nothing unsaved). `<leader>jt` opens the test class of the current class (`src/test/java`, same package, `<Name>Test`), creating it with a JUnit 5 `@Test` method when it does not exist. An existing file is never overwritten (message, opened instead), invalid names and directories outside a source root are refused with a message. `:e Foo.java` and neo-tree's `a` use the same templates (kind picker) and also leave the template on disk. Code: `nvim/lua/nv4j/scaffold.lua`, details in `specs/features/scaffolding.md` (decision D22). Numbers from 3 consecutive runs of `61_scaffold` (27 of 27 PASS each) and the full run before the commit (27 of 27):

| What you get | Measured (budget) | Check |
|--------------|-------------------|-------|
| Each of the 9 type kinds: file on disk with the right `package` line, opened, stereotype import and annotation | 28 to 112 ms (300 ms) | `61_scaffold` `kind_*` |
| Kind and name asked, dotted name, test class for the current class, default package, class in `src/test/java` | 28 to 72 ms (300 ms) | `prompts`, `nested_name`, `test_for`, `default_package`, `test_dir_class` |
| New package (directory) | 1 to 6 ms | `package` |
| `:e Foo.java` and neo-tree `a`: template on disk | 52 to 79 ms, 6 to 9 ms | `edit_template`, `neotree_fill` |
| Every created file compiles: jdt.ls error state settled, zero errors after a build | slowest file 1.0 to 1.1 s (3 s) | `compiles`, `compiles_all` |
| Existing file, invalid names, outside `src/*/java`, test of a test: refused with a message, nothing written | rules checked | `exists`, `invalid_name`, `outside_root`, `test_from_test` |

### Refactors (P3)

Rename as in IntelliJ (Shift+F6): `<leader>jr` renames the class under the cursor (or the file's class): the file is renamed, references and imports in every file are updated, the touched files are written and a notification lists them. On the `package` line (or with `<leader>jp`) it renames the package: `package` and `import` lines in every file, the folder moved in `src/main/java` and the same package folder in `src/test/java`, open buffers follow the move. Renaming or moving a `.java` file or a package folder in neo-tree does the same (jdt.ls is asked before the move; LazyVim asked after it and left the old `package` line). A buffer with your unsaved changes is edited in place and left unsaved (a moved file's buffer is written by the move), and the notification says so. Refusals (name exists, package exists, into itself) change nothing and say why; a failure part-way lists what changed; errors left after the rename (for example a reference jdt.ls skipped in a file with a syntax error) come as a warning 3 s later. One `u` per file undoes the text (the file keeps its new name). `<leader>cr` stays LazyVim's rename of any symbol.

Move as in IntelliJ (F6): `<leader>jm` moves the class under the cursor (the file's own top-level class) to another package, picked from the project's packages or typed ("New package..."; the folder is created). The file moves to that package's folder, its `package` line and every import and reference are updated by jdt.ls, touched files are written and listed, the buffer follows, unsaved edits are kept as for rename, one `u` per file undoes the text. Refused with nothing changed: an invalid package name, a class of that name already in the target package (also in `src/test/java`), the cursor in a nested class or in a second class of the file; the same package only gets a message. The class's test (`InvoiceTest` in `src/test/java`) stays in its package, and the notification says so. A Spring component moved out of the `@SpringBootApplication` package gets a warning (component scanning will not find it). The old qualified name left in strings or config (`demo.billing.Invoice` in `application.properties`) is listed, not rewritten.

Inline as in IntelliJ (Ctrl+Alt+N): `<leader>ji` inlines the method call, local variable or constant under the cursor through jdt.ls. What is inlined follows jdt.ls: on a call (or a constant's reference) that one occurrence, the declaration stays; on the method's or constant's declaration every occurrence, in every file, and the declaration is removed; a local variable everywhere it is used. `require("nv4j.refactor").inline({ all = true })` on a call does the "all" variant from there. Touched files are written and listed, unsaved edits are kept as for rename, one `u` per file undoes it. Refused with the reason and nothing changed: nothing to inline at the cursor (a parameter, a plain field such as an `@Value` field, a keyword), jdt.ls offering the inline but giving no edit (a recursive method, a body using something not visible at the call, a syntax error in the file), "all" for a method not in the project (a JDK method). Occurrences jdt.ls did not inline (a file it skipped) are named in a warning. Spring: inlining a `@Bean` method gets a warning (the call returned the container's bean; from the declaration, the bean is gone).

Change signature as in IntelliJ (Ctrl+F6): `<leader>js` on a method's declaration (or on a call of it) asks for the new signature as text, prefilled with the current one: `public int total(Invoice invoice)` edited to `public int total(Invoice invoice, int discount = 0)` adds a parameter and every call site passes `0`. A parameter matches the old one by name (a new type retypes it), a name without `= default` in the place of a vanished one of the same type renames it (another type there is refused as ambiguous: use `= default` or the explicit options), removing it from the text removes it, writing them in another order reorders them; visibility, return type and the method name can change too. jdt.ls does the change (Eclipse's engine): the declaration, every call in main and test sources, the body for a renamed parameter, a constructor's `new X(...)` calls, and every method that implements or overrides it (named in the notification; such a change takes jdt.ls about 2.6 to 3.9 s, and `<leader>js` runs it in the background with a "Changing signature..." message so the editor stays usable). From Lua: `require("nv4j.refactor").change_signature({ add = { { type = "int", name = "discount", default = "0" } }, remove = { "x" or 2 }, rename = { old = "new" }, retype = { name = "long" }, reorder = { ... }, name = ..., returns = ..., visibility = ... })`. Touched files are written and listed, unsaved edits are kept as for rename, one `u` per file undoes it. Refused with the reason and nothing changed: the cursor not on a method or a call, an invalid name or type, a new parameter without a default, a duplicate name, removing a parameter the body still uses, a new name the body already uses (it would clash with a local or hide a field), a renamed constructor, a method of a library, an implementation of an interface or superclass method (change it where it is declared), and jdt.ls's own refusals (an invalid default expression) with its message. Calls jdt.ls did not update (a file it skipped) are named in a warning. Spring: a parameter added to a `@Bean` method (Spring injects it, your default is not used) or to a request handler (bound from the request), and a renamed `@Bean` method (the bean name changes), get a warning. Not exposed: `throws` (kept as it is) and "keep the old method as a delegate"; nvim-jdtls's editable float is still there through the `<leader>ca` code action.

Safe delete as in IntelliJ (Alt+Delete): `<leader>jd` on the name of a method, field, constant or class (or on a reference to it) looks for its usages first, with jdt.ls's references in main and test sources (and, for a method, the methods that implement or override it). With usages nothing is deleted: every usage goes into the quickfix list, which opens, and the message gives the count ("method total(Invoice) NOT deleted: 8 usage(s) in 3 file(s) ..."). Without usages the declaration is removed with its javadoc, annotations and one blank line, the file is written (or left unsaved when you had unsaved changes there), one `u` gives it back; the only class of its file deletes the file (copied first to a trash under Neovim's cache folder, `nv4j-trash`; its buffer is closed, jdt.ls told): no `u` for that, `:Nv4jRestoreDeleted` puts the latest deleted file back. A buffer with unsaved changes and a file with errors are also read as text, since jdt.ls may not have seen the change or may skip the broken file: a call of the name there blocks the delete as a "possible usage". Refused with the reason and nothing changed: a local variable or parameter (use inline or change signature), a constructor, an enum constant, a record component, a field declared together with another on one line, a method that overrides or implements another (with or without `@Override`: jdt.ls is asked for its super method), a library declaration. Spring and other frameworks use some code by reflection, which has no reference: a `@Bean` method, a request handler, an `@Value` field, a stereotype class, a `@Test` method... are deleted with a warning saying what goes (the bean, the endpoint, the property), and strings or config still naming it (`application.properties`, JPQL) are listed. Imports only the deleted code used are reported, not removed (`<leader>co`).

Code: `nvim/lua/nv4j/refactor.lua`, details in `specs/features/refactors.md` (decision D23). Numbers from 3 consecutive runs of `62_refactor` (the rename cases all PASS each run; the fix-round rows from one run, `/tmp/nv4j/logs/test-20261026-112854.log`). All six refactor functions are built: no "pending" line is left; all cases pass, including `change_signature_interface_ceiling` (a method with implementations has a 5 s ceiling, see the table).

| What you get | Measured (budget) | Check |
|--------------|-------------------|-------|
| Rename a class: file renamed, imports and references in 5 files, written, summary, build clean | 634 to 1009 ms (2 s) | `62_refactor` `rename_class` |
| One `u` per touched buffer gives its text back | 3 of 3 open buffers | `rename_class_undo` |
| Unsaved edits kept (referencing file left unsaved, renamed file written) | 370 to 499 ms | `rename_class_unsaved` |
| Spring controller renamed, annotations kept, build clean | 60 to 105 ms | `rename_class_boot` |
| Rename a package: folder moved, `package` line on disk, buffer re-pointed | 1.17 to 1.23 s (2 s; 1.1 s of it is jdt.ls's first answer) | `rename_package` |
| Package in `src/main/java` and `src/test/java`, imports elsewhere, no same-package imports | 654 to 806 ms | `rename_package_imports`, `rename_package_fallback` |
| neo-tree rename of a package folder / a class file | 113 to 152 ms / 313 to 351 ms | `neotree_rename_package`, `neotree_rename_file` |
| Name or package exists, into itself: refused with a message, nothing changed | at once | `rename_class_conflict`, `rename_package_conflict` |
| A skipped reference (syntax error in that file) is reported | warning names the file | `rename_class_errors`, `rename_class_errors_twin` |
| Strings and config still naming the old class (JPQL, class-name string, `application.properties`) listed in a warning, not rewritten | 3 of 3 places, scan 17 ms | `rename_class_strings` |
| neo-tree rename of a package with a `src/test/java` namesake: both folders move | 485 ms | `neotree_rename_billing` |
| jdt.ls gives no edit (busy): refused, nothing changed, also from neo-tree (no success toast, buffers intact) | about 1 s (10 tries) | `rename_package_first_null`, `neotree_refused` |
| `<leader>jr` on a `package` line, and the name prompt when no name is given | prompt and default checked | `jr_package_line`, `prompt_class` |
| Move a class to another package: file moved, `package` line, imports in 5 files, written, summary, build clean | 382 to 461 ms (2 s) | `move_class`, `move_class_undo` |
| Move to a new package (folder created), from the picker or `<leader>jm` "New package..." | 361 to 583 ms (once 1.7 s, jdt.ls busy) | `move_class_new_package`, `move_prompt`, `move_key_new_package` |
| Move with unsaved edits, a Spring controller (annotations kept; warning outside the scanned package), the test class staying | 94 to 1184 ms | `move_class_unsaved`, `move_class_boot`, `move_class_boot_scan`, `move_class_test_stays` |
| Move refused: invalid name, same package, class exists (main or test), cursor in a nested/second class | at once, nothing changed | `move_invalid`, `move_same_package`, `move_conflict`, `move_not_top_level` |
| Inline a method call / a local variable, written, summary, build clean, one `u` | 742 to 1296 ms (first inline of the session) / 143 to 240 ms (2 s) | `inline_method`, `inline_variable` (+ `_undo`) |
| Inline from the declaration or with `all`: every occurrence in every file, declaration removed | 176 to 287 ms | `inline_method_all`, `inline_method_declaration`, `inline_constant_all` |
| `<leader>ji` on a constant reference (that one only); unsaved edits kept | 96 to 170 ms | `inline_constant`, `inline_unsaved` |
| Spring: `@Bean` method inlined (warning), constant used as `@Value` key inlined (build clean) | 46 to 229 ms | `inline_bean_call`, `inline_bean_declaration`, `inline_value_constant` |
| Inline refused: nothing to inline, recursion (no edit), jdt.ls error, all on a JDK method; a skipped occurrence named | at once, nothing changed | `inline_refused`, `inline_recursive`, `inline_resolve_error`, `inline_errors(_twin)` |
| Change signature: `int discount = 0` added, 3 calls in main and 5 in test sources pass 0, written, summary, build clean, one `u` per file | 524 to 560 ms (2 s) | `change_signature` (+ `_undo`) |
| From a call, with unsaved edits, `<leader>js` typed form, constructor, rename + reorder + method name, remove + retype, visibility + return type | 308 to 867 ms | `change_signature_call_site`, `_unsaved`, `_prompt`, `_constructor`, `_reorder`, `_remove`, `_header` |
| Interface method: implementation changed too and named; `<leader>js` does not block the editor while jdt.ls works (progress message) | correctness and async checked | `change_signature_interface` |
| Interface or overridden method within a 5 s ceiling (budget 2 s elsewhere) | 3.7 to 4.0 s on the first such change of a session on an idle machine (up to 5 s when the machine is loaded), 2.6 s on the second; almost all of it is jdt.ls's own search for implementations. A ruling you can overturn | `change_signature_interface_ceiling` |
| Spring: parameter added to a `@Bean` method or request handler, `@Bean` renamed: warning | 272 to 335 ms | `change_signature_boot` |
| Change signature refused (15 reasons, jdt.ls's own message shown once), a call jdt.ls did not update named, stale diagnostics refreshed | at once, nothing changed | `change_signature_refused`, `_no_edit`, `_errors(_twin)`, `_stale_twin` |
| Safe delete with usages (`total`: 8 in main and test sources): nothing deleted, all in the quickfix, count in the message | 156 to 172 ms | `safe_delete_blocked` |
| Safe delete without usages (`legacyTotal`): method and one blank line gone, written, summary, build clean, one `u` | 172 to 185 ms (2 s) | `safe_delete_free` (+ `_undo`) |
| Safe delete with unsaved edits (left unsaved), an unsaved or broken file's call blocks it, errors elsewhere noted, recursion with javadoc/annotation | 148 to 209 ms | `safe_delete_unsaved`, `_unsaved_usage`, `_unconfirmed_twin`, `_errors`, `_self_ref` |
| Safe delete of a class (file deleted, jdt.ls told) / a second class of a file / Spring `@Bean`, handler, `@Value` field (warnings, unused imports reported) | 92 to 168 ms | `safe_delete_class`, `safe_delete_boot` |
| Safe delete refused (local, parameter, constructor, enum constant, record component, two declarators, overriding with or without `@Override`, library, no answer, refactor pending) or blocked by an implementation | at once, nothing changed | `safe_delete_refused`, `_hierarchy`, `_supertypes(_twin)`, `_no_answer`, `_busy` |
| Deleted class file copied to the trash first, `:Nv4jRestoreDeleted` brings it back byte for byte; a failing removal keeps file and buffer | checked | `safe_delete_trash` |
### Run Spring Boot (P2)

`<leader>rs` runs the `@SpringBootApplication` main class of the project, `<leader>rd` debugs it (the Debug path above), `<leader>rp` asks for a profile (offers the `application-<profile>` files it finds) and runs. The app runs as `java -cp <classpath from jdt.ls> <main class>` on the project's JDK, after the same refresh and build as a debug launch ("Building before run..."). It was measured faster than `mvn spring-boot:run` (2.5 s against 5 to 7 s to "Started", and Maven first had to resolve its plugin over the network), see `specs/features/run.md`. `<leader>rS` runs through the build tool instead (`mvnw`/`mvn spring-boot:run`, or `gradlew`/`gradle bootRun` when there is no `pom.xml`); `vim.g.nv4j_run_tool = "maven"` (or `"gradle"`, Gradle first) makes that the default for `<leader>rs` and `<leader>rp` (debug always goes through jdt.ls). Without jdt.ls for the project (looked up by the project root, so it works from `application.yml` or a module's `pom.xml` too) you get a notice and the build tool is used. The build tool runs in the Spring Boot module (the buffer's module if it is Boot, else the first Boot module found), not at the aggregator, so `spring-boot:run`/`bootRun` does not run the whole reactor; for Maven the sibling modules it depends on must be installed first (`mvn install` once). What `<leader>rs` skips and when to switch: Known limitations. Output goes to a terminal split at the bottom: `<C-c>` (normal mode) stops the app, `q` stops it and closes the split, `<leader>rx` stops every run. Code: `nvim/lua/nv4j/run.lua`. Numbers from 3 consecutive runs of `41_run` (18 of 18 PASS each; 22 of 22 after the review fix round, 3 of 3 runs; 27 of 27 after the final review, 3 of 3 runs) and the three final full runs (22 of 22 each):

| What you get | Measured (budget) | Check |
|--------------|-------------------|-------|
| `<leader>rs` starts the app and says so (notification with port and Boot's start time) | "Started" 3.8 to 7.7 s after the key, including refresh, build and classpath (info, no budget); Boot's own start 2.0 to 2.3 s | `41_run` `started`, `started_notice` |
| The app runs on the project's JDK (JDK 21 first on `PATH`, `JAVA_HOME` unset), env and profile reach it | Java 25.0.4, `DEMO_GREETING_TEXT` and `application-dev.yml` seen by the app | `41_run` `java25`, `env`, `profile` |
| Starting a second copy on a used port reports it, nothing hangs | ERROR notification with Boot's failure analysis ("Port N was already in use" plus its Action), the second process exits, the first keeps running | `41_run` `port_in_use`, `no_hung` |
| Stop leaves nothing behind: the app, and a whole process tree (stand-in for `mvn` and its forked JVM: children in the app's process group and one that left it) even when they ignore SIGTERM | JVM gone within 10 s; tree gone in 1.7 to 2.1 s (SIGTERM to the process group and every descendant, SIGKILL after the grace time) | `41_run` `stop_no_orphan`, `tree_kill`, `close` |
| `<leader>rd` debugs with profile and env, breakpoints hit | stop 2.7 to 4.9 s (20 s), profile and `SERVER_PORT` seen at the stop, no JVM after terminate | `41_run` `debug_stop`, `debug_profile`, `debug_env`, `debug_no_orphan` |
| A JVM that printed Boot's failure but keeps running can still be stopped; `vim.g.nv4j_run_tool = "maven"` runs `spring-boot:run` with jdt.ls attached; jdt.ls is found from non-Java buffers, a project without it gets a notice | rules checked | `41_run` `failed_alive`, `force_tool`, `client_lookup` |
| Multi-module: Boot only in `app/`, from `common/`, the aggregator `pom.xml` or a buffer with no file, `<leader>rs` finds the Boot project and the build tool runs in `app/`; quitting Neovim stops a `<leader>rd` app; a failing `dap.run` is reported | rules checked | `41_run` `multi_module`, `leave_stops_debug`, `dap_run_error`, `dap_scan` |

Boot detection (one rule shared with the Spring Boot language server, `nvim/lua/nv4j/root.lua`): in `pom.xml` (outside comments) the `org.springframework.boot` groupId or a `spring-boot-starter*`, `spring-boot-maven-plugin` or `spring-boot-dependencies` artifact; in Gradle the `org.springframework.boot` plugin or group, a `spring-boot-starter*` dependency, the catalog aliases `libs.plugins.spring.boot`/`libs.spring.boot.starter*`, or `gradle/libs.versions.toml` naming `org.springframework.boot`. A `spring-boot.version` property alone does not count (`41_run` `detect`, `50_spring_ls` `detect`). The project root and its modules up to 2 levels down are looked at (`41_run` `multi_module`). Quitting Neovim stops running apps, also those started with `<leader>rd` (`41_run` `leave_stops_debug`).

### Spring Boot language server (P2)

In a Spring Boot project (same detection as Run Spring Boot above, also in a module up to 2 levels below the project root) the Spring Boot language server (VMware's, Mason package `vscode-spring-boot-tools`) runs next to jdt.ls as a second client named `spring-boot`, on Java files and on `application*.properties`/`application*.yml`. Typing a key in `application.properties` completes it (blink menu as usual), `K` shows its type, default and description (no new keys: the usual completion menu and `K`). A plain Maven or Gradle project and a loose `.java` file get no Spring server and no extra process. The server runs on a JDK >= 21 picked by the same discovery as jdt.ls (never `PATH`). Wiring: `JavaHello/spring-boot.nvim` pinned (decision D14), configured in `nvim/lua/nv4j/spring.lua`; details and trials in `specs/features/spring-language-server.md`. Turn it off with `vim.g.nv4j_spring = false` in `nvim/lua/config/options.lua`: the plugin is then not loaded at all (no `:SpringBoot`, no client). The server starts with the first Java buffer of the project, so "initialized" below overlaps jdt.ls's import; the server keeps indexing after that. Numbers from 3 consecutive runs of `50_spring_ls` (11 of 11 PASS each; 13 cases since review fix round 1) and the three final full runs (13 of 13 each):

| What you get | Measured (budget) | Check |
|--------------|-------------------|-------|
| The Spring server is initialized when jdt.ls is ready | 34 to 330 ms after jdt.ls is ready (10 s) | `50_spring_ls` `attached` |
| `application.properties` key completion (`server.po` lists `server.port` first) | first 18 to 90 ms (400 ms), warm p95 3.4 to 4.9 ms (150 ms) | `50_spring_ls` `props_first`, `props_warm` |
| Hover on a key | 4 to 8 ms (500 ms) | `50_spring_ls` `props_hover` |
| Memory of the Spring server | 415 to 477 MB (1 GB, hard limit 1.5 GB) | `50_spring_ls` `rss` |
| Only Boot projects, one client for `.java`/`.yml`/`.properties`, jdt.ls gets its five extension bundles (debug bundles kept), JDK from discovery not `PATH`, off switch works | rules checked (plain Maven project, loose file, `vim.g.nv4j_spring = false`, JDK 21 first on `PATH`) | `50_spring_ls` `plain_maven`, `loose_file`, `yml_java_attached`, `bundles`, `server_jvm`, `disabled`, `off_at_start`, `detect` |
| P1 budgets hold with it running | completion worst warm p95 41 to 55 ms (150; 40 to 47 ms with it off, A/B in the feature spec), cold first 43 to 61 ms (400), `@` RestController rank 1 (top 5), diagnostics 443 to 516 ms (3 s), over the Task 3 and the three final full runs | checks `10`, `11`, `30` |

`:SpringBoot` (from the plugin) also exists; use `<leader>sp` below, which asks only the Spring server.

### Spring completion and navigation (P2/P4)

The Spring items come through the usual blink menu and the usual keys (`gd`, `K`); one new key, `<leader>sp`. Numbers from 3 consecutive runs of `51_spring_completion` (20 of 20 PASS each) and `52_spring_nav` (12 of 12 PASS each, after review round 1) plus the three final full runs (same counts), the menu as blink shows it (every source, Nv4J's sorting, `max_items`):

| What you get | Measured (budget) | Check |
|--------------|-------------------|-------|
| `application.properties`: `server.po` -> `server.port`, `spring.jpa.hibernate.ddl` -> `ddl-auto` | rank 1 (top 3) | `51` `props_port`, `props_ddl` |
| `application-dev.yml`: `server:` + `po` -> `port`, top-level `server.po` -> `server.port`; no docker-compose snippets in Spring yml/properties files | rank 1 (top 3); first 27 to 39 ms (400 ms), warm p95 9.5 to 11.3 ms (150 ms) | `51` `yml_port`, `yml_dotted`, `yml_no_snippets`, `yml_first`, `yml_warm` |
| `@Value("${` lists the keys (about 1850): the ones set in your own `application*.properties`/`yml` first (`demo.greeting.text`, and `zz.sample.flag`, which sorts after every Boot key), then Boot's; `@Value("${server.po` -> `server.port` | `demo.greeting.text` rank 1, `zz.sample.flag` rank 3, `server.port` rank 1 (top 3); first 74 to 107 ms (400 ms, sent 1 s after the file opens), warm p95 43 to 58 ms (150 ms) | `51` `value_keys`, `value_project_late`, `value_prefix`, `value_first`, `value_warm` |
| `@Profile("")` lists the profiles of `application-*.yml` (`dev`), no snippets inside string literals (they still show in code) | rank 1 (top 3) | `51` `profile`, `profile_clean`, `snippets_kept` |
| A properties file with syntax errors and a yml with bad indentation: completion on the next valid line works, the server stays up (same process) | rank 1, client alive | `51` `broken_props`, `broken_yml`, `alive_after` |
| `@` still lists `RestController` first with the Spring server on the buffer (0 Spring items in the list) | rank 1 (top 5) | `51` `at_regression` |
| `K` on a key in yml and properties | 8 to 26 ms yml (`logging.level`), 1 to 2 ms properties (500 ms); first yml `server.port` 225 to 286 ms (regression limit 1 s, see Known limitations) | `52` `hover_yml`, `hover_props`, `hover_yml_port` |
| `gd` on `@Value("${server.port}")` lists `application.properties` and `application-dev.yml` at the key | 44 to 69 ms (500 ms) | `52` `definition` |
| `<leader>sp`: beans and request mappings with full paths (`/customers -- GET`, `/customers/{id} -- PUT`, `/hello -- GET`) in Telescope; Enter jumps to the mapping; a non-Boot buffer, or a server that does not answer within 5 s, gets a warning | picker with 17 entries in 108 to 150 ms (1 s) | `52` `mappings`, `beans`, `key`, `picker`, `picker_jump`, `no_client`, `no_answer` |

Code: `nvim/lua/nv4j/completion.lua` (server order kept for Spring items, snippet rules), `nvim/lua/nv4j/spring_nav.lua`. Trials and negative controls: `specs/features/spring-language-server.md`.

### Also available (from LazyVim, not covered by the checks)

Telescope, neo-tree, git signs, `lemminx` for XML (`pom.xml` formatting and validation), and from the user's dotfiles (D26) the AI agent keys, hlchunk indent guides, Markdown rendering, Prettier on demand, `mini.align` and tag editing for HTML/XML. They are here because the base config had them, they are not part of P1's measured work.

## Not yet

Be aware before you rely on Nv4J for a full workday:

- **P2 leftovers: Spring awareness.** Properties/yml completion and hover, `@Value`/`@Profile` completion, `@Value` go to definition, beans and request mappings are checked (Capabilities). Not checked yet: annotation attribute checks beyond jdt.ls (`@Table(`/`@Column(` lists come from jdt.ls only), the Spring server's own diagnostics (unknown keys, bad values), `:SpringBoot` (the plugin's command; `<leader>sp` is the checked path).
- **P2 leftovers: run.** Spring Boot run and debug are checked (Capabilities). The build-tool fallback (`spring-boot:run`, `bootRun`, used only without jdt.ls) is checked as a command, not run (Maven could not reach its plugin offline here). No saved run configurations: the profile is asked each time with `<leader>rp`, `<leader>rs` runs without one. `<leader>rj` (plain main class) is checked by hand only.
- **P3: tests runner leftovers.** The runner is checked (Capabilities: Tests). Not done: TestNG (`<leader>tT`, nvim-jdtls's picker, still runs it), JUnit 4 and multi-module or Gradle projects are not covered by a check, no tree view of every test (`<leader>to` is the quickfix list).
- **P3: scaffolding leftovers.** Scaffolding is checked (Capabilities: Scaffolding). Not checked: driving neo-tree's UI (its `file_added` handler is), insert mode after the keys (needs a UI), the JUnit 4 template, Gradle. No Exception kind or user templates.
- **P3: refactors beyond what jdt.ls already offers.** Rename class, rename package, move class, inline and change signature are built and checked (Capabilities: Refactors); extract works through jdt.ls. Safe delete is built too (own code: jdt.ls has none). Safe delete leftovers: constructors, enum constants, record components, locals and parameters are refused, not deleted; a deleted file has no `u` (it is in the trash: `:Nv4jRestoreDeleted`). Change signature leftovers: `throws` and the delegate option are not exposed; a method with implementations/overrides takes 2.6 to 4 s, so it has a separate 5 s ceiling (`change_signature_interface_ceiling`; a ruling you can overturn). Inline leftovers: "inline this occurrence" of a local variable and "inline all but keep the declaration" are not offered by jdt.ls. Move leftovers: several classes at once, a nested class, a whole package into another, another module: not supported. Rename leftovers: the prompt path, neo-tree moves to another package, Gradle and files outside the project are not checked (`specs/features/refactors.md` open items).
- **P3: carried follow-ups.** Saved run configurations (profile, env, VM args per project). (Asynchronous import apply and project ranking above frecency shipped with P3 Task 1: Capabilities, Imports and Completion.)
- **P4: Gradle** (supported by jdt.ls, not tested; the Boot detector, the `bootRun` fallback command and the build-file notification know Gradle files, nothing runs a Gradle build in the checks), JPA checks. Spring beans/request mappings navigation, planned for P4, already shipped with P2 (`<leader>sp`, Capabilities).
- **P5:** everything else.

## Install

### Requirements

- Neovim 0.12 or newer (`nvim --version`). Developed on 0.12.4.
- A JDK 21 or newer for jdt.ls, via SDKMAN or installed on the system. Your projects can use any JDK from 8 up that is installed; `.sdkmanrc` and the pom decide.
- Maven (`mvn`) on `PATH`. Needed for the test fixture build; jdt.ls brings its own m2e for project imports.
- ripgrep (`rg`). Used for the project usage counts that improve ranking. Without it everything works, ranking just falls back to jdt.ls order.
- The tree-sitter CLI (`tree-sitter`). `brew install tree-sitter-cli`. If it is missing, LazyVim installs it through Mason on first start.
- `git` and internet on first start (plugins and tools are downloaded).

### Steps

```sh
# from the repo root (the folder that holds nvim/, specs/, tests/)
ln -s "$PWD/nvim" ~/.config/nv4j
echo 'alias nv4j="NVIM_APPNAME=nv4j nvim"' >> ~/.zshrc   # then open a new shell
nv4j path/to/a/Maven/project/src/main/java/com/example/App.java
```

Why a symlink: with `NVIM_APPNAME=nv4j` Neovim reads `~/.config/nv4j` instead of `~/.config/nvim`, and the symlink points that at `nvim/` in this repo. Edit the repo files and you edit the config.

### First start

Expect it to be slow once. Neovim downloads the plugins (lazy.nvim, pinned by `nvim/lazy-lock.json`) into `~/.local/share/nv4j`, and Mason installs `jdtls`, `java-debug-adapter`, `java-test`, `vscode-spring-boot-tools` (the Spring Boot language server, about 90 MB; its Neovim client `JavaHello/spring-boot.nvim` is pinned at commit `9880be4` in `nvim/lua/plugins/spring.lua` and `nvim/lazy-lock.json`), `lemminx`, `lua-language-server`, `stylua`, `shfmt` and the tree-sitter CLI if needed. Wait until the Mason window says it is done, then restart. Opening the first Java file imports the project: about 15 s for a Spring project the first time, about 6 s after. State, cache and data live in `~/.local/share/nv4j`, `~/.local/state/nv4j` and `~/.cache/nv4j`, separate from your normal Neovim.

### Roll back

Nothing of your old setup changed. Just use `nvim` instead of `nv4j`. To remove Nv4J completely: delete the `~/.config/nv4j` symlink, the `alias` line, and `~/.local/share/nv4j`, `~/.local/state/nv4j`, `~/.cache/nv4j`.

## How to use

All keys in one table: [docs/KEYS.md](docs/KEYS.md). Short recipes (open a project, create a class, run tests, refactor): [docs/GUIDE.md](docs/GUIDE.md).

`<leader>` is Space. Every key below was read from the config and checked in a real jdt.ls session (`vim.fn.maparg` in a Java buffer). If a key does not do what is written here, that is a bug in this README.

### Daily Java and Spring workflow

1. Open a file inside the Maven project (`nv4j src/main/java/...`). Opening only a folder (`nv4j .`) reloads the last session for that folder. jdt.ls starts, you see progress in the corner, and it is ready when the progress toasts stop.
2. Write code. Completion opens as you type.
3. Accept with the keys below, the import is added for you.
4. Fix what is red or faded with `<leader>ca`, tidy with `<leader>co`.

**Completion** (blink.cmp, "enter" preset):

| Key | Does |
|-----|------|
| `<CR>` | accept the selected item (adds the import) |
| `<C-y>` | accept (select and accept) |
| `<C-n>` / `<C-p>`, `<Down>` / `<Up>` | next / previous item |
| `<C-e>` | close the menu |
| `<C-Space>` | open the menu, show or hide the docs |
| `<Tab>` / `<S-Tab>` | next / previous snippet field |

The menu also shows ghost text, a docs popup after 200 ms and signature help inside call arguments.

**Imports and code actions**

| Key | Does |
|-----|------|
| `<leader>ca` (normal and visual) | code actions: quick fixes, generate, extract |
| `<leader>co` | organize imports (also removes unused, also when the file has errors) |
| `<leader>cA` | source actions |
| `<leader>cxv` / `<leader>cxc` (normal or visual) | extract variable / constant |
| `<leader>cxm` (visual) | extract method |
| `<leader>cr`, `<F2>`, `<leader>rn` | rename symbol |
| `<leader>cf` | format |

Generate getters, constructors, `toString`, `equals`/`hashCode`: put the cursor on the class name or a field, press `<leader>ca`, pick the "Generate ..." entry. The field picker is a numbered prompt (type numbers, Enter), not a checkbox list.

**Diagnostics**

| Key | Does |
|-----|------|
| `]d` / `[d` or `<F8>` / `<S-F8>` | next / previous diagnostic |
| `]e` | next error |
| `<leader>cd` | line diagnostics popup |
| `<leader>xx` / `<leader>xX` | all diagnostics / this buffer (Trouble) |

**Navigation**

| Key | Does |
|-----|------|
| `gd`, `<F12>`, `<C-Down>` | go to definition |
| `gr`, `<C-Up>` | references (usages) |
| `gI` / `gy` | implementation / type definition |
| `K` | hover docs |
| `<leader>cS` / `<leader>cP` | subtype / supertype hierarchy |
| `<leader>ci` / `<leader>cO` | incoming / outgoing calls |
| `<leader>cgs` / `<leader>cgS` | go to super implementation / go to test subjects |
| `<C-m>` | methods of the current file (needs a terminal with the kitty keyboard protocol, else it acts as Enter) |
| `<leader>sp` | Spring symbols: beans and request mappings of the Spring Boot project (Telescope; `<leader>ss` stays LazyVim's symbols of the file; with the snacks picker extra `<leader>sp` would collide with its plugin-spec search) |
| `<C-p>` / `<C-o>` / `<C-f>` | find files / grep project / search in file |
| `<C-b>` / `<leader>e` / `<leader>ef` | file explorer / explorer at root / reveal current file |
| `<leader>cc` / `<leader>cC` | run / refresh code lens ("n references" above methods) |

**Run, debug, test** (debugging a main class is covered by `40_debug`, the Spring Boot keys by `41_run`, the test keys by `60_tests_runner`; the rest is not checked, see Not yet):

| Key | Does |
|-----|------|
| `<leader>rs` / `<leader>rd` / `<leader>rp` | run the Spring Boot app / debug it / pick a profile and run (terminal split: `<C-c>` stops, `q` stops and closes) |
| `<leader>rS` | run the Spring Boot app through Maven/Gradle (`spring-boot:run` / `bootRun`) |
| `<leader>rx` | stop every Spring Boot run |
| `<leader>rj` | run a main class with plain `java` in a terminal (picks the class if several; uses the project's JDK from jdt.ls) |
| `<leader>tr` / `<leader>tt` / `<leader>tp` | run the nearest test / the class / every test of the project, results in the editor (`<leader>tp` replaces the old `mvn test` terminal; for `mvn test` open a terminal with `<leader>tn`) |
| `<leader>tf` / `<leader>tl` / `<leader>to` | run the failed tests again / the last run again / open the results (quickfix list) |
| `<leader>td` | debug the nearest test (breakpoints stop) |
| `<leader>tT` | pick a test of the file (nvim-jdtls's picker bound by Nv4J, its own result layer; also runs TestNG) |
| `<leader>db` / `<leader>dc` / `<leader>dO` / `<leader>di` / `<leader>dB` / `<leader>dt` / `<leader>du` | toggle breakpoint / run or continue / step over / step into / conditional breakpoint / terminate / debug UI |

**New files** (checked by `61_scaffold`):

| Key | Does |
|-----|------|
| `<leader>jn` | new class / interface / record / enum / annotation / Spring controller, service, repository, entity / package / test (kind, then name; `foo.Bar` creates the package) in the current directory (neo-tree node or current file) |
| `<leader>jt` | test class of the current class: open it, or create it in `src/test/java` |

**Refactors** (checked by `62_refactor`):

| Key | Does |
|-----|------|
| `<leader>jr` | rename the class under the cursor (or the file's class): file, references, imports; on the `package` line: rename the package |
| `<leader>jp` | rename the current file's package (folders in `src/main/java` and `src/test/java` moved) |
| `<leader>jm` | move the class under the cursor to another package (picked, or typed: the folder is created) |
| `<leader>ji` | inline the method call, local variable or constant under the cursor (on a declaration: every occurrence, declaration removed) |
| `<leader>js` | change the signature of the method under the cursor (declaration or call): typed as `public int total(Invoice invoice, int discount = 0)`, call sites pass the default |
| `<leader>jd` | safe delete the method, field, constant or type under the cursor: with usages nothing is deleted and they are listed in the quickfix; without, the declaration goes (the file, for the only type of its file) |
| neo-tree `r` on a `.java` file or package folder | same rename with the code updated (`m`, move, goes the same way, not checked) |

### Terminal, comments, AI agents, guides, Markdown (merged from the user's dotfiles, D26)

| Key | Does |
|-----|------|
| `<C-/>` (`<C-_>` in terminals that send that) | toggle the terminal (LazyVim core). `<C-t>` inside it opens a new terminal tab, `<D-]>` / `<D-[>` go to the next / previous; `<C-j>` is window navigation again |
| `<D-/>` (normal, visual, insert) | toggle comment (`gcc` / `gc` work too). `<C-/>` no longer comments |
| `<leader>a` group "AI agents" | `ac` Claude, `ak` Cursor, `aa` toggle the active one, `ap` pick, `ab` add buffer, `as` send selection (visual), `ar` / `aC` resume / continue, `am` model, `af` focus Claude, `ay` / `an` accept / deny the Claude diff. Nothing loads at startup. If the Claude panel was open when you left a folder, it reopens on the next `nvim` / `nvim .` there |
| `<leader>uI` | toggle indent guides (hlchunk; snacks indent and scope are disabled, one provider only) |
| `<leader>cp` / `<leader>um` (Markdown) | toggle the in-buffer rendering (render-markdown.nvim) |
| `ga` / `gA` | align text (mini.align) |

`<leader>co` (organize imports), `<leader>cO` (outgoing calls) and `<leader>tp` (project tests) stay Nv4J's. Checked by `65_dotfiles_merge`; the agents themselves (`claude`, `cursor-agent`) are not run by any check.

### Projects without a build file (`.nv4j`)

jdt.ls takes the project root from the nearest `pom.xml`/`build.gradle*` (or the repo root when that has one). A folder of plain `.java` files with no build file has no such marker, so every folder you open a file in becomes its own project and gets its own jdt.ls (about 1.3 GB each). Mark the project instead: put an empty file named `.nv4j` in its top folder.

```sh
touch ~/code/data-structures-and-algorithms/.nv4j
```

The nearest `.nv4j` above a file is its project root, before any build file (decision D25): every folder below it shares one jdt.ls and one workspace, and classes in one folder resolve classes in the sibling folders. It needs nothing inside (no settings yet). Restart Neovim after adding or removing it (a running jdt.ls keeps its root). When a second jdt.ls starts for a loose folder while another loose folder already has one, Nv4J warns once with both folders and their common parent, the place for the `.nv4j` file (when that parent is your home folder, `/` or a short path like `/opt`, it says "the project folder that holds both" instead); the second jdt.ls still starts. A `.nv4j` in your home folder or above is honoured but warned about once, and it never turns on the usage-count scan there. A `.nv4j` next to a `pom.xml` keeps Maven, Spring Boot and run as usual; a `.nv4j` without a build file next to it means no Spring Boot server and no `mvn` run, files are scaffolded in the default package, and usage counts include the whole folder. Checked by `64_project_marker` (one client and one workspace for 3 sibling folders, jdt.ls 1257 to 1294 MB over 5 runs, proposed budget 2 GB, not yet confirmed; the warning once).

### Switch JDK with `sdk use`

The JDK that jdt.ls runs on is chosen when it starts, from `$JAVA_HOME`. Set it before you start Neovim:

```sh
sdk use java 21.0.7-amzn     # sets JAVA_HOME in this shell (SDKMAN)
nv4j path/to/File.java       # jdt.ls now runs on JDK 21
```

Checked: with that command, `JAVA_HOME` was the 21 JDK and the config picked it as the server JVM. The JDK used to compile your project is separate and follows the build file (the fixture still got JavaSE-25 as its default with `JAVA_HOME` on 21). To change the project's JDK edit `<maven.compiler.release>` or `.sdkmanrc`. After changing either of these in a running session, quit and start Neovim again.

### Hide or show more types in completion

Some JDK packages are hidden from completion by default (`com.sun.*`, `sun.*`, `jdk.internal.*`, `com.apple.*`, AspectJ internals, `java.awt.List` and a few more; the list is `DEFAULT_FILTERED_TYPES` in `nvim/lua/nv4j/completion.lua`). To change it, set this before jdt.ls starts, for example in `nvim/lua/config/options.lua`:

```lua
vim.g.nv4j_filtered_types = {
  add = { "javax.swing.*" },        -- hide these too
  remove = { "java.awt.List" },     -- show these again
}
```

Checked: the resulting list has `javax.swing.*` added and `java.awt.List` removed. Restart Neovim after changing it.

### Options (`vim.g`, set in `nvim/lua/config/options.lua`)

| Option | Default | Effect |
|--------|---------|--------|
| `vim.g.nv4j_spring` | on (unset) | `false` at startup: spring-boot.nvim is not loaded, no Spring Boot LS, Mason does not install `vscode-spring-boot-tools` (if it was false at the first start). Set later in a session it only stops new buffers from attaching. Checked: `50_spring_ls` `disabled`, `off_at_start` |
| `vim.g.nv4j_run_tool` | unset (`java -cp` with jdt.ls's classpath) | `"maven"` (Maven first) or `"gradle"` (Gradle first): `<leader>rs`/`<leader>rp` run through `spring-boot:run`/`bootRun`; debug always goes through jdt.ls. Checked: `41_run` `force_tool` |
| `vim.g.nv4j_filtered_types` | `DEFAULT_FILTERED_TYPES` in `nvim/lua/nv4j/completion.lua` | `{ add = {...}, remove = {...} }` types hidden from completion, see the section above |

### Completion profiler

`:CompletionProfile on` starts a profiler that you turn on only when something feels slow. It records, per keystroke, the time to the menu, jdt.ls round trips, whether the list was incomplete, and UI stalls, as JSON lines in `~/.local/state/nv4j/completion-profile.jsonl`. `:CompletionProfile off` stops it, `status` shows the file and its size, `clear` deletes it (after `off`). It is always off after a restart.

## Configuration map

```
nvim/
  init.lua                 sets up the nv4j paths (/tmp/nv4j, ~/.cache/nv4j) and the LSP log, then lazy.nvim
  lazyvim.json             LazyVim extras: telescope, neo-tree, blink, mini-surround, dap.core, formatting.prettier, lang.markdown, lang.java
  lazy-lock.json           pinned plugin versions
  lua/config/              options.lua, keymaps.lua, autocmds.lua, lazy.lua
  lua/plugins/
    java.lua               jdt.ls settings, JDK runtimes, import order, code generation, hooks
    blink.lua              completion UI and the Java ranking hooks
    diagnostics.lua        inline diagnostics (tiny-inline-diagnostic)
    lsp.lua, xml.lua       code lens on, inlay hints off, lemminx
    spring.lua             spring-boot.nvim (pinned) + Mason vscode-spring-boot-tools
    neo-tree, telescope, gitsigns, noice, which_key, theme, treesitter, expand-region
    ai, claudecode, sidekick, hlchunk, markdown, mini-align, ts-autotag   from the user's dotfiles (D26)
  lua/nv4j/                Nv4J's own small Lua modules
    jdk.lua                JDK discovery and runtimes
    completion.lua         Java ranking, filtered types, snippet rules
    usage.lua              project usage counts (ripgrep)
    warmup.lua             warm-up completion when jdt.ls is ready
    unused_imports.lua     unused-import warnings while the file has errors
    buildfile.lua          notifications for broken pom.xml / build.gradle
    codegen.lua            field pickers preselect all fields
    debug.lua              debug fixes: serialized first launching calls, build before launch, no orphan
    run.lua                run/debug Spring Boot (<leader>rs/rd/rp), terminal split, process tree stop
    spring.lua             Spring Boot LS: Boot-only gating, JDK, jars, jdt.ls bundles (vim.g.nv4j_spring)
    root.lua               project root shared by jdt.ls and the Spring Boot LS
    paths.lua              log dirs (/tmp/nv4j) and jdt.ls workspace dirs (~/.cache/nv4j)
    tests.lua              test runner (<leader>tr/tt/tp/tf/tl/td/to)
    scaffold.lua           new class/package/test (<leader>jn/jt), the :e and neo-tree templates
    refactor.lua           rename class/package, move class, inline, change signature, safe delete (<leader>jr/jp/jm/ji/js/jd), neo-tree renames through jdt.ls
  lua/util/                profile.lua (:CompletionProfile), ai.lua (<leader>a agents: Claude, Cursor; Claude panel per folder)
specs/                     001 architecture, 002 P1 numbers and trial log, features/*.md
tests/                     run.sh, checks/, fixtures/, lib/
```

## Testing

```sh
tests/run.sh                          # every check, each in its own headless Neovim
NV4J_CHECKS=30 tests/run.sh           # only checks whose file name starts with 30
NV4J_CHECKS='3*' tests/run.sh         # a glob works too
NV4J_PATH_JDK=25 tests/run.sh         # friendly case: JDK 25 first on PATH (default is the hostile 21)
NV4J_FIXTURE_DIRTY=restore tests/run.sh  # restore a fixture an aborted run left changed (default: stop with the command)
```

It needs `~/.config/nv4j` linked (above), a JDK 25 (to compile the fixture) and Maven. It installs jdt.ls and `vscode-spring-boot-tools` into Nv4J's own Mason directory if they are missing, prints only PASS/FAIL/SKIP lines plus one `DONE <check> <passed> <failed>` line per check, and writes the full output to `/tmp/nv4j/logs/test-<timestamp>.log`. Exit code is 0 only if everything passed. A check that stops before its `DONE` line (an error outside its guarded cases) counts as FAIL, with its last output lines shown, so missing cases never pass silently. Each run moves the previous `latency.jsonl` to `latency.prev.jsonl`, so the samples file holds one run.

The checks (each file lists its cases at the top):

| Check | Covers |
|-------|--------|
| `00_boot`, `01_jdtls_ready` | config loads as `nv4j`, paths (logs in `/tmp/nv4j`, jdt.ls workspace in `~/.cache/nv4j`), jdt.ls attaches and imports with zero errors |
| `10_completion_latency` | warm and cold latency against budgets |
| `11_completion_ranking` | where the expected item sits, noise and snippet rules |
| `12_usage_index` | the ripgrep counts, their failure handling, no count for a loose file outside a project |
| `20_java25` | JDK selection, Java 25 and Java 21 projects |
| `30_diagnostics` | diagnostics, build file errors, unused imports with errors |
| `31_imports` | auto-import, grouping, organize imports |
| `32_code_actions` | quick fixes, generate, extract, Lombok |
| `40_debug` | debug a main class and a JUnit test: breakpoints, project JDK, no orphan, classpath race |
| `41_run` | run Spring Boot: start, env, profile, port in use, stop (process tree), debug with profile and env, quit stops apps, detection (also multi-module), build-tool path and its cwd, keys (27 cases) |
| `50_spring_ls` | Spring Boot language server: attach, properties completion and hover, memory, gating, server JDK, off switch |
| `51_spring_completion` | Spring completion in blink: properties, yml, `@Value`, `@Profile`, broken files, latency, `@` regression |
| `52_spring_nav` | Spring hover, `@Value` go to definition, beans and request mappings, `<leader>sp` picker |
| `60_tests_runner` | test runner: nearest/class/file/project/failed/last, counts with parameterized, nested, `@Disabled`, failure in quickfix and diagnostics, debug, non-compiling class, no JUnit, bounded time, keys, one session name per launch, timeout backstop (29 cases) |
| `64_project_marker` | `.nv4j` project marker: root order (unit), one jdt.ls and one workspace for 3 sibling folders under one `.nv4j`, its memory, the once-only warning for a second loose-folder jdt.ls |
| `65_dotfiles_merge` | the dotfiles merge (D26): `<C-/>` terminal and `<C-j>` window navigation, `<D-/>` comment, Nv4J keys kept (`<leader>co`, `<leader>cO`, `<leader>tp`), AI keys and lazy loading, one indent provider and the `<leader>uI` toggle, Markdown keys and extras, ported-not list, startup time (report-only), Claude panel restore |
| `61_scaffold` | scaffolding: 9 type kinds, package, dotted name, test class, prompts, default package, test dir, `:e` and neo-tree templates on disk, refusals (existing file, invalid name, outside a source root, test of a test), every created file compiles, keys (27 cases) |

Budgets: warm completion p95 at most 150 ms per case; first completion after ready at most 400 ms; expected item in the top 5 plus a relative rule per case; diagnostics at most 3 s from edit to screen; import accept at most 1.5 s (P3: item text in at most 100 ms after the accept, its import at most 1.5 s, `63_async_import`; nearest test result at most 10 s warm, `60_tests_runner`; new file on disk and opened at most 300 ms, no jdt.ls error within 3 s, `61_scaffold`); one code action round trip at most 1 s. P2: breakpoint hit at most 20 s from launch, no JVM 10 s after terminate, Spring LS initialized at most 10 s after jdt.ls is ready, `application.properties`/yml/`@Value` first completion at most 400 ms and warm p95 at most 150 ms, Spring hover and go to definition at most 500 ms, Spring LS memory at most 1 GB (hard limit 1.5 GB). D25: one jdt.ls per `.nv4j` project; its memory is measured and printed by `64_project_marker` `rss` (1257 to 1294 MB on the check's project), report-only: the proposed 2 GB is not applied as a budget. `NV4J_SPRING=0 tests/run.sh` starts every check with the Spring LS off (A/B timing). The fixture is `tests/fixtures/demo`, planted broken sources are in `tests/fixtures/planted/*.java.txt` and are loaded into a buffer in memory only, never written to disk.

### What is measured and what you must judge

Measured by the checks: everything in the Capabilities tables, as time from request or edit until the data is in Neovim (including blink.cmp's own sort and the diagnostic store).

Not measurable headless, so you decide by feel in a real session: menu drawing and colors, how typing feels at your real project's size, documentation popup timing and its `completionItem/resolve`, signature help, ghost text, inline diagnostic redraw, and the real keystroke to screen time. If something feels slow, use `:CompletionProfile on`, reproduce, and look at the file. The fixture is small; a project 10 times bigger can behave differently.

## Logs

Logs and test output are under `/tmp/nv4j/` (macOS clears `/tmp` on reboot and after a few days; none of it is needed after a run). The jdt.ls workspace and config copy are not temporary (losing them means a full re-import), so they live in Neovim's cache dir, `~/.cache/nv4j/` (`stdpath("cache")` for `NVIM_APPNAME=nv4j`):

| Path | Content |
|------|---------|
| `/tmp/nv4j/logs/test-<timestamp>.log` | full output of `tests/run.sh` |
| `/tmp/nv4j/logs/lsp.log` | Neovim LSP client log |
| `/tmp/nv4j/logs/latency.jsonl` | timing samples of the last `tests/run.sh` (the run before: `latency.prev.jsonl`) |
| `~/.cache/nv4j/jdtls-data/<project>-<hash>/` | jdt.ls workspace (project index), kept across reboots; its own log is `.metadata/.log` inside |
| `~/.cache/nv4j/jdtls-config/<project>-<hash>/` | jdt.ls writable config copy, kept across reboots |

The checks' temporary Maven projects (`/tmp/nv4j/pomcase`, `lombokcase`, `proj21`) also get their own workspace there (`<name>-<hash>`); deleting one only costs its next import.

The test run keeps its blink.cmp state in `/tmp/nv4j/state` so your own accepted completions never change test results, and never receives yours.

## Troubleshooting

| Symptom | What to do |
|---------|-----------|
| jdt.ls does not start | `<leader>cl` (LSP info), then read `/tmp/nv4j/logs/lsp.log` and `~/.cache/nv4j/jdtls-data/<project>-<hash>/.metadata/.log`. Check `:Mason` that `jdtls` is installed. |
| Error "no JDK >= 21 found for jdtls. Searched: ..." | Install one: `sdk install java 25-amzn` (or any 21+), or set `JAVA_HOME` to a JDK 21+ before starting. The message lists the folders searched. |
| Several `java` processes of jdt.ls, GBs of memory, warning "Starting a second jdt.ls" | A project without a build file: each folder got its own jdt.ls. Put an empty `.nv4j` in the project's top folder (How to use: Projects without a build file) and restart Neovim. |
| No ranking boost from project usage | `rg` is not on `PATH`. `brew install ripgrep`. Everything else still works. |
| Java files show strange old errors, or the project looks stuck | Quit Neovim, delete that project's workspace `~/.cache/nv4j/jdtls-data/<project>-<hash>` (or all of `~/.cache/nv4j/jdtls-data`), start again (the next start re-imports, about 15 s). |
| Red `pom.xml` notification | Read it, it is jdt.ls's reason (malformed XML, missing artifact). Fix the pom; it reloads on save with no prompt. |
| First start errors about tree-sitter parsers | Install the CLI: `brew install tree-sitter-cli`, then `:TSUpdate`. |
| `tests/run.sh`: "symlink missing" | Run the `ln -s` step from Install. |
| `tests/run.sh`: "the fixture has uncommitted changes" | An aborted run left edits in `tests/fixtures/demo`. Run the printed `git -C ... checkout ... && git -C ... clean ...` command (it touches only the fixture's `src` and `pom.xml`), or rerun with `NV4J_FIXTURE_DIRTY=restore` (does the same) or `NV4J_FIXTURE_DIRTY=allow` (keeps your fixture changes). |
| `tests/run.sh`: "JDK 25 not found" | `sdk install java 25-amzn`; the fixture needs a JDK 25 compiler. |

## Known limitations

- **Rename leaves strings and config alone.** After a class or package rename, JPQL strings, `@Qualifier`/`@Named` names and class names in `application.yml`/`.properties`/`.xml` that still name the old class are listed in a warning, not rewritten (IntelliJ's "search in strings" is not built). `.sql`, `.json` and other files are not scanned.
- **A late import can be dropped.** When jdt.ls sends the import after the item is in (P3), Nv4J drops it if you undid the accept or closed the buffer first, and gives up if jdt.ls does not answer within 10 s. The unresolved type then shows as an error; the quick fix (`<leader>ca`, Import) or `<leader>co` adds it. Only import edits are taken from jdt.ls's resolve and only the import statement is used (Nv4J places it); other late edits are not applied.
- **jdt.ls sometimes sends no import.** Right after the same import was removed from the file (a fast edit-undo-complete sequence), jdt.ls's resolve can still see the old import and send no import edit: the type is inserted without its import. Recover with the quick fix or `<leader>co`. Measured: 0 of 100 resolves in the 50-run loop of `63_async_import` (each run waits for jdt.ls to settle first); seen once in several early check runs, in a case that started right after the previous case ended with that import, before the check waited for jdt.ls. Frequency in normal editing: not measured.
- **Frecency still counts once you type.** With a typed prefix blink's frecency bonus (up to +6) still adds to the match score, as before; on lists with nothing typed it only breaks ties (P3).
- **Usage counts are by name**, not resolved references: `save` on any receiver counts. They need `rg`. A loose file outside any project (no `pom.xml`, `build.gradle*`, `settings.gradle*`, `.git` or `.nv4j` in its folder) gets no counts.
- **Prefix-less `@`** gives `RestController` at 1 on the fixture (4 before P2's ranking changes) because the project uses annotations. In a project that has never used an annotation the list is jdt.ls's order. Typing one letter fixes it.
- **Unused local in a method that has an error** is not reported (jdt.ls skips that method). Unused imports are handled (Nv4J's own pass). That pass also treats a fully qualified use or the same name used as a local as a use, so it can miss an unused import (a false negative, not a false alarm).
- **Cosmetic gaps vs IntelliJ:** a blank line between every import group, `Objects.hash(name, Integer.valueOf(age))`, `toString` without quotes around strings, a numbered prompt for field selection.
- **Cold request edge:** the 400 ms first-completion budget is measured 1 s after jdt.ls is ready. A completion in that first second, or right after a `pom.xml` change reloads the project in the same session, can still cost 0.7 to 0.9 s once. A first-ever import of a project takes longer (about 15 s).
- **Only the project's own `pom.xml` and `.sdkmanrc` decide the project JDK.** A `release` inherited from a parent pom (not the Spring Boot starter parent) is not seen and falls back to `$JAVA_HOME` or the newest JDK.
- **Format-on-save is off** (`vim.g.autoformat = false`, kept). The Prettier extra is back (D26): `<leader>cf` formats YAML/JSON/Markdown/HTML/CSS through Prettier (Mason installs it at the first start); Java and XML still format through the language servers. Nothing formats on save.
- **Mason installs more at the first start (D26):** `prettier`, `markdownlint-cli2`, `markdown-toc` and the `marksman` server, for the Markdown and Prettier extras. `tests/run.sh` never reaches Mason's `ensure_installed`, so they do not block a check.
- **AI agents are not run by any check (D26):** `65_dotfiles_merge` checks the keys, the lazy loading and the Claude panel restore with a stubbed command. Claude needs the `claude` CLI, Cursor needs `cursor-agent`; neither is installed by Nv4J.
- **`<leader>uI` differs from the dotfiles (D26):** there the first press ran `:DisableHLIndent`, which does not exist while hlchunk's indent module is off (its default), so the key errored. Here the first press switches the guides on.
- **Plugin update check in the background:** lazy.nvim's update checker (`checker.enabled = true`, `notify = false`) periodically runs a background `git fetch` for every plugin. It only checks, it never installs or updates anything; updates happen only when you run `:Lazy update`. `nvim/lazy-lock.json` pins what the tests ran with.
- **`<leader>rs` is not `mvn spring-boot:run`** (decision D15: faster, no network). It runs `java -cp` with jdt.ls's classpath and classes, so it skips the `spring-boot-maven-plugin` `<configuration>` (`jvmArguments`, `environmentVariables`, `profiles`, `mainClass`, `arguments`), a `spring.profiles.active` set by a pom profile, plugins bound to `process-classes` or earlier phases that jdt.ls does not run, and the plugin's `-XX:TieredStopAtLevel=1`. Resource filtering does happen: m2e inside jdt.ls replaced `@project.version@` in `application.properties` on the fixture (one probe, `specs/features/run.md`). Annotation processors (Lombok, MapStruct) were not verified for this path. If your project relies on any of that, use `<leader>rS` or set `vim.g.nv4j_run_tool = "maven"`.
- **Spring Boot language server limits:** the first second after it starts, a properties completion can come back empty (its index is still loading; the check sends its first request 1 s after start). Boot detection reads the build files once per session: adding Spring Boot to a `pom.xml` needs a restart. With two Spring Boot projects open, the server's Java questions go to the first jdt.ls. `vim.g.nv4j_spring = false` in `options.lua` keeps the plugin from loading; set later in a session it only stops new buffers from attaching (a running server stays). The Mason package stays installed unless the flag was false at the first start. Not detected as Spring Boot: modules deeper than 2 levels below the project root, and a project whose corporate parent pom (outside the repo) brings Boot while its own build files name no Boot groupId, starter, plugin or BOM: `<leader>rs` says "Not a Spring Boot project" and no Spring server starts. Adds about 400 MB of memory per Spring Boot project. The first `K` on some yml keys waits for the server once: `server.port` 202 to 286 ms (up to 516 ms seen), other keys 1 to 99 ms, then 1 ms (`52_spring_nav` `hover_yml_port` fails above 1 s). A `@Value("${` completion in the same instant the Java file opens can take about 0.5 s once, and `@Profile("")` can come back empty once (the checks send them 1 s after opening). In `@Value("${` the keys set in your own `application*.properties`/`yml` come first (your own namespaces before `spring.*`/`server.*`/`logging.*`); the rest of the about 1850 Boot keys follow in the server's alphabetical order and the menu shows 200, so with an empty prefix a Boot key late in the alphabet can be missing: type a prefix. New config files are seen within 10 s. No snippets inside a Java `"..."` string, judged on the current line only (inside a text block body they still show).
- **Debug limits:** the JUnit fix replaces JDT's bundled `junit-platform-launcher` with the one that matches your `junit-platform-engine`, taken from `~/.m2`; if that jar is not downloaded (or the engine does not come from a Maven repository, e.g. Gradle) you get a one-time warning and the bundled launcher stays (the test can then die with `ClassNotFoundException` in about 1 of 4 jdt.ls sessions). The `mvn dependency:get` the warning suggests goes through your Maven settings: behind a company mirror that is unreachable (VPN off, offline) it fails like any download. Then add `org.junit.platform:junit-platform-launcher` as a test dependency of the project (Spring Boot's BOM manages the version), which `mvn` fetches the next time the mirror is reachable. Why jdt.ls puts its own launcher on the classpath only in some sessions is not known. The build before launch is a refresh plus two incremental builds because jdt.ls signals no end of its refresh: near-deterministic (every recorded run passed), not guaranteed. A build with compile errors warns and launches anyway (decision D16).
- **Spring Boot LS install for everyone:** Mason's `ensure_installed` installs `vscode-spring-boot-tools` (about 90 MB) at the first start for every user, also for non-Spring work, unless `vim.g.nv4j_spring = false` was set before that first start. Offline or behind a proxy Mason shows its install error at start; Java support (jdt.ls) is not affected. `tests/run.sh` then prints a WARN and a SKIP line for each Spring check (50, 51, 52) and runs the rest.
- **Plugin internals wrapped at runtime:** to fix upstream races Nv4J wraps, in memory, the jdt.ls client's `request`, `jdtls.start_or_attach` (nvim-jdtls) and `dap.adapters.java` (`nvim/lua/nv4j/debug.lua`). No files of the plugins are patched, and `nvim/lazy-lock.json` pins the versions the checks ran with; a plugin update can break a wrap, and `40_debug` is what catches it.
- **Run limits:** the real `mvn spring-boot:run` (and the kill of Maven's forked JVM) was never run by the checks here (Maven could not resolve the plugin through an unreachable company mirror): `<leader>rS` is checked as a command, the process-tree stop on a synthetic tree whose processes ignore SIGTERM. `<leader>rd`'s Started and failure notifications are read from nvim-dap's terminal buffer, whose width is unknown (a pooled or hidden terminal is 80 columns or less): Started and the port are matched on the rows joined, the failure block row by row, so a Description or Action wrapped in the middle of a word shows a stray space (`41_run` `dap_scan`, `leave_stops_debug`). Children forked after the stop's process snapshot are only caught through the process group.
- **Test runner limits:** only JUnit 5 is covered by a check (JUnit 4 takes the same path, TestNG is not run: use `<leader>tT`). Stack frames jump to files under `src/*/java` of the project root and one module level down. Test output (`System.out`) goes to the dap-repl, not into the results. One run at a time: a second key press while a run is going, or still finding its tests, says so. Finding the tests is bounded at 15 s (`vim.g.nv4j_test_discovery_timeout_ms`): a jdt.ls that never answers gives "no answer from jdt.ls within 15 s", the whole run at 120 s (`vim.g.nv4j_test_timeout_ms`). `require("nv4j.tests")._last_raw` keeps the last 500 lines of the runner stream (all of it with `vim.g.nv4j_tests_debug = true`). LazyVim's java extra test keys are off (`opts.test = false` in `plugins/java.lua`, which adds the java-test bundle back itself); every `<leader>t` test key, `<leader>tT` included, is Nv4J's.
- **One jdt.ls per loose folder without `.nv4j`:** plain `.java` files with no build file and no `.nv4j` above them still get one jdt.ls per folder (about 1.3 GB each; nothing caps the number); Nv4J only warns once per folder when a second one starts. Add a `.nv4j` (How to use). jdt.ls has no `-Xmx` set by Nv4J (its launcher's `-Xms1G`; the JVM's default ceiling is 25% of RAM). The `.nv4j` file has no settings yet (format open), and adding or removing it needs a restart. A `.nv4j` above several Maven projects (none at its own level) makes them one jdt.ls root without Spring Boot server or `mvn` run (not checked).
- **Terminal needs:** `<C-m>` needs the kitty keyboard protocol, `<D-Left>`/`<D-Right>`, `<D-/>` (comment) and the Cmd+bracket terminal keys are for kitty on macOS. `<C-/>` reaches Neovim as `<C-/>` or `<C-_>` depending on the terminal; both toggle the terminal.
- **Test harness limits:** the latency checks type each case in one step, not key by key (two cases cover the typed path); `lsp.complete` in the harness sends no completion context, the ranking path uses blink's own.

Each later plan (P3, P4, P5) updates the Capabilities and Not yet sections as its last task.
