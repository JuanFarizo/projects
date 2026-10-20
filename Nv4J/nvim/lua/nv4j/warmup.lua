-- One throw-away completion request when jdt.ls reports ServiceReady, so the first completion the
-- user asks for does not pay the server's one-time cost. That cost (about 0.8 s with Spring Boot
-- on the classpath, measured: specs/002-p1-completion.md) is JDT opening the library jars and
-- reading the binary type of every candidate the first time an empty-prefix type list runs (`@`
-- checks @Target on ~500 annotation types; JFR shows ZipFile/BinaryTypeFactory). Later lists reuse
-- that cache. An idle wait, a workspace/symbol query, a prefixed completion or a CDS archive do
-- not remove it; one empty-prefix type-position completion does. The cache is reset when the
-- project is (re)built at ServiceReady, so the request is sent then, not earlier.
-- The buffer is never changed: the request goes to a position that already is a type position
-- (right after the `@` of an existing annotation, else after an existing `new `).
local M = {}

local warmed = {} -- client id -> true

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

--- Send the warm-up request once per client, for the first loaded Java buffer it serves.
--- Result (ms, item count) is kept in vim.g.nv4j_warmup for inspection and the checks.
function M.run(client)
  if not client or warmed[client.id] then return end
  for bufnr in pairs(client.attached_buffers) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "java" then
      local line, col = position(bufnr)
      if line then
        warmed[client.id] = true
        local t0 = vim.uv.hrtime()
        client:request("textDocument/completion", {
          textDocument = { uri = vim.uri_from_bufnr(bufnr) },
          position = { line = line, character = col },
          context = { triggerKind = 1 },
        }, function(err, res)
          vim.g.nv4j_warmup = {
            ms = (vim.uv.hrtime() - t0) / 1e6,
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
function M.status_handler(_, result)
  if not result then return end
  -- Same echo as nvim-jdtls's default handler (quote-safe).
  pcall(vim.cmd, "echohl Function | echo " .. vim.fn.string((result.message or ""):sub(1, vim.v.echospace)) .. " | echohl None")
  if result.type == "ServiceReady" then
    vim.schedule(function()
      for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do M.run(c) end
    end)
  end
end

return M
