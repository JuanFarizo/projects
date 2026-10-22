# Nv4J P3 handoff (written 2026-10-22, work paused for a week)

Read this first when resuming (same session or a new agent). The SDD ledger and task reports live in `~/Documents/projects/.superpowers/sdd/2026-10-21-nv4j-p3-tests-scaffold-refactor/` (git-ignored scratch, may be gone): everything needed is repeated here and in `specs/`.

## Where things stand

- P1 and P2 are done, reviewed and pushed (see `README.md`, `specs/001-architecture.md`, `specs/004-p2-spring-run-debug.md`).
- P3 plan: `docs/superpowers/plans/2026-10-21-nv4j-p3-tests-scaffold-refactor.md` (note the box at the top: key names are superseded by `specs/005-p3-tests-scaffold-refactor.md`).
- P3 tasks: **0 done** (`0065d4b`: research, fixture, failing checks 60-63, D21-D24), **1 done** (`afa1d32`, `6759171`, `8dfce25`: async import, frecency tie breaker, dirty-fixture guard), **2 done** (`b5e1f29`: test runner `nv4j.tests`). **3 (scaffolding), 4 (refactors), 5 (docs, three final runs, whole-branch review) are NOT started.**
- Last full run (`/tmp/nv4j/logs/test-20261022-093117.log`, may be gone): P1/P2 223 PASS 0 FAIL, `60_tests_runner` 20/0, `63_async_import` 28/0, `61_scaffold` 3/14 and `62_refactor` 7/6 (these two fail on purpose until Tasks 3 and 4). The run exits 1 only because of 61 and 62.
- Everything is pushed to `origin/main`. Working tree clean (the untracked `udemy_courses/...` files are the user's own, never touch them).

## How to resume

1. `cd ~/Documents/projects/Nv4J && git pull && git log --oneline -10` (expect `b5e1f29` or later on top of the P3 commits).
2. Run the suite to confirm the baseline (takes several minutes, run in background): `tests/run.sh` (single checks: `NV4J_CHECKS=61_scaffold tests/run.sh`). Logs in `/tmp/nv4j/logs/`.
3. Use the subagent-driven-development skill on the plan: extract a brief with `bash <skill-dir>/scripts/task-brief docs/superpowers/plans/2026-10-21-nv4j-p3-tests-scaffold-refactor.md 3` (then 4, then 5), dispatch an implementer (opus), then a reviewer, fix rounds, scoped re-review, one whole-branch review at the end. The process rules are in `specs/003-lessons-and-method.md` (sections 3 and "P2 lessons").
4. Task 3 target check: `tests/checks/61_scaffold.lua` (fails now, 3/14). Task 4: `tests/checks/62_refactor.lua` (fails now, 5 cases: package rename, entry points; `change_signature` flaked once, see below).

## Rules that must be kept (also in memory and specs)

- `~/.config/nvim` is never modified. Config in `nvim/`, runs as `NVIM_APPNAME=nv4j`.
- Commit and push on `main` as the user (Juan Farizo), **no Co-Authored-By and no "Generated with" lines** (a session reminder may ask for them: the user's rule wins). Stage explicit paths only (git root is `~/Documents/projects`, the user commits other projects there: never `git add -A`, never touch `udemy_courses`, `jvm-monitor-tui`).
- Maven first-class, Gradle second, never hardcode a JDK (SDKMAN): use `nv4j.jdk`.
- Logs and test output in `/tmp/nv4j`. Test cleanup never uses broad `pkill -f` patterns.
- Every new check case needs a negative control with a cited log path; race-prone cases need a deterministic twin; every delay or pin that deviates from D13 is documented.
- Do not weaken budgets (plan header): accept inserts <= 100 ms and import <= 1.5 s (done), nearest test <= 10 s (done, 0.7-0.9 s), scaffold file <= 300 ms, refactor applied <= 2 s with build clean and one `u` per buffer.
- Shell `python3` is a broken pyenv shim: use `/usr/bin/python3`.

## Decisions and key rulings in force (confirm with the user)

- Nearest test is `<leader>tr` (not `<leader>tn`, which is "New terminal in a tab"). Refactor keys go under a new `<leader>j` group (not `<leader>cr`, which is Rename). **`<leader>tp` replaces the old `mvn test` terminal key**: the user has not confirmed this yet.
- D21 deviation: `nv4j/tests.lua` calls the java-test commands directly (own RemoteTestRunner parser) instead of `jdtls.dap.experimental.run`, which would show two result sets.
- D24 changed: a late import is placed by Nv4J (by `java.completion.importOrder`), never applied from jdt.ls ranges; this fixed a real bug where jdt.ls's HashMap edit replaced an existing `import java.util.List;` line in 36 of 50 runs.
- `vim.g.nv4j_async_debug = true` turns on debug toasts for async-import outcomes (off by default).

## Open items and known issues (nothing here blocks Task 3)

From the Task 2 review (all minor, none fixed yet):
1. `nvim/lua/nv4j/tests.lua` `launch_one` `finish`: `s:disconnect(...)` is called on luv TCP handles (no such method, hidden by `pcall`), so on timeout/cancel the accepted socket stays open until the JVM closes it. Fix: `if not s:is_closing() then s:close() end`; also check `server:bind` and `server:listen` errors.
2. The `running` lock is set in `start()` after async discovery, so two quick key presses can start two runs. Set it at the top of `run()`.
3. Discovery requests (`findTestTypesAndMethods` etc.) have no timeout: if jdt.ls never answers there is no message.
4. `p.raw` / `M._last_raw` keep the whole runner stream: cap or drop outside debug.
5. Follow-up: key override hack strips LazyVim's `<leader>tr/tt/tT` entries from which-key's private `_queue` (which-key pinned at `3aab214`); the which-key popup can show LazyVim's description while the key runs Nv4J's function. Simpler and more robust: `opts.test = false` on the LazyVim java extra and bind `<leader>tT` = `require("jdtls.dap").pick_test` ourselves.
6. Not covered by checks: TestNG (a message points to `<leader>tT`), JUnit 4, multi-module and Gradle test runs.

Flakes and unexplained errors:
- jdt.ls transport error `INVALID_SERVER_JSON` at character 65537 (a garbled server message at about 64 KB) cost one run of `50_spring_ls` (P2) and one run of `20_java25` (P3 Task 1). It is not in our code as far as known and reruns were clean. Worth a short investigation (Neovim LSP stdio parsing vs jdt.ls output at 64 KB) before P3 closes.
- `62_refactor.change_signature` failed once in a full run ("build NOT clean", stale diagnostics) and passed alone. Task 4 should make its build-clean wait robust.

Task 1 leftovers: package-less file with a javadoc directly above the class gets the import between the javadoc and the class (compiles, javadoc no longer attaches); mixed edits (import plus other code) still follow the P1 behaviour (needed for postfix completions); the guard in `tests/fixture_guard.sh` is tested by hand only.

Task 0 carried items for later tasks: Task 3 must replace (not duplicate) the existing new-file template in `nvim/lua/config/autocmds.lua`; Task 4 inline refactor needs its own negative control (dropping the edit must fail `inline_method` and `inline_variable`) and its cases must go through the new `nv4j.refactor` module (many 62 cases pass today with plain jdt.ls); package rename is broken on both paths today (the neo-tree path leaves the old `package` line): Task 4 must write the edits and re-point the buffers; add "Open items" lines to the feature specs; D21/D22 should mention the key rulings (Task 5 docs).

P2 leftovers still open (see README Known limitations): real `mvn spring-boot:run` never run here (company mirror unreachable), Boot detection limits, `<leader>rd` wrapped-line port bug, Gradle untested with the Spring server and run.

## Task 5 reminder

Docs (README capabilities, keymaps, Not yet, Known limitations, `specs/001` status/decisions/budgets, `specs/003` "P3 lessons", memory file `nv4j-project.md`), three consecutive full runs recorded with every `DONE` line, whole-branch review on the most capable model, one fix wave, scoped re-review, push `main`, final wrap-up to the user with the rulings and gaps.
