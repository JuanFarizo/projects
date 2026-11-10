# Idea: migrate the pickers to fzf-lua (not decided, not started)

Status: thinking only, 2026-11-10. Nothing here is built. Decide later, when a repository feels slow or the pickers need a rewrite anyway.

## What is what

- Neovim has no fuzzy finder with a list and a preview built in. It has `:find`, `:grep`, `:vimgrep` and the `matchfuzzy()` function.
- Telescope, the snacks picker (part of `snacks.nvim`) and fzf-lua are all plugins.
- `fzf` is a separate command-line program (`junegunn/fzf`, written in Go). The `fzf-lua` plugin calls it. It is on this Mac at `/opt/homebrew/bin/fzf`, with `rg` and `fd`.
- Today the config uses Telescope as the main picker: `lazyvim.json` has the Telescope extra, `config/options.lua` sets `vim.g.lazyvim_picker = "telescope"`, and `plugins/telescope.lua` sets the vertical layout and a tall preview. `:Nv4JLogs` is the exception: it was built on the snacks picker.

## What the config uses from the pickers

| Use | Where | fzf-lua equivalent |
|---|---|---|
| `<C-p>` find files (`--hidden`, `.git/` ignored) | `config/keymaps.lua:69` | `files` |
| `<C-o>` grep the project | `config/keymaps.lua:71` | `live_grep` |
| `<C-f>` search the current file | `config/keymaps.lua:72` | `blines` |
| `<C-e>` open buffers, most recent first | `config/keymaps.lua:42` | `buffers` |
| `<leader>fo` find files in another folder | `config/keymaps.lua:84` | `files` with `cwd` |
| Document symbols | `config/keymaps.lua:108` | `lsp_document_symbols` |
| `gd` / `gr` mirrors | `config/keymaps.lua:379, 383` | `lsp_definitions`, `lsp_references` |
| Colorscheme with live preview | `config/keymaps.lua:496`, `plugins/theme.lua` | `colorschemes` |
| `<leader>sp` Spring symbols (custom picker) | `nv4j/spring_nav.lua` | `fzf_exec` with a custom previewer |
| `:Nv4JLogs` (custom picker, snacks) | `nv4j/logsui.lua` | `fzf_exec` |
| LazyVim's own `<leader>f*` and `<leader>s*` | LazyVim extra | LazyVim fzf extra (`lazyvim.plugins.extras.editor.fzf`) |

The vertical layout, the tall preview and the filename-first path display all have fzf-lua settings.

## Performance

- fzf is compiled and multi-threaded. It copes with millions of lines. Telescope sorts in Lua, which is slower on very large lists. The optional `telescope-fzf-native` plugin closes most of that gap.
- Real numbers on this machine (files not ignored by git, `.git` excluded, counted with `fd`):
  - largest single repositories in `~/Documents/k12_projects`: `tcl-backend` 2,960, `learnx` 2,150, `dynamo-services` 2,029, `docker-learnx` 1,999, `calms-tools` 1,921
  - `nrps-liquibase` is a very small repository
  - all of `k12_projects` together: 19,316 files, counted in about 0.5 s
- At a few thousand files per repository, Telescope is not a bottleneck. A difference would show on a monorepo of hundreds of thousands of files, or when the root is a folder that holds many repositories.
- NOT measured: the picker latency of Telescope against fzf-lua on these repositories. If a repository ever feels slow, measure first (same query, same repository, time to the first result and to the final list), then decide.

## Cost of a migration

- Code to rewrite: nine call sites in `config/keymaps.lua`, the colorscheme picker in `plugins/theme.lua`, `nv4j/spring_nav.lua` (a real custom picker), and `nv4j/logsui.lua`.
- Tests: `tests/checks/52_spring_nav.lua` has 5 Telescope references. The pickers need a redraw check in a real terminal (private tmux server), as was done for the blink menu.
- Behaviour: the keys inside a picker (select, scroll the preview, send to quickfix) are not identical. They would have to be relearned.
- New dependency: the `fzf` program on every machine. Add it to the new-machine checklist (`brew install fzf`, `apt install fzf`).

## When it becomes worth it

- A repository where Telescope's file or grep picker is slow after trying `telescope-fzf-native` first.
- The pickers need a larger rewrite anyway.

## Related decision (not part of this idea)

`:Nv4JLogs` is on the snacks picker today. The plan under discussion is to port it to Telescope, so the config has one picker. If the config moves to fzf-lua later, only the picker part of `nv4j/logsui.lua` changes; the registry in `nv4j/logs.lua` stays as it is.
