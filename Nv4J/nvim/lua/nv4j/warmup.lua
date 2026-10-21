-- Throw-away completion requests while jdt.ls starts, so the first completion the user asks for
-- does not pay the server's one-time cost. That cost (0.7-0.9 s with Spring Boot on the classpath,
-- measured: specs/002-p1-completion.md) is JDT opening the library jars and reading the binary
-- type of every candidate the first time an empty-prefix type list runs (`@` checks @Target on
-- ~500 annotation types; JFR shows ZipFile/BinaryTypeFactory). Later lists reuse that cache. An
-- idle wait, a workspace/symbol query, a prefixed completion or a CDS archive do not remove it;
-- one empty-prefix type-position completion does.
--
-- Two requests per jdtls client:
-- 1. at language/status "Started" (about 2 s before ServiceReady with a warm workspace): pays the
--    cost while jdt.ls is still importing, before the start-up build competes for the CPU;
-- 2. at "ServiceReady": about 70 ms when (1) already filled the cache, the full cost otherwise
--    (e.g. a first import, where "Started" comes before the classpath is known).
-- Sent once per client: a project reload in the same client pays the full cost on its first list.
-- The buffer is never changed: the request goes to a position that already is a type position
-- (right after the `@` of an existing annotation, else after an existing `new `).
local M = {}

local sent = {} -- "<client id>:<phase>" -> true

local function position(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, l in ipairs(lines) do
    local c = l:find("^%s*@%a")
    if c then return i - 1, l:find("@", 1, true) end -- 0-based column just after '@'
  end
  for i, l in ipairs(lines) do
    local s, e = l:find("%f[%w]new%s+%u")
    if s then return i - 1, e - 1 end -- before the class name's first letter
  end
end

--- Send the warm-up request for `phase` ("Started" or "ServiceReady") once per client, for the
--- first loaded Java buffer it serves. Timings land in vim.g.nv4j_warmup ({ started_ms, ms,
--- items, err }; `ms` is the ServiceReady request) for inspection and the checks.
function M.run(client, phase)
  if not client or sent[client.id .. ":" .. phase] then return end
  for bufnr in pairs(client.attached_buffers) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "java" then
      local line, col = position(bufnr)
      if line then
        sent[client.id .. ":" .. phase] = true
        local t0 = vim.uv.hrtime()
        client:request("textDocument/completion", {
          textDocument = { uri = vim.uri_from_bufnr(bufnr) },
          position = { line = line, character = col },
          context = { triggerKind = 1 },
        }, function(err, res)
          local ms = (vim.uv.hrtime() - t0) / 1e6
          if phase == "Started" then
            M.started_ms = ms
            return
          end
          vim.g.nv4j_warmup = {
            started_ms = M.started_ms,
            ms = ms,
            items = res and #(res.items or res) or 0,
            err = err and tostring(err.message or err) or nil,
          }
        end, bufnr)
        return
      end
    end
  end
end

--- language/status handler for nvim-jdtls (keeps its default echo of the status message).
--- `root_dir` is the sending client's project root (nvim-jdtls passes no ctx): only that client warms
--- up, so a second project reaching ServiceReady never re-sends requests to the first one's server.
function M.status_handler(_, result, root_dir)
  if not result then return end
  -- Same echo as nvim-jdtls's default handler (quote-safe).
  pcall(vim.cmd, "echohl Function | echo " .. vim.fn.string((result.message or ""):sub(1, vim.v.echospace)) .. " | echohl None")
  if result.type == "ServiceReady" then
    -- First ServiceReady of the session, hrtime in ms (read by tests/checks/10_*).
    vim.g.nv4j_service_ready_ms = vim.g.nv4j_service_ready_ms or vim.uv.hrtime() / 1e6
  end
  if result.type == "Started" or result.type == "ServiceReady" then
    vim.schedule(function()
      for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do
        if root_dir == nil or c.config.root_dir == root_dir then M.run(c, result.type) end
      end
    end)
  end
end

return M
