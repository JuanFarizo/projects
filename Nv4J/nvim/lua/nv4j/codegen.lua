-- Field pickers for jdt.ls source actions (toString, hashCode/equals, constructors, delegates).
-- nvim-jdtls asks with jdtls.ui.pick_many, which starts with nothing selected unless the caller
-- passes is_selected, and its toString/hashCode callers do not: pressing Enter generates a
-- toString() or equals() over zero fields. IntelliJ (and vscode-java) start with every field
-- selected. This wraps pick_many so items that carry jdt.ls's `isField` flag start selected when the
-- caller gave no preselection; methods/getters stay unselected. Enter keeps the preselection.
local M = {}

function M.setup()
  local ok, ui = pcall(require, "jdtls.ui")
  if not ok or ui._nv4j_wrapped then return end
  local pick_many = ui.pick_many
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
