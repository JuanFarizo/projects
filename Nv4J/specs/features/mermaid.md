# Mermaid diagrams in markdown (POC)

Status: proof of concept, opt-in, 2026-11-16. Not seen drawn in a real kitty by the author: see "Verified" below.

## What it does

A ```` ```mermaid ```` block in a markdown buffer is drawn as an image under the block, inside Neovim (kitty graphics protocol). The text stays editable; the image refreshes on save.

## How (nothing new to write)

`snacks.image` (part of LazyVim's snacks.nvim) already finds mermaid blocks (its `queries/markdown/images.scm`) and converts them by running `mmdc` (mermaid-cli = Node + headless Chromium: heavy install, seconds per diagram). Nv4J keeps snacks and replaces only the converter:

- `:Nv4JMermaid install` downloads `mmdr` (github.com/1jehuang/mermaid-rs-renderer, v0.3.1: one 3.5 MB native binary, no Node, no browser) for this OS/CPU into `stdpath("data")/mermaid/` (`~/.local/share/nv4j/mermaid`), checks the tarball against a pinned SHA-256 (four targets: macOS and Linux, x86_64 and aarch64), and writes a 5-line `mmdc` shim next to it. The shim maps snacks' flags (`-i -o -b -t -s`) to `mmdr -i -o -e png -t`.
- `nv4j/mermaid.lua` `setup()` (called from `config/keymaps.lua`) puts that directory first on `PATH` only when both files exist.
- `plugins/mermaid.lua` turns `snacks.image` on only when mmdr is installed. A machine that never ran `install` pays nothing: image support is off in LazyVim, so no terminal query and no treesitter attach.

Needs: `curl`, `tar`, and `sha256sum` or `shasum` for the install; kitty (or another kitty-graphics terminal); inside tmux snacks sets `allow-passthrough` for the pane itself (its tmux environment setup), so no tmux.conf change should be needed (not tested in a user tmux). No root, no compiler, no Linuxbrew, no ImageMagick for diagrams. The same on Ubuntu (tarball `x86_64-unknown-linux-gnu` / `aarch64-unknown-linux-gnu`).

## Code or image (`<leader>cm`)

Default: the code stays visible and the image is drawn under the block. `<leader>cm` (markdown buffers) flips the buffer to "image instead of the code": the block's lines are covered by the image (the text is only hidden, never changed); pressing it again brings the code back. While the cursor is inside the block the code shows again so it can be edited (snacks hides the image under the cursor). Implemented by wrapping `Snacks.image.placement.new` to remember the mermaid placements (snacks keeps no registry), flipping their `conceal` and forcing a re-render (`_state = nil`, snacks skips re-rendering when its window state is unchanged).

Verified with real key presses in a private tmux with kitty detection forced (`SNACKS_KITTY=1`): after `<leader>cm` the code lines were replaced by the image rows, after a second press the code was back. The picture itself in kitty: not seen by the author.

## Commands

| Command | Does |
|---------|------|
| `:Nv4JMermaid install` | download, verify, write the shim. Restart Neovim afterwards |
| `:Nv4JMermaid remove` | delete `~/.local/share/nv4j/mermaid` (rollback). Restart |
| `<leader>cm` | markdown buffer: image instead of the code / code visible |
| `:Nv4JMermaid status` | mmdr version, terminal image support, dir, target |

## Rollback (any one)

1. `:Nv4JMermaid remove`, restart.
2. `vim.g.nv4j_mermaid = false` (PATH and snacks.image stay untouched).
3. Revert the commit (`nv4j/mermaid.lua`, `plugins/mermaid.lua`, the `:Nv4JMermaid` block in `config/keymaps.lua`, this file, check 101).
`~/.cache/mmdr` (font cache of the binary) and `~/.cache/nv4j/snacks/image` (converted PNGs) can be deleted by hand.

## Verified (2026-11-16, macOS arm64)

- mmdr renders flowchart, sequence, ER, class and state diagrams to PNG in about 0.2 s each (the first run took 4 s: macOS scans a new binary). Output read by eye: sequence and flowchart were correct and legible with the `dark` theme.
- `:Nv4JMermaid install` end to end: download, SHA-256, unpack, shim, PATH.
- snacks `Snacks.image.convert` on a `.mmd` file, through the shim, produced a valid 13.6 KB PNG (same size as calling mmdr directly).
- snacks attaches to a markdown buffer once enabled and finds the mermaid block (`doc.find` returned 1 image).
- Check `101_mermaid` (5 cases; the shim control, `-e png` changed to `-e svg`, fails `shim_args`).

## NOT verified

- The picture drawn on screen in kitty (and in kitty inside tmux). My test terminal was a nested private tmux, where snacks reports no image support, so no placement was exercised. First thing to look at when you try it: `:Nv4JMermaid status` must say `terminal images: true`.
- Other diagram types (Gantt, mindmap, git graph, C4...) and big diagrams: mmdr lists 23 types but is not the real Mermaid engine; output may differ from mermaid.js or fail.
- Light themes (snacks passes `neutral` when `background=light`; mmdr has a `neutral` preset, not seen).
- Linux: the pinned hashes are computed from the release files; the Linux binaries were not run.
- Cursor placement and scrolling with the image under the block; `conceal` of the source block (not enabled: the code stays visible).
- Pinned version bump process: update `M.VERSION` and the four hashes together.
