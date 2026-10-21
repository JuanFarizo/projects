-- Central runtime paths for nv4j.
-- Logs and temp output live under /tmp/nv4j (disposable). The jdt.ls workspace (-data: project
-- index, build state) and its writable -configuration copy are not disposable: losing them forces a
-- full re-import, and macOS empties /tmp on reboot and after 3 days, possibly while jdt.ls runs.
-- They live under stdpath("cache") (~/.cache/nv4j with NVIM_APPNAME=nv4j).
local root = "/tmp/nv4j"
local cache = vim.fn.stdpath("cache")
local M = {
  root = root,
  logs = root .. "/logs",
  cache = cache,
  jdtls_data = cache .. "/jdtls-data",
  jdtls_config = cache .. "/jdtls-config",
}

for _, dir in ipairs({ M.root, M.logs, M.jdtls_data, M.jdtls_config }) do
  vim.fn.mkdir(dir, "p")
end

return M
