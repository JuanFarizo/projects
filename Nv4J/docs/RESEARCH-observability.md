# Research: observability for Nv4J (2026-11-10)

Status: research and design only. Nothing here is built. Every path and command below was checked by grep or by looking at the file, unless marked UNVERIFIED. Owner's questions: (1) how are logs seen today, (2) how can that improve, (3) can observability be built.

Short answers:
1. Today you have to know the file names. Only three things have a command (`:LspLog`, `:JdtShowLogs`, `:DapShowLog`), and one of them (`:JdtShowLogs`) opens the wrong LSP log. Nothing shows the Spring LS log, the route log, or "which jdt.ls root is this".
2. Move the logs out of `/tmp` into `stdpath("state")`, and add one command that lists them.
3. Yes, a small layer is worth it: one status/health command and one logs picker. A JSONL event log, a statusline component and a bundle command are not worth it yet (see the options table).

## 1. Current state

Log directory: `/tmp/nv4j/logs` (`nvim/lua/nv4j/paths.lua`: `root = "/tmp/nv4j"`, `logs = root .. "/logs"`). The jdt.ls data dir is deliberately NOT in `/tmp`: `~/.cache/nv4j/jdtls-data/<project>-<hash8>` (`paths.lua`, `plugins/java.lua` line 107).

| Source | Writer | Where | Format / rotation / level | How to view today | Gap |
|---|---|---|---|---|---|
| Neovim LSP client log (RPC traffic, `on_error`, `INVALID_SERVER_JSON`, server stderr) | Neovim core `vim.lsp.log`; file name overridden in `nvim/init.lua` with the private `vim.lsp.log._set_filename(paths.lsp_log(...))` | `/tmp/nv4j/logs/lsp-<project>-<pid>.log`; test runner (`NV4J_RUNNER`) uses `lsp.log` | Neovim's own text format. Level: Neovim default (WARN); no Nv4J knob. Rotation: `logrotate.lua` deletes per-session files older than `vim.g.nv4j_log_keep_days` (14); `lsp.log` is renamed to `.1` above `vim.g.nv4j_log_max_mb` (20) | `:LspLog` (defined by nvim-lspconfig, `plugin/lspconfig.lua`: `tabnew <log filename>`; so it follows the override). Docs: GUIDE.md line 105 | One file per nvim PID: finding "yesterday's" means `ls -t` in a directory with 137 files. At WARN level the file is thin; no runtime level switch. `:LspLog` was `exists()=0` in a headless run before plugins loaded (lazy); UNVERIFIED in a UI session |
| jdt.ls own log | Eclipse/jdt.ls | `~/.cache/nv4j/jdtls-data/<project>/.metadata/.log` (example seen: 251 KB, 6 Nov) | Eclipse plain text; no rotation by Nv4J; survives reboot (cache dir) | `:JdtShowLogs` (nvim-jdtls `setup.show_logs`) opens this file in a split | Same command ALSO opens `stdpath("log")/lsp.log` = `~/.local/state/nv4j/lsp.log` in a vsplit. That file is a stale 441-byte file from 4 Nov, because Nv4J redirected the real LSP log. So `:JdtShowLogs` shows one useful and one dead file |
| Spring LS log | spring_boot.nvim `log_file` option, set in `nv4j/spring.lua` line 466 | `/tmp/nv4j/logs/spring-boot-ls.log` | Spring LS own format; level `warn` (hard-coded line 467); `NV4J_SPRING_INDEX_LOG=1` / `vim.g.nv4j_spring_index_log` adds an INFO logger for the indexer only (tests set it). Rotation: renamed to `.1` above 20 MB | No command. `:e /tmp/nv4j/logs/spring-boot-ls.log` | One file shared by every Neovim session (not per project, not per PID): concurrent sessions interleave. No command, no level toggle |
| Spring route log (which jdt.ls an `sts/*` request went to, fallbacks, listener re-registration) | `nv4j/spring.lua` `M.route_log` (line 124) | `/tmp/nv4j/logs/spring-route.log` | `HH:MM:SS message`, no date, no PID, append. Rotation: `.1` above 20 MB | No command | No date and no PID: cannot tell sessions apart or order across midnight. Debug aid for the `two_boot_index` flake |
| Raw LSP stdout capture (flake A) | `nv4j/lspcapture.lua` | `/tmp/nv4j/logs/lsp-capture-<client>-<YYYYmmdd-HHMMSS>[-exit].bin` (two exist, from 6 Nov) | Raw bytes, last 128 KB. OFF unless `vim.g.nv4j_lsp_capture` or `NV4J_LSP_CAPTURE=1`. Deleted after 14 days | A WARN names the path when it fires; no command | OFF in daily use, so the next real INVALID_SERVER_JSON will not be captured unless the owner turns it on (it costs nothing when off, but needs a restart to switch) |
| `latency.jsonl` | NOT product code. Only test helpers: `tests/lib/completion.lua`, `tests/lib/edit.lua` (`LATENCY_LOG`) and checks | `/tmp/nv4j/logs/latency.jsonl` (+ `latency.prev.jsonl`, `mv` by `tests/run.sh` line 25) | `{"count":1,"case":"...","ms":1600.3}` per sample. One run's worth | `cat` | Test timings, not daily-use telemetry. There is NO product startup or import timing anywhere |
| Test run logs | `tests/run.sh` | `/tmp/nv4j/logs/test-*.log` (77 files now), `flake50-run*.log`, `control-*.log` | Plain text. `test-*.log` deleted after 14 days (HANDOFF-p3 line 12 warns old flake evidence is lost) | `less` | Evidence of past flakes is deleted by design; it lives only in docs |
| nvim-dap log | nvim-dap | `~/.local/state/nv4j/dap.log` (1 byte now) | Level controlled by `require("dap").set_log_level(...)` (nvim-dap API, UNVERIFIED in this config; grep found no call) | `:DapShowLog` (nvim-dap `plugin/dap.lua`; also cited in `nv4j/tests.lua` line 461 error text) | Level default is INFO, so adapter traffic is not logged. In state dir: survives reboot |
| Debuggee / app output (run) | `nv4j/run.lua` | Terminal split buffer `nv4j-run://<name>#<id>` (line 348) | Terminal scrollback; not on disk | The split itself; `q` stops AND closes it, so the output is lost | After `q` or a crash-close there is no copy. Not a file |
| Debuggee output (debug) | nvim-dap-ui / dap-repl | dap-repl / console | In memory | Debug UI console | Not persisted |
| Build output (refresh+build before launch) | `nv4j/debug.lua` `M.build` | `vim.notify` only ("Building before ...", "has compile errors", "failed ... see :JdtShowLogs", lines 71, 87, 90) | Notification text | Notification, or `:messages`, or noice history | Problems are found as diagnostics (Trouble, `]d`); build detail is in `.metadata/.log` via `:JdtShowLogs`. Gradle build output of an import failure: in the same `.log` (UNVERIFIED which lines) |
| Test output | `nv4j/tests.lua` | diagnostics + signs + quickfix titled by `QF_TITLE` (line 400) + one notify; `<leader>to` | Quickfix; raw output cut to `raw_max` unless `vim.g.nv4j_tests_debug` (line 160, 599) | `<leader>to` (quickfix, per tests.lua line 405) | Raw runner lines trimmed; the full thing only with `vim.g.nv4j_tests_debug` set before the run |
| Memory warning | `nv4j/memwatch.lua` | `vim.notify` WARN, once per jdt.ls client per session | Timer every `vim.g.nv4j_memwatch_ms` (60 s); threshold `vim.g.nv4j_jdtls_warn_mb` (2048; 0 = off) | Notification only | Reads RSS and then throws it away: you cannot ask "how big is it now". It is an alarm, not a gauge |
| Completion profile | `util/profile.lua` | `~/.local/state/nv4j/completion-profile.jsonl` | JSONL; opt-in `:CompletionProfile on|off|status|clear`, off after every restart | `:CompletionProfile status` (command defined by `util.profile.setup`; was `exists()=0` at headless startup, so it is probably lazily set up: UNVERIFIED when) | The only existing JSONL writer in the product, and the only one with a command. A model for the pattern |
| Notifications / messages | `vim.notify` all over (`run.lua`, `tests.lua`, `debug.lua`, `root.lua`, `memwatch.lua`); noice.nvim | In memory; noice log at `~/.local/state/nv4j/noice.log` | Volatile | `:messages`; noice history via `:Noice` (command was `exists()=0` at headless startup, lazy: UNVERIFIED); snacks has a notifications picker (snacks.nvim installed; not checked whether enabled) | The important WARNs (root refused, loose cap, memory, recover_stream, capture) vanish with the toast |
| Other state logs | mason, nio, nvim | `~/.local/state/nv4j/{mason,nio,nvim}.log` | | `:e` | Not relevant |

Clients attached / roots / JDK: `:LspInfo` is an nvim-lspconfig alias for `:checkhealth vim.lsp` (`plugin/lspconfig.lua` line 18). Neovim 0.12 also has `:lsp` (not checked here). There is no Nv4J view of: jdt.ls root vs. Spring LS projects, JDK per root, `.nv4j` loose/build/nv4j root kind (`root.lua` returns kind `"nv4j"|"build"` but nothing shows it), refused roots, import state, or startup time.

Missing entirely: `nvim/lua/nv4j/health.lua` (no `:checkhealth nv4j`; `ls` finds no `health*` file anywhere in `nvim/lua`), any `Nv4J*` log/status command (the only `Nv4j*` commands are `:Nv4jMark` and `:Nv4jRestoreDeleted`), any statusline use of jdt.ls state (lualine is installed with LazyVim; no Nv4J lualine component), any progress ($/progress) consumer.

### Is /tmp a problem?
Yes, for exactly the owner's use case. macOS empties `/tmp` on reboot (stated in `paths.lua` comment, which also says macOS empties it after 3 days; the 3-day claim is UNVERIFIED by me) so "yesterday's log" is gone after a restart, and `logrotate.lua`'s 14-day keep is meaningless across a reboot. The jdt.ls `.metadata/.log` and `dap.log` do survive. `/tmp/nv4j/logs` also is `/private/tmp`, shared with the test runner, which writes 77 `test-*.log` into the same directory as the daily-use logs (137 files, hard to browse). Moving daily-use logs to `stdpath("state") .. "/logs"` (= `~/.local/state/nv4j/logs`) is cheap, but the tests read `/tmp/nv4j/logs/lsp.log`, `spring-route.log` and `spring-boot-ls.log` by path (`tests/` use `paths.logs`; exact count of hard-coded uses not measured), so the test runner would keep a separate dir (runner already sets `NV4J_RUNNER`).

## 2. What a user types today

| Want to see | Type | Works? |
|---|---|---|
| jdt.ls log | `:JdtShowLogs` (jdt.ls `.metadata/.log` in a split, but plus the dead `~/.local/state/nv4j/lsp.log` in a vsplit) | partly; or `:e ~/.cache/nv4j/jdtls-data/<project>-<hash>/.metadata/.log` (hash not shown anywhere) |
| Neovim's LSP log (RPC, errors) | `:LspLog` | yes (follows the `_set_filename` override) |
| Spring LS log | `:e /tmp/nv4j/logs/spring-boot-ls.log` | no command; level is warn so it is mostly empty |
| Spring routing decisions | `:e /tmp/nv4j/logs/spring-route.log` | no command |
| Debuggee output | run: the `nv4j-run://` terminal split (`q` destroys it); debug: dap-repl / dap-ui console | not persisted |
| Adapter (DAP) log | `:DapShowLog` | file is empty unless `dap.set_log_level` was raised (UNVERIFIED how to raise it here) |
| Build output | notifications, then `:messages`; detail via `:JdtShowLogs`; compile errors as diagnostics | scattered |
| Test output | `<leader>to` (quickfix); full raw only with `vim.g.nv4j_tests_debug` | summarised |
| Why a project failed to import | `:JdtShowLogs`, look for the Maven/Gradle error; the product shows nothing proactively except `BUILD_STATUS` after a launch | manual |
| Which clients are attached | `:LspInfo` (= `:checkhealth vim.lsp`) | yes, but shows no Nv4J root kind and no JDK |
| jdt.ls memory/CPU | nothing on demand (memwatch only warns at 2 GB); outside nvim `ps`/`top` | gap |
| Startup time | `nvim --startuptime`; nothing for "time until jdt.ls ready" in daily use (`vim.g.nv4j_warmup` and `vim.g.nv4j_service_ready_ms` exist, `warmup.lua` lines 54, 76, but nothing shows them: their purpose not read in detail) | gap |

## 3. Pain points and the information that was missing

From `docs/TODO.md` (line 15-17) and `docs/HANDOFF-p3.md` (Flakes A, A.2, B, C, D, D2, D5, E, F, line 50-64):

| Pain | What was missing when diagnosing |
|---|---|
| A / A.2 `INVALID_SERVER_JSON` (about 0.1% of starts; 3 hits + 1) | The raw stdout. The capture exists but is off by default and the hit rate is 1 in ~1000 starts, so it is never on when it happens. `recover_stream` recovers silently (WARN once). A permanent, small, rotating record of "what happened at attach time" is missing |
| C stall / D5 / E (jdt.ls stops answering; slow under load) | The machine load at that moment and jdt.ls state. `tests/run.sh` now logs load, but daily use does not. No jdt.ls CPU/RSS history, no "last request that got no answer". The old log of the C stall was deleted before analysis (`/tmp`, 14-day rule) |
| D `two_boot_index` (1 in 4, then never) | Which classpath events each jdt.ls delivered and when. Added as `_state.events` and test-only EVIDENCE; real sessions have only `spring-route.log` (no date, no PID) and `spring-boot-ls.log` at WARN (nothing about the indexing) |
| Slow starts | No timeline: Neovim start -> jdt.ls spawned -> initialized -> project imported -> Spring LS initialized -> first diagnostics. Every figure in the docs was measured by a test harness, none by the product |
| "Which jdt.ls root is this?" | No command prints root, root kind (`nv4j`/`build`/`loose`), data dir, JDK, PID, RSS per client. The 2 GB WARN says "Several jdt.ls running?" and the user has no way to list them |
| Logs vanish | `/tmp` cleared, test logs deleted at 14 days, run split destroyed with `q`, toasts gone |

## 4. Options

Effort S under half a day, M about a day, L several days. Costs assume the existing pcall-everything style.

| Option | Effort | Value | Risk | YAGNI verdict |
|---|---|---|---|---|
| A. Move daily-use logs to `stdpath("state")/logs` (lsp-<project>-<pid>, spring-route, spring-boot-ls); tests keep `/tmp/nv4j/logs` via `NV4J_RUNNER` | S | high (answers "yesterday's log" and the 137-file mixing) | Tests read the old paths: they must keep using the runner branch. Logrotate must follow. `_set_filename` already private API | DO. Smallest change with the largest effect |
| B. `:Nv4JLogs` snacks picker: lists every log file (and the jdt.ls `.metadata/.log` of each running client) newest first with size and age, `<CR>` opens, a second action tails (`:terminal tail -f`) , live grep over all via snacks grep | S-M | high | Low: read-only. Depends on snacks picker (installed; `source/files.lua`, `grep.lua` exist). Needs a plain `vim.ui.select` fallback | DO (with the Spring and route logs given stable names by A) |
| C. `:Nv4JStatus` / `:checkhealth nv4j` (`lua/nv4j/health.lua`): per jdtls/spring-boot client: id, name, root, root kind, data dir, PID, RSS/CPU (`ps`, async like memwatch), JDK of the root, attached buffers; Spring LS project count; knobs in effect (`vim.g.nv4j_*`, env); log paths with sizes; last N WARN/ERROR notifications | M | high (answers "which jdt.ls root is this", "how big", "is Spring LS up") | Low: read-only, no new state except a small ring buffer of notifications (a few lines wrapping `vim.notify`, which already is wrapped by noice) | DO. `:checkhealth` is the standard Neovim UX and needs no keymap |
| D. Statusline component (lualine): jdt.ls state (starting / importing / indexing / ready), from `$/progress` and `language/status` | M | medium: ends "is it still importing?" guessing | Medium: needs a progress consumer, lualine config; stale states if a client dies; per-buffer vs. per-root wrong answers | NOT YET. Do it only after C exists and the ring buffer proves which state matters |
| E. Structured JSONL event log (`start`, `ready`, `import`, `index`, `refactor`, `test`, `debug`, durations) + a viewer | L | medium-high for flake diagnosis and timeline; low for daily comfort | Medium: new write path in many modules (spring.lua, root.lua, debug.lua, tests.lua, refactor.lua = 3700+ lines), schema drift, performance if on hot paths | NOT YET. Start with ONE writer for lifecycle events (jdt.ls spawn/initialized/exit/`on_error`, Spring listener events) inside the status module; add event kinds only when a flake demands them. Pattern exists: `util/profile.lua` |
| F. Startup / latency timeline | M | medium | Low | Fold into E's lifecycle events (three or four timestamps per client). The `latency.jsonl` file is test-only, do not reuse the name |
| G. Diagnostic bundle (`:Nv4JBundle`: zip logs + versions + `:checkhealth nv4j` text for a bug report) | S-M | low-medium: personal config, one user; useful mostly when preserving flake evidence | Low (copying files). Privacy: logs contain paths/source snippets | LATER. `cp` of a directory does 90% of it once A exists. Cheap variant: `:Nv4JStatus` output saved next to the logs |
| H. Runtime log-level toggle (`:Nv4JLogLevel debug|info|warn`): `vim.lsp.log.set_level`, `dap.set_log_level`, `vim.g.nv4j_lsp_capture` on | S | medium: turns on the flake A capture (0.1%) and DAP traffic without a restart | Low-medium: capture installs at the first Java file (`spring.lua` `start()` calls `lspcapture.install()`; it wraps `vim.lsp.rpc.start`), so toggling after start has no effect. Only the lsp/dap levels can be live | Do the level part as a few lines inside B or C. For flake A, simply set `vim.g.nv4j_lsp_capture = true` permanently in the config: it costs nothing when no error happens (ring of 128 KB per server only) and is the real cure for "never on when it happens". Measure the overhead before (UNVERIFIED claim) |
| I. Keep run output on disk (tee the `nv4j-run://` job output to `logs/run-<name>.log`) | S-M | medium (a crashed app's output survives `q`) | Low-medium | LATER; ask whether it has bitten the owner |

## 5. Recommended first slice (3 items)

### Slice 1: Persistent log directory (option A)
Daily-use logs go to `stdpath("state") .. "/logs"` (`~/.local/state/nv4j/logs`); the test runner (`NV4J_RUNNER` set, as `paths.lsp_log` already branches) keeps `/tmp/nv4j/logs`. `spring-route.log` lines get the date and the PID. Logrotate runs on the new dir.
Test (new check, same style as `73_logrotate`):
- Run: headless `NVIM_APPNAME=nv4j nvim` without `NV4J_RUNNER`, open a Java fixture, wait for jdt.ls.
- Assert: `paths.logs` starts with `stdpath("state")`; `vim.lsp.log.get_filename()` is inside it; the file exists and is non-empty after the attach; a `route_log("x")` line matches `^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d pid=%d+ x$`; with `NV4J_RUNNER=1` the paths are still `/tmp/nv4j/logs/lsp.log` (existing checks unchanged: run the 73 check).
- Negative control: revert the `paths.lua` branch (or set `NV4J_RUNNER` wrongly) and the first assertion must FAIL; a second control: `os.date` format removed, the regex assertion FAILs.

### Slice 2: `:Nv4JLogs` picker (option B)
Lists the files of the log dir plus each running jdtls client's `.metadata/.log` (data dir is known from `paths.jdtls_data` + `project_name`, or from the client's `-data` argument), sorted newest first with size and age; actions: open, tail in a terminal split, live grep over all of them. Fallback to `vim.ui.select` without snacks. Pure function `entries()` returns the list (testable without UI).
Test: headless, create 3 files in a temp log dir (set via the same override the tests use for logrotate: `logrotate.run(dir)` shows the dir is injectable) with distinct mtimes and one `.1` rotated file; call `entries(dir)`. Assert: order newest first, the `.1` file listed, a file older than the keep window not listed if deleted by logrotate, and with a fake jdtls client (stub like `memwatch.check`'s `clients` argument) its `.metadata/.log` is included. Live: open a Java fixture, call `entries()`, assert the real `.metadata/.log` of that jdt.ls is among them and exists. Negative control: point the data dir at a missing folder: the jdt.ls entry must be absent and no error thrown (no entry for a missing file).

### Slice 3: `:checkhealth nv4j` (option C) with the notification ring
`lua/nv4j/health.lua` with `check()`: one section per jdtls / spring-boot client (id, root, root kind, data dir, PID, RSS in MB via async `ps -o rss= -p`, attached buffers), JDK of the root (`nv4j.jdk`), Spring LS project count, knobs in effect, log paths with sizes, last 20 WARN/ERROR `vim.notify` messages from a small ring. `vim.health.warn` when more than one jdt.ls runs (the memwatch hint made visible), when `vim.g.nv4j_lsp_capture` is off, when the log dir is under `/tmp`.
Test: headless, open a Java fixture, wait ready (existing `lsp.wait_ready`), run `vim.cmd("checkhealth nv4j")`, read the buffer. Assert: it contains the jdtls client's root exactly as `client.config.root_dir`, the PID equals the client's job PID (memwatch's cached lookup), RSS is a number > 100, and the log paths listed exist. Open a second project and assert two sections plus the "several jdt.ls" warning. Negative control: stop the jdt.ls client (`client:stop(true)`) and the health output must no longer list it (and not error); a second control: ring buffer test, send `vim.notify("x", WARN)` and assert it is in the output, with the wrapper disabled it is absent.

Not in the slice: statusline, JSONL events, bundle, run-output tee (revisit after living with the three for a few weeks).

## 6. Could not verify

- `:LspLog`, `:Noice`, `:CompletionProfile` were `exists()=0` in a headless startup before lazy plugins loaded; whether they exist in a normal UI session was not checked. `:LspLog` and `:JdtShowLogs` definitions were read in the plugin sources.
- `:lsp` core command of Neovim 0.12 (not checked) and what `:checkhealth vim.lsp` prints for this config.
- Whether snacks notifications / picker are enabled in the LazyVim config (installed, not checked), whether lualine statusline is enabled as default.
- The "macOS empties /tmp after 3 days" claim (from the comment in `paths.lua`); reboot behaviour is documented by Apple but I did not test.
- Number of tests that hard-code `/tmp/nv4j/logs/...` (grep sampled, not counted). That number sets the real cost of Slice 1.
- Whether `dap.set_log_level` is used anywhere (grep for `set_log_level` found nothing).
- Content of Gradle/Maven import failures inside `.metadata/.log` for the "why did import fail" question.
- Overhead of leaving `vim.g.nv4j_lsp_capture` on permanently; not measured (the code comment says it costs nothing when off, nothing about on).
- No heavy test run, no process killed; the only experiment was a headless command-existence probe.
