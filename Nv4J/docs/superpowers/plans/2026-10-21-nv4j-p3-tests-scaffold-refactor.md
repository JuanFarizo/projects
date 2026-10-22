# Nv4J P3: Tests, Scaffolding, Refactors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A daily workflow close to IntelliJ for tests (run nearest/class/all/failed with results shown in the editor), scaffolding (new package/class/interface/record/enum, Spring stereotypes, test class for a class) and refactors (rename with file move, move class/package, inline, change signature, safe delete), plus the two P1 follow-ups: asynchronous import apply on completion accept and project ranking weighted above blink's frecency.

**Architecture:** Everything rides on jdt.ls (workspace edits, `willRenameFiles`, refactor code actions and commands) and the java-test bundle already wired in P2. Thin Lua in `nvim/lua/nv4j/` only where a workflow is missing: test results view, scaffold prompts, refactor entry keys. Each feature is proven by a headless check with a numeric budget against the Spring Boot fixture, using the P1/P2 harness.

**Tech Stack:** Neovim 0.12, nvim-jdtls, jdt.ls 1.62, java-test bundle, nvim-dap, blink.cmp, neo-tree, Telescope, Maven, Corretto 25, Lua, sh.

**Spec:** `specs/001-architecture.md` (decisions, budgets), `specs/003-lessons-and-method.md` (method rules, P2 lessons). This plan adds decisions D21+ to 001 and a P3 spec `specs/005-p3-tests-scaffold-refactor.md`.

> **Superseded by Task 0 rulings (`specs/005-p3-tests-scaffold-refactor.md`, D21-D24):** nearest test stays `<leader>tr` (not `<leader>tn`); refactor keys live under `<leader>j` (not `<leader>cr`); `<leader>tp` replaces the old `mvn test` terminal key. Where a task below names other keys, use 005.

## Global Constraints

- `~/.config/nvim` is never modified. Config lives in `Nv4J/nvim/`, run as `NVIM_APPNAME=nv4j`.
- Maven first-class, Gradle second. Nothing hardcoded to one JDK (SDKMAN): use `nv4j.jdk`.
- Logs and test output under `/tmp/nv4j/`. Persistent caches under `~/.cache/nv4j/`.
- Git: commit and push on `main` as the user, no Co-Authored-By or "Generated with" line. Stage explicit paths only (git root is `~/Documents/projects`, the user commits other projects there in parallel: never touch them). Check `git status` before and after each agent. Test cleanup never uses broad `pkill -f` patterns (unique anchored markers only).
- No regression: `tests/run.sh` stays at 0 FAIL, all P1/P2 checks pass (223 PASS at the end of P2: P1 135, 40=16, 41=27, 50=13, 51=20, 52=12) and P1/P2 budgets hold (completion warm p95 <= 150 ms, cold first <= 400 ms, diagnostics <= 3 s, breakpoint hit <= 20 s).
- P3 budgets (set now, do not weaken; measured on the fixture, written into 001 at the end): accept of a completion returns control with the item text inserted <= 100 ms and the import present within 1.5 s of the accept, never lost; run nearest test result visible <= 10 s from key press (warm); scaffold file created, opened, with correct `package` line <= 300 ms; rename/move refactor applied <= 2 s on the fixture with all references and imports correct and the build clean afterwards; every refactor undoable with one `u` per buffer.
- References (read only, `~/.cache/nv4j/`): `intellij-community` (New Java Class action, create test, rename/move/inline/change signature/safe delete refactorings, test runner UI), `eclipse.jdt.ls` (refactor and rename handlers, `willRenameFiles`, test discovery/run commands), `eclipse.jdt.core` (refactoring engine, `org.eclipse.jdt.internal.corext.refactoring`). EPL-2.0: no code copy without header and a note in the feature spec; prefer dependencies.
- Per-feature loop and rules: `specs/003-lessons-and-method.md` section 3 and "P2 lessons". Write the failing check first; every check needs a negative control cited with a log path; a race-prone check needs a deterministic twin; log every trial (also failed) in the feature spec; pins/delays that deviate from D13 are documented as deviations.
- Each task ends with: feature spec updated, README Capabilities/Not yet updated for that feature, `tests/run.sh` full run recorded with its `DONE` lines.

## Review Focus

Failure modes the spec implies but no task's tests would otherwise cover (each gets a test in the owning task):

1. Async import apply when the buffer changed between accept and the late resolve (text typed, cursor moved, buffer closed, undo): the import lands in the right place or not at all, never corrupts text, never duplicates. Owner: Task 1.
2. Rename/move with unsaved buffers and with files outside the project root open: no data loss, no stale buffer pointing at a deleted path. Owner: Task 4.
3. Scaffolding: existing file (no overwrite), invalid names (`1Foo`, spaces, keywords), directory outside `src/*/java` (resources, root), default package, test directory vs main directory. Owner: Task 3.
4. Tests: parameterized, nested and `@Disabled` tests, a test class that does not compile, a project without JUnit: results or a clear message, no hang. Owner: Task 2.
5. Refactors on a project with compile errors elsewhere, and on a Boot project (renaming a `@RestController` class, a bean method, an `@Entity` field used in a JPQL string): the result is reported honestly, partial failures are visible. Owner: Task 4.

---

### Task 0: Research, fixture and failing baselines

**Files:**
- Create: `specs/005-p3-tests-scaffold-refactor.md`, `specs/features/{tests-runner,scaffolding,refactors,async-import}.md`
- Modify: `tests/fixtures/demo/` (more tests: several JUnit 5 classes with passing, failing (kept in a separate class excluded from the normal build or tagged), parameterized, nested and `@Disabled` cases; a multi-package layout that supports move/rename; a method with a changeable signature and call sites; keep it compiling and P1/P2 checks passing)
- Create: `tests/checks/60_tests_runner.lua`, `61_scaffold.lua`, `62_refactor.lua`, `63_async_import.lua` (stubs that FAIL for the right reason now)
- Refresh sparse clones in `~/.cache/nv4j/` as needed, pin commits in the specs

**Interfaces:**
- Consumes: P1/P2 harness (`tests/lib/lsp.lua`, DONE-line contract, negative-control habit).
- Produces: the decisions below filled in, fixture, four failing checks with the budgets from Global Constraints.

- [ ] **Step 1: Baseline the current behaviour** of `<leader>tt/tT/tp`, new-file template, rename, code-action refactors (move, inline, change signature) and the accept-import wait. Record measured numbers and exact failure modes.
- [ ] **Step 2: Research IntelliJ then jdt.ls** for each feature (paths, mechanisms), with commits pinned. Decide D21: test results UI (nvim-jdtls test bundle + quickfix/diagnostics/signs vs a thin view over surefire XML), D22: scaffolding entry (neo-tree add hook vs own command with Telescope/`vim.ui.select`), D23: refactor surface (code actions + `workspace/applyEdit` + `willRenameFiles` vs custom commands), D24: async import mechanism. Smallest approach that meets budgets (ponytail rule); write in 001.
- [ ] **Step 3: Extend the fixture and write the four failing checks**, each printing `DONE <check> <pass> <fail>` and failing for the right reason, with a negative-control plan.
- [ ] **Step 4: Commit** specs, fixture and checks. Full `tests/run.sh`: P1/P2 checks still pass, the four new checks fail with the expected reasons. Record the log path in 005.

### Task 1: Async import apply and ranking weights (P1 follow-ups)

**Files:**
- Modify: `nvim/lua/nv4j/completion.lua`, `nvim/lua/plugins/blink.lua`, possibly `nvim/lua/nv4j/usage.lua`
- Test: `tests/checks/63_async_import.lua` (and `31_imports`, `11_completion_ranking` stay green)

**Interfaces:**
- Consumes: Task 0 decision D24, P1 `resolve_timeout_ms` behaviour, `31_imports`.
- Produces: accept returns immediately, import applied when the late `completionItem/resolve` returns (guarded), project ranking above frecency for Java.

- [ ] **Step 1: Make `63_async_import` pass:** accept `List`/`HashMap` with the doc popup unresolved; control returns <= 100 ms; import present within 1.5 s; second accept immediately after the first works.
- [ ] **Step 2: Review Focus 1.** Buffer edited, cursor moved, buffer closed, undo between accept and resolve: import lands correctly or is dropped; never duplicates, never corrupts. Deterministic tests with a stubbed slow resolve.
- [ ] **Step 3: Frecency vs project ranking:** with a polluted blink frecency database (accept `List` 20 times), `@` still gives `RestController` in the top 5 and `http.` `authorizeHttpRequests` in the top 3, without relying on the harness' `XDG_STATE_HOME` isolation (the check sets its own polluted state). Log trials.
- [ ] **Step 4: P1 regression** (`10_completion_latency`, `11`, `31`), profile, log trials, README, commit.

### Task 2: Test runner (P3)

**Files:**
- Create: `nvim/lua/nv4j/tests.lua`
- Modify: `nvim/lua/config/keymaps.lua`, `nvim/lua/plugins/java.lua` (wire only), `README.md`
- Test: `tests/checks/60_tests_runner.lua`

**Interfaces:**
- Consumes: Task 0 decision D21, P2 debug/launcher code (`nv4j/debug.lua`, JUnit launcher swap), `nv4j.jdk`.
- Produces: `require("nv4j.tests").run({ scope = "nearest"|"class"|"file"|"project"|"failed", debug = boolean })`; keys `<leader>tn` nearest, `<leader>tc` class, `<leader>tf` failed, `<leader>tp` project, `<leader>tl` last, `<leader>to` results panel (names confirmed in Task 0 against existing LazyVim `<leader>t*` keys and written in the spec); results as signs/diagnostics in the file plus a quickfix list with failure messages and stack frames that jump to the line.

- [ ] **Step 1: Failing `60_tests_runner` first:** nearest, class, project and failed-only runs against the fixture; pass/fail counts match the fixture; a failing assertion shows message and jump-to-line; budget: result visible <= 10 s warm.
- [ ] **Step 2: Implement** with the smallest mechanism chosen in D21 (JDT test bundle results or surefire reports). JDK from `nv4j.jdk`; build before run as in P2 (`debug.lua`).
- [ ] **Step 3: Review Focus 4.** Parameterized, nested, `@Disabled`, non-compiling test class, project without JUnit: results or a clear message, no hang.
- [ ] **Step 4: Debug a test** from the same keys (reuses P2 path). Profile, log trials, README, commit.

### Task 3: Scaffolding (P3)

**Files:**
- Create: `nvim/lua/nv4j/scaffold.lua`
- Modify: `nvim/lua/plugins/neo-tree.lua` (hook only if D22 says so), `nvim/lua/config/keymaps.lua`, `nvim/lua/config/autocmds.lua` (existing template logic: replace or reuse, no duplicates), `README.md`
- Test: `tests/checks/61_scaffold.lua`

**Interfaces:**
- Consumes: Task 0 decision D22, `nv4j.root`, existing new-file template code.
- Produces: `require("nv4j.scaffold").new({ kind = "class"|"interface"|"record"|"enum"|"annotation"|"package"|"controller"|"service"|"repository"|"entity"|"test", name = string, dir = string|nil })` and key `<leader>jn` (and neo-tree add hook); package derived from the directory under `src/<set>/java`.

- [ ] **Step 1: Failing `61_scaffold` first:** every kind creates the right file with the right `package` and Spring annotations, opens it, ready for completion; "test" creates the matching test class in `src/test/java` for the current class; budget <= 300 ms.
- [ ] **Step 2: Implement** `scaffold.lua`; `vim.ui.select`/`input` prompts, `Foo.Bar` creates a package path, directory-based package inference, templates close to IntelliJ's (no header comments).
- [ ] **Step 3: Review Focus 3.** Existing file (no overwrite, message), invalid names, directories outside `src/*/java`, default package, main vs test dir. Tests for each.
- [ ] **Step 4: Compiles check.** After scaffolding in the fixture, jdt.ls reports zero errors for each kind within 3 s. Profile, log trials, README, commit.

### Task 4: Refactors (P3)

**Files:**
- Create: `nvim/lua/nv4j/refactor.lua`
- Modify: `nvim/lua/config/keymaps.lua`, `nvim/lua/plugins/java.lua` (capabilities such as `willRenameFiles` if needed), `README.md`
- Test: `tests/checks/62_refactor.lua`

**Interfaces:**
- Consumes: Task 0 decision D23, `nv4j.root`, jdt.ls code actions and commands.
- Produces: `require("nv4j.refactor").{rename_class, move, inline, change_signature, safe_delete}()` and keys under `<leader>cr` (names confirmed in Task 0, no collision with `<leader>co`/`cO`/P2 keys).

- [ ] **Step 1: Failing `62_refactor` first:** rename a class (file renamed, all references and imports updated, build clean), move a class to another package, rename a package, inline a method/variable, change a method signature (parameter added with default at call sites), safe delete (blocked with usages listed, allowed without). Each applied <= 2 s, undo restores each buffer with one `u`.
- [ ] **Step 2: Implement** the smallest wrappers over jdt.ls (and `willRenameFiles` or `workspace/applyEdit`), with a visible summary of touched files. Unsaved buffers are written or edited in place, no data loss.
- [ ] **Step 3: Review Focus 2 and 5.** Unsaved buffers, files outside the root, compile errors elsewhere, Boot cases (controller class rename, bean method, JPQL string field): honest result, partial failures visible.
- [ ] **Step 4: Profile, log trials, README, commit.**

### Task 5: Docs, final run and whole-branch review

**Files:**
- Modify: `README.md` (Capabilities P3, Not yet, keymaps, Known limitations), `specs/001-architecture.md` (status, decisions D21+, budgets table with final results, open items), `specs/003-lessons-and-method.md` ("P3 lessons"), memory file `nv4j-project.md`

- [ ] **Step 1: Full `tests/run.sh` three times;** record every DONE line and numbers in 001 and README rows with check names. A flake is recorded with its log, not hidden.
- [ ] **Step 2: README re-read against the last run and the code:** every number, key and case count matches.
- [ ] **Step 3: Final whole-branch review** on the most capable model, one fix wave, one scoped re-review, push `main`.
