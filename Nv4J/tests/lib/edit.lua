-- Helpers for the diagnostics / imports / code-action checks (tests/checks/3x_*.lua).
-- Planted sources live in tests/fixtures/planted/*.java.txt. They declare `public class App` and are
-- loaded into the App.java buffer in memory only (never written), so the fixture on disk keeps
-- compiling. M.restore puts the original text back and marks the buffer unmodified.
local M = {}

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)/lib/")
M.PLANTED = here .. "/fixtures/planted"
M.LATENCY_LOG = "/tmp/nv4j/logs/latency.jsonl"

function M.planted(name)
  return vim.fn.readfile(M.PLANTED .. "/" .. name)
end

function M.log(case, ms, count)
  local f = io.open(M.LATENCY_LOG, "a")
  if f then
    f:write(vim.json.encode({ case = case, ms = math.floor(ms * 10 + 0.5) / 10, count = count }) .. "\n")
    f:close()
  end
end

local function now() return vim.uv.hrtime() / 1e6 end
M.now = now

--- Replace the whole buffer (like a user edit). Returns the time of the edit (ms).
function M.set(buf, lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return now()
end

function M.text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

--- Wait until pred(diagnostics) holds. Returns ok, ms since t0 (the edit), diagnostics.
function M.wait_diags(buf, pred, timeout_ms, t0)
  t0 = t0 or now()
  local d
  local ok = vim.wait(timeout_ms, function()
    d = vim.diagnostic.get(buf)
    return pred(d)
  end, 5)
  return ok, now() - t0, d
end

--- Holds pred for `ms` (no late publish breaks it). Returns ok, diagnostics at failure.
function M.stays(buf, pred, ms)
  local bad
  vim.wait(ms, function()
    local d = vim.diagnostic.get(buf)
    if not pred(d) then bad = d return true end
    return false
  end, 10)
  return bad == nil, bad
end

function M.has(diags, sev, pat)
  for _, d in ipairs(diags) do
    if (sev == nil or d.severity == sev) and d.message:find(pat) then return d end
  end
end

function M.count(diags, sev)
  local n = 0
  for _, d in ipairs(diags) do
    if sev == nil or d.severity == sev then n = n + 1 end
  end
  return n
end

function M.fmt(diags)
  local out = {}
  for _, d in ipairs(diags) do
    out[#out + 1] = ("L%d:%s:%s"):format(d.lnum + 1, vim.diagnostic.severity[d.severity]:sub(1, 1), d.message)
  end
  return table.concat(out, "; ")
end

--- 0-based line index of the first line matching a Lua pattern (plain=false), or nil.
function M.line_of(buf, pat)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:find(pat) then return i - 1 end
  end
end

--- textDocument/codeAction at a range, with the buffer's diagnostics overlapping it as context
--- (what Neovim sends for <leader>ca). Returns { actions, ms, err? }. Checks MUST assert not r.err.
function M.code_actions(client, buf, sl, sc, el, ec, only)
  el, ec = el or sl, ec or sc
  local diags = vim.tbl_filter(function(d) return d.lnum <= el and d.end_lnum >= sl end, vim.diagnostic.get(buf))
  local t0 = now()
  local res, rerr = client:request_sync("textDocument/codeAction", {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    range = { start = { line = sl, character = sc }, ["end"] = { line = el, character = ec } },
    context = { diagnostics = vim.lsp.diagnostic.from(diags), only = only, triggerKind = 1 },
  }, 20000, buf)
  local ms = now() - t0
  if not res then return { actions = {}, ms = ms, err = "request failed: " .. tostring(rerr) } end
  if res.err then return { actions = {}, ms = ms, err = "lsp error: " .. vim.inspect(res.err) } end
  return { actions = res.result or {}, ms = ms }
end

function M.titles(actions)
  return table.concat(vim.tbl_map(function(a) return a.title end, actions), " | ")
end

function M.find(actions, pat)
  for i, a in ipairs(actions) do
    if a.title:find(pat) then return a, i end
  end
end

--- Apply the action whose title matches `pat` through Neovim's own path (what <leader>ca does:
--- vim.lsp.buf.code_action -> codeAction/resolve -> apply edit or run the command). Cursor goes to
--- (sl, sc) (0-based); a range selects (sl,sc)-(el,ec). Waits until the buffer text changes.
--- Returns ok, ms.
function M.apply(buf, pat, sl, sc, el, ec, timeout_ms)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { sl + 1, sc })
  local before = M.text(buf)
  local t0 = now()
  -- jdt.ls often offers the same action twice (quickassist and source kinds, e.g. "Generate
  -- Constructors..."): take the first match only, else Neovim would open a picker instead of applying.
  local taken = false
  local opts = {
    apply = true,
    filter = function(a)
      if taken or not a.title:find(pat) then return false end
      taken = true
      return true
    end,
  }
  -- mark-like range, end column inclusive (Neovim adds 1 for the exclusive LSP end); el/ec here are
  -- exclusive like LSP, as in M.code_actions
  if el then opts.range = { start = { sl + 1, sc }, ["end"] = { el + 1, ec - 1 } } end
  vim.lsp.buf.code_action(opts)
  local ok = vim.wait(timeout_ms or 10000, function() return M.text(buf) ~= before end, 5)
  return ok, now() - t0
end

--- Put the original lines back and mark the buffer unmodified.
function M.restore(buf, lines)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modified = false
  end
end

--- Collect vim.notify messages (the config's visible notifications) from now on.
function M.capture_notify()
  local got = {}
  local orig = vim.notify
  vim.notify = function(msg, level, opts)
    got[#got + 1] = { msg = tostring(msg), level = level }
    return orig(msg, level, opts)
  end
  return got
end

return M
