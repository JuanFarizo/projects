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

--- What blink.cmp's menu would list, produced by blink's own pipeline instead of a copy of it:
--- a blink Context at (lnum, col), `sources.request_completions` (every provider enabled for the
--- buffer: lsp with a real CompletionContext, snippets, path, buffer fallback, each with its
--- score_offset, should_show_items and transform_items, deprecated items at -2), then
--- `completion.list.fuzzy` (fuzzy, sorts, per-source and global max_items).
--- Only the drawing of the menu is missing. Trigger: the character before the cursor when it is
--- a trigger character and nothing was typed after it (like typing `.`), else a keyword trigger.
--- Returns { items, ms, lsp_ms } or nil + reason. ms = request until the sorted list exists.
local ctx_id = 1e6
function M.menu(buf, lnum, col)
  local sources = require("blink.cmp.sources.lib")
  local list = require("blink.cmp.completion.list")
  vim.wo.virtualedit = "onemore" -- normal mode: allow the cursor after the last character
  vim.api.nvim_win_set_cursor(0, { lnum + 1, col })
  local line = vim.api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1]
  local before = line:sub(1, col)
  local typed = before:match("[%w_]*$")
  local prev = before:sub(#before - #typed, #before - #typed)
  -- blink's own rule (trigger characters minus the blocked ones: space, tab, newline). Nothing
  -- typed after a blocked or non-trigger character means the user pressed <C-Space>: manual.
  local trig = typed == "" and prev ~= "" and require("blink.cmp.completion.trigger").is_trigger_character(prev)
    and prev or nil
  ctx_id = ctx_id + 1
  local kind = trig and "trigger_character" or (typed == "" and "manual" or "keyword")
  local ctx = require("blink.cmp.completion.trigger.context").new({
    id = ctx_id,
    providers = sources.get_enabled_provider_ids("default"),
    initial_trigger_kind = kind, initial_trigger_character = trig,
    trigger_kind = kind, trigger_character = trig,
  })
  local got, lsp_ms
  local function on(ev) if ev.context.id == ctx.id then got = ev end end
  sources.completions_emitter:on(on)
  local t0 = vim.uv.hrtime()
  sources.request_completions(ctx)
  local ok = vim.wait(30000, function() return got ~= nil end, 1)
  lsp_ms = (vim.uv.hrtime() - t0) / 1e6
  sources.completions_emitter:off(on)
  if not ok then return nil, "blink sources did not answer within 30 s" end
  -- blink hides the menu when every source that owns the trigger character returned nothing
  -- (completion/init.lua); mirror that so an empty answer is not padded by other sources.
  if trig then
    local owner_has_items = false
    for _, id in ipairs(ctx.providers) do
      local its = got.items[id]
      if its and #its > 0 and vim.tbl_contains(sources.get_provider_by_id(id):get_trigger_characters(), trig) then
        owner_has_items = true
      end
    end
    if not owner_has_items then
      return { items = {}, ms = (vim.uv.hrtime() - t0) / 1e6, lsp_ms = lsp_ms, by_source = got.items, hidden = true }
    end
  end
  local items = list.fuzzy(ctx, got.items)
  return { items = items, ms = (vim.uv.hrtime() - t0) / 1e6, lsp_ms = lsp_ms, by_source = got.items }
end

--- The next keystroke on a complete (isIncomplete = false) list: blink does not ask the server
--- again, it fuzzy-filters the items it already has. `by_source` is M.menu(...).by_source from the
--- earlier position; the buffer line must already hold the new text. Returns the visible items.
function M.refilter(buf, lnum, col, by_source)
  vim.api.nvim_win_set_cursor(0, { lnum + 1, col })
  ctx_id = ctx_id + 1
  local ctx = require("blink.cmp.completion.trigger.context").new({
    id = ctx_id, providers = vim.tbl_keys(by_source),
    initial_trigger_kind = "keyword", trigger_kind = "keyword",
  })
  return require("blink.cmp.completion.list").fuzzy(ctx, by_source)
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
