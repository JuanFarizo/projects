-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

-- ── General ────────────────────────────────────────────────────────
-- (Esc-clear-hlsearch, Ctrl+S save, Ctrl-hjkl window nav, Alt-jk move line,
--  gcc/gc comment, splits <leader>-/|/wd are all LazyVim core defaults already)
map("n", "<leader>q", ":q<CR>", { desc = "Quit", silent = true })
map("n", "<leader>w", ":w<CR>", { desc = "Save file", silent = true })
map("n", "<leader>W", ":wa<CR>", { desc = "Save all files", silent = true })

-- Alt+Up/Down: VS Code-style aliases for LazyVim core's Alt+J/Alt+K move-line
-- (same underlying commands, just the arrow-key muscle memory too).
map("n", "<A-Down>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move line down" })
map("n", "<A-Up>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move line up" })
map("i", "<A-Down>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move line down" })
map("i", "<A-Up>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move line up" })
map("v", "<A-Down>", ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", { desc = "Move selection down" })
map("v", "<A-Up>", ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", { desc = "Move selection up" })

-- Ctrl+Shift+D: duplicate line (normal mode) / selection (visual mode), VS Code style.
map("n", "<C-S-d>", "yyp", { desc = "Duplicate line" })
map("v", "<C-S-d>", ":t'><CR>gv", { desc = "Duplicate selection" })

-- Open a terminal in a real new nvim tabpage (:tabnew), not a Snacks float —
-- lets you use gt/gT or {n}gt like switching between file tabs.
map("n", "<leader>tn", function()
  vim.cmd.tabnew()
  vim.cmd.terminal()
  vim.cmd.startinsert()
end, { desc = "New terminal in a tab" })

-- ── Buffers ────────────────────────────────────────────────────────
-- (LazyVim core also provides <S-h>/<S-l> and [b/]b for this)
map("n", "<Tab>", ":bnext<CR>", { desc = "Next buffer", silent = true })
map("n", "<S-Tab>", ":bprevious<CR>", { desc = "Previous buffer", silent = true })

-- Ctrl+E: fuzzy-search open buffers (VS Code/IntelliJ "recent files" style).
-- Overrides Vim's native <C-e> (scroll down one line).
map("n", "<C-e>", ":Telescope buffers sort_mru=true ignore_current_buffer=true<CR>", { desc = "Search open buffers", silent = true })

-- Close buffer without closing nvim or losing unsaved work.
-- Snacks.bufdelete() already prompts "Save changes?" on modified buffers
-- and never closes the window/quits nvim on the last buffer.
map("n", "<C-q>", function()
  Snacks.bufdelete()
end, { desc = "Close buffer" })

-- ── Expand selection (vim-expand-region, see lua/plugins/expand-region.lua) ──
map("i", "<C-d>", "<Esc>vw", { desc = "Exit insert and select word" })

-- ── File explorer ──────────────────────────────────────────────────
-- (<leader>e already toggles neo-tree at root via LazyVim's neo-tree extra)
map("n", "<C-b>", ":Neotree toggle<CR>", { desc = "Toggle file explorer", silent = true })
map("n", "<leader>ef", function()
  -- Dependency classes open as jdt://contents/... (jar-internal, no path on disk), so neo-tree can't reveal them.
  if vim.api.nvim_buf_get_name(0):match("^%a[%w+.-]*://") then
    return vim.notify("Not a file on disk (dependency source)", vim.log.levels.WARN)
  end
  vim.cmd("Neotree reveal")
end, { desc = "Reveal current file in explorer", silent = true })

-- ── Telescope (fuzzy finder) ───────────────────────────────────────
-- (<leader>ff/fb/fr/<leader>ss already provided by LazyVim's telescope extra)
map("n", "<C-p>", function()
  -- rg (telescope default) honors .gitignore, so node_modules/target/build are skipped like VS Code/IntelliJ; --hidden shows dotfiles.
  require("telescope.builtin").find_files({ hidden = true, file_ignore_patterns = { "^%.git/" } })
end, { desc = "Find files", silent = true })
map("n", "<C-o>", ":Telescope live_grep<CR>", { desc = "Search in all files (grep)", silent = true })
map("n", "<C-f>", ":Telescope current_buffer_fuzzy_find<CR>", { desc = "Search in current file", silent = true })

-- Open a file, or search for files, in another workspace/dir, not the one
-- nvim is currently rooted in. Accepts either a full file path (opens it
-- directly) or a directory (opens Telescope find_files rooted there).
map("n", "<leader>fo", function()
  vim.ui.input({ prompt = "Path or workspace dir: ", completion = "file" }, function(path)
    if not path or path == "" then
      return
    end
    path = vim.fn.expand(path)
    if vim.fn.isdirectory(path) == 1 then
      require("telescope.builtin").find_files({ cwd = path })
    elseif vim.fn.filereadable(path) == 1 then
      vim.cmd.edit(path)
    else
      vim.notify("No such file or directory: " .. path, vim.log.levels.WARN)
    end
  end)
end, { desc = "Open file / find files in other workspace" })

map("n", "<leader>fy", function()
  vim.fn.setreg("+", vim.fn.expand("%"))
end, { desc = "Yank relative path" })
map("n", "<leader>fY", function()
  vim.fn.setreg("+", vim.fn.expand("%:p"))
end, { desc = "Yank absolute path" })

-- Ctrl+M: search only methods/functions in the current file (LSP document
-- symbols filtered to Method/Function/Constructor kinds — narrower than
-- <leader>ss which lists every symbol kind, e.g. fields/classes too).
-- Requires the kitty keyboard protocol to disambiguate Ctrl+M from Enter
-- (both are ASCII 0x0D otherwise); works locally, but plain Ctrl+M will
-- fall back to acting like Enter over a plain SSH/tmux session without
-- pass-through of the extended protocol.
map("n", "<C-m>", function()
  require("telescope.builtin").lsp_document_symbols({
    symbols = { "Method", "Function", "Constructor" },
  })
end, { desc = "Search methods in current file" })

-- Ctrl+T: browser-style "new tab" for quick notes — opens LazyVim's
-- persistent scratch buffer (Snacks.scratch), markdown by default,
-- auto-saved to disk and restored across restarts.
map("n", "<C-t>", function()
  Snacks.scratch()
end, { desc = "New scratch note (persistent)" })

-- ── Navigation ────────────────────────────────────────────────────
-- The "app" modifier: Cmd (<D-...>, kitty on macOS) on a Mac, Alt (<A-...>) everywhere else. macOS keeps Option
-- free for Unicode input, and Linux has no Cmd key to forward. `vim.g.nv4j_mod = "D"` or "A" in init forces one.
local MOD = vim.g.nv4j_mod or (vim.uv.os_uname().sysname == "Darwin" and "D" or "A")
local function appkey(k)
  return ("<%s-%s>"):format(MOD, k)
end

-- App+Left/Right jump the cursor history (back/forward navigation style,
-- like browser back/forward).
-- Ctrl+Left/Right left at LazyVim's default (window-resize) since terminals
-- commonly reserve Ctrl+Left/Right for word-jump before nvim ever sees them.
map("n", appkey("Left"), "<C-o>", { desc = "Jump backward" })
map("n", appkey("Right"), "<C-i>", { desc = "Jump forward" })

-- ── Toggles ────────────────────────────────────────────────────────
-- Same mechanism LazyVim core already uses for <leader>uw (Snacks.toggle),
-- just adding the VS Code muscle-memory key on top.
Snacks.toggle.option("wrap", { name = "Wrap" }):map("<A-z>")

-- ── Terminal (LazyVim core binds <C-/> (and <C-_>, what terminals send for it) to toggle it; <C-j> stays window nav) ──
-- Terminal "tabs": each session is its own float (same as <C-/>, which
-- is already a float, not a split), but only one is ever shown at a time —
-- <C-t> hides the current one and opens a fresh one in its place; Cmd+]/
-- Cmd+[ hide the current one and show the next/prev. Never touches the file
-- window or file buffers.
--
-- Cmd+bracket, not Ctrl+Tab/Ctrl+Shift+Tab: those are kitty's own built-in
-- tab-switch shortcuts, so kitty eats the keypress before nvim ever sees it
-- — same class of issue as Option/Alt (see the Cmd+Left/Right jump binds
-- above). Only shift+cmd+[ / shift+cmd+] are reserved by kitty, so plain
-- Cmd+[ / Cmd+] are free — and match Chrome's back/forward convention.
--
-- (Earlier version swapped buffers into the terminal window directly via
-- win="current" — broke because Snacks closes a terminal's window whenever
-- its buffer stops being displayed, which a plain buffer-swap triggers.)
local function next_terminal_id()
  local used = {}
  for _, t in ipairs(Snacks.terminal.list()) do
    local info = vim.b[t.buf].snacks_terminal
    if info and info.id then
      used[info.id] = true
    end
  end
  local id = 1
  while used[id] do
    id = id + 1
  end
  return id
end

local function hide_all_terminals()
  for _, t in ipairs(Snacks.terminal.list()) do
    if t:buf_valid() then
      t:hide()
    end
  end
end

map("t", "<C-t>", function()
  hide_all_terminals()
  Snacks.terminal.open(nil, { count = next_terminal_id(), cwd = LazyVim.root() })
end, { desc = "New terminal tab" })

local function cycle_terminal(step)
  local terms = Snacks.terminal.list()
  table.sort(terms, function(a, b)
    return (vim.b[a.buf].snacks_terminal.id or 0) < (vim.b[b.buf].snacks_terminal.id or 0)
  end)
  if #terms < 2 then
    return
  end
  local cur, idx = vim.api.nvim_get_current_win(), 1
  for i, t in ipairs(terms) do
    if t.win == cur then
      idx = i
      break
    end
  end
  local target = terms[((idx - 1 + step) % #terms) + 1]
  hide_all_terminals()
  target:show():focus()
end

map("t", appkey("]"), function()
  cycle_terminal(1)
end, { desc = "Next terminal tab" })
map("t", appkey("["), function()
  cycle_terminal(-1)
end, { desc = "Previous terminal tab" })

-- ── Run Java main via raw `java` command line (no mvn/gradle, no debugger) ──
-- Space dc (DAP) launches main classes too, but goes through the debug
-- adapter. This is the plain-terminal equivalent: asks jdtls (which already
-- incrementally compiles the project for LSP/autocomplete) to resolve the
-- classpath + main class the same way it does for DAP, then runs a raw
-- `java -cp <classpath> <mainClass>` in a terminal split — nothing built or
-- invoked via Maven/Gradle at all.
map("n", "<leader>rj", function()
  local ok, jdtls_dap = pcall(require, "jdtls.dap")
  if not ok then
    vim.notify("jdtls isn't attached to this buffer (not a Java file?)", vim.log.levels.WARN)
    return
  end

  local function launch(config)
    local cmd = { config.javaExec or "java" }
    if config.vmArgs then
      vim.list_extend(cmd, vim.split(config.vmArgs, " "))
    end
    if config.classPaths and #config.classPaths > 0 then
      vim.list_extend(cmd, { "-cp", table.concat(config.classPaths, ":") })
    end
    table.insert(cmd, config.mainClass)
    -- auto_close defaults to true for Snacks terminals, which closes the
    -- window the instant the java process exits — for a fast main() that
    -- prints and returns, this looks like an instantaneous blink instead
    -- of a terminal you can read. Keep it open until you close it yourself.
    Snacks.terminal.open(cmd, { cwd = config.cwd, auto_close = false })
  end

  -- After a save, jdtls rebuilds the project model in the background; a
  -- fetch right after can race that rebuild and come back empty ("No main
  -- method found") even though the project is fine — previously worked
  -- around by restarting jdtls. Build time isn't predictable, so retry
  -- several times over a few seconds instead of guessing one timeout.
  local max_attempts = 6
  local function try_fetch(attempt)
    jdtls_dap.fetch_main_configs({}, function(configs)
      if #configs == 0 then
        if attempt < max_attempts then
          vim.defer_fn(function()
            try_fetch(attempt + 1)
          end, 800)
        else
          vim.notify("No main method found in this project", vim.log.levels.WARN)
        end
      elseif #configs == 1 then
        launch(configs[1])
      else
        vim.ui.select(configs, {
          prompt = "Run which main class?",
          format_item = function(c)
            return c.mainClass
          end,
        }, function(choice)
          if choice then
            launch(choice)
          end
        end)
      end
    end)
  end
  try_fetch(1)
end, { desc = "Run Java main (terminal, no debugger)" })

-- ── Run Spring Boot (nv4j/run.lua, check 41_run) ──────────────────────────
-- Main class from jdt.ls, project JDK, build before launch. Output in a terminal split:
-- <C-c> (normal mode) stops the app, q stops it and closes the split.
require("nv4j.settings") -- :Nv4jMark
map("n", "<leader>rs", function()
  require("nv4j.run").spring_boot()
end, { desc = "Run Spring Boot app" })
-- Through Maven (spring-boot:run; Gradle bootRun if there is no pom): applies the plugin's
-- <configuration>, pom profiles and process-classes plugins that <leader>rs skips. To make it the
-- default for <leader>rs/<leader>rp: vim.g.nv4j_run_tool = "maven" (or "gradle").
map("n", "<leader>rS", function()
  require("nv4j.run").spring_boot({ tool = "maven" })
end, { desc = "Run Spring Boot (build tool)" })
map("n", "<leader>rd", function()
  require("nv4j.run").spring_boot({ debug = true })
end, { desc = "Debug Spring Boot app" })
map("n", "<leader>rp", function()
  require("nv4j.run").prompt_profile()
end, { desc = "Run Spring Boot app with profile" })
map("n", "<leader>rx", function()
  require("nv4j.run").stop_all()
end, { desc = "Stop Spring Boot app(s)" })
pcall(function()
  require("which-key").add({ { "<leader>r", group = "run" } })
end)

-- ── Spring symbols (nv4j/spring_nav.lua, check 52_spring_nav) ─────────────
-- Beans and request mappings from the Spring Boot LS in Telescope. <leader>ss stays LazyVim's Goto Symbol.
map("n", "<leader>sp", function()
  require("nv4j.spring_nav").pick()
end, { desc = "Spring symbols (beans, request mappings)" })

-- ── Tests (nv4j/tests.lua, decision D21, check 60_tests_runner) ─────────────────────────────
-- <leader>tr nearest, <leader>tt class, <leader>tp project (replaces the old `mvn test` terminal: results
-- now in the editor), <leader>tf failed again, <leader>tl last again, <leader>to results (quickfix),
-- <leader>td debug nearest, <leader>tT pick (nvim-jdtls's picker, also TestNG). Global here; Java buffers
-- get the same keys per buffer on attach (plugins/java.lua). LazyVim's java extra test keys are off
-- (opts.test = false). `mvn test` itself: <leader>tn opens a terminal.
require("nv4j.tests").bind()
pcall(function()
  require("which-key").add({ { "<leader>t", group = "test" } })
end)

-- ── Java scaffolding (nv4j/scaffold.lua, decision D22, check 61_scaffold) ───────────────────
-- <leader>jn: new class/interface/record/enum/annotation/Spring stereotype/package/test (kind, then name;
-- `foo.Bar` creates the package foo). Directory: neo-tree's node, else the current file's, else cwd.
-- <leader>jt: test class of the current class (src/test/java, same package), created when missing.
map("n", "<leader>jn", function()
  require("nv4j.scaffold").new({ insert = true })
end, { desc = "New Java file/package (scaffold)" })
map("n", "<leader>jt", function()
  require("nv4j.scaffold").test_for_current()
end, { desc = "Test for this class (open or create)" })

-- ── Refactors (nv4j/refactor.lua, decision D23, check 62_refactor) ─────────────────────────────
-- <leader>jr: rename (the package on a `package` line, else the class: file renamed, references and
-- imports updated, touched files written and listed). <leader>jp: rename the current file's package
-- (package/import lines, folders in src/main and src/test moved, buffers re-pointed). <leader>cr stays
-- LazyVim's Rename (any symbol). <leader>jm: move the class at the cursor to another package (picked
-- from the project's packages or typed; the folder is created when missing). <leader>ji: inline the
-- method call, local variable or constant at the cursor (jdt.ls's choice: a call/reference inlines that
-- occurrence, the declaration inlines every one and removes it; a local variable every use).
-- <leader>js: change the signature of the method at the cursor (on its declaration or a call): the
-- signature is asked as text, e.g. `public int total(Invoice invoice, int discount = 0)` (a new
-- parameter's default is what the call sites pass). <leader>jd: safe delete the method, field, constant or
-- type at the cursor: with usages nothing is deleted and they are listed in the quickfix list; without,
-- the declaration is removed (the file, for the only type of its file).
map("n", "<leader>jr", function()
  require("nv4j.refactor").rename()
end, { desc = "Refactor: rename class (package on a package line)" })
map("n", "<leader>jp", function()
  require("nv4j.refactor").rename_package()
end, { desc = "Refactor: rename package" })
map("n", "<leader>jm", function()
  require("nv4j.refactor").move()
end, { desc = "Refactor: move class to another package" })
map("n", "<leader>ji", function()
  require("nv4j.refactor").inline()
end, { desc = "Refactor: inline method / variable / constant" })
map("n", "<leader>js", function()
  require("nv4j.refactor").change_signature()
end, { desc = "Refactor: change method signature" })
map("n", "<leader>jd", function()
  require("nv4j.refactor").safe_delete()
end, { desc = "Refactor: safe delete (usages listed, else deleted)" })
-- A class file deleted by safe delete goes to a trash (stdpath("cache")/nv4j-trash): put the latest back.
vim.api.nvim_create_user_command("Nv4jRestoreDeleted", function()
  require("nv4j.refactor").restore_deleted()
end, { desc = "Restore the file safe delete deleted last (from the Nv4J trash)" })
pcall(function()
  require("which-key").add({ { "<leader>j", group = "java" } })
end)

-- ── LSP (additive aliases; LazyVim core already binds gd/gr/gI/gy/K/<leader>ca/<leader>cr) ──
map("n", "<F2>", vim.lsp.buf.rename, { desc = "Rename symbol" })
map("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename symbol" })
-- Mirrors gd exactly (Telescope-backed once the picker attaches, same as LazyVim's own gd)
local goto_definition = function()
  require("telescope.builtin").lsp_definitions({ reuse_win = true })
end
-- Mirrors gr exactly (Telescope-backed, same as LazyVim's own gr)
local goto_references = function()
  require("telescope.builtin").lsp_references({ reuse_win = true })
end
map("n", "<C-Down>", goto_definition, { desc = "Go to definition" })
map("n", "<C-Up>", goto_references, { desc = "Find references (usages)" })
map("n", "<F12>", goto_definition, { desc = "Go to definition" })

-- ── Type/call hierarchy (IntelliJ-style; builtin since Neovim 0.11+ LSP,
-- backed by jdtls's typeHierarchyProvider/callHierarchyProvider) ───────────
map("n", "<leader>cS", function()
  vim.lsp.buf.typehierarchy("subtypes")
end, { desc = "Subtype hierarchy" })
map("n", "<leader>cP", function()
  vim.lsp.buf.typehierarchy("supertypes")
end, { desc = "Supertype hierarchy" })
map("n", "<leader>ci", vim.lsp.buf.incoming_calls, { desc = "Incoming calls" })
-- <leader>co is Organize Imports (LazyVim's jdtls extra, buffer-local in Java buffers); outgoing
-- calls live on <leader>cO only, so each key means one thing.
map("n", "<leader>cO", vim.lsp.buf.outgoing_calls, { desc = "Outgoing calls" })

-- ── Diagnostics / error navigation (VS Code F8 style; LazyVim core already
-- binds ]d/[d next/prev diagnostic and ]e/[e next/prev error) ──────────────
map("n", "<F8>", "]d", { desc = "Next diagnostic", remap = true })
map("n", "<S-F8>", "[d", { desc = "Previous diagnostic", remap = true })

-- ── Comment toggle (LazyVim core already binds gcc/gc) ──────────────
-- Not <C-/> or <C-_>: LazyVim core uses them for the terminal. <C-o>gcc would jump the
-- cursor to column 0, so restore it, shifted by the comment marker's length.
local function toggle_comment_insert()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local before = #vim.api.nvim_get_current_line()
  vim.cmd("normal gcc")
  local delta = #vim.api.nvim_get_current_line() - before
  vim.api.nvim_win_set_cursor(0, { row, math.max(col + delta, 0) })
end
map("n", appkey("/"), "gcc", { desc = "Toggle comment", remap = true })
map("x", appkey("/"), "gc", { desc = "Toggle comment", remap = true })
map("i", appkey("/"), toggle_comment_insert, { desc = "Toggle comment" })

-- ── Toggle hlchunk indent guides (lua/plugins/hlchunk.lua; snacks indent/scope are off) ──
-- Off at start (hlchunk's indent module is not even created when enable = false, so there is no
-- :EnableHLIndent yet: the first press sets it up from the plugin's own opts with enable = true).
map("n", "<leader>uI", function()
  if vim.g.hlchunk_indent_enabled == true then
    vim.g.hlchunk_indent_enabled = false
    vim.cmd("DisableHLIndent")
    return
  end
  if vim.fn.exists(":EnableHLIndent") == 2 then
    vim.cmd("EnableHLIndent")
  else
    require("lazy").load({ plugins = { "hlchunk.nvim" } })
    local o = require("lazy.core.plugin").values(require("lazy.core.config").plugins["hlchunk.nvim"], "opts", false)
    require("hlchunk").setup({ indent = vim.tbl_extend("force", o.indent or {}, { enable = true }) })
  end
  vim.g.hlchunk_indent_enabled = true
end, { desc = "Toggle indent guides" })

-- ── Undo / Redo (VS Code style) ──────────────────────────────────────
-- Ctrl+Z natively suspends nvim (job control) — remap it to undo instead,
-- since that's a footgun for VS Code muscle memory and suspend is rarely useful.
map("n", "<C-z>", "u", { desc = "Undo" })
map("n", "<C-S-z>", "<C-r>", { desc = "Redo" })
map("i", "<C-z>", "<C-o>u", { desc = "Undo" })
map("i", "<C-S-z>", "<C-o><C-r>", { desc = "Redo" })
-- Visual mode wasn't covered above — fell through to the native <C-z>
-- suspend (SIGTSTP), which backgrounds the whole nvim process (looks like a
-- crash/close, session stuck stale until the job is killed or `fg`'d back).
-- Plain "u" would also be wrong here: in Visual mode "u" means lowercase the
-- selection, not undo — hence <Esc> first to drop back to Normal mode.
map("v", "<C-z>", "<Esc>u", { desc = "Undo" })
map("v", "<C-S-z>", "<Esc><C-r>", { desc = "Redo" })

-- ── Folding (VS Code style; native vim folds, zM/zR already do this) ──────
-- Kitty's keyboard protocol (auto-negotiated by nvim over TERM=xterm-kitty)
-- reports Alt+Shift+symbol as the base key + explicit Shift modifier
-- (<A-S-->, <A-S-=>) rather than the resolved shifted glyph (<A-_>, <A-+>).
-- Both are genuinely distinct key codes, so bind every form as a fallback.
map("n", "<A-_>", "zM", { desc = "Collapse all folds", remap = true })
map("n", "<A-->", "zM", { desc = "Collapse all folds", remap = true })
map("n", "<A-S-->", "zM", { desc = "Collapse all folds", remap = true })
map("n", "<A-+>", "zR", { desc = "Expand all folds", remap = true })
map("n", "<A-=>", "zR", { desc = "Expand all folds", remap = true })
map("n", "<A-S-=>", "zR", { desc = "Expand all folds", remap = true })

-- ── Full-file inline diff (whole file, all hunks at once, no split) ───────
-- gitsigns' own <leader>ghp / preview_hunk_inline() only previews one hunk
-- near the cursor and auto-clears on cursor move. The old toggle_deleted()
-- showed every hunk's removed lines inline throughout the whole buffer at
-- once and stayed on until toggled off — that's still the only whole-buffer
-- inline option gitsigns has, but the function wrapper itself is deprecated
-- upstream (gitsigns/actions.lua). The underlying show_deleted config field
-- it flipped isn't deprecated, so set that directly and force a redraw.
map("n", "<leader>ghi", function()
  local config = require("gitsigns.config").config
  config.show_deleted = not config.show_deleted
  require("gitsigns").refresh()
end, { desc = "Toggle inline diff (whole file, no split)" })

-- ── Go to line (VS Code style) ──────────────────────────────────────
map("n", "<C-g>", function()
  vim.ui.input({ prompt = "Go to line: " }, function(input)
    local line = tonumber(input)
    if line then
      vim.api.nvim_win_set_cursor(0, { math.min(line, vim.api.nvim_buf_line_count(0)), 0 })
    end
  end)
end, { desc = "Go to line" })

-- ── Colorscheme picker override (LazyVim core binds <leader>uC to this same
-- call minus ignore_builtins) — hides Vim's stock built-in colorschemes
-- (zaibatsu, delek, elflord, industry, morning, pablo, peachpuff, quiet,
-- retrobox, ron, shine, torte, zellner, etc.) from the picker; never used them.
map("n", "<leader>uC", function()
  require("telescope.builtin").colorscheme({
    enable_preview = true,
    ignore_builtins = true,
  })
end, { desc = "Colorscheme with Preview" })
