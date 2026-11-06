-- blink.cmp source "jpql": entity fields, entities, aliases and :params inside @Query strings (nv4j/jpqlcomplete.lua).
local S = {}
function S.new() return setmetatable({}, { __index = S }) end
function S:enabled() return vim.bo.filetype == "java" end
function S:get_trigger_characters() return { ".", ":" } end
function S:get_completions(ctx, callback)
  local empty = { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
  local ok = pcall(require("nv4j.jpqlcomplete").complete, ctx.bufnr, ctx.cursor[1] - 1, ctx.cursor[2], function(items)
    callback(items and { items = items, is_incomplete_forward = false, is_incomplete_backward = false } or empty)
  end)
  if not ok then callback(empty) end
  return function() end
end
return S
