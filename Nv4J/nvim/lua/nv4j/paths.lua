-- Central runtime paths for nv4j. Logs and temp output live under /tmp/nv4j.
local root = "/tmp/nv4j"
local M = {
  root = root,
  logs = root .. "/logs",
  jdtls_data = root .. "/jdtls-data",
}

for _, dir in ipairs({ M.root, M.logs, M.jdtls_data }) do
  vim.fn.mkdir(dir, "p")
end

return M
