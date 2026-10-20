-- Run via tests/run.sh (needs JAVA_HOME for JDK 25).
local lsp = require("lsp")
local file = vim.env.NV4J_FIXTURE .. "/src/main/java/demo/App.java"
local t0 = vim.uv.hrtime()
local buf = lsp.open(file)
local client = lsp.wait_ready(buf, 120000)
local ready_ms = (vim.uv.hrtime() - t0) / 1e6
lsp.report("01_jdtls_ready.attached", client ~= nil,
  (client and ("client " .. client.name) or "jdtls not ready") .. (" (open to ready %.0f ms)"):format(ready_ms))
if client then
  local errs = vim.tbl_filter(function(d) return d.severity == vim.diagnostic.severity.ERROR end, lsp.diagnostics(buf))
  lsp.report("01_jdtls_ready", #errs == 0, #errs .. " errors")
end
lsp.finish()
