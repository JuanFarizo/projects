-- Multi-select picker for override / delegate / toString / constructors (nv4j/codegen.lua), pure, no jdt.ls.
-- nvim-jdtls asks with jdtls.ui.pick_many (a vim.fn.input prompt: type the number of each line). codegen.setup() replaces it
-- with a loop of vim.ui.select (checkbox lines, "Done" first; cancel finishes with what is selected), so the pickers of the
-- user's UI (snacks, telescope, ...) are used. Same contract as before: returns the chosen items synchronously.
--  toggle        : two items toggled, then Done: both returned, in the order toggled.
--  untoggle      : an item toggled twice is not selected.
--  preselect     : opts.is_selected items start checked (checkbox line "[x]"); Done at once keeps them.
--  isfield       : items carrying isField start selected when the caller gave no preselection (the old wrapper's rule kept).
--  cancel        : cancelling (nil) finishes with the current selection; nothing toggled returns {}.
--  empty         : no items returns {} without asking.
--  no_input      : vim.fn.input is never called (the old number prompt is gone).
--  async_ui      : a vim.ui.select that answers later (like snacks' picker) still returns the chosen items from the blocking call.
--  labels        : format_item shows "[ ] label" / "[x] label"; Done shows how many are selected.
local lsp = require("lsp")
local P = "110_pick_many."
local jp = vim.fn.stdpath("data") .. "/lazy/nvim-jdtls"
if vim.uv.fs_stat(jp) then vim.opt.rtp:append(jp) end
local ok_ui, ui = pcall(require, "jdtls.ui")
lsp.report(P .. "plugin", ok_ui, ok_ui and "jdtls.ui loaded" or tostring(ui))
if not ok_ui then return lsp.finish() end
require("nv4j.codegen").setup()

local real_select, real_input = vim.ui.select, vim.fn.input
local input_calls = 0
vim.fn.input = function() input_calls = input_calls + 1; return "" end
local seen = {}
-- script: list of answers, each a function(entries, fmt) -> entry index or nil
local function with_select(script, fn)
  local n = 0
  vim.ui.select = function(entries, o, cb)
    n = n + 1
    seen[#seen + 1] = vim.tbl_map(o.format_item, entries)
    local want = script[n]
    local idx = want and want(entries, o.format_item)
    cb(idx and entries[idx] or nil, idx)
  end
  local r = fn()
  vim.ui.select = real_select
  return r
end
-- index of the entry whose label contains `s`
local function pick(s) return function(entries, fmt)
  for i, e in ipairs(entries) do if fmt(e):find(s, 1, true) then return i end end
end end
local function done() return function(entries, fmt)
  for i, e in ipairs(entries) do if fmt(e):find("Done", 1, true) then return i end end
end end
local function names(list) return table.concat(vim.tbl_map(function(x) return x.name end, list), ",") end

local items = { { name = "alpha" }, { name = "beta" }, { name = "gamma" } }
local lab = function(x) return x.name end

lsp.report(P .. "toggle", names(with_select({ pick("gamma"), pick("alpha"), done() }, function()
  return ui.pick_many(items, "Pick", lab) end)) == "gamma,alpha", "gamma then alpha toggled, Done")

lsp.report(P .. "untoggle", names(with_select({ pick("beta"), pick("beta"), pick("alpha"), done() }, function()
  return ui.pick_many(items, "Pick", lab) end)) == "alpha", "beta toggled twice is out")

lsp.report(P .. "preselect", names(with_select({ done() }, function()
  return ui.pick_many(items, "Pick", lab, { is_selected = function(i) return i.name ~= "beta" end }) end)) == "alpha,gamma",
  "alpha and gamma start checked, Done keeps them")

local fields = { { name = "f1", isField = true }, { name = "m1", isField = false }, { name = "f2", isField = true } }
lsp.report(P .. "isfield", names(with_select({ done() }, function()
  return ui.pick_many(fields, "Fields", lab) end)) == "f1,f2", "isField items start selected")

lsp.report(P .. "cancel", names(with_select({ pick("alpha"), function() return nil end }, function()
  return ui.pick_many(items, "Pick", lab) end)) == "alpha" and #with_select({ function() return nil end }, function()
  return ui.pick_many(items, "Pick", lab) end) == 0, "cancel keeps the toggled ones; nothing toggled gives {}")

local asked = 0
vim.ui.select = function() asked = asked + 1 end
lsp.report(P .. "empty", #ui.pick_many({}, "Pick", lab) == 0 and asked == 0, "no items: {} and no question")
vim.ui.select = real_select

lsp.report(P .. "no_input", input_calls == 0, "vim.fn.input calls: " .. input_calls)

-- a UI that answers on a later tick (snacks picker): the call still blocks until it answers
local script, n = { pick("beta"), done() }, 0
vim.ui.select = function(entries, o, cb)
  n = n + 1
  local want = script[n]
  vim.defer_fn(function()
    local idx = want(entries, o.format_item)
    cb(entries[idx], idx)
  end, 30)
end
local r = ui.pick_many(items, "Pick", lab)
vim.ui.select = real_select
lsp.report(P .. "async_ui", names(r) == "beta", "answers: " .. names(r))

seen = {}
with_select({ pick("alpha"), done() }, function() return ui.pick_many(items, "Pick", lab) end)
local first, second = table.concat(seen[1], "|"), table.concat(seen[2], "|")
lsp.report(P .. "labels", first:find("[ ] alpha", 1, true) and second:find("[x] alpha", 1, true) and second:find("Done (1", 1, true) ~= nil,
  first .. " ... " .. second)

vim.fn.input = real_input
lsp.finish()
