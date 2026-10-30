# 001 - Architecture and workflow

Status: P1 and P2 confirmed and built (14 checks, 218 PASS 0 FAIL in each of the three consecutive final P2 runs; 223 PASS 0 FAIL after the final review fix wave, `41_run` 27 cases; P2 details in `specs/004-p2-spring-run-debug.md`), P3 in progress (Task 0 done: research, fixture, decisions D21 to D24, failing checks 60 to 63; Task 1 done: async import and frecency, `63_async_import` passes; Task 2 done: test runner, `60_tests_runner` 29 cases; Task 3 done: scaffolding, `61_scaffold` 27 cases; Task 4 done: five refactors, `62_refactor` 118 cases (116 on a case-sensitive file system); `specs/005-p3-tests-scaffold-refactor.md`; D25 `.nv4j` project marker built as an extra task, `64_project_marker` 17 cases; D26 dotfiles merge built, `65_dotfiles_merge` 10 cases; final runs and whole-branch review done, see 005), P4 and P5 not started. Source of truth for Nv4J. Later specs must not contradict this file. User-facing summary: `README.md` (keep both consistent; each later plan updates the README Capabilities section in its last task).

## Goal

A fast, lightweight Neovim setup for Java and Spring development. IntelliJ is the feature reference. Each feature gets a priority (P1 highest, P5 lowest) and a measurable pass/fail criterion.

## Decisions

D1 to D6 are confirmed by P1 (nothing was reversed). D7 to D13 are decisions taken during P1. D14 to D20 are P2 decisions (`specs/004-p2-spring-run-debug.md`). D21 and later are P3 decisions (`specs/005-p3-tests-scaffold-refactor.md`).

| # | Decision | Owner | Status |
|---|----------|-------|--------|
| D1 | Start from the existing LazyVim-based config, keep only what Java/Spring needs. No rewrite from scratch. | Claude (user agreed to approach) | Confirmed. `lazyvim.json` dropped `lang.typescript.vtsls` and `formatting.prettier` (nothing used them). Later: D26 added `formatting.prettier` back (with `lang.markdown`) by the user's ruling; `lang.typescript.vtsls` stays dropped. |
| D2 | Maven is first-class. Gradle is supported but second. | User | Confirmed. Gradle is untested (P4). |
| D3 | The existing `~/.config/nvim` is never modified. | User | Confirmed. |
| D4 | Config lives in this repo under `nvim/` and runs as a separate Neovim app named `nv4j`. | User | Confirmed. `~/.config/nv4j` is a symlink to `nvim/`. |
| D5 | Logs and temporary test output live under `/tmp/nv4j/`. The jdt.ls workspace (`-data`) and its writable `-configuration` copy are not temporary and live under `stdpath("cache")` (`~/.cache/nv4j/jdtls-data`, `~/.cache/nv4j/jdtls-config`): macOS empties `/tmp` on reboot and after 3 days, which forces a full re-import and can corrupt a running index. | User (`/tmp/nv4j`); final review (jdt.ls dirs) | Confirmed (`nvim/lua/nv4j/paths.lua`, check `00_boot`). |
| D6 | Priorities: P1 completion/diagnostics/imports/code actions/Java 25; P2 Spring awareness, run, debug; P3 tests, scaffolding, refactors; P4 Gradle, Spring navigation, JPA checks; P5 everything else. | User | Confirmed. P1 done. |
| D7 | Nothing is pinned to one JDK. JDKs come from SDKMAN (`~/.sdkman/candidates/java`), `~/Library/Java/JavaVirtualMachines`, `/Library/Java/JavaVirtualMachines`. jdt.ls runs on `$JAVA_HOME` if >= 21, else the newest >= 21; the project JDK follows `.sdkmanrc` and the pom. | User (Task 4) | Built: `nvim/lua/nv4j/jdk.lua`, `specs/features/jdk-java25.md`. |
| D8 | Unused-import warnings must show even when the file has compile errors (jdt.ls/ECJ drops them then, IntelliJ keeps them). | User (Task 6) | Built: `nvim/lua/nv4j/unused_imports.lua`. |
| D9 | `<leader>co` is Organize Imports (removes unused, orders groups). Outgoing calls moved to `<leader>cO` so each key means one thing. | User (Task 6) | Built, checked in `31_imports`. |
| D10 | Organize imports on save stays off (IntelliJ default). | User (Task 6) | Built (`java.saveActions.organizeImports = false`). |
| D11 | Completion ranking uses project usage counts, counted with ripgrep (IntelliJ `PreferMostUsedWeigher` idea), as a tie breaker after jdt.ls relevance. | Claude, accepted by user (Task 5) | Built: `nvim/lua/nv4j/usage.lua`; without `rg` ranking falls back to jdt.ls order. |
| D12 | `java.awt.List` is hidden from completion by default so `List` completes to `java.util.List`. Override with `vim.g.nv4j_filtered_types = { add = {...}, remove = {...} }`. | User (Task 5 review) | Built: `nvim/lua/nv4j/completion.lua`. |
| D13 | Budgets stay as set below, not weakened. `cold_first` is measured 1.0 s after jdt.ls ServiceReady. | Task 5 ruling | Confirmed with the numbers below. |
| D14 | Spring Boot language server wiring: the `JavaHello/spring-boot.nvim` plugin (pinned, commit `9880be4`) with the Mason `vscode-spring-boot-tools` server, configured by nv4j (root = the jdt.ls project root, `java_cmd` from `nv4j.jdk`, start only for Spring Boot projects), not our own thin Lua client. Reason: the plugin already implements the client half of the `sts/*` protocol (12 forwarders to jdt.ls, classpath-listener callbacks, language ids, settings push after classpath events), which our own client would have to re-implement in at least about 150 lines; it is Neovim 0.12 native and met every P2 Spring LS budget in the Task 0 trial (first completion 195 to 205 ms, warm p95 5 to 6 ms, hover 7 ms, RSS about 300 to 430 MB). Ponytail rule: a plugin only because it removes real code. Revisit if the pinned plugin breaks or costs a budget. Details: `specs/features/spring-language-server.md`. | Claude (P2 Task 0), user can overturn | Built (P2 Task 3): `nvim/lua/nv4j/spring.lua`, `nvim/lua/plugins/spring.lua`, `50_spring_ls` 13 of 13. |
| D15 | Spring Boot run (`<leader>rs`) starts the `@SpringBootApplication` main class with plain `java -cp <jdt.ls classpath>` on the project JDK (`nv4j.jdk`), after jdt.ls's refresh + build, not `mvn spring-boot:run`; the build tool (Maven first, then Gradle `bootRun`) is the fallback without jdt.ls and an opt-in (`<leader>rS`, `vim.g.nv4j_run_tool`) for projects that need the plugin's `<configuration>` or pom profiles. Stop kills the whole process tree. | Task 2 trials | Built: `nvim/lua/nv4j/run.lua`, `41_run`. Measured 2.5 s against 5 to 7 s to "Started", and `spring-boot:run` hung on plugin resolution over the network (`specs/features/run.md`). |
| D16 | Every Java debug or run launch first refreshes the project's source folders in jdt.ls and runs two incremental builds (VS Code builds before launch too; nvim-jdtls does not). Compile errors, a failed build or a 60 s timeout only warn, then the launch goes ahead (VS Code asks). | P2 Task 1 ruling | Built: `nvim/lua/nv4j/debug.lua` (`M.build`, `M.refresh_and_build`), `40_debug` `breakpoint_hit`, `build_guard`. Cost if wrong: a launch on stale classes after a warning the user may miss. |
| D17 | One Spring Boot detector, shared by run and the Spring Boot LS (`nvim/lua/nv4j/root.lua` `boot_build`/`boot_project`): Boot groupId, starters, Maven plugin, BOM, Gradle plugin/group/starters, catalog aliases, outside comments; a bare `spring-boot` text (a `spring-boot.version` property) does not count. Root plus modules up to 2 levels down, memoized per session (`root.is_boot`, used by both since the P2 final review; before, run checked only the root and the buffer's module). | P2 Task 3 review | Built: `41_run` `detect`, `multi_module`, `50_spring_ls` `detect`. Cost: a Boot parent brought only by a corporate parent pom outside the repo is not seen; adding Boot needs a restart. |
| D18 | The `spring-boot` client stays on Java buffers with full capabilities (needed for `@Value`/`@Profile` completion and go to definition). Spring items keep the server's order inside blink; jdt.ls's sortText formula is read only for `jdtls` items; inside `@Value("${` the keys set in the project's own config files rank first. | P2 Tasks 3 and 4 | Built: `nvim/lua/nv4j/completion.lua`, `51_spring_completion`. A/B with the Spring LS off: worst warm p95 +5 ms (budget 150). |
| D19 | The Spring symbols picker is `<leader>sp` (beans `@+`, request mappings `@/`, Spring client only). `<leader>ss` stays LazyVim's Goto Symbol. | P2 Task 4 ruling | Built: `nvim/lua/nv4j/spring_nav.lua`, `52_spring_nav` `key`, `picker`. Cost: collides with the snacks picker extra's plugin-spec search if that extra is enabled. |
| D20 | First requests to the Spring Boot LS (properties completion, `@Value`, `@Profile`, yml hover) are measured 1.0 s after the client initializes or the file opens, the D13 rule applied to P2. Outliers get their own case with a regression limit instead of a warm-up (`hover_yml_port`, 1 s). | P2 Tasks 0 and 4 rulings | Confirmed by `50_spring_ls`, `51_spring_completion`, `52_spring_nav`. Deviation listed in README Known limitations. |
| D21 | Test results UI: keep nvim-jdtls's launch path (java-test bundle via `jdtls.dap.experimental`: test items, launch arguments, `dap.run`, so P2's build-before-launch, project JDK and JUnit-launcher fixes apply) and add a thin result layer in `nvim/lua/nv4j/tests.lua`: own parse of JDT's RemoteTestRunner stream (pass/fail/ignored counts, nested and parameterized names), failures as `vim.diagnostic` + quickfix with message and frames that jump to the line, a summary notification, scopes nearest/class/failed/project/last. Not a view over surefire XML: `mvn test` costs seconds of Maven start, depends on plugin resolution (failed offline in P2), honours `excludedGroups` (a tagged-out class never runs from the editor, unlike IntelliJ) and is Maven only. Reason: nearest already runs in 0.8 to 1.0 s warm (budget 10 s) through nvim-jdtls; what is missing is the result layer (it counts `@Disabled` as passed, no counts, no project or failed scope). | P3 Task 0, Claude (user can overturn) | Built in Task 2 (`60_tests_runner`, 29 cases after the review fixes). Key ruling (user, 2026-10-26): `<leader>tp` (project tests) replaces the old `mvn test` terminal key, no old key kept; it also covers Gradle, the runner goes through jdt.ls. `<leader>tT` = nvim-jdtls pick, bound by Nv4J (`opts.test = false` on the LazyVim java extra). Deviation: the same java-test commands are called directly from `nv4j/tests.lua` instead of through `jdtls.dap.experimental.run`, which always adds nvim-jdtls's own result layer; project scope = one launch per Java project with every test class (java-test 0.43.1 refuses project/package `testLevel`, measured). Details: `specs/features/tests-runner.md`. |
| D22 | Scaffolding entry: own command `require("nv4j.scaffold").new({ kind, name, dir })` with `vim.ui.select`/`vim.ui.input` for missing answers, global key `<leader>jn`; neo-tree's add and the `:e Foo.java` template call the same templates (one source). The file is written with its content before it is opened. Reason: works without the tree open and from any buffer; a neo-tree-only hook needs the tree and gets the file after neo-tree created it; today's template leaves only the EMPTY file nvim-jdtls writes for new buffers on disk. | P3 Task 0, Claude (user can overturn) | Built in Task 3 (`61_scaffold`, 27 cases; also `<leader>jt` test of this class). Replaced `util/java_scaffold.lua`. Details: `specs/features/scaffolding.md`. |
| D23 | Refactor surface: jdt.ls code actions and nvim-jdtls's command handlers (rename with file rename, move, inline, change signature already work and measured 101 to 761 ms against the 2 s budget), behind thin functions in `nvim/lua/nv4j/refactor.lua` that pick the action by kind (`refactor.move`, `refactor.inline`, `refactor.change.signature`) and take answers as arguments; own code only for what jdt.ls/the clients lack: package rename (`workspace/willRenameFiles` BEFORE the folder moves, edits written, buffers re-pointed; also for neo-tree folder renames, where LazyVim asks after the move and leaves the wrong `package` line), safe delete (references first: usages listed in quickfix, else delete), change signature with arguments (`java/getChangeSignatureInfo` + `java/getRefactorEdit`). Keys `<leader>jm/ji/js/jd/jr` (Java group shared with `<leader>jn`); `<leader>cr` stays Rename (a `<leader>cr` prefix would delay rename by `timeoutlen`). | P3 Task 0, Claude (user can overturn) | Built (`62_refactor`, 118 cases). Wording note: the table text above says "code actions" for move; the build uses `workspace/willRenameFiles` for move (same jdt.ls `MoveHandler.move` as the code action, shares the package-rename path); the user has not yet ruled on this deviation (can overturn). Change signature of a method that has implementations or overrides an interface method has a 5 s ceiling (`CEILING_IMPL_MS`, jdt.ls takes 3.7 to 4.0 s cold, 2.6 s warm); every other refactor keeps 2 s (ruling, user can overturn). Task 4a: rename class/package built. Task 4b: move built on `workspace/willRenameFiles` for the file (jdt.ls runs the same `MoveHandler.move` as the code action's `java/move`) through the package-rename path, so buffers, summary and checks are shared. Task 4c: inline built on jdt.ls's `refactor.inline` code actions as decided (picked by kind and title, "Make Static" excluded; edit from `codeAction/resolve` applied through the rename path's apply/summary/follow-up); jdt.ls's own scope by cursor position (a call/reference: that one; the declaration: all, declaration removed; a local variable: all), `opts.all` asks at the declaration. Task 4d: change signature built as decided on `java/getChangeSignatureInfo` + `java/getRefactorEdit` (command `changeSignature`) with arguments (add with default, remove, rename, retype, reorder, method name, return type, visibility; `throws` and the delegate switch not exposed), no float (`<leader>js` asks the signature as one line of text, `vim.ui.input`; nvim-jdtls's float stays on `<leader>ca`); on a call the declaration is found with `textDocument/definition` (jdt.ls answers on the declaration header only); the edit goes through the shared apply/summary/follow-up, then `java/validateDocument` for the touched open files (stale diagnostics of a dependent file). Task 4e: safe delete built as decided: references first (`textDocument/references`, main and test sources; for a method also `textDocument/implementation`; unsaved and broken files also read as text): usages listed in the quickfix and nothing deleted, else the declaration removed (javadoc, annotations, one blank line; the file for the only type of its file, jdt.ls told with `didChangeWatchedFiles`); refused: locals, parameters, constructors, enum constants, record components, `@Override` methods, two declarators on one line; framework entry points (`@Bean`, request handlers, `@Value`...) deleted with a warning. All five D23 refactors are built (`62_refactor`). Details: `specs/features/refactors.md`. |
| D24 | Async import on accept: blink's `resolve_timeout_ms` lowered so the text lands <= 100 ms (about 50 ms), and Nv4J applies the import when the item's resolve, which blink keeps running after its timeout (`task:timeout` does not cancel, the provider caches the task), completes: a wrapper around blink's accept function adds the late import once, guarded (buffer valid, imports only, not already imported, accepted text still there, else dropped). Task 1 changes: jdt.ls's import ranges are never applied (they can be stale, and jdt.ls sent a range replacing the existing import line in 22 of 50 measured `HashMap` resolves): only the import statement is taken and Nv4J inserts it at a place computed from the current buffer, by `java.completion.importOrder` group and sorted (also when the resolve came in time: blink no longer applies import-only edits); joined to the accept's undo step when nothing changed since. No second resolve request. Also Task 1: for Java lists with nothing typed, blink's `score` (then only score_offset plus a frecency bonus blink adds even with an empty keyword) is replaced by score_offset, jdt.ls relevance, project usage, then frecency as tie breaker (`java_sort_empty`). Reason: smallest change that meets both halves of the budget; before, the text waited 0.4 to 0.8 s for the javadoc render that carries the import, and 20 accepts of `List` pushed `@` `RestController` to rank 24. | P3 Task 0/1, Claude (user can overturn) | Built in Task 1 (`63_async_import`, 28 cases). Details: `specs/features/async-import.md`. |
| D25 | One jdt.ls per project instead of one per directory. A `.nv4j` file marks the project root (nearest one above the file wins, before build markers and the loose-file fallback; empty, no format or settings yet). A one-time warning when a second loose-file jdt.ls starts. No `-Xmx`/`-Xms` change (developer's decision). See "Problem: one jdt.ls per loose-file directory". | User (memory report on a project without a build file); `-Xmx` dropped and warning confirmed by the user | Key rulings (user): no `-Xmx`/`-Xms`; the second-loose-file warning is wanted; the 2 GB jdt.ls RSS budget stays "proposed", not applied. Built (extra task outside the P3 plan): `nvim/lua/nv4j/root.lua` (`project`, `warn_loose`), `plugins/java.lua`, `nv4j/usage.lua`; `64_project_marker` (17 cases). |
| D26 | Dotfiles merge (the user's `~/.config/nvim`, source `dotfiles/lazyvim`, never modified). Seven rulings: (1) `<C-/>` is LazyVim's terminal toggle (`<C-_>` too, what terminals send); Nv4J's `<C-j>` terminal toggle and its `<C-/>` / `<C-_>` comment maps are removed, `<C-j>` is window navigation again; comment is `<D-/>` in normal, visual and insert mode (`toggle_comment_insert`), `gcc` / `gc` stay; the terminal tabs (`<C-t>`, `<D-]>`, `<D-[>`) work from `<C-/>`. (2) Nv4J keeps `<leader>co` (organize imports), `<leader>cO` (outgoing calls) and `<leader>tp` (project tests); the dotfiles' versions are not ported. (3) Indent guides: hlchunk on, toggle `<leader>uI`, snacks `indent` and `scope` disabled (never both). (4) AI agents: `ai.lua`, `claudecode.lua`, `sidekick.lua`, `util/ai.lua`, all `<leader>a*` keys (Claude `<leader>ac`, Cursor `<leader>ak`), and the per-folder restore of the Claude panel (VimLeavePre and a state file) merged into `autocmds.lua` beside, not touching, the scaffold autocmd (D22). (5) Markdown: `markdown.lua` (render-markdown.nvim; markview and markdown-preview stay disabled) and the `lang.markdown` extra, keys `<leader>cp`, `<leader>um`. (6) Also the `formatting.prettier` extra (format only on `<leader>cf`, `vim.g.autoformat` stays false), `ts-autotag` for `html` and `xml` only, and `mini.align`. (7) Not ported: smear-cursor, mini.animate, image, lint, the typescript/vtsls extra, anything else. | User (rulings 1 to 7, final) | Built, `65_dotfiles_merge` (10 cases; the 10th, `os_keys`, is the 2026-10-30 follow-up below). Cost if wrong: (1) a `<C-j>` / `<C-/>` habit from Nv4J's earlier keys now does something else (comment moves to `<D-/>`, which needs kitty on macOS); `<C-/>` as comment is gone. (2) none known. (3) one guide provider only: the choice costs snacks' scope-aware indent. (4) five new plugins pinned to the dotfiles' commits (`claudecode.nvim`, `sidekick.nvim`, `hlchunk.nvim`, `render-markdown.nvim`, `mini.align`; `nvim-ts-autotag` already pinned), Claude restore writes `claudecode_sessions.json` on every exit; the agents themselves are not run by a check. (5) and (6) Mason installs `prettier`, `markdownlint-cli2`, `markdown-toc`, `marksman` at the first start (an offline first start shows install errors); Prettier now owns `<leader>cf` for Markdown, JSON, YAML, HTML and CSS (Java and XML unchanged). Follow-up 2026-10-30 (user, Ubuntu): Cmd keys do not exist on Linux, so comment, jump back/forward and the terminal tabs did nothing there. Ruling: one config, the modifier is chosen at start (`D` on Darwin, `A` elsewhere, `vim.g.nv4j_mod` forces one): `<D-/>` / `<A-/>`, `<D-Left>` / `<A-Left>` (and Right), `<D-]>` / `<A-]>`, `<D-[>` / `<A-[>`. Same keys as the dotfiles' `keymaps-linux.lua`, without two copies of the file. Cost if wrong: on a Linux terminal that does not forward Alt those keys still do nothing (`gcc` works). Check 65 `os_keys`, control n65j. Two small deviations to make it work: the `<leader>uI` toggle sets hlchunk's indent up on the first press (the dotfiles' key called a command that does not exist while the module is off), and the which-key group "AI agents" is declared in `which_key.lua` (the `nil` lazy key in `ai.lua` is dropped once snacks is loaded). |
| D27 | Saved run defaults live in `.nv4j` (the D25 marker). Empty file: marker only. Optional JSON `{ "run": { "profile", "env", "vm_args" } }`. `<leader>rs` / `<leader>rd` use them when the call omits those fields; `<leader>rp` still asks (this run only) and does not write the file; Lua `opts` win. No named configs, no picker, no second store. `:Nv4jMark` writes an empty marker in cwd (the folder Neovim was opened at, not the current file's folder; refuses `$HOME` and above, does not overwrite). First settings keys: decide more keys when needed (D25). | User (2026-10-30): one default, `rp` covers the exception; 2026-10-30 follow-up: mark at cwd, not the open file's D25 loose root | Built: `nvim/lua/nv4j/settings.lua`, `run.lua` `apply`, `66_settings` 13 cases. Details: `specs/features/run-defaults.md`. |

## Budgets and results (P1, P2)

Budgets are confirmed (they were provisional until the Task 5 re-baseline). Measured on the Spring Boot fixture `tests/fixtures/demo`; details, per-case tables and trial logs in the linked feature specs. Result columns are the ranges over the consecutive full runs recorded there.

| Metric | Budget | Result | Check |
|--------|--------|--------|-------|
| Warm completion round trip p95, per case | <= 150 ms | worst case 38 to 45 ms (baseline 43 ms) | `10_completion_latency` |
| Menu list (blink sort) p95, per case | <= 150 ms | worst about 40 ms | `10_completion_latency` |
| First completion, 1.0 s after jdt.ls ServiceReady | <= 400 ms | 51 to 55 ms (baseline 740 to 827 ms) | `10_completion_latency` |
| Expected item rank in the order the user sees | top 5 plus a relative rule | `@` `RestController` 4 (jdt.ls order 6), `http.` `authorizeHttpRequests` 2 (baseline 19), `repository.` `save` 1 (baseline 42) | `11_completion_ranking` |
| Edit to diagnostics in `vim.diagnostic` | <= 3 s | errors 462 to 476 ms, unused 674 to 684 ms, fix clears 471 to 511 ms, burst settles 633 to 683 ms, Java 25 file clean 490 to 521 ms | `30_diagnostics` |
| Unused imports shown while the file has errors | <= 3 s | 473 to 506 ms; pass cost on 3000 lines p95 1.6 to 1.9 ms over 100 passes, 5 runs (budget 5 ms) | `30_diagnostics` |
| Accept a completion with its import | <= 1.5 s | first `List` 685 to 746 ms, second type 379 to 439 ms | `31_imports` |
| One code action round trip | <= 1 s | 9 to 120 ms | `32_code_actions` |
| jdt.ls open to ready | none (info) | about 6.1 to 6.4 s warm workspace, about 15 s first import | `01_jdtls_ready`, `10_completion_latency` |
| Change signature of a method with implementations or overrides (P3) | <= 5 s ceiling (every other refactor and plain change signature: <= 2 s) | 3.7 to 4.0 s cold, 2.6 s warm (4.4 to 5.0 s with the machine at load 11 to 15); jdt.ls-bound (`getRefactorEdit` hierarchy search), nothing left to overlap. A ruling the user can overturn (delegated, recorded in the SDD ledger) | `62_refactor` `change_signature_interface_ceiling` |
| Java 25 / Java 21 project correctness, JDK discovery | zero errors, right runtime | pass with `JAVA_HOME` unset and JDK 21 first on `PATH` | `20_java25` |

Last full `tests/run.sh` runs (final review, two consecutive): 135 PASS, 0 FAIL, 0 SKIP each, a `DONE` line for every check (00: 11, 01: 2, 10: 17, 11: 26, 12: 7, 20: 10, 30: 24, 31: 10, 32: 28). Logs `/tmp/nv4j/logs/test-20261020-225853.log`, `-230137.log`. Earlier (Task 7): 129 PASS, log `test-20261020-223125.log`.

P1 budgets with the Spring Boot LS running, in the three final P2 runs (logs below): completion worst warm p95 41 to 54 ms, menu p95 worst 43 to 49 ms, first completion 48 to 61 ms, `@` `RestController` rank 1 (the P2 completion changes moved it from 4 to 1), diagnostics errors 443 to 455 ms and unused 590 to 656 ms, unused pass p95 1.3 to 2.1 ms, first `List` accept 676 to 749 ms, second type 307 to 466 ms, code action round trip worst 114 to 144 ms, jdt.ls open to ready 6.1 to 6.9 s. All inside the P1 budgets. Worst warm p95 rose from about 43 ms (P1) to 41 to 54 ms: the A/B in `specs/features/spring-language-server.md` (trial `ab`) attributes about 5 ms to the Spring LS sharing the CPU.

### P2 budgets and final results

Budgets set at P2 plan start, not weakened. Ranges over the three consecutive final full runs (P2 Task 5): logs `/tmp/nv4j/logs/test-20261021-154523.log`, `-154956.log`, `-155439.log`, each exit 0, 218 PASS 0 FAIL, a `DONE` line for every check (P1 as above; 40: 16, 41: 22, 50: 13, 51: 20, 52: 12).

| Metric | Budget | Result | Check |
|--------|--------|--------|-------|
| Breakpoint hit in a Spring Boot main class, from launch (includes refresh + build) | <= 20 s | 3.24 to 3.60 s | `40_debug` `breakpoint_hit` |
| Breakpoint hit in a JUnit 5 test | <= 20 s | 768 to 792 ms | `40_debug` `test_breakpoint_hit` |
| Debuggee gone after terminate (no orphan JVM) | <= 10 s | pass, 3 of 3 | `40_debug` `no_orphan`, `41_run` `debug_no_orphan` |
| `<leader>rd` breakpoint with profile and env | <= 20 s | 2.71 to 2.95 s | `41_run` `debug_stop` |
| `<leader>rs` to "Started" (refresh, build, classpath, Boot start) | none (info) | 3.8 to 4.4 s; Boot's own start 2.0 to 2.3 s | `41_run` `started` |
| Stop a process tree that ignores SIGTERM | <= 10 s | 1.95 to 2.00 s | `41_run` `tree_kill` |
| Spring LS initialized after jdt.ls ready | <= 10 s | 34 to 49 ms | `50_spring_ls` `attached` |
| `application.properties` first completion (1.0 s after init, D20) | <= 400 ms | 18 to 21 ms | `50_spring_ls` `props_first` |
| `application.properties` warm completion p95 | <= 150 ms | 3.4 to 4.0 ms | `50_spring_ls` `props_warm` |
| Hover (properties / yml `logging.level`) | <= 500 ms | 4 to 8 ms / 16 to 26 ms | `50_spring_ls` `props_hover`, `52_spring_nav` `hover_yml` |
| First yml hover of `server.port` | <= 1 s (regression limit, D20) | 225 to 286 ms | `52_spring_nav` `hover_yml_port` |
| Extra RSS of the Spring LS | <= 1 GB (hard 1.5 GB) | 416 to 477 MB | `50_spring_ls` `rss` |
| yml completion first / warm p95 | <= 400 / 150 ms | 28 to 39 ms / 9.5 to 10.9 ms | `51_spring_completion` `yml_first`, `yml_warm` |
| `@Value("${` completion first / warm p95 | <= 400 / 150 ms | 74 to 87 ms / 42.5 to 53.2 ms | `51_spring_completion` `value_first`, `value_warm` |
| Expected Spring item rank (properties, yml, `@Value`, `@Profile`) | top 3 | 1 (`zz.sample.flag` 3) | `51_spring_completion` |
| `@Value` go to definition | <= 500 ms | 44 to 68 ms | `52_spring_nav` `definition` |
| `<leader>sp` picker (17 entries) | <= 1 s | 108 to 150 ms | `52_spring_nav` `picker` |

Feature specs: [`specs/002-p1-completion.md`](002-p1-completion.md) (budget, baseline, trials), [`specs/features/completion-ranking.md`](features/completion-ranking.md), [`specs/features/diagnostics-imports-actions.md`](features/diagnostics-imports-actions.md), [`specs/features/jdk-java25.md`](features/jdk-java25.md). P2: [`specs/004-p2-spring-run-debug.md`](004-p2-spring-run-debug.md), [`specs/features/debug-run.md`](features/debug-run.md), [`specs/features/run.md`](features/run.md), [`specs/features/spring-language-server.md`](features/spring-language-server.md).

Open follow-ups from P1: cosmetic gaps versus IntelliJ (see README, Known limitations). Async import apply and frecency vs project ranking were built in P3 Task 1 (D24).

See `003-lessons-and-method.md` for how the reference repos are used, what P1 taught us, and the improved working method.

## Reference: IntelliJ Community source

Repo: https://github.com/jetbrains/intellij-community (Apache 2.0). It is the reference for how IntelliJ implements Java and Spring-relevant features. Use: check, adapt, enhance. Not a port and not a full reverse engineering.

- Per feature, read how IntelliJ does it (completion ranking and sorting, inspections, intentions, refactorings, run configurations, test runner, debugger behaviour). Record the finding in `specs/features/<feature>.md`.
- Adapt the idea to what Neovim, JDTLS, the Spring language server and DAP can do. Where IntelliJ is better than those tools, enhance with config, sorting or small Lua, within the performance budget.
- Each feature spec holds: IntelliJ behaviour (with source path in the repo), priority P1-P5, Neovim approach, pass/fail test.
- Spring features in IntelliJ are mostly in the closed-source Ultimate plugin, not in Community. For Spring the reference is the IntelliJ user-visible behaviour and the Spring Tools language server, not Community code. This is a known limit.
- Local copy: shallow sparse clone at `~/.cache/nv4j/intellij-community`. Not committed to this repo, read only.

### More reference repos

| Repo | Use | Priority area |
|------|-----|---------------|
| https://github.com/eclipse-jdt/eclipse.jdt.core | JDT core: `CompletionEngine`, relevance computation, search/index, compiler behavior. This is what JDTLS runs on, so completion ranking and code-assist behavior can be tuned or extended against its real source. | P1 |
| https://github.com/spring-projects/spring-tools | Spring Tools (STS) source: the Spring Boot language server (annotation, `application.properties`/`yml`, bean and request-mapping support), launch and Boot Dash behavior. Reference and likely the Spring server we install. | P2, P4 |

- Same method as IntelliJ: check, adapt, enhance. Local shallow sparse clones in `~/.cache/nv4j/`, read only, not committed.
- License: both are EPL-2.0 (IntelliJ Community is Apache-2.0). Copying code into this repo is allowed only with the original license header and a note in the feature spec naming the source path. Prefer reusing the tool as a dependency (Mason or release jar) over copying source.

## Layout

```
Nv4J/
  README.md         user guide: capabilities, install, keys, limits
  specs/            source of truth (this folder)
  nvim/             the Neovim config (init.lua, lua/, lazyvim.json)
  tests/
    fixtures/       demo/ (Spring Boot Maven project) and planted/ (broken sources, in-memory only)
    run.sh          runs all checks headlessly
    checks/         one script per measurable requirement
    lib/            headless helpers (lsp, completion, edit, jdk_home, fixture)
```

## How to run

`~/.config/nv4j` is a symlink to `Nv4J/nvim`. With `NVIM_APPNAME=nv4j`, Neovim reads that directory instead of `~/.config/nvim`.

```sh
ln -s "$PWD/nvim" ~/.config/nv4j   # once, from <repo> (the Nv4J folder)
NVIM_APPNAME=nv4j nvim                                                  # use it
nvim                                                                    # old config, unchanged
```

Rollback: stop using `NVIM_APPNAME=nv4j` (plain `nvim` is the old config), delete the symlink. The `nv4j` shell alias is `alias nv4j="NVIM_APPNAME=nv4j nvim"`. Requirements and first-start steps: `README.md`.

Side effect to know: data, state and cache go to `~/.local/share/nv4j`, `~/.local/state/nv4j`, `~/.cache/nv4j`. Plugins and Mason tools install again there. They do not share the old config's installs.

## How to test

Principle: build, measure, compare against the spec number, iterate.

- `tests/run.sh` starts `nvim --headless` with `NVIM_APPNAME=nv4j` against `tests/fixtures/`.
- Each check opens a fixture file, waits for the language server, then calls LSP requests directly (completion, diagnostics, code actions) and asserts on results.
- Check types:
  - Latency: completion p50/p95 against the budget set in the P1 spec.
  - Ranking: expected item appears in the top N.
  - Diagnostics: planted errors are reported, valid Java 25 code reports none.
  - Spring (P2, built): Spring Boot LS gating and memory, `application.properties`/yml and `@Value`/`@Profile` completion, hover, `@Value` go to definition, beans and request mappings (`50_spring_ls`, `51_spring_completion`, `52_spring_nav`).
  - Run and debug (P2, built): start the fixture app or one JUnit test through DAP and the jdtls test bundles, assert a breakpoint hit, the project JDK, no orphan JVM (`40_debug`); run the Boot app with profile and env, port in use, process-tree stop (`41_run`). Test runner polish is P3.
- Not testable here, done by hand by the user: how typing and UI plugins feel.

## Logs and temp files

Logs and test output under `/tmp/nv4j/`; the jdt.ls workspace and config copy under `~/.cache/nv4j/` (`stdpath("cache")`, follows `NVIM_APPNAME`):

| Path | Content |
|------|---------|
| `/tmp/nv4j/logs/test-<timestamp>.log` | output of `tests/run.sh` |
| `/tmp/nv4j/logs/lsp.log` | Neovim LSP client log |
| `~/.cache/nv4j/jdtls-data/<project>-<hash>/.metadata/.log` | JDTLS server log (inside the workspace) |
| `/tmp/nv4j/logs/latency.jsonl` | timing samples of the last `tests/run.sh` (previous run: `latency.prev.jsonl`, rotated by `run.sh`) |
| `~/.cache/nv4j/jdtls-data/`, `~/.cache/nv4j/jdtls-config/` | JDTLS workspace data and writable config copy (persistent: losing them forces a full re-import) |

`/tmp` is cleared by macOS on reboot and after a few days. Nothing under `/tmp/nv4j` is needed after a run finishes; the jdt.ls dirs are therefore not there.

## Problem: one jdt.ls per loose-file directory

Status: diagnosed; D25 built (`.nv4j` marker and the warning; no `-Xmx`, by the developer's decision). Results under "Built (D25)" below.

### Observed

One Neovim session on a single small project (plain `.java` files under `data-structures-and-algorithms/`, no `pom.xml` or `build.gradle`, an old IntelliJ `.iml` that was later deleted) had three jdt.ls processes, all children of the same `nvim` (`ps`, `/proc/<pid>/cmdline`):

| Workspace (`-data`) | RSS | Age |
|---|---|---|
| `~/.cache/nv4j/jdtls-data/data-structures-a553159e` | about 2.0 GB | 22 h |
| `~/.cache/nv4j/jdtls-data/streams-a2a255a0` | about 1.4 GB | 1 h |
| `~/.cache/nv4j/jdtls-data/scratch-548843c0` | about 1.4 GB | 3 min |

Total about 4.9 GB for jdt.ls, plus about 0.7 GB for Neovim itself. CPU was 0%, so this is resident memory, not load.

### Cause (diagnosed from the code and specs)

1. `nvim/lua/nv4j/root.lua` `M.project`: a file with no build marker above it gets its **own directory** as root (second return value `false`). This was deliberate: the `.git` fallback would give a loose file an unrelated enclosing repo as root and break jdt.ls's invisible-project support.
2. `nvim/lua/plugins/java.lua` `opts.project_name` = `basename(root_dir) .. "-" .. sha256(root_dir):sub(1, 8)`, and `jdtls_workspace_dir` is `jdtls-data/<project_name>`. A different root therefore means a different workspace, and nvim-jdtls starts one jdt.ls client (one JVM) per root.
3. In a project without a build file, every directory where a Java file is opened becomes a root, so the number of JVMs grows with the number of directories touched, not with the number of projects. Nothing limits it.
4. Each JVM has a fixed cost that does not depend on project size: JVM base (JIT, metaspace, about 50 threads), the JDK and library index, and its own on-disk workspace. The `-Xms1G` visible in the command line makes the floor 1 GB per instance. It is not set in the nv4j code (grep of `nvim/` finds no `-Xms`/`-Xmx`); it comes from the jdtls launcher of Mason or LazyVim (not verified).
5. Gap in the specs: the only RAM budget is for the Spring LS (<= 1 GB, measured 416 to 477 MB). jdt.ls has no RAM budget and no limit of instances, and every check uses one fixture project, so the multi-root case was never measured.

So the one-JVM-per-directory behaviour is a consequence of an intentional root rule; the unbounded memory is an unspecified gap, not a requirement.

### Proposed solution (D25)

1. **`.nv4j` project marker.**
   - `root.lua` looks for a `.nv4j` file walking up from the buffer. The nearest one is the project root, checked before the build markers and before the loose-file fallback. Every directory below it then resolves to the same root, so the same jdt.ls and the same workspace serve the whole tree (jdt.ls treats the root as an invisible project that includes its subdirectories).
   - Nothing else changes: with no `.nv4j`, today's rules apply (build marker, then repo root with a build marker, then the file's own directory).
   - An empty file is enough. The file is also the place for per-project settings later (for example JDK, jdt.ls `-Xmx`, extra source folders, Spring Boot on/off, run profile defaults). The format and the first keys are open: decide when the first setting is needed, not before.
   - It does not depend on any IDE files (`.idea`, `.iml`), which the developer does not want to keep for Neovim.
   - Spring Boot LS, run and debug use the same `root.lua`, so they follow the new root.
2. **Fixed `-Xmx` for jdt.ls as a safety net.** At the limit the JVM does not take more memory: the GC runs almost continuously (completion and diagnostics take seconds), and if it still cannot allocate it throws `OutOfMemoryError` and jdt.ls becomes unusable until `:LspRestart`. Without `-Xmx` the default ceiling is 25% of physical RAM. `-Xms` only sets the initial heap and caps nothing. **The `-Xmx` value (the discussion so far points at 1.5 to 2 GB) and the `-Xms` value must be confirmed with the developer before it is built.**
3. **Visibility of the problem.** Open question for the same confirmation: warn once when a second jdt.ls would start for a loose file (a root without build marker and without `.nv4j`) while another loose-file jdt.ls is running, instead of starting it silently.

### Built (D25)

- `root.lua` `M.project(path)` returns `root, has_marker, kind`. Rule 1 (new): the nearest dir with a `.nv4j` file, kind `"nv4j"`; `has_marker` is true only when that dir also holds a build marker itself (`pom.xml`, `build.gradle*`, ...). Rules 2 and 3 unchanged (kind `"build"` / `"loose"`). So the callers that gate build-tool features on `has_marker` behave as follows: `.nv4j` next to a build file = a normal build project (Spring Boot LS via `spring.boot_root`, `run.lua`'s `outer_root` and its build-tool fallback); `.nv4j` without one = treated like a loose root (no Spring Boot LS, no `mvn`/`gradle` run, `scaffold.lua` creates files in the default package, as jdt.ls's invisible project expects: measured, `A` in `alpha/` resolves `B` in `beta/` with no package line). jdt.ls (`java.lua` `root_dir`), the Spring Boot LS, run, debug and tests use the root through `M.project` or `client_for_path`, so they all follow the `.nv4j` root. `usage.lua` counts a `.nv4j` root (the user marked it as a project; the loose-file skip was only to keep `rg` out of `$HOME`).
- Warning: `root.lua` `M.warn_loose(root)`, called from `java.lua`'s `opts.jdtls` (once per Java buffer attach, before `start_or_attach`, not per keystroke). WARN, title `Nv4J`, once per root, when the root is loose and no client has it yet while a client for another loose root runs: names both roots, their common parent and says to create an empty `.nv4j` there and restart. It never blocks or changes the start. Measured: `opts.jdtls` runs 4 times for the second root before its client registers (negative control n64c), so the once-per-root guard is needed.
- Broad dirs (fix round 1): the warning names no folder ("the project folder that holds both") when the common parent is `/`, `$HOME`, an ancestor of `$HOME` or has fewer than 3 path segments (`M.too_broad`); a `.nv4j` at `$HOME` or above is honoured as the root but warned once per dir (`M.project`), and `usage.lua` never scans with rg for it (`M.home_or_above`). Cases `warn_broad`, `project_home_warn`, `usage_home` ($HOME stubbed under the temp dir); negative control n64d (the three guards removed) -> all three FAIL, log `/tmp/nv4j/logs/test-20261027-093842.log`.
- No `-Xmx`/`-Xms` change: the launcher's `-Xms1G` stays, no ceiling set by Nv4J.

| Metric | Budget | Result | Check |
|--------|--------|--------|-------|
| jdt.ls clients for files in 3 sibling dirs under one `.nv4j` | 1 (max jdt.ls processes per `.nv4j` project) | 1, one `-data` workspace | `64_project_marker` `single_client`, `one_workspace` |
| RSS of that single jdt.ls (3 small files, JDK 25 server) | <= 2 GB PROPOSED (from the measurement, about 1.6x), not applied: `rss` is report-only (PASS with the MB; FAIL only if the process or its RSS cannot be read) | 1257 to 1294 MB (5 runs) | `64_project_marker` `rss` |
| Warning for a second loose-file jdt.ls | exactly once per root, start not blocked | 1 warning, 2 clients | `64_project_marker` `warn`, `warn_unit` |

Negative controls (product or check patched for one run, reverted): n64a no `.nv4j` in the check's project -> `single_client` FAIL (3 clients at `alpha`, `beta`, `gamma`, `B cannot be resolved to a type`) and `one_workspace` FAIL (3 workspaces), log `/tmp/nv4j/logs/test-20261027-092744.log`; n64b `warn_loose` call removed from `java.lua` -> `warn` FAIL (0 warnings), log `/tmp/nv4j/logs/test-20261027-092901.log`; n64c once-only guard removed -> `warn_unit` FAIL (2 notifications) and `warn` FAIL (4 warnings for one start), log `/tmp/nv4j/logs/test-20261027-092940.log`. `warn_unit` (stub clients) is the deterministic twin of `warn`.

Fix wave (2026-10-29, final review S-I2): `rss` became report-only per the user's ruling (the 2 GB stays proposed). Controls: n64c (`rss_kb(nil)`: the process RSS cannot be read) -> `rss` FAIL, log `/tmp/nv4j/logs/test-20261029-095537.log`; n64d (proposed figure set to 1 MB, i.e. the measured 1.3 GB is far over) -> `rss` still PASS ("OVER" in the detail), `DONE 64_project_marker 17 0`, log `/tmp/nv4j/logs/test-20261029-095616.log`.

### Alternatives considered

| Option | Why not (for now) |
|---|---|
| `.idea` / `.iml` as root marker | The developer does not use them with Neovim and removed them. |
| The repo's `.git` as root for loose files | Rejected before (see Cause 1); an unrelated repo such as a notes repo would become the root again. |
| Base directories listed in the Neovim config | Works, but it is a second place to maintain; `.nv4j` travels with the project. |
| One jdt.ls with several workspace folders | jdt.ls handles invisible projects outside its first root poorly; needs its own trial before it is trusted. |
| Lower `-Xms` / `-Xmx` only | Does not remove the duplication (one JVM per directory). It only shrinks each one. |

### To do when built

Done (see "Built (D25)"): marker lookup with a unit check of the order, the single-client check with workspace and RSS, budget rows (RSS budget proposed from the measurement), negative controls, README (How to use, Testing, Troubleshooting, Known limitations). First settings keys: D27 (`run.profile` / `run.env` / `run.vm_args`). Still open: a `.nv4j` above several Maven projects (not checked), whether to cap the number of loose-file jdt.ls processes instead of only warning.

## Open items

Carried to P3 or later (each also in README Not yet or Known limitations):

- D25 (`.nv4j` project marker): built with the warning, no `-Xmx` (developer's decision). First settings keys: D27. Open: the 2 GB RSS figure (proposed, report-only, not applied), a `.nv4j` above several Maven projects. Details in "Problem: one jdt.ls per loose-file directory".

- Async import apply on accept (removes the up to 0.8 s wait), and project ranking weighted above blink's frecency (P1 follow-ups): built in P3 Task 1 (D24, `63_async_import`).
- Saved run configurations (profile, env, VM args per project): built as D27 (`66_settings`); `<leader>rp` still asks for this run only and does not write the file.
- The real `mvn spring-boot:run` / `gradle bootRun` path and the kill of Maven's forked JVM are not run by the checks (company mirror unreachable here): run once on a machine with the plugin in `~/.m2`.
- JUnit debug depends on the engine-matching `junit-platform-launcher` jar in `~/.m2`; why jdt.ls adds its bundled launcher only in some sessions is unknown. Gradle projects are not handled. The warning's `mvn dependency:get` fails through an unreachable company mirror; the fix is a `junit-platform-launcher` test dependency (README Known limitations).
- `vscode-spring-boot-tools` (about 90 MB) is installed by Mason's `ensure_installed` for every user unless `vim.g.nv4j_spring = false` before the first start; offline or behind a proxy Mason shows its install error at start. `tests/run.sh` then WARNs and SKIPs checks 50, 51, 52 instead of stopping (P1 checks still run).
- The build-tool run path needs the sibling modules installed for Maven multi-module projects (`spring-boot:run` runs in the Boot module only).
- `nvim/lua/nv4j/debug.lua` wraps nvim-jdtls/nvim-dap internals at runtime (`client.request`, `jdtls.start_or_attach`, `dap.adapters.java`); re-run `40_debug` after any update of those plugins, and drop a wrap when upstream fixes the race.
- Spring Boot LS: with two Spring Boot projects open the plugin's jdt.ls forwarders use the first `jdtls` client (untested); Boot detection misses Boot brought only by a parent pom outside the repo and modules deeper than 2 levels; the first yml hover of some keys (`server.port`) takes up to about 0.5 s once; the `@Value` project-key tiers use a fixed Boot namespace list; `project_keys` has no size cap (fine for normal config files).
- Spring server diagnostics (unknown keys, bad values) and annotation attribute checks beyond jdt.ls are not covered by checks.
- Gradle (P4) is untested end to end.
- jdt.ls logs "Failed to save JDT index" at every headless shutdown (index rebuilt next session); not investigated.
