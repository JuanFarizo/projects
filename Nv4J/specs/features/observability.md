# Observability: `:Nv4JLogs`

One command lists every log Nv4J and the tools under it write, shows the tail of each, follows or greps them, and saves a copy for analysis. The logs stay where their writers put them (mostly `/tmp/nv4j/logs`, which macOS empties on reboot); saving is how you keep one. Code: `nvim/lua/nv4j/logs.lua` (registry, pure) and `nvim/lua/nv4j/logsui.lua` (picker). Research behind it: `docs/RESEARCH-observability.md`. Check: `tests/checks/90_logs.lua`.

## Sources

| id | What | Where |
|----|------|-------|
| `lsp` | Neovim LSP client log, one per Neovim process and project (and `.1`) | `/tmp/nv4j/logs/lsp-<project>-<pid>.log` |
| `lsp-projects` | same, session started without a project | `/tmp/nv4j/logs/lsp-projects-<pid>.log` |
| `spring-ls` | Spring language server | `/tmp/nv4j/logs/spring-boot-ls.log` (+ `.1`) |
| `spring-route` | which jdt.ls an `sts/*` request went to; lines are `YYYY-mm-dd HH:MM:SS [pid] message` | `/tmp/nv4j/logs/spring-route.log` (+ `.1`) |
| `jdtls` | jdt.ls own log, one per project | `~/.cache/nv4j/jdtls-data/<project>/.metadata/.log` |
| `dap` | nvim-dap | `stdpath("state")/dap.log` |
| `lsp-capture` | raw LSP stdout capture (only when `vim.g.nv4j_lsp_capture`) | `/tmp/nv4j/logs/lsp-capture-*.bin` |
| `latency` | test timing samples | `/tmp/nv4j/logs/latency.jsonl`, `latency.prev.jsonl` |
| `completion-profile` | `:CompletionProfile on` output | `stdpath("state")/completion-profile.jsonl` |
| `test` | test run logs, hidden unless `tests` | `/tmp/nv4j/logs/test-*.log` |

## Use

- `:Nv4JLogs [period] [tests]` opens the picker, newest first: label, age, size, file. Period is `30m`, `2h`, `1d` or `7d` (nothing = all). The preview is the end of the file.
- `:Nv4JLogs save [period] [tests]` copies every file of the period at once.
- No `<leader>` key: the repo's `<leader>l`, `<leader>L` and `<leader>s` keys belong to LazyVim. Command only.

Keys in the picker (`Tab` selects several):

| Key | Does |
|-----|------|
| `<CR>` | Open in a buffer at the end, read-only, `autoread` on |
| `<C-f>` | Follow: `:terminal tail -n 200 -f` in a bottom split |
| `<C-g>` | Live grep across the selected files (all listed when none is selected). Asks for a level text first (`ERROR`, `WARN`, empty = none); a line must contain it before the typed pattern |
| `<C-s>` | Save the selected files (the one under the cursor when none is selected) and notify the folder |

Saved copies go to `stdpath("state")/nv4j/saved-logs/<YYYYmmdd-HHMMSS>/` (`~/.local/state/nv4j/nv4j/saved-logs/...` with `NVIM_APPNAME=nv4j`), byte for byte. Originals are never changed or deleted. A jdt.ls log is saved as `jdt.ls_<project>.log`. Saved folders are not rotated: delete them yourself.

`:JdtShowLogs` now opens the jdt.ls log of the current project and the real Neovim LSP log (before, the second window was the stale `stdpath("log")/lsp.log`). `:LspLog` already followed the renamed log.

## Add a source

Add one entry to `M.SOURCES` in `nvim/lua/nv4j/logs.lua`, or call `require("nv4j.logs").register(entry)` (same id replaces):

```lua
{ id = "mine", label = "My log", kind = "other", files = function(d) return vim.fn.glob(d.logs .. "/mine-*.log", true, true) end }
```

`files(d)` gets `d.logs`, `d.state`, `d.jdtls_data` and returns paths, or `{ path = ..., label = ... }`. `kind = "test"` hides the source unless `tests`. Missing files and errors in `files` give no entry. A file found by an earlier source is not listed twice.
