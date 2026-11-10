# Neovim 0.13 discovery for Nv4J (2026-11-06)

Sources: news.txt / lua.txt / starting.txt on neovim master, the dotfiles.substack article, neovim.io/roadmap,
milestone 48 (GitHub API), and a grep of `Nv4J/nvim`. Nothing was installed or run: this is read-only discovery.

## 1. Status
- Milestone 0.13: 77 open / 275 closed, **due 2026-11-18**. Today's `nightly` tag: 2026-11-06. Latest stable: v0.12.6 (2026-10-09).
- Local: nvim 0.12.4 (brew, /opt/homebrew/bin/nvim). No `bob` installed.
- Roadmap: headline items done (multicursor, CmdAtom, vim.async, vim.ui.img, autoread watchers, cmdwin, dir browser).
  Still open: interactive `:!`, packspec/pkg.json, remote SSH. None matter for Nv4J.
- Open milestone bugs are mostly RPC/ui2/treesitter-on-32bit/Windows. None found that hits LSP + Java directly,
  but only the first page of the list was readable, so this is not exhaustive.

## 2. The logging feature (the one that was liked)
- `vim.log.new({name, level, format_func})` returns a **file-backed** logger with `trace/debug/info/warn/error`,
  `set_level`, `get_level`, `set_format_func`. Default level WARN. Default file `{name}.log` under `stdpath('log')`
  (now `stdpath('state')/logs`). Line format `[LEVEL][timestamp] file:line  msg`.
- `:log nvim` (and other names) opens log files inside Neovim. NEWS: ":log opens log files".
- **Colors: not documented anywhere I could read.** The docs describe levels and a file format, not highlighting.
  Whether `:log` colors levels (a syntax/ftplugin) is UNVERIFIED: must be checked on a nightly (`:log nvim`, `:help :log`).
- Fit for Nv4J: today logs are ad-hoc files in `/tmp/nv4j/` + `logrotate.lua` + `vim.notify(..., vim.log.levels.X)` (48 notify calls).
  `vim.log` could replace the hand-made file logging (levels, format, `:log`) but does NOT replace notifications and
  has no rotation. `logrotate.lua` stays. Value: medium-low, nice-to-have.

## 3. Features that could help Nv4J
| Feature | Where in Nv4J | Value |
|---|---|---|
| `vim.async` (structured concurrency, cancel, semaphores) | run/tests/refactor/scaffold use callbacks + vim.system + uv (127 uv uses). Replacing is a refactor, not a fix | Medium, long term |
| `'autoread'` with fs watchers | `scaffold.lua:382` forces `checktime` after codegen; external edits from Maven/formatters/AI agents (claudecode, sidekick) would reload live | Medium, cheap |
| LSP: `commitCharacters`, `preselect`, nested snippets, `applyKind`, dynamic completion registration | completion order/lag was the original pain (P1); blink.cmp owns completion, so only if blink adopts them | Low-medium |
| LSP: definition/implementation honor `'switchbuf'`, arbitrary positions; `foldingRange` foldtext; `format()` `timeout_ms` with async | `gd` wrapper in `jpqlcomplete.lua:203-208` overrides `vim.lsp.buf.definition` (must re-test) | Low |
| LSP: shared file watchers (one native watcher per dir on macOS) | two jdt.ls + Spring LS = many watchers; may cut CPU/RAM. Worth measuring against memwatch | Medium (measure) |
| LSP semantic tokens overscan (less flicker), `workspace/foldingRange/refresh` | free | Low |
| `:restart` saves/restores session; `ZR`; `:detach!`/`:connect` (incl. ssh://) | restart after config edits; keep jdt.ls alive across terminal drop (but jdt.ls dies with the server only if nvim dies) | Medium QoL |
| Treesitter 50-100% faster on injection-heavy files | JPQL-in-`@Query` injection, markdown | Low-medium |
| `vim.treesitter.select()`, `v_]N` | alternative to vim-expand-region | Low |
| Multicursor (`Q`) | not used | Low |
| `vim.ui.img` | user chose NOT to port image plugin | Skip |
| `vim.diagnostic` `virtual_lines.overflow`, `status()` | tiny-inline-diagnostic is in use | Low |
| `vim.pack` | Nv4J uses lazy.nvim/LazyVim; article also advises keeping lazy | Skip |
| `vim.fs.mkdir{parents}`, `slug`, `vim.uri` module, `Iter:count`, `vim.isnil/npcall` | small cleanups in paths/root | Low |
| `Dimmed` hl, ui2 (`'messagesopt'`) | ui2 is an experimental replacement for noice-style UI; noice.nvim conflicts if both on | Watch |

## 4. Breaking changes: grep of Nv4J/nvim (nothing is a hard blocker in our own code)
| Change | Hit in Nv4J | Impact |
|---|---|---|
| `client.attached_buffers[buf]` is now a languageId string, not boolean | `lua/nv4j/warmup.lua:38` uses `pairs(...)` over keys | Likely safe (keys unchanged); verify value is not tested as boolean |
| `stdpath("log")` -> `stdpath("state")/logs` | no use. Our logs are in `/tmp/nv4j` | None. Third-party plugins writing logs move |
| `BufModifiedSet` removed | 0 uses | None in ours; check plugins |
| `vim.opt` infix chaining removed | 0 uses | None |
| `lsp.buf.*` drop `reuse_win` | 2 uses are `telescope.builtin ... reuse_win` (telescope option, not core) | None |
| LSP: with string-array `cmd`, `root_dir` is default cwd | jdtls is started by nvim-jdtls, Spring LS via spring-boot.nvim | Re-test cold start + `two_boot_index` |
| `nvim_win_set_width` deprecated | `plugins/neo-tree.lua:21` | Works, deprecation warning; migrate to `nvim_win_resize` |
| `vim.on_key` doesn't fire for keys consumed by getchar() | `util/profile.lua:107` (completion profiler) | Possible behavior change in profile only |
| `Q`/`gQ` remapped | users' habits only | Low |
| `vim.lsp.buf.definition` rewritten | `jpqlcomplete.lua` monkey-patches it (check 86) | **Re-run check 86 first** |
| TUI/--remote reject server-to-client API calls by default | headless test harness uses `--headless` + own RPC? (verify `tests/lib`) | Unknown: check |
| Ex-mode / `-es` rewritten | `tests/run.sh` uses headless nvim; verify it does not use `-es` | Check |
| `:helptags` needs vimdoc parser | lazy/mason doc builds | Low |

## 5. Plugin risk (biggest unknown, not testable from reading)
Pinned in lazy-lock.json (all must work on 0.13): nvim-treesitter (main branch, parser/ABI), blink.cmp (Rust fuzzy lib, uses LSP completion internals),
noice.nvim (hooks cmdline/messages; 0.13 changes `msg_show.completion` -> `progress` and ui2), nvim-jdtls, spring-boot.nvim,
neo-tree (reads window width, patched in Nv4J), snacks.nvim, hlchunk, tiny-inline-diagnostic, nvim-dap(-ui), mason.
LazyVim itself raises its minimum version only after stable 0.13. Plugin maintainers usually fix nightly breakage within weeks of release.

## 6. Can we migrate?
- **Not before 0.13 stable.** Due 2026-11-18, 12 days away. Even then expect 0.13.0 -> 0.13.1 fixes in the first weeks, and plugin lag.
- **A POC is feasible and cheap right now** because Nv4J is isolated (`NVIM_APPNAME=nv4j`, user's real nvim untouched):
  nightly in a separate prefix, same config, run the 20-check suite. The suite (86+ checks, real jdt.ls) is a strong migration oracle.
- Risks in order: (1) plugin breakage (blink.cmp, noice, treesitter), (2) LSP internals changes vs our `definition` wrap and the jdtls/Spring startup,
  (3) test timing under new `vim.async`/watchers, (4) flaky checks already known (`two_boot_index`, 50, 60) become hard to attribute.

## 7. Suggested POC (if approved)
1. Install nightly beside 0.12 without touching it (`bob` or a tarball in `~/.local/share/nvim-0.13/`), alias `nv4j13`.
2. `:checkhealth`, `:log nvim` (answers the **colors** question), `:help vim.log`.
3. Run `tests/run.sh` with that binary; diff failures vs the 0.12 baseline (3 green runs). Triage: plugin vs core vs our code.
4. Only then try opt-ins, in this order: `autoread` (+ drop `checktime`), `vim.log` for debug logging, `nvim_win_resize` in neo-tree, measure LSP watcher sharing (memwatch RSS/CPU).
5. Gate: all checks green on 0.13 and no Nv4J code path needs `if vim.fn.has("nvim-0.13")` forks. Keep 0.12.x as supported until then.
Cost: roughly one session for steps 1-3; steps 4-5 depend on results.

## 8. Unverified (be honest)
- Whether `:log` color-highlights levels. Check on nightly.
- Full 77-issue list of milestone 48 (only first page seen).
- Whether blink.cmp/noice/nvim-treesitter at the pinned commits already run on nightly.
- `tests/lib` use of RPC/`-es` (not inspected).
