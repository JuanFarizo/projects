-- Guard for a Neovim 0.12.4 sharp edge: the underline diagnostic handler (runtime/lua/vim/diagnostic.lua:1845) calls
-- nvim_buf_get_lines(bufnr, lnum, lnum + 1, true) with strict indexing and no range check. Diagnostics are clamped to the
-- buffer only while it is loaded when they are shown; for an unloaded buffer the handler defers (show_once_loaded, on BufRead)
-- and then uses the stored, unclamped list. A diagnostic set for a file that was later shortened on disk (refactor,
-- scaffold, git checkout; jdt.ls keeps publishing for closed files; our test failure marks) makes opening the file fail with
-- "E5108 ... BufReadPost ... Index out of bounds", which aborts the rest of the BufReadPost chain. signs and virtual_text
-- handlers are not affected (checked with real buffers, check 74).
--  * M.setup()  wraps vim.diagnostic.handlers.underline: loaded buffer -> entries past the end are dropped / clamped before the
--                original show; unloaded -> our own once-BufRead autocmd re-checks the list against the loaded buffer, then calls
--                the original. hide() also cancels ours. Idempotent, pcall-safe (a failure leaves the original handler).
--  * M.fit(buf, diags) -> list for diagnostics we set ourselves: same rules against the buffer, or against the file on disk
--                when the buffer is not loaded.
-- Drop rule: lnum < 0 or lnum >= line count -> dropped.
local M = {}

local api = vim.api

--- Entries of `diags` that start inside `n` lines. An end_lnum past the end is harmless (checked: extmarks clamp it).
local function fit_lines(diags, n)
  local out = {}
  for _, d in ipairs(diags) do
    local l = d.lnum or 0
    if l >= 0 and l < n then out[#out + 1] = d end
  end
  return out
end

--- `diags` reduced to what exists in `buf` (loaded) or in its file on disk (not loaded; no file -> unchanged).
---@param buf integer
---@param diags table[]
---@return table[]
function M.fit(buf, diags)
  local ok, res = pcall(function()
    if api.nvim_buf_is_loaded(buf) then return fit_lines(diags, api.nvim_buf_line_count(buf)) end
    local name = api.nvim_buf_get_name(buf)
    if name == "" or vim.fn.filereadable(name) ~= 1 then return diags end
    return fit_lines(diags, math.max(#vim.fn.readfile(name), 1))
  end)
  return ok and res or diags
end

local pending = {} -- [namespace][buf] = autocmd id of our deferred show

function M.setup()
  local h = vim.diagnostic.handlers.underline
  if not h or h._nv4j_guard then return false end
  local show, hide = h.show, h.hide
  M._upstream = h -- tests only: the unguarded Neovim handler
  local function cancel(ns, buf)
    local id = pending[ns] and pending[ns][buf]
    if id then
      pending[ns][buf] = nil
      pcall(api.nvim_del_autocmd, id)
    end
  end
  vim.diagnostic.handlers.underline = {
    _nv4j_guard = true,
    show = function(ns, buf, diags, opts)
      local ok, b = pcall(vim._resolve_bufnr, buf)
      if not ok or not api.nvim_buf_is_valid(b) or type(diags) ~= "table" then return show(ns, buf, diags, opts) end
      cancel(ns, b)
      if api.nvim_buf_is_loaded(b) then
        local fitted = M.fit(b, diags)
        return show(ns, b, fitted, opts)
      end
      pending[ns] = pending[ns] or {}
      pending[ns][b] = api.nvim_create_autocmd("BufRead", {
        buf = b,
        once = true,
        callback = function()
          pending[ns][b] = nil
          show(ns, b, M.fit(b, diags), opts)
        end,
      })
    end,
    hide = function(ns, buf, ...)
      pcall(cancel, ns, buf)
      return hide(ns, buf, ...)
    end,
  }
  return true
end

return M
