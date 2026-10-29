-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- LazyVim's lazyvim_wrap_spell autocmd turns wrap+spell on for markdown/text/
-- gitcommit. Registered here (after that one, so it runs later and wins),
-- markdown only, to turn both back off — text/gitcommit untouched.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.opt_local.wrap = false
    vim.opt_local.spell = false
  end,
})

-- LazyVim loads this file (config/autocmds.lua) at two different points
-- depending on how nvim was started:
--   - `nvim` with NO arguments at all: loaded later, on the VeryLazy event
--     (which fires after VimEnter).
--   - `nvim .` / `nvim somefile`: loaded immediately, synchronously, during
--     LazyVim's own startup — BEFORE VimEnter, and crucially BEFORE
--     LazyVim applies its own default colorscheme (the last step of its
--     setup()). Code that runs directly in that path gets silently
--     overwritten a moment later when LazyVim's default colorscheme kicks in.
-- `vim.v.vim_did_enter` tells us which situation we're in at the moment
-- this file runs, so we can pick the branch that actually wins: run now if
-- VimEnter already happened, otherwise defer to VimEnter so we apply after
-- LazyVim's own defaults instead of before them.
local function on_ready(fn)
  if vim.v.vim_did_enter == 1 then
    fn()
  else
    vim.api.nvim_create_autocmd("VimEnter", { once = true, nested = true, callback = fn })
  end
end

-- `nvim .` / `nvim <dir>` should count as "opened like a workspace" (like
-- bare `nvim`), for both the colorscheme and the session-restore logic
-- below — only opening a specific FILE should skip them.
local function opened_as_workspace()
  local argc = vim.fn.argc(-1)
  return argc == 0 or (argc == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1)
end

-- ── Per-project colorscheme ───────────────────────────────────────────────
-- Java/Spring projects (pom.xml, build.gradle) get IntelliJ's Darcula theme
-- (colors/darcula-intellij.lua); everything else keeps tokyonight (default,
-- set in lua/plugins/theme.lua). A manual override (e.g. Space uC) is
-- remembered per project cwd and wins over this default on the next open.
do
  local state_file = vim.fn.stdpath("state") .. "/project_colorschemes.json"

  local function read_state()
    local ok, lines = pcall(vim.fn.readfile, state_file)
    if not ok then
      return {}
    end
    local ok2, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
    return (ok2 and type(decoded) == "table") and decoded or {}
  end

  -- Remember whatever colorscheme is active whenever it changes, by whatever
  -- means (Space uC, :colorscheme, or our own default pick below). Uses
  -- args.match (the name passed to `:colorscheme`) rather than
  -- vim.g.colors_name — some schemes with variants (e.g. kanagawa's
  -- wave/dragon/lotus) set colors_name to the same base name regardless of
  -- which variant was actually loaded, which would lose the variant here.
  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function(args)
      local state = read_state()
      state[vim.fn.getcwd()] = args.match
      pcall(vim.fn.writefile, { vim.json.encode(state) }, state_file)
    end,
  })

  on_ready(function()
    local cwd = vim.fn.getcwd()
    local remembered = read_state()[cwd]
    if remembered then
      vim.cmd.colorscheme(remembered)
    elseif vim.fn.glob(cwd .. "/pom.xml") ~= "" or vim.fn.glob(cwd .. "/build.gradle*") ~= "" then
      vim.cmd.colorscheme("darcula-intellij")
    elseif vim.fn.glob(cwd .. "/package.json") ~= "" then
      vim.cmd.colorscheme("tokyonight-night")
    end
  end)
end

-- ── Session persistence (restore last-open tabs/buffers per project) ──────
-- persistence.nvim (LazyVim core: Space qs/qS/ql/qd) already auto-*saves* a
-- session per project dir on exit, but doesn't auto-*load* on startup — wire
-- that up here, only when nvim is opened like a workspace (`nvim` or
-- `nvim .`), never when opening a specific file.
do
  if opened_as_workspace() then
    on_ready(function()
      require("persistence").load()

      -- The startup empty buffer survives :source of the session; wipe it.
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if
          vim.api.nvim_buf_get_name(b) == ""
          and vim.bo[b].buftype == ""
          and not vim.bo[b].modified
          and #vim.fn.win_findbuf(b) == 0
          and vim.api.nvim_buf_line_count(b) == 1
        then
          pcall(vim.api.nvim_buf_delete, b, {})
        end
      end

      require("util.ai").restore_panel()
    end)
  end
end

-- ── Claude Code panel per project ─────────────────────────────────────────
-- The panel is a terminal buffer, not a normal file buffer, so :mksession (persistence.nvim above) does
-- not capture it. Remember on exit whether it was open for this cwd; util/ai.lua restore_panel() (called
-- from the workspace restore above) reopens it. State: stdpath("state")/claudecode_sessions.json.
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("nv4j_claude_panel", { clear = true }),
  callback = function()
    local ai = require("util.ai")
    -- not loaded = never opened this session: do not load (and auto-start) the plugin just to quit
    local terminal = package.loaded["claudecode.terminal"]
    local is_open = terminal ~= nil and terminal.get_active_terminal_bufnr() ~= nil
    local state = ai.read_state()
    state[vim.fn.getcwd()] = is_open
    ai.write_state(state)
  end,
})

-- ── Java scaffolding for `:e NewClass.java` / `gf` (nv4j/scaffold.lua, D22) ──
-- Asks the kind, fills the buffer from the same templates as <leader>jn and writes it (so the file on
-- disk is not the empty one nvim-jdtls writes on attach). neo-tree's `a` goes through
-- plugins/neo-tree.lua's file_added handler; <leader>jn (config/keymaps.lua) needs neither.
vim.api.nvim_create_autocmd("BufNewFile", {
  pattern = "*.java",
  callback = function(args)
    require("nv4j.scaffold").fill_buf(args.buf, vim.api.nvim_buf_get_name(args.buf))
  end,
})

-- Opt-in completion profiler: only registers :CompletionProfile, stays off until invoked.
require("util.profile").setup()
