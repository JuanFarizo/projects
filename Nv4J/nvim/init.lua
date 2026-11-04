-- nv4j: Java/Spring Neovim config (runs with NVIM_APPNAME=nv4j)
local paths = require("nv4j.paths")

-- Housekeeping before any log is opened: big logs renamed to .1, old test logs and LSP captures deleted (nv4j/logrotate.lua).
pcall(function() require("nv4j.logrotate").run(paths.logs) end)

-- Neovim LSP client log goes to /tmp/nv4j/logs/lsp.log (no public setter in 0.12).
pcall(vim.lsp.log._set_filename, paths.logs .. "/lsp.log")

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
