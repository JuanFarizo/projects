-- Picker and commands of :Nv4JLogs (pure registry: nv4j/logs.lua). snacks.picker; preview = tail of the file.
local logs = require("nv4j.logs")
local M = {}

local TAIL_BYTES = 16 * 1024

local function tail(path)
  local f = io.open(path, "rb")
  if not f then return "(unreadable)" end
  local size = f:seek("end")
  f:seek("set", math.max(0, size - TAIL_BYTES))
  local s = f:read("*a") or ""
  f:close()
  if path:match("%.bin$") then return ("(binary capture, %d bytes; use <C-s> to save it)"):format(size) end
  return s
end

local function human(n)
  if n < 1024 then return n .. "B" end
  if n < 1048576 then return ("%.0fK"):format(n / 1024) end
  return ("%.1fM"):format(n / 1048576)
end

--- Opens a log at its end, read-only; `autoread` shows new lines when focus returns / :checktime.
function M.open(path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.bo.readonly, vim.bo.modifiable, vim.bo.autoread = true, false, true
  vim.cmd("normal! G")
end

--- tail -f in a terminal split.
function M.follow(path)
  vim.cmd("botright 15split")
  vim.cmd("terminal tail -n 200 -f " .. vim.fn.shellescape(path))
  vim.cmd("normal! G")
end

local function save(items)
  local dest, copied = logs.save(items)
  if #copied == 0 then
    vim.notify("Nv4JLogs: nothing to save", vim.log.levels.WARN)
  else
    vim.notify(("Nv4JLogs: saved %d file(s) to %s"):format(#copied, dest))
  end
  return dest, copied
end

local function grep(items)
  local files = vim.tbl_map(function(i) return i.path end, items)
  local function ask(level)
    local base = require("snacks.picker.source.grep").grep
    Snacks.picker.grep({
      dirs = files, title = "Nv4J logs grep" .. (level ~= "" and (" [" .. level .. "]") or ""), hidden = true, ignored = true,
      finder = function(o, ctx)
        local orig = ctx.filter.search
        if level ~= "" and orig ~= "" then ctx.filter.search = level .. ".*" .. orig end
        local r = base(o, ctx)
        ctx.filter.search = orig
        return r
      end,
    })
  end
  vim.ui.input({ prompt = "Level filter (ERROR, WARN, empty = none): " }, function(level) ask(level or "") end)
end

function M.pick(opts)
  local entries = logs.entries(opts)
  if #entries == 0 then vim.notify("Nv4JLogs: no logs" .. (opts.since and (" in the last " .. opts.since) or ""), vim.log.levels.INFO); return end
  local items = {}
  for _, e in ipairs(entries) do
    items[#items + 1] = { text = e.label .. " " .. e.path, file = e.path, entry = e,
      preview = { text = tail(e.path), loc = false } }
  end
  local function sel(picker) return vim.tbl_map(function(i) return i.entry end, picker:selected({ fallback = true })) end
  Snacks.picker.pick({
    source = "nv4j_logs", title = "Nv4J logs" .. (opts.since and (" (" .. opts.since .. ")") or ""), items = items,
    format = function(item)
      local e = item.entry
      return { { ("%-34s"):format(e.label:sub(1, 34)), "SnacksPickerLabel" }, { ("%5s "):format(logs.age_str(e.age)), "SnacksPickerComment" },
        { ("%6s "):format(human(e.size)), "SnacksPickerComment" }, { vim.fs.basename(e.path), "SnacksPickerDir" } }
    end,
    preview = function(ctx)
      require("snacks.picker.preview").preview(ctx)
      pcall(function()
        local w = ctx.preview.win.win
        vim.api.nvim_win_set_cursor(w, { vim.api.nvim_buf_line_count(ctx.buf), 0 })
      end)
    end,
    confirm = function(picker, item) picker:close(); if item then M.open(item.entry.path) end end,
    actions = {
      nv4j_follow = function(picker, item) picker:close(); if item then M.follow(item.entry.path) end end,
      nv4j_grep = function(picker) local s = sel(picker); picker:close(); grep(s) end,
      nv4j_save = function(picker) save(sel(picker)) end,
    },
    win = { input = { keys = {
      ["<C-f>"] = { "nv4j_follow", mode = { "i", "n" }, desc = "follow (tail -f)" },
      ["<C-g>"] = { "nv4j_grep", mode = { "i", "n" }, desc = "grep selected/all" },
      ["<C-s>"] = { "nv4j_save", mode = { "i", "n" }, desc = "save selected for analysis" },
    } } },
  })
end

--- `:Nv4JLogs [period] [tests]` / `:Nv4JLogs save [period] [tests]`
function M.command(args)
  local o, save_all = {}, false
  for _, a in ipairs(args) do
    if a == "save" then save_all = true
    elseif a == "tests" then o.tests = true
    elseif logs.parse_period(a) then o.since = a
    else vim.notify("Nv4JLogs: unknown argument '" .. a .. "'", vim.log.levels.WARN); return end
  end
  if save_all then save(logs.entries(o)) else M.pick(o) end
end

return M
