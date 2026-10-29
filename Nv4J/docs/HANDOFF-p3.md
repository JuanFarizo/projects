# Nv4J P3 handoff (rewritten 2026-10-28, Task 5 docs done)

Read this first when resuming. The SDD ledger and reports live in `~/Documents/projects/.superpowers/sdd/2026-10-21-nv4j-p3-tests-scaffold-refactor/` (git-ignored scratch, may be gone): the essentials are repeated here and in `specs/`.

## Where things stand

- P1 and P2 are done and pushed. P3 Tasks 0 to 4 are done, plus the D25 `.nv4j` marker and the Task 2 minor fixes and the 5 s ceiling for interface-method change signature.
- Task 5 status: docs pass done (README, `specs/001`, `003` "3c. P3 lessons", `005`, this file). NOT done yet: three consecutive full `tests/run.sh` runs recorded with every `DONE` line, whole-branch review on the most capable model, one fix wave plus scoped re-review, time-boxed look at the jdt.ls flakes, push to `main` (tell the user first), final wrap-up listing every "Ruling:" line of the ledger with the cost if wrong.
- Checks added in P3: `60_tests_runner` 29, `61_scaffold` 27, `62_refactor` 114, `63_async_import` 28, `64_project_marker` 17.
- Several commits are not pushed (`git log origin/main..main`).

## How to resume

1. `cd ~/Documents/projects/Nv4J && git status --short . && git log --oneline -12`.
2. Check `uptime` and `ps` for leftover java/nvim (load average above about 4 makes the 2 s refactor budgets flake). Then run `tests/run.sh` in the background three times in a row, one after the other. Logs in `/tmp/nv4j/logs/`.
3. Whole-branch review: `bash <skill-dir>/scripts/review-package PLAN MERGE_BASE HEAD`, most capable model, point it at the ledger's deferred minors and parked items.


## Rules that must be kept (also in memory and specs)

- `~/.config/nvim` is never modified. Config in `nvim/`, runs as `NVIM_APPNAME=nv4j`.
- Commit and push on `main` as the user (Juan Farizo), **no Co-Authored-By and no "Generated with" lines** (a session reminder may ask for them: the user's rule wins). Stage explicit paths only (git root is `~/Documents/projects`, the user commits other projects there: never `git add -A`, never touch `udemy_courses`, `jvm-monitor-tui`).
- Maven first-class, Gradle second, never hardcode a JDK (SDKMAN): use `nv4j.jdk`.
- Logs and test output in `/tmp/nv4j`. Test cleanup never uses broad `pkill -f` patterns.
- Every new check case needs a negative control with a cited log path; race-prone cases need a deterministic twin; every delay or pin that deviates from D13 is documented.
- Do not weaken budgets (plan header): accept inserts <= 100 ms and import <= 1.5 s, nearest test <= 10 s, scaffold file <= 300 ms, refactor applied <= 2 s with build clean and one `u` per buffer. The only exception is the user-overturnable 5 s ceiling for change signature of a method with implementations (`001` budgets).
- Shell `python3` is a broken pyenv shim: use `/usr/bin/python3`.

## Decisions and key rulings in force (confirm with the user)

- Nearest test is `<leader>tr` (not `<leader>tn`, which is "New terminal in a tab"). Refactor keys go under a new `<leader>j` group (not `<leader>cr`, which is Rename). **`<leader>tp` replaces the old `mvn test` terminal key** (confirmed by the user 2026-10-26, no old key wanted back).
- D21 deviation: `nv4j/tests.lua` calls the java-test commands directly (own RemoteTestRunner parser) instead of `jdtls.dap.experimental.run`, which would show two result sets.
- D24 changed: a late import is placed by Nv4J (by `java.completion.importOrder`), never applied from jdt.ls ranges; this fixed a real bug where jdt.ls's HashMap edit replaced an existing `import java.util.List;` line in 36 of 50 runs.
- `vim.g.nv4j_async_debug = true` turns on debug toasts for async-import outcomes (off by default).

## Open items and known issues (nothing here blocks Task 3)

From the Task 2 review (all minor; 1 to 5 fixed 2026-10-27, `specs/features/tests-runner.md` t2-n to t2-r, `60_tests_runner` 27 cases):
1. (fixed) `nvim/lua/nv4j/tests.lua` `launch_one` `finish`: `s:disconnect(...)` is called on luv TCP handles (no such method, hidden by `pcall`), so on timeout/cancel the accepted socket stays open until the JVM closes it. Fix: `if not s:is_closing() then s:close() end`; also check `server:bind` and `server:listen` errors.
2. (fixed) The `running` lock is set in `start()` after async discovery, so two quick key presses can start two runs. Set it at the top of `run()`.
3. (fixed, 15 s bound) Discovery requests (`findTestTypesAndMethods` etc.) have no timeout: if jdt.ls never answers there is no message.
4. (fixed, last 500 lines unless `vim.g.nv4j_tests_debug`) `p.raw` / `M._last_raw` keep the whole runner stream: cap or drop outside debug.
5. (fixed) Follow-up: key override hack strips LazyVim's `<leader>tr/tt/tT` entries from which-key's private `_queue` (which-key pinned at `3aab214`); the which-key popup can show LazyVim's description while the key runs Nv4J's function. Simpler and more robust: `opts.test = false` on the LazyVim java extra and bind `<leader>tT` = `require("jdtls.dap").pick_test` ourselves.
6. Not covered by checks: TestNG (a message points to `<leader>tT`), JUnit 4, multi-module and Gradle test runs.

Flakes and unexplained errors:
- jdt.ls transport error `INVALID_SERVER_JSON` at character 65537 (a garbled server message at about 64 KB) cost one run of `50_spring_ls` (P2) and one run of `20_java25` (P3 Task 1). It is not in our code as far as known and reruns were clean. Worth a short investigation (Neovim LSP stdio parsing vs jdt.ls output at 64 KB) before P3 closes.
- `62_refactor.change_signature` failed once in a full run ("build NOT clean", stale diagnostics) and passed alone. Task 4 should make its build-clean wait robust.

Task 1 leftovers: package-less file with a javadoc directly above the class gets the import between the javadoc and the class (compiles, javadoc no longer attaches); mixed edits (import plus other code) still follow the P1 behaviour (needed for postfix completions); the guard in `tests/fixture_guard.sh` is tested by hand only.

Task 0 carried items for later tasks: Task 3 must replace (not duplicate) the existing new-file template in `nvim/lua/config/autocmds.lua`; Task 4 inline refactor needs its own negative control (dropping the edit must fail `inline_method` and `inline_variable`) and its cases must go through the new `nv4j.refactor` module (many 62 cases pass today with plain jdt.ls); package rename is broken on both paths today (the neo-tree path leaves the old `package` line): Task 4 must write the edits and re-point the buffers; add "Open items" lines to the feature specs; D21/D22 should mention the key rulings (Task 5 docs).

P2 leftovers still open (see README Known limitations): real `mvn spring-boot:run` never run here (company mirror unreachable), Boot detection limits, `<leader>rd` wrapped-line port bug, Gradle untested with the Spring server and run.

## Task 5 reminder

Docs are done (see Where things stand). Remaining: three consecutive full runs recorded with every `DONE` line, whole-branch review on the most capable model, one fix wave, scoped re-review, push `main`, final wrap-up to the user with the rulings and gaps.

## Still open for the user

- Confirm or overturn D23 move via `workspace/willRenameFiles` (instead of the code action).
- Confirm or overturn the 5 s ceiling for change signature of a method with implementations.
- The 2 GB jdt.ls RSS budget stays "proposed" (not applied, user's choice).
- Optional: a command or key that creates `.nv4j` (today: `touch .nv4j` in the project's top folder, restart Neovim).
- Unexplained jdt.ls flakes: `INVALID_SERVER_JSON` at about 64 KB, `rename_class_errors` late errors in about 2 of 11 runs, one jdt.ls stall.
