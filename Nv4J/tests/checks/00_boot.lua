-- Boot check. Run: NVIM_APPNAME=nv4j nvim --headless -c "luafile tests/checks/00_boot.lua" -c qa
local failed = false
local function check(name, ok, detail)
  print((ok and "PASS " or "FAIL ") .. name .. (detail and (" " .. tostring(detail)) or ""))
  if not ok then
    failed = true
  end
end

check("appname", vim.env.NVIM_APPNAME == "nv4j", vim.env.NVIM_APPNAME)
local cfg = vim.fn.stdpath("config")
check("stdpath_config", cfg:match("/nv4j$") ~= nil, cfg)

local ok, paths = pcall(require, "nv4j.paths")
check("paths_module", ok, ok and "" or paths)
if ok then
  check("paths_logs", paths.logs == "/tmp/nv4j/logs", paths.logs)
  check("paths_jdtls_data", paths.jdtls_data == "/tmp/nv4j/jdtls-data", paths.jdtls_data)
end
check("logs_dir", vim.fn.isdirectory("/tmp/nv4j/logs") == 1)
check("jdtls_data_dir", vim.fn.isdirectory("/tmp/nv4j/jdtls-data") == 1)
check("lsp_log", vim.lsp.log.get_filename() == "/tmp/nv4j/logs/lsp.log", vim.lsp.log.get_filename())

if failed then
  vim.cmd("cquit 1")
end
