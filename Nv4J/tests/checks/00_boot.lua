-- Boot check. Run via tests/run.sh (or: NVIM_APPNAME=nv4j nvim --headless --cmd "set rtp+=tests/lib"
-- -c "lua package.path='tests/lib/?.lua;'..package.path" -c "luafile tests/checks/00_boot.lua" -c qa!).
local lsp = require("lsp")
local function check(name, ok, detail) lsp.report("00_boot." .. name, ok, detail) end

check("appname", vim.env.NVIM_APPNAME == "nv4j", vim.env.NVIM_APPNAME)
local cfg = vim.fn.stdpath("config")
check("stdpath_config", cfg:match("/nv4j$") ~= nil, cfg)

local ok, paths = pcall(require, "nv4j.paths")
check("paths_module", ok, ok and "" or paths)
-- jdt.ls workspace and config copy: persistent cache that follows NVIM_APPNAME, never /tmp
-- (macOS empties /tmp); logs and test output stay in /tmp/nv4j.
local cache = vim.fn.stdpath("cache")
check("stdpath_cache", cache:match("/nv4j$") ~= nil and not vim.startswith(cache, "/tmp"), cache)
if ok then
  check("paths_logs", paths.logs == "/tmp/nv4j/logs", paths.logs)
  check("paths_jdtls_data", paths.jdtls_data == cache .. "/jdtls-data", paths.jdtls_data)
  check("paths_jdtls_config", paths.jdtls_config == cache .. "/jdtls-config", paths.jdtls_config)
end
check("logs_dir", vim.fn.isdirectory("/tmp/nv4j/logs") == 1)
check("jdtls_data_dir", vim.fn.isdirectory(cache .. "/jdtls-data") == 1)
check("jdtls_config_dir", vim.fn.isdirectory(cache .. "/jdtls-config") == 1)
check("lsp_log", vim.lsp.log.get_filename() == "/tmp/nv4j/logs/lsp.log", vim.lsp.log.get_filename())

lsp.finish()
