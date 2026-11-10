-- IntelliJ IDEA debugger keys (specs/features/debug-run.md, "IntelliJ keys"; check 92_debug_keys).
-- Installed only while a debug session is active (nvim-dap event_initialized), removed when it ends
-- (event_terminated / event_exited / disconnect / session closed); a mapping that was there before
-- (F8 / S-F8: next / previous diagnostic) is saved with maparg and put back with mapset.
--   F7 step into · F8 step over · S-F8 step out · F9 resume · A-F9 run to cursor
--   A-F8 evaluate expression (visual: the selection, else the word under the cursor) · S-F7 smart step into
-- Any time: <D-F8> (Cmd+F8 on a Mac) or <C-F8> (Linux; <A-F8> is evaluate) toggles a breakpoint, platform chosen like the other app keys (vim.g.nv4j_mod).
local M = {}

M.mod = vim.g.nv4j_mod or (vim.uv.os_uname().sysname == "Darwin" and "D" or "A")
M.bpkey = function() return M.mod == "D" and "<D-F8>" or "<C-F8>" end
M.session_keys = nil -- list of { mode, lhs } while installed; nil when not
M.saved = {}
M.last_eval = nil -- { expr, result } of the last A-F8, for tests and the float

local function evaluate_here()
  local dap = require("dap")
  local session = dap.session()
  if not session then return end
  local expr
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
    expr = table.concat(lines, " ")
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  else
    expr = vim.fn.expand("<cexpr>")
    if expr == "" then expr = vim.fn.expand("<cword>") end
  end
  expr = vim.trim(expr or "")
  if expr == "" then return vim.notify("Evaluate: nothing under the cursor", vim.log.levels.WARN) end
  session:evaluate(expr, function(err, resp)
    local text = err and ("error: " .. (err.message or vim.inspect(err))) or (resp and resp.result) or "nil"
    M.last_eval = { expr = expr, result = text, ok = not err }
    -- reuse nvim-dap-ui's eval float when it is installed, else a plain float
    if package.loaded["dapui"] or pcall(require, "dapui") then
      if pcall(require("dapui").eval, expr) then return end
    end
    vim.lsp.util.open_floating_preview(vim.split(expr .. " = " .. text, "\n"), "java", { border = "rounded" })
  end)
end

local function smart_step_into()
  local dap = require("dap")
  local session = dap.session()
  if session and session.capabilities and session.capabilities.supportsStepInTargetsRequest then
    dap.step_into({ askForTargets = true })
  else
    vim.notify("Smart step into: this adapter has no stepInTargets; plain step into", vim.log.levels.INFO)
    dap.step_into()
  end
end

local function defs()
  local dap = require("dap")
  return {
    { { "n" }, "<F7>", function() dap.step_into() end, "Debug: step into" },
    { { "n" }, "<F8>", function() dap.step_over() end, "Debug: step over" },
    { { "n" }, { "<S-F8>", "<F20>" }, function() dap.step_out() end, "Debug: step out" },
    { { "n" }, "<F9>", function() dap.continue() end, "Debug: resume" },
    { { "n" }, { "<A-F9>", "<F57>" }, function() dap.run_to_cursor() end, "Debug: run to cursor" },
    { { "n", "x" }, { "<A-F8>", "<F56>" }, evaluate_here, "Debug: evaluate expression" },
    { { "n" }, { "<S-F7>", "<F19>" }, smart_step_into, "Debug: smart step into" },
  }
end

function M.install()
  if M.session_keys then return end
  M.session_keys, M.saved = {}, {}
  for _, d in ipairs(defs()) do
    for _, lhs in ipairs(type(d[2]) == "table" and d[2] or { d[2] }) do
      for _, mode in ipairs(d[1]) do
        local prev = vim.fn.maparg(lhs, mode, false, true)
        if prev and prev.lhs and prev.buffer ~= 1 then M.saved[#M.saved + 1] = prev end
        vim.keymap.set(mode, lhs, d[3], { desc = d[4] })
        M.session_keys[#M.session_keys + 1] = { mode, lhs }
      end
    end
  end
end

function M.remove()
  if not M.session_keys then return end
  for _, k in ipairs(M.session_keys) do pcall(vim.keymap.del, k[1], k[2]) end
  M.session_keys = nil
  for _, prev in ipairs(M.saved) do pcall(vim.fn.mapset, prev) end
  M.saved = {}
end

local function hook()
  local dap = require("dap")
  local L = dap.listeners
  L.after.event_initialized["nv4j_keys"] = M.install
  for _, ev in ipairs({ "event_terminated", "event_exited", "disconnect" }) do
    L.after[ev]["nv4j_keys"] = M.remove
  end
  L.on_session["nv4j_keys"] = function(_, new) if new == nil then M.remove() end end
  if dap.session() then M.install() end
end

function M.setup()
  if M._setup then return end
  M._setup = true
  local map = vim.keymap.set
  map("n", M.bpkey(), function() require("dap").toggle_breakpoint() end, { desc = "Debug: toggle breakpoint" })
  -- Terminals without the kitty keyboard protocol (and tmux) send Shift+F8, Alt+F8, Alt+F9, Ctrl+F8, Shift+F7 as the terminfo keys
  -- F20, F56, F57, F32, F19 (measured, see debug-run.md): the same keys under those names. F20 is the S-F8 diagnostic alias outside a session.
  map("n", "<F20>", "[d", { desc = "Previous diagnostic", remap = true })
  if M.mod ~= "D" then map("n", "<F32>", function() require("dap").toggle_breakpoint() end, { desc = "Debug: toggle breakpoint" }) end
  pcall(function()
    require("which-key").add({
      { "<F7>", desc = "Debug: step into (during a session)", mode = "n" },
      { "<F8>", desc = "Next diagnostic; debug: step over (during a session)", mode = "n" },
      { "<S-F8>", desc = "Previous diagnostic; debug: step out (during a session)", mode = "n" },
      { "<F9>", desc = "Debug: resume (during a session)", mode = "n" },
      { "<A-F9>", desc = "Debug: run to cursor (during a session)", mode = "n" },
      { "<A-F8>", desc = "Debug: evaluate expression (during a session)", mode = { "n", "x" } },
      { "<S-F7>", desc = "Debug: smart step into (during a session)", mode = "n" },
    })
  end)
  if package.loaded["dap"] then return hook() end
  vim.api.nvim_create_autocmd("User", {
    pattern = "LazyLoad",
    callback = function(a)
      if a.data == "nvim-dap" and package.loaded["dap"] then hook(); return true end
    end,
  })
end

return M
