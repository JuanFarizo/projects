local M = {}

M.active = "claude" -- not persisted: every session starts on Claude

local function sk()
  return require("sidekick.cli")
end

-- sidekick keys sessions by tool name, so resume/continue are separate
-- sessions; send/toggle must follow whichever one was started last.
local cursor_tool = "cursor"

local function cursor_start(tool)
  cursor_tool = tool
  sk().toggle({ name = tool, focus = true })
end

M.providers = {
  claude = {
    toggle = function() vim.cmd("ClaudeCode") end,
    resume = function() vim.cmd("ClaudeCode --resume") end,
    continue = function() vim.cmd("ClaudeCode --continue") end,
    model = function() vim.cmd("ClaudeCodeSelectModel") end,
    add_buffer = function() vim.cmd("ClaudeCodeAdd %") end,
    send_selection = function() vim.cmd("ClaudeCodeSend") end,
  },
  cursor = {
    toggle = function() cursor_start(cursor_tool) end,
    resume = function() cursor_start("cursor_resume") end,
    continue = function() cursor_start("cursor_continue") end,
    model = function() vim.notify("Cursor: change the model inside its own UI", vim.log.levels.INFO) end,
    add_buffer = function() sk().send({ name = cursor_tool, msg = "{file}" }) end,
    -- {this} = file:line position + the selection (plain {selection} has no path)
    send_selection = function() sk().send({ name = cursor_tool, msg = "{this}" }) end,
  },
}

-- Per-project "Claude panel was open" memory (config/autocmds.lua writes it on VimLeavePre).
M.state_path = nil -- override of the state file path (tests point it at a temp dir)

function M.state_file()
  return M.state_path or (vim.fn.stdpath("state") .. "/claudecode_sessions.json")
end

function M.read_state()
  local ok, lines = pcall(vim.fn.readfile, M.state_file())
  if not ok then
    return {}
  end
  local ok2, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  return (ok2 and type(decoded) == "table") and decoded or {}
end

function M.write_state(state)
  pcall(vim.fn.writefile, { vim.json.encode(state) }, M.state_file())
end

-- Reopens the Claude panel when it was open the last time nvim left this cwd.
function M.restore_panel()
  if M.read_state()[vim.fn.getcwd()] then
    vim.schedule(function()
      -- never raise at startup (plugin missing, e.g. offline first start)
      pcall(vim.cmd, "ClaudeCodeOpen")
    end)
  end
end

function M.run(action)
  M.providers[M.active][action]()
end

function M.direct(name)
  M.active = name
  M.run("toggle")
end

function M.pick()
  local names = vim.tbl_keys(M.providers)
  table.sort(names)
  vim.ui.select(names, { prompt = "AI provider" }, function(choice)
    if choice then
      M.direct(choice)
    end
  end)
end

return M
