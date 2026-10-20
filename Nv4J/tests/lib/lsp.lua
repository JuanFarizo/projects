-- Headless LSP test helpers for nv4j. Used by tests/checks/*.lua.
local M = {}
local failed = false
local published = {} -- uri -> true once publishDiagnostics received

-- Track publishDiagnostics so wait_ready knows jdtls finished a first pass.
local orig = vim.lsp.handlers["textDocument/publishDiagnostics"]
vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
  if result and result.uri then
    published[result.uri] = true
  end
  return orig(err, result, ctx, config)
end

local function jdtls_client(bufnr)
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = "jdtls" })) do
    return c
  end
end

--- Open a file and trigger FileType so the lazy-loaded nvim-jdtls starts jdtls.
function M.open(path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = "java"
  vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
  return buf
end

--- Returns the jdtls client once attached AND the project is imported, else nil.
function M.wait_ready(bufnr, timeout_ms)
  local deadline = vim.uv.hrtime() + timeout_ms * 1e6
  local left = function() return math.max(0, (deadline - vim.uv.hrtime()) / 1e6) end

  -- 1. attached (re-fire FileType once in case the lazy plugin loaded late)
  local refired = false
  local ok = vim.wait(left(), function()
    if not refired and vim.uv.hrtime() > deadline - (timeout_ms * 1e6) + 5e9 and not jdtls_client(bufnr) then
      refired = true
      vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr, modeline = false })
    end
    return jdtls_client(bufnr) ~= nil
  end, 200)
  if not ok then return nil end
  local client = jdtls_client(bufnr)

  -- 2. project imported: java.project.getAll lists a project, and the first
  --    diagnostics pass for this buffer has been published.
  local uri = vim.uri_from_bufnr(bufnr)
  local imported = false
  ok = vim.wait(left(), function()
    if client:is_stopped() then return true end
    if not imported then
      local done, res = false, nil
      local sent = client:request("workspace/executeCommand", { command = "java.project.getAll" }, function(err, r)
        if not err then res = r end
        done = true
      end, bufnr)
      if sent then
        vim.wait(math.min(5000, left()), function() return done end, 50)
      end
      imported = type(res) == "table" and #res > 0
    end
    return imported and published[uri] == true
  end, 500)
  if not ok or client:is_stopped() then return nil end
  return client
end

--- Synchronous textDocument/completion. Returns { items = {...}, ms = wall time }.
function M.complete(bufnr, line, col)
  local client = jdtls_client(bufnr)
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = line, character = col },
  }
  local t0 = vim.uv.hrtime()
  local res = client and client:request_sync("textDocument/completion", params, 30000, bufnr)
  local ms = (vim.uv.hrtime() - t0) / 1e6
  local r = res and res.result or {}
  local items = r.items or r
  return { items = items or {}, ms = ms }
end

--- All diagnostics for the buffer.
function M.diagnostics(bufnr)
  return vim.diagnostic.get(bufnr)
end

--- Print PASS|FAIL and append to the shared test log.
function M.report(name, ok, detail)
  if not ok then failed = true end
  local line = (ok and "PASS " or "FAIL ") .. name .. (detail and detail ~= "" and (" " .. tostring(detail)) or "")
  print(line)
  local log = vim.env.NV4J_LOG
  if log then
    local f = io.open(log, "a")
    if f then f:write(line .. "\n"); f:close() end
  end
end

--- Call at the end of a check: non-zero exit if anything failed.
function M.finish()
  if failed then vim.cmd("cquit 1") end
end

return M
