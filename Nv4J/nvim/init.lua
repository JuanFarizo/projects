-- nv4j: Java/Spring Neovim config (runs with NVIM_APPNAME=nv4j)
local paths = require("nv4j.paths")

-- Neovim LSP client log goes to /tmp/nv4j/logs/lsp.log (no public setter in 0.12).
pcall(vim.lsp.log._set_filename, paths.logs .. "/lsp.log")

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
