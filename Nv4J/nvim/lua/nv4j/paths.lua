-- Central runtime paths for nv4j. Logs and temp output live under /tmp/nv4j.
local root = "/tmp/nv4j"
local M = {
  root = root,
  logs = root .. "/logs",
  jdtls_data = root .. "/jdtls-data",
  jdtls_config = root .. "/jdtls-config",
}

for _, dir in ipairs({ M.root, M.logs, M.jdtls_data, M.jdtls_config }) do
  vim.fn.mkdir(dir, "p")
end

return M
