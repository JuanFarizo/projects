# Nv4J P3 handoff (rewritten 2026-10-28, Task 5 docs done)

Read this first when resuming. The SDD ledger and reports live in `~/Documents/projects/.superpowers/sdd/2026-10-21-nv4j-p3-tests-scaffold-refactor/` (git-ignored scratch, may be gone): the essentials are repeated here and in `specs/`.

## Where things stand

- P1 and P2 are done and pushed. P3 Tasks 0 to 4 are done, plus the D25 `.nv4j` marker and the Task 2 minor fixes and the 5 s ceiling for interface-method change signature.
- Task 5 status: docs pass done (README, `specs/001`, `003` "3c. P3 lessons", `005`, this file). NOT done yet: three consecutive full `tests/run.sh` runs recorded with every `DONE` line, whole-branch review on the most capable model, one fix wave plus scoped re-review, time-boxed look at the jdt.ls flakes, push to `main` (tell the user first), final wrap-up listing every "Ruling:" line of the ledger with the cost if wrong.
- Checks added in P3: `60_tests_runner` 34 (29 until 2026-11-03), `61_scaffold` 27, `62_refactor` 118 (116 on a case-sensitive file system: two cases SKIP), `63_async_import` 28, `64_project_marker` 25, `65_dotfiles_merge` 10 (D26 dotfiles merge, outside the P3 plan).
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
- D26 (user rulings, `specs/001`): `<C-/>` is the terminal toggle (LazyVim) and `<C-j>` is window navigation again (no Nv4J terminal key on it); comment is `<D-/>` (n, x, i), `gcc` / `gc` stay, `<C-/>` / `<C-_>` no longer comment; AI agents under `<leader>a` (Claude `ac`, Cursor `ak`; Claude panel restored per folder); hlchunk indent guides with `<leader>uI` and snacks indent/scope disabled; Markdown (render-markdown, `<leader>cp`, `<leader>um`), Prettier extra, `mini.align`, ts-autotag for html/xml. `<leader>co`, `<leader>cO`, `<leader>tp` stay Nv4J's. Not ported: smear-cursor, mini.animate, image, lint, typescript/vtsls.
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
- A. `INVALID_SERVER_JSON` (investigated 2026-11-02, cause narrowed, not proven, not fixed). `/tmp/nv4j/logs/lsp.log` has 3 hits (2026-10-21 16:34, 22:33, 2026-10-27 16:06), each within 2 s of a jdt.ls start with the Spring LS: error at character 65512 / 65537 of one server message (a first read chunk is 64 KiB, header about 24 bytes), then `Content-Length not found in header: ...` with the rest of the same message, which is jdt.ls's `sts.java.classpath` data (`"kind":"binary","path":".../.m2/...jar","sourceContainerUrl"...`, over 64 KB with a Spring project), then jdt.ls logs `Bad file descriptor` reading stdin (a consequence: Neovim drops the client). The message is the server's, not built by Nv4J code. Neovim 0.12.4's parser (`vim/lsp/rpc.lua`, `request_parser_loop`) is cleared: 3000 random chunkings of 1 to 4 messages of 50 to 140 KB fed to `vim.lsp.rpc.create_read_loop` (chunks of exactly 65536 included) gave 0 bad, and a real pipe test (300 messages of 60 to 300 KB from a child process, stderr mixed in) gave 0 errors. The jdtls wrapper does `os.execvp`, so stdout is jdt.ls's own. Rate: 3 hits in about 3270 LSP sessions in that log. Best remaining hypothesis (untested): two writers in jdt.ls on the same stdout, or Neovim being busy at startup while a message larger than the 64 KiB pipe is written, interleaving a second message into the first. Capture added 2026-11-02: `vim.g.nv4j_lsp_capture = true` (or env `NV4J_LSP_CAPTURE=1`) writes the last 128 KB of raw stdout to `/tmp/nv4j/logs/lsp-capture-<client>-<time>.bin` when `on_error` fires with INVALID_SERVER_JSON or the server exits abnormally (`nvim/lua/nv4j/lspcapture.lua`); turn it on and wait for the next hit. A rerun is clean; the hit rate is about 0.1% of starts.
- B. `rename_class_errors` (investigated 2026-11-02). Two things. (1) Deterministic cold case: with a syntax error in Checkout, the FIRST rename of Invoice in a fresh jdt.ls session is refused by jdt.ls itself (`'.../Checkout.java' has syntax errors. Content of that file will not be updated.`, shown by the product as "jdt.ls refused ... nothing changed"); after a real earlier rename of Invoice in the same session (`rename_class_unsaved`) jdt.ls applies the edit and only skips Checkout. Reproduced in 9 of 10 scratch runs (the very first one applied; `/tmp/nv4j/logs/test-20261102-125329.log`, `-125533.log` single case `NV4J_CASE='^rename_class_errors$'`); a prior rename of another class (`rename_class_boot`, `-125627.log`), references, prepareRename or an unplanted dry-run rename did NOT warm it. The refusal is honest (nothing changed) so it was left as is; the check needs its group (`'^rename_class_[ue]'`). (2) The flake itself (`follow-up: nil`, 2 of 20 logs from 10-29 on, 1 of 4 in a fresh group run): after the rename jdt.ls did not republish Checkout, the dependent it skipped, so the follow-up saw no new error (the twin showed only the old lines 9 and 13). FIXED: `rename_class` now sends `java/validateDocument` for every open Java file of the jdt.ls (as change signature already did for the touched files), new case `62_refactor.rename_class_revalidates` (deterministic: records the notifications). Negative control: without the change it FAILs `validateDocument sent for the untouched GreetingController false, Checkout false, PriceCalculator false (0 sent)` (`/tmp/nv4j/logs/test-20261102-130105.log`); with it PASS (`-130047.log`); `rename_class_errors` follow-up present in 3 of 3 group runs after the fix (`-130159.log`, `-130214.log`, `-130228.log`, load up to 9). The flake rate is too low to prove the cure statistically. (3) FIXED (cold first rename without any syntax error: the full run `/tmp/nv4j/logs/test-20261102-130250.log` left PriceCalculator and both test classes on `Invoice` under a success message): `rename_class` now compares the files of the edit with `textDocument/references` of the old declaration (same helpers as change signature's `untouched_refs`), sends the rename once more when files are missing, and if still missing applies what jdt.ls gave with a WARN listing the files. Cases `rename_class_cold_retry`, `_cold_warn`, `_cold_warm_once` with controls (see `specs/features/refactors.md`, Rename class). Warm cost: one references request, 55 to 80 ms. Follow-up (renamecold fix): the references check is async; an error/timeout of it is "unknown" (retry once, then apply with a WARN "could not verify that all usages were renamed"), each request has its own `rename_ms` bound, the WARN lists at most 10 entries then "... and N more"; cases `rename_class_refs_*` (see `specs/features/refactors.md`).
- C. jdt.ls stall (not found). The stalled run (`-120005.log`, 2026-10-27, `willRenameFiles` timeout 3 s, a rename 19.7 s) is gone: the oldest log in `/tmp/nv4j/logs` is 2026-10-29. Evidence left: the 10-27 trials ran at load average 11 to 15 (specs/features/refactors.md), the three full runs of 2026-11-02 started at load 4.9, 49 and 7.2, and a separate long-lived jdt.ls (pid 27934, 25.0.4-amzn, over an hour) was running next to the tests. In the logs since 10-29 no PASS/FAIL line shows an "after N ms" of 10 s or more except the two-Boot case under construction (60 s, fixed since). Most likely CPU starvation (the product bounds the wait: `rename_ms` 10 s, refactor request limits). Added one log line before every check in `tests/run.sh` (`load: ..., java processes: N`) so the next stall can be matched to the machine load. Nothing else changed.
- `62_refactor.change_signature` failed once in a full run ("build NOT clean", stale diagnostics) and passed alone. Task 4 should make its build-clean wait robust.

Task 1 leftovers: package-less file with a javadoc directly above the class gets the import between the javadoc and the class (compiles, javadoc no longer attaches); mixed edits (import plus other code) still follow the P1 behaviour (needed for postfix completions); the guard in `tests/fixture_guard.sh` is tested by hand only.

Task 0 carried items for later tasks: Task 3 must replace (not duplicate) the existing new-file template in `nvim/lua/config/autocmds.lua`; Task 4 inline refactor needs its own negative control (dropping the edit must fail `inline_method` and `inline_variable`) and its cases must go through the new `nv4j.refactor` module (many 62 cases pass today with plain jdt.ls); package rename is broken on both paths today (the neo-tree path leaves the old `package` line): Task 4 must write the edits and re-point the buffers; add "Open items" lines to the feature specs; D21/D22 should mention the key rulings (Task 5 docs).

P2 leftovers still open (see README Known limitations): real `mvn spring-boot:run` never run here (company mirror unreachable), Boot detection limits, `<leader>rd` wrapped-line port bug, Gradle untested with the Spring server and run.

## Task 5 reminder

Docs are done (see Where things stand). Remaining: three consecutive full runs recorded with every `DONE` line, whole-branch review on the most capable model, one fix wave, scoped re-review, push `main`, final wrap-up to the user with the rulings and gaps.

## Still open for the user

- Confirm or overturn D23 move via `workspace/willRenameFiles` (instead of the code action).
- Confirm or overturn the 5 s ceiling for change signature of a method with implementations.
- Optional: a command or key that creates `.nv4j` (today: `touch .nv4j` in the project's top folder, restart Neovim).
- Unexplained jdt.ls flakes: `INVALID_SERVER_JSON` at about 64 KB, `rename_class_errors` late errors in about 2 of 11 runs, one jdt.ls stall.
