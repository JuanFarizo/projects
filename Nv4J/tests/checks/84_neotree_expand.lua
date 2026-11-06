-- neo-tree `e` (nvim/lua/plugins/neo-tree.lua nv4j_toggle_auto_expand): back to the width the window had before auto-expand.
-- Headless, no jdt.ls. Temp tree /tmp/nv4j/nt-<pid>: nested dirs, each level holding a longer file name, so opening them one by
-- one grows the window in steps (35 -> 40 -> 47 -> ...).
--  restores_start   start 35, e ON, open every level (width grows), e OFF -> exactly 35 (neo-tree's own command gave 54 here)
--  restores_manual  the window was resized to 41 before e ON -> back to 41, not to the configured 35
--  twice            ON/OFF a second time gives the same width
--  cursor_stays     the cursor is on the node it was on, also after moving it while ON
--  grows            while ON the window really grew (the test would pass vacuously otherwise)
local lsp = require("lsp")
local P = "84_neotree_expand."
local T = "/tmp/nv4j/nt-" .. vim.fn.getpid()
vim.fn.delete(T, "rf")
local names = { "a", "b", "c", "d", "e", "f" }
local path = T
for i, n in ipairs(names) do
  path = path .. "/" .. n
  vim.fn.mkdir(path, "p")
  io.open(path .. "/f" .. i .. "_" .. ("x"):rep(i * 6), "w"):close()
end
require("lazy").load({ plugins = { "neo-tree.nvim" } })
local function open()
  require("neo-tree.command").execute({ action = "focus", source = "filesystem", dir = T, reveal = false })
  vim.wait(1500, function() return false end, 50)
  return vim.api.nvim_get_current_win()
end
local function press(keys) vim.cmd("normal " .. keys) vim.wait(500, function() return false end, 50) end
local function line_of(buf, pat)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do if l:find(pat, 1, true) then return i end end
end
local function open_levels(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local grown = vim.api.nvim_win_get_width(win)
  for _, n in ipairs(names) do
    local l = line_of(buf, " " .. n)
    if l then vim.api.nvim_win_set_cursor(win, { l, 0 }) press("l") end
    grown = math.max(grown, vim.api.nvim_win_get_width(win))
  end
  return grown
end

local win = open()
local w0 = vim.api.nvim_win_get_width(win)
press("e")
local grown = open_levels(win)
local buf = vim.api.nvim_win_get_buf(win)
local on_line = vim.api.nvim_win_get_cursor(win)[1]
local on_text = vim.api.nvim_get_current_line()
press("e")
local w1 = vim.api.nvim_win_get_width(win)
lsp.report(P .. "grows", grown > w0 + 10, ("start %d, widest while ON %d"):format(w0, grown))
lsp.report(P .. "restores_start", w1 == w0, ("start %d -> OFF %d"):format(w0, w1))
lsp.report(P .. "cursor_stays", vim.api.nvim_win_get_cursor(win)[1] == on_line and vim.api.nvim_get_current_line() == on_text,
  ("line %d [%s] -> %d [%s]"):format(on_line, vim.trim(on_text), vim.api.nvim_win_get_cursor(win)[1], vim.trim(vim.api.nvim_get_current_line())))
press("e")
press("e")
lsp.report(P .. "twice", vim.api.nvim_win_get_width(win) == w0, "after a second ON/OFF: " .. vim.api.nvim_win_get_width(win))

-- manual width
vim.api.nvim_win_set_width(win, 41)
press("e")
open_levels(win)
press("e")
lsp.report(P .. "restores_manual", vim.api.nvim_win_get_width(win) == 41, "manual 41 -> OFF " .. vim.api.nvim_win_get_width(win))
vim.fn.delete(T, "rf")
lsp.finish()
