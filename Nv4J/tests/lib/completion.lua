-- Completion measurement helpers shared by tests/checks/1x_completion_*.lua.
-- Cases are typed into the open buffer in memory (never saved), so the fixture on disk keeps
-- compiling and checks 00/01 are unaffected. Neovim flushes didChange before each request.
local M = {}

M.LATENCY_LOG = "/tmp/nv4j/logs/latency.jsonl"

--- Replace buffer line `lnum` (0-based) with `text` (or insert when insert=true).
--- Returns the 0-based line and the column at the end of `text` (cursor position for completion).
function M.put_line(buf, lnum, text, insert)
  vim.api.nvim_buf_set_lines(buf, lnum, insert and lnum or lnum + 1, false, { text })
  return lnum, #text
end

--- 0-based index of the first line matching a Lua pattern.
function M.find_line(buf, pat)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:find(pat) then return i - 1 end
  end
  error("pattern not found in buffer: " .. pat)
end

--- Nearest-rank percentile of a list of numbers.
function M.pct(samples, p)
  local s = vim.deepcopy(samples)
  table.sort(s)
  if #s == 0 then return 0 end
  return s[math.max(1, math.ceil(p / 100 * #s))]
end

function M.append_latency(case, ms, count)
  local f = io.open(M.LATENCY_LOG, "a")
  if f then
    f:write(vim.json.encode({ case = case, ms = math.floor(ms * 10 + 0.5) / 10, count = count }) .. "\n")
    f:close()
  end
end

--- Items in the order JDTLS intends: sortText ascending (ties keep server order), like a client
--- with no fuzzy scoring would show them.
function M.lsp_order(items)
  local idx = {}
  for i, it in ipairs(items) do idx[it] = i end
  local out = vim.list_slice(items)
  table.sort(out, function(a, b)
    local sa, sb = a.sortText or a.label, b.sortText or b.label
    if sa ~= sb then return sa < sb end
    return idx[a] < idx[b]
  end)
  return out
end

--- Load blink.cmp with the config's own opts and wait for its fuzzy matcher.
--- Returns the blink fuzzy module, or nil + reason.
function M.blink()
  local ok, err = pcall(function() require("lazy").load({ plugins = { "blink.cmp" } }) end)
  if not ok then return nil, "lazy load failed: " .. tostring(err) end
  local fuzzy = require("blink.cmp.fuzzy")
  -- setup() picks the implementation asynchronously after checking the prebuilt binary.
  vim.wait(10000, function() return fuzzy.implementation_type == "rust" end, 50)
  return fuzzy
end

--- Items in the order blink.cmp's menu would show them for the LSP source: the user's fuzzy
--- config (sorts, max_typos, proximity, frecency) applied to `items` at `line`/`col`.
--- Approximation: other sources (snippets, buffer, path) are not mixed in.
function M.blink_order(fuzzy, buf, lnum, col, items)
  vim.api.nvim_win_set_cursor(0, { lnum + 1, col })
  local line = vim.api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1]
  local copy = {}
  for i, it in ipairs(items) do
    copy[i] = vim.tbl_extend("force", {}, it, { source_id = "lsp", score_offset = it.score_offset or 0 })
  end
  fuzzy.haystacks_by_provider_cache = {}
  local range = require("blink.cmp.config").completion.keyword.range
  return fuzzy.fuzzy(line, col, { lsp = copy }, range)
end

--- Raw completion result (CompletionList fields like isIncomplete), not timed. nil on failure.
function M.raw(buf, lnum, col)
  local client = vim.lsp.get_clients({ bufnr = buf, name = "jdtls" })[1]
  if not client then return nil end
  local res = client:request_sync("textDocument/completion", {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    position = { line = lnum, character = col },
  }, 30000, buf)
  return res and res.result
end

--- Open (once) and wait for jdtls. Returns bufnr or nil.
local opened = {}
function M.open_ready(lsp, path, timeout_ms)
  if opened[path] then
    vim.api.nvim_set_current_buf(opened[path])
    return opened[path]
  end
  local buf = lsp.open(path)
  if not lsp.wait_ready(buf, timeout_ms or 120000) then return nil end
  opened[path] = buf
  return buf
end

--- Run fn(buf) with the buffer restored afterwards and marked unmodified, so nothing is ever
--- written and `:qa` does not stop on a modified buffer.
function M.scratch(buf, fn)
  local orig = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ok, a, b, c = pcall(fn, buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, orig)
  vim.bo[buf].modified = false
  if not ok then error(a, 0) end
  return a, b, c
end

--- 1-based rank of the first item satisfying pred, or nil.
function M.rank(list, pred)
  for i, it in ipairs(list) do
    if pred(it) then return i end
  end
end

function M.labels(list, n)
  local out = {}
  for i = 1, math.min(n, #list) do
    local k = vim.lsp.protocol.CompletionItemKind[list[i].kind] or "?"
    out[#out + 1] = list[i].label .. "<" .. k .. ">"
  end
  return table.concat(out, ", ")
end

return M
