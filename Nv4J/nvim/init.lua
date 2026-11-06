-- nv4j: Java/Spring Neovim config (runs with NVIM_APPNAME=nv4j)
local paths = require("nv4j.paths")

-- Housekeeping before any log is opened: big logs renamed to .1, old test logs and LSP captures deleted (nv4j/logrotate.lua).
pcall(function() require("nv4j.logrotate").run(paths.logs) end)

-- Underline diagnostics past the end of a shortened file must not abort BufReadPost (Neovim 0.12.4 sharp edge, nv4j/diagfix.lua).
pcall(function() require("nv4j.diagfix").setup() end)

-- Neovim LSP client log: /tmp/nv4j/logs/lsp-<project>-<pid>.log, one per session (paths.lsp_log; the test runner keeps lsp.log).
-- No public setter in 0.12.
pcall(function()
  local arg = vim.fn.argv(0)
  local file = (type(arg) == "string" and arg ~= "") and vim.fn.fnamemodify(arg, ":p") or nil
  vim.lsp.log._set_filename(paths.lsp_log(file and vim.uv.fs_stat(file) and file or nil))
end)

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
