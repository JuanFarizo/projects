-- Test results view (:Nv4JTestResults, <leader>tv): a plain scratch buffer in a bottom split drawing the model of
-- nv4j/testresults.lua for the current project (kept in memory, last run per project). Plain Lua, no plugin.
--   <CR> on a test: expand/collapse its detail (message, stack trace, output); on a frame: jump to file:line (project frames only);
--   r rerun the test under the cursor, R rerun the failed tests, q close.
local tr = require("nv4j.testresults")
local M = {}

local NS = vim.api.nvim_create_namespace("nv4j_test_results")
local state = { buf = nil, win = nil, origin = nil, root = nil, meta = {}, expanded = {} }
M._state = state

local function define_hl()
  local function hl(name, opts) vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", { default = true }, opts)) end
  hl("Nv4JTestPassed", { link = "DiagnosticOk" })
  hl("Nv4JTestFailed", { link = "DiagnosticError" })
  hl("Nv4JTestSkipped", { link = "DiagnosticWarn" })
  hl("Nv4JTestDim", { link = "Comment" })
  hl("Nv4JTestProject", { link = "Special" }) -- the project's own frames stand out, library frames are Nv4JTestDim
end

local function valid() return state.buf and vim.api.nvim_buf_is_valid(state.buf) end

--- Root of the project whose results to show: the current buffer's jdt.ls root, else the last run's.
local function current_root()
  local b = vim.api.nvim_get_current_buf()
  if b ~= state.buf then
    local c = vim.lsp.get_clients({ bufnr = b, name = "jdtls" })[1]
    local path = vim.api.nvim_buf_get_name(b)
    c = c or (path ~= "" and require("nv4j.root").client_for_path(path)) or nil
    local root = c and c.config and c.config.root_dir
    if root and tr.get(root) then return root end
  end
  return state.root or tr.last_root
end

--- Re-draw the buffer from the model (keeps the cursor on the same test when it is still there).
function M.render()
  if not valid() then return end
  local model = tr.get(state.root)
  if not model then return end
  local expanded = state.expanded[state.root] or {}
  local keep_key, keep_off
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    local m = state.meta[row]
    if m and m.test then
      keep_key = m.test.key
      for r = row, 1, -1 do
        if state.meta[r] and state.meta[r].kind == "test" then keep_off = row - r; break end
      end
    end
  end
  local lines, meta, spans = tr.render(model, expanded)
  state.meta = meta
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
  for _, s in ipairs(spans) do
    pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, s[1] - 1, s[2], { end_col = s[3] >= 0 and s[3] or #lines[s[1]], hl_group = s[4] })
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local target
    if keep_key then
      for i, m in ipairs(meta) do
        if m.kind == "test" and m.test.key == keep_key then target = math.min(i + (keep_off or 0), #lines); break end
      end
    end
    if not target then
      for i, m in ipairs(meta) do
        if m.kind == "test" then target = i; break end
      end
    end
    pcall(vim.api.nvim_win_set_cursor, state.win, { target or 1, 0 })
  end
end

--- After a run: re-draw an open view (of the project that just ran, or switch to it).
function M.refresh()
  if not valid() then return end
  local last = tr.last_root
  if last and last ~= state.root and state.win and vim.api.nvim_win_is_valid(state.win) then state.root = last end
  M.render()
end

local function target_window()
  if state.origin and vim.api.nvim_win_is_valid(state.origin) and state.origin ~= state.win then return state.origin end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= state.win and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" then return w end
  end
end

local function jump(file, lnum)
  local w = target_window()
  if not w then
    vim.cmd("aboveleft split")
    w = vim.api.nvim_get_current_win()
    state.origin = w
  end
  vim.api.nvim_set_current_win(w)
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, lnum or 1), 0 })
  vim.cmd("normal! zz")
end

local function entry_at_cursor()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return state.meta[row], row
end

function M.activate()
  local m = entry_at_cursor()
  if not m then return end
  if m.kind == "frame" then
    if m.file then return jump(m.file, m.lnum) end
    return vim.notify("Library frame: no source of the project here", vim.log.levels.INFO, { title = "Tests" })
  end
  if m.test then
    local set = state.expanded[state.root] or {}
    state.expanded[state.root] = set
    -- <CR> on a detail line of an open test folds it again
    set[m.test.key] = not set[m.test.key] or nil
    M.render()
  end
end

local function same_project()
  local t = require("nv4j.tests")
  local req = t.last_request
  local root = req and req.client and req.client.config and req.client.config.root_dir
  if root == state.root then return true end
  vim.notify("These results are from another project than the last run: run its tests once from the editor first (<leader>tt, <leader>tp)",
    vim.log.levels.WARN, { title = "Tests" })
  return false
end

function M.rerun()
  local m = entry_at_cursor()
  if not (m and m.test) then return vim.notify("No test under the cursor", vim.log.levels.INFO, { title = "Tests" }) end
  if not same_project() then return end
  require("nv4j.tests").run({ scope = "failed", only = { m.test } })
end

function M.rerun_failed()
  local failed = tr.failed(tr.get(state.root))
  if #failed == 0 then return vim.notify("No failed tests in these results", vim.log.levels.INFO, { title = "Tests" }) end
  if not same_project() then return end
  require("nv4j.tests").run({ scope = "failed", only = failed })
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    if #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.api.nvim_win_close(state.win, true) else vim.cmd("bwipeout") end
  end
  state.win = nil
end

--- Open (or focus) the view for the current project.
function M.open()
  define_hl()
  local root = current_root()
  if not root or not tr.get(root) then
    return vim.notify("No test results yet in this session: run a test first (<leader>tr, <leader>tt, <leader>tp)", vim.log.levels.INFO,
      { title = "Tests" })
  end
  state.root = root
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return M.render()
  end
  state.origin = vim.api.nvim_get_current_win()
  if not valid() then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype = "nofile"
    vim.bo[state.buf].bufhidden = "wipe"
    vim.bo[state.buf].swapfile = false
    vim.bo[state.buf].filetype = "nv4jtests"
    pcall(vim.api.nvim_buf_set_name, state.buf, "Nv4J test results")
    local function map(lhs, fn, desc) vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, desc = desc }) end
    map("<CR>", M.activate, "Expand test / jump to frame")
    map("r", M.rerun, "Rerun test under the cursor")
    map("R", M.rerun_failed, "Rerun failed tests")
    map("q", M.close, "Close")
  end
  vim.cmd("botright " .. math.max(8, math.min(20, math.floor(vim.o.lines / 3))) .. "split")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  for k, v in pairs({ number = false, relativenumber = false, signcolumn = "no", wrap = false, cursorline = true, foldcolumn = "0",
    spell = false, list = false }) do vim.wo[state.win][k] = v end
  vim.api.nvim_create_autocmd("BufWipeout", { buffer = state.buf, once = true, callback = function() state.buf, state.win = nil, nil end })
  M.render()
end

function M.setup()
  pcall(vim.api.nvim_create_user_command, "Nv4JTestResults", function() M.open() end,
    { desc = "Test results of the last run (tree, traces, output)" })
end

return M
