-- Picker and commands of :Nv4JLogs (pure registry: nv4j/logs.lua). Telescope (the config's picker: vim.g.lazyvim_picker, plugins/
-- telescope.lua); the preview is the END of the file, read by seeking the last TAIL_BYTES, never the whole log.
local logs = require("nv4j.logs")
local M = {}

M.TAIL_BYTES = 64 * 1024
M.TAIL_LINES = 200

--- Last `M.TAIL_LINES` lines of a file, reading at most `M.TAIL_BYTES` from its end (a 20 MB log is not loaded).
--- A `.bin` capture gives one placeholder line. Returns lines, file size, bytes read.
---@return string[] lines, integer size, integer read
function M.tail(path)
  local f = io.open(path, "rb")
  if not f then return { "(unreadable)" }, 0, 0 end
  local size = f:seek("end") or 0
  if path:match("%.bin$") then f:close(); return { ("(binary capture, %d bytes; use <C-s> to save it)"):format(size) }, size, 0 end
  local start = math.max(0, size - M.TAIL_BYTES)
  f:seek("set", start)
  local s = f:read("*a") or ""
  f:close()
  local lines = vim.split(s, "\n", { plain = true })
  if lines[#lines] == "" then lines[#lines] = nil end
  if start > 0 and #lines > 0 then table.remove(lines, 1) end -- the first line is cut at the seek point
  if #lines > M.TAIL_LINES then lines = vim.list_slice(lines, #lines - M.TAIL_LINES + 1, #lines) end
  return lines, size, #s
end

function M.human(n)
  if n < 1024 then return n .. "B" end
  if n < 1048576 then return ("%.0fK"):format(n / 1024) end
  return ("%.1fM"):format(n / 1048576)
end

--- Telescope entry of a registry entry: "label  age  size  file" (columns built here: entry_display.create needs a live picker
--- window for its widths, this stays pure); the ordinal (what you type to filter) is label + path.
function M.entry_maker(e)
  return {
    value = e, ordinal = e.label .. " " .. e.path, path = e.path,
    display = function(entry)
      local x = entry.value
      local label, age, size = ("%-34s"):format(x.label:sub(1, 34)), ("%5s"):format(logs.age_str(x.age)), ("%6s"):format(M.human(x.size))
      local text = ("%s %s %s %s"):format(label, age, size, vim.fs.basename(x.path))
      return text, {
        { { 35, 35 + #age }, "TelescopeResultsComment" }, { { 36 + #age, 36 + #age + #size }, "TelescopeResultsComment" },
        { { 37 + #age + #size, #text }, "TelescopeResultsIdentifier" },
      }
    end,
  }
end

--- rg argv of one live-grep prompt over `files`; with a level the line must hold it BEFORE the query (`LEVEL.*query`). nil = no search.
function M.grep_cmd(level, prompt, files)
  if not prompt or prompt == "" then return nil end
  local pattern = (level and level ~= "") and (level .. ".*" .. prompt) or prompt
  local args = vim.deepcopy(require("telescope.config").values.vimgrep_arguments)
  args[#args + 1] = "--"
  args[#args + 1] = pattern
  vim.list_extend(args, files)
  return args
end

--- Registry entries of the Tab multi-selection, else of the current entry (`current`, a Telescope entry).
function M.selected(picker, current)
  local multi = picker and picker:get_multi_selection() or {}
  if #multi == 0 then multi = current and { current } or {} end
  return vim.tbl_map(function(i) return i.value end, multi)
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

--- Live grep (rg) across the given registry entries; asks the level text first.
local function grep(items)
  local files = vim.tbl_map(function(i) return i.path end, items)
  local function ask(level)
    local conf = require("telescope.config").values
    local cwd = vim.uv.cwd()
    require("telescope.pickers").new({}, {
      prompt_title = "Nv4J logs grep" .. (level ~= "" and (" [" .. level .. "]") or ""),
      finder = require("telescope.finders").new_job(function(prompt) return M.grep_cmd(level, prompt, files) end,
        require("telescope.make_entry").gen_from_vimgrep({ cwd = cwd }), nil, cwd),
      previewer = conf.grep_previewer({}),
      sorter = require("telescope.sorters").highlighter_only({}),
    }):find()
  end
  vim.ui.input({ prompt = "Level filter (ERROR, WARN, empty = none): " }, function(level) ask(level or "") end)
end

function M.pick(opts)
  local entries = logs.entries(opts)
  if #entries == 0 then vim.notify("Nv4JLogs: no logs" .. (opts.since and (" in the last " .. opts.since) or ""), vim.log.levels.INFO); return end
  local conf = require("telescope.config").values
  local actions, state = require("telescope.actions"), require("telescope.actions.state")
  local previewer = require("telescope.previewers").new_buffer_previewer({
    title = "end of file",
    define_preview = function(self, entry)
      local lines = M.tail(entry.value.path)
      local buf, win = self.state.bufnr, self.state.winid
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      -- Telescope puts the buffer in the preview window on the next tick: the scroll to the end must come after that.
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
          pcall(vim.api.nvim_win_set_cursor, win, { math.max(1, #lines), 0 })
        end
      end)
    end,
  })
  require("telescope.pickers").new({}, {
    prompt_title = "Nv4J logs" .. (opts.since and (" (" .. opts.since .. ")") or "") .. "  <CR> open  <C-f> follow  <C-g> grep  <C-s> save",
    finder = require("telescope.finders").new_table({ results = entries, entry_maker = M.entry_maker }),
    sorter = conf.generic_sorter({}),
    previewer = previewer,
    attach_mappings = function(prompt_bufnr, map)
      local function with(fn)
        return function()
          local picker, cur = state.get_current_picker(prompt_bufnr), state.get_selected_entry()
          fn(picker, cur)
        end
      end
      actions.select_default:replace(with(function(_, cur) actions.close(prompt_bufnr); if cur then M.open(cur.value.path) end end))
      map({ "i", "n" }, "<C-f>", with(function(_, cur) actions.close(prompt_bufnr); if cur then M.follow(cur.value.path) end end), { desc = "follow (tail -f)" })
      map({ "i", "n" }, "<C-g>", with(function(picker)
        local s = M.selected(picker, nil) -- Tab selection, else every listed log
        actions.close(prompt_bufnr)
        -- Next tick: opened in the same tick as the close, the level input ends up in normal mode (the prompt window's mode
        -- change lands after the input's startinsert) and the typed level is eaten.
        vim.schedule(function() grep(#s > 0 and s or entries) end)
      end), { desc = "grep selected/all" })
      map({ "i", "n" }, "<C-s>", with(function(picker, cur) save(M.selected(picker, cur)) end), { desc = "save selected for analysis" })
      return true
    end,
  }):find()
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
