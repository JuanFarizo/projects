-- Pickers for jdt.ls source actions (toString, hashCode/equals, constructors, override, delegates).
-- nvim-jdtls asks with jdtls.ui.pick_many, a vim.fn.input prompt (type the number of each line). Two changes here:
--  * fields start selected: its toString/hashCode callers pass no preselection, so Enter generated a toString() or equals()
--    over zero fields. IntelliJ (and vscode-java) start with every field selected. Items carrying jdt.ls's `isField` flag
--    start selected when the caller gave no preselection; methods/getters stay unselected.
--  * the question is asked with vim.ui.select (the user's picker: snacks, telescope, ...) as a checkbox list: choosing a
--    line toggles it and the list comes back; "Done" (first line) or cancelling finishes with what is selected. The call
--    still blocks and returns the chosen items, because nvim-jdtls uses the return value (the old prompt blocked too).
local M = {}

local function pick_many(items, prompt, label_f, opts)
  if not items or #items == 0 then return {} end
  label_f = label_f or function(item) return item end
  opts = opts or {}
  local is_selected = opts.is_selected or function() return false end
  local selected = {}
  local function index_of(item) for i, x in ipairs(selected) do if x == item then return i end end end
  for _, item in ipairs(items) do
    if is_selected(item) then selected[#selected + 1] = item end
  end
  local DONE = {}
  while true do
    local entries = { DONE }
    vim.list_extend(entries, items)
    local answered, choice = false, nil
    vim.ui.select(entries, {
      prompt = prompt,
      format_item = function(e)
        if e == DONE then return ("Done (%d selected)"):format(#selected) end
        return (index_of(e) and "[x] " or "[ ] ") .. tostring(label_f(e))
      end,
    }, function(item) answered, choice = true, item end)
    vim.wait(600000, function() return answered end, 10) -- a UI that answers on a later tick
    if choice == nil or choice == DONE then break end
    local at = index_of(choice)
    if at then table.remove(selected, at) else selected[#selected + 1] = choice end
  end
  return selected
end
M.pick_many = pick_many

function M.setup()
  local ok, ui = pcall(require, "jdtls.ui")
  if not ok or ui._nv4j_wrapped then return end
  ui.pick_many = function(items, prompt, label_f, opts)
    opts = opts or {}
    if opts.is_selected == nil and type(items) == "table" and type(items[1]) == "table" and items[1].isField ~= nil then
      opts.is_selected = function(item) return item.isField == true end
    end
    return pick_many(items, prompt, label_f, opts)
  end
  ui._nv4j_wrapped = true
end

return M
