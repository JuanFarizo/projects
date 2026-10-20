-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.g.lazyvim_picker = "telescope"
vim.g.lazyvim_explorer = "neo-tree"
vim.g.lazyvim_cmp = "blink.cmp"

-- Format-on-save off by default. Toggle back on per-buffer with Space uf,
-- or globally with Space uF; :w still saves either way, just without
-- silently reformatting the file first.
vim.g.autoformat = false

local opt = vim.opt
opt.tabstop = 4
opt.shiftwidth = 4
opt.hlsearch = true
opt.scrolloff = 8
opt.swapfile = false
opt.relativenumber = false

-- LazyVim default is 200ms. Raised because jdtls's referencesCodeLens
-- (java.lua) re-searches references on every CursorHold, which redraws the
-- "n references" lens text often enough to look like a blink while navigating.
opt.updatetime = 700
