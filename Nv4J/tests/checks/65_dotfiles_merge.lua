-- D26 dotfiles merge. Run via tests/run.sh. Spec: specs/001-architecture.md D26. Code: nvim/lua/config/keymaps.lua,
-- config/autocmds.lua, util/ai.lua, plugins/{ai,claudecode,sidekick,hlchunk,markdown,mini-align,ts-autotag,which_key}.lua,
-- lazyvim.json (extras markdown, prettier). Deterministic and headless; no jdt.ls (the startup case opens a plain text file), no network, no real Claude.
--  terminal_key   : <C-/> and <C-_> (n and t) are LazyVim core's terminal toggle (map defined in lazyvim/config/keymaps.lua,
--                   not a comment); <C-j> is window navigation (LazyVim), no Nv4J map; the terminal "tabs" keys (<C-t>,
--                   <D-]>, <D-[> in terminal mode) are still there.
--  comment_key    : <D-/> exists in n, x and i with the comment behaviour; gcc comments a line of a scratch buffer, <D-/>
--                   in normal and insert mode comments/uncomments it and the insert cursor stays on its character.
--  keep_nv4j_keys : <leader>co stays LazyVim's Organize Imports (jdtls extra definition; no global map), <leader>cO is
--                   outgoing calls, <leader>tp is Nv4J's project tests.
--  ai_keys        : every <leader>a* key of the dotfiles (aa ap ac ak as ab ar aC am af ay an), the which-key group
--                   "AI agents", util.ai loads, sidekick.cli and claudecode are NOT loaded at startup.
--  indent_one     : snacks indent and scope disabled (spec and runtime), hlchunk present, <leader>uI toggles
--                   vim.g.hlchunk_indent_enabled, never two indent providers at once.
--  markdown       : render-markdown spec, markview and markdown-preview disabled, <leader>cp / <leader>um in a markdown
--                   buffer, extras markdown + prettier in lazyvim.json, vim.g.autoformat still false.
--  not_ported     : smear-cursor, mini.animate, vtsls, snacks image, nvim-lint luacheck are not in the plugin list / spec;
--                   no lang.typescript extra; ts-autotag only for html and xml.
--  startup        : REPORT-ONLY: median of 3 `nvim --startuptime` runs on a plain text file, so no jdt.ls (PASS with the ms; FAIL only if
--                   the time cannot be read). The new plugins must not be loaded in it.
--  claude_restore : VimLeavePre autocmd registered (group nv4j_claude_panel) and writes the state file under
--                   stdpath("state"); a state file with cwd=true makes restore_panel call ClaudeCodeOpen (command stubbed),
--                   cwd=false does not.
local lsp = require("lsp")
local P = "65_dotfiles_merge."
local ROOT = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

-- keymaps and autocmds load on VeryLazy, after -c commands: load them now (require caches them, so LazyVim's own load
-- later is a no-op). LazyVim's own defaults first (that is where <C-/> lives), then the user file.
pcall(require, "lazyvim.config.keymaps")
pcall(require, "config.keymaps")

-- which of the new plugins are loaded right after startup (the cases below load some of them)
local loaded0 = {}
for _, m in ipairs({ "sidekick", "claudecode", "hlchunk", "render-markdown", "mini.align" }) do
  if package.loaded[m] then loaded0[#loaded0 + 1] = m end
end

local function map(lhs, mode, buf)
  local m
  if buf then
    vim.api.nvim_buf_call(buf, function() m = vim.fn.maparg(lhs, mode, false, true) end)
  else
    m = vim.fn.maparg(lhs, mode, false, true)
  end
  return m
end
local function src(m)
  local cb = m.callback
  if not cb then return "" end
  local i = debug.getinfo(cb, "S")
  return i and i.source or ""
end
local function plugin_opts(name)
  local pl = require("lazy.core.config").plugins[name]
  if not pl then return nil end
  return require("lazy.core.plugin").values(pl, "opts", false)
end
local function plugin_names()
  local t = {}
  for name in pairs(require("lazy.core.config").plugins) do t[#t + 1] = name end
  return t
end
local function has_plugin(name) return require("lazy.core.config").plugins[name] ~= nil end

-- ── terminal_key ─────────────────────────────────────────────────────────────────────────────────
do
  local details, ok = {}, true
  for _, lhs in ipairs({ "<C-/>", "<C-_>" }) do
    for _, mode in ipairs({ "n", "t" }) do
      local m = map(lhs, mode)
      local is_core = m.callback ~= nil and src(m):find("lazyvim/config/keymaps.lua", 1, true) ~= nil
      local is_comment = (m.rhs or ""):find("gc") ~= nil or (m.desc or ""):lower():find("comment") ~= nil
      ok = ok and is_core and not is_comment
      details[#details + 1] = ("%s[%s] desc=%s src=%s"):format(lhs, mode, tostring(m.desc), src(m):match("[^/]*/[^/]*/[^/]*$") or "none")
    end
  end
  local cj = map("<C-j>", "n")
  local cjt = map("<C-j>", "t")
  local j_nav = (cj.desc or ""):find("Lower Window") ~= nil and (cj.rhs or ""):lower() == "<c-w>j"
  ok = ok and j_nav and next(cjt) == nil
  details[#details + 1] = ("<C-j>[n] desc=%s rhs=%s, [t] %s"):format(tostring(cj.desc), tostring(cj.rhs), next(cjt) and "mapped" or "unmapped")
  local tabs = {}
  for _, lhs in ipairs({ "<C-t>", "<D-]>", "<D-[>" }) do
    local m = map(lhs, "t")
    tabs[#tabs + 1] = lhs .. "=" .. tostring(m.desc)
    ok = ok and m.callback ~= nil
  end
  details[#details + 1] = "terminal tabs: " .. table.concat(tabs, ", ")
  lsp.report(P .. "terminal_key", ok, table.concat(details, "; "))
end

-- ── comment_key ──────────────────────────────────────────────────────────────────────────────────
do
  local ok_all, err = pcall(function()
    local kn, kx, ki = map("<D-/>", "n"), map("<D-/>", "x"), map("<D-/>", "i")
    local keys_ok = (kn.rhs or "") == "gcc" and (kx.rhs or "") == "gc" and ki.callback ~= nil
      and kn.desc == "Toggle comment" and kx.desc == "Toggle comment" and ki.desc == "Toggle comment"
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "java"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "int a = 1;", "int b = 2;" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal gcc")
    local gcc = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    local gcc_ok = gcc:find("^//") ~= nil
    vim.cmd("normal gcc") -- back to plain
    -- <D-/> through its mapping (feedkeys with remap, "x" = execute now)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.api.nvim_feedkeys(vim.keycode("<D-/>"), "mx", false)
    local nline = vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]
    local n_ok = nline:find("^//") ~= nil
    -- insert mode: the callback comments the line and keeps the cursor on the same character
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "int a = 1;" })
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    ki.callback()
    local iline = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local i_ok = iline:find("^//") ~= nil and iline:sub(col + 1, col + 1) == "a"
    -- visual
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "int a = 1;", "int b = 2;" })
    vim.cmd("normal ggVj")
    vim.api.nvim_feedkeys(vim.keycode("<D-/>"), "mx", false)
    local x_lines = vim.api.nvim_buf_get_lines(buf, 0, 2, false)
    local x_ok = x_lines[1]:find("^//") ~= nil and x_lines[2]:find("^//") ~= nil
    vim.cmd("stopinsert")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    lsp.report(P .. "comment_key", keys_ok and gcc_ok and n_ok and i_ok and x_ok,
      ("<D-/> n/x/i mapped %s (n=%s x=%s i=%s); gcc -> %q; <D-/> normal -> %q; insert -> %q cursor col %d on %q; visual -> %q / %q")
        :format(tostring(keys_ok), tostring(kn.rhs), tostring(kx.rhs), kn.desc and "fn" or "nil", gcc, nline, iline, col,
          iline:sub(col + 1, col + 1), x_lines[1], x_lines[2]))
  end)
  if not ok_all then lsp.report(P .. "comment_key", false, "error: " .. tostring(err)) end
end

-- ── keep_nv4j_keys ───────────────────────────────────────────────────────────────────────────────
do
  local lazyvim_java = vim.fn.stdpath("data") .. "/lazy/LazyVim/lua/lazyvim/plugins/extras/lang/java.lua"
  local text = table.concat(vim.fn.readfile(lazyvim_java), "\n")
  local organize_def = text:find('"<leader>co", require("jdtls").organize_imports, desc = "Organize Imports"', 1, true) ~= nil
  local other = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_set_current_buf(other)
  local co = map("<leader>co", "n")
  local cO = map("<leader>cO", "n")
  local tp = map("<leader>tp", "n")
  pcall(vim.api.nvim_buf_delete, other, { force = true })
  local co_ok = organize_def and next(co) == nil -- no global <leader>co: Java buffers only, from the jdtls extra
  local cO_ok = cO.desc == "Outgoing calls" and cO.callback ~= nil
  local tp_ok = (tp.desc or ""):find("Test project", 1, true) ~= nil and src(tp):find("nv4j/tests.lua", 1, true) ~= nil
  lsp.report(P .. "keep_nv4j_keys", co_ok and cO_ok and tp_ok,
    ("<leader>co: jdtls extra defines Organize Imports %s, global map %s (want none); <leader>cO desc=%s; <leader>tp desc=%s src=%s")
      :format(tostring(organize_def), next(co) and tostring(co.desc) or "none", tostring(cO.desc), tostring(tp.desc), src(tp):match("[^/]*/[^/]*$") or "none"))
end

-- ── ai_keys ──────────────────────────────────────────────────────────────────────────────────────
do
  local want = { "aa", "ap", "ac", "ak", "as", "ab", "ar", "aC", "am", "af", "ay", "an" }
  local missing = {}
  -- lazy.nvim creates these from the plugins' `keys` (snacks.nvim ai.lua, claudecode.nvim): the handler holds them
  local active = {}
  for _, pl in pairs(require("lazy.core.config").plugins) do
    for _, k in pairs(((pl._ or {}).handlers or {}).keys or {}) do active[k.lhs] = k end
  end
  for _, k in ipairs(want) do
    local lhs = "<leader>" .. k
    local m = map(lhs, "n")
    local mx = map(lhs, "x")
    if next(m) == nil and next(mx) == nil and not active[lhs] then missing[#missing + 1] = k end
  end
  local wk = plugin_opts("which-key.nvim")
  local group = false
  for _, s in ipairs(wk and wk.spec or {}) do
    if s[1] == "<leader>a" and s.group == "AI agents" then group = true end
  end
  local ok_util, ai = pcall(require, "util.ai")
  local providers = ok_util and ai.providers.claude ~= nil and ai.providers.cursor ~= nil
  local lazy_ok = package.loaded["sidekick.cli"] == nil and package.loaded["claudecode"] == nil
  lsp.report(P .. "ai_keys", #missing == 0 and group and providers and lazy_ok,
    ("missing keys: %s; which-key group 'AI agents' %s; util.ai providers claude+cursor %s; sidekick.cli loaded %s, claudecode loaded %s (want both false)")
      :format(#missing == 0 and "none" or table.concat(missing, ","), tostring(group), tostring(providers),
        tostring(package.loaded["sidekick.cli"] ~= nil), tostring(package.loaded["claudecode"] ~= nil)))
end

-- ── indent_one ───────────────────────────────────────────────────────────────────────────────────
do
  local ok_all, err = pcall(function()
    local so = plugin_opts("snacks.nvim") or {}
    local spec_off = (so.indent or {}).enabled == false and (so.scope or {}).enabled == false
    local snacks_cfg = require("snacks").config
    local run_off = not (snacks_cfg.indent and snacks_cfg.indent.enabled) and not (snacks_cfg.scope and snacks_cfg.scope.enabled)
    local present = has_plugin("hlchunk.nvim")
    require("lazy").load({ plugins = { "hlchunk.nvim" } })
    local m = map("<leader>uI", "n")
    vim.g.hlchunk_indent_enabled = nil
    m.callback()
    local after1 = vim.g.hlchunk_indent_enabled
    local on_cmd = vim.fn.exists(":DisableHLIndent") == 2 -- the module exists once it was switched on
    m.callback()
    local after2 = vim.g.hlchunk_indent_enabled
    local hl = plugin_opts("hlchunk.nvim") or {}
    local hl_indent_default = (hl.indent or {}).enable
    -- never two providers: with snacks off, hlchunk indent is the only one (and off by default)
    local both = (not run_off) and (hl_indent_default == true or after1 == true)
    vim.g.hlchunk_indent_enabled = nil
    lsp.report(P .. "indent_one", spec_off and run_off and present and m.desc == "Toggle indent guides"
      and after1 == true and on_cmd and after2 == false and not both,
      ("snacks indent/scope disabled in spec %s, at runtime %s; hlchunk present %s; <leader>uI desc=%s, toggles nil->%s->%s (want true, false; :DisableHLIndent exists after the first %s); hlchunk indent default %s (off); both providers %s")
        :format(tostring(spec_off), tostring(run_off), tostring(present), tostring(m.desc), tostring(after1), tostring(after2), tostring(on_cmd),
          tostring(hl_indent_default), tostring(both)))
  end)
  if not ok_all then lsp.report(P .. "indent_one", false, "error: " .. tostring(err)) end
end

-- ── markdown ─────────────────────────────────────────────────────────────────────────────────────
do
  local ok_all, err = pcall(function()
    local cfg = require("lazy.core.config")
    local present = has_plugin("render-markdown.nvim")
    -- markview is keyed by its short name in the disabled table
    local mv_off = cfg.spec.disabled["markview.nvim"] ~= nil and not has_plugin("markview.nvim")
    local mp_off = cfg.spec.disabled["markdown-preview.nvim"] ~= nil and not has_plugin("markdown-preview.nvim")
    local lj = vim.json.decode(table.concat(vim.fn.readfile(ROOT .. "/nvim/lazyvim.json"), "\n"))
    local extras = table.concat(lj.extras, " ")
    local extras_ok = extras:find("lang.markdown", 1, true) and extras:find("formatting.prettier", 1, true)
    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "markdown"
    vim.wait(2000, function() return map("<leader>cp", "n", buf).buffer == 1 end, 20)
    local cp, um = map("<leader>cp", "n", buf), map("<leader>um", "n", buf)
    local keys_ok = cp.buffer == 1 and (cp.rhs or ""):find("RenderMarkdown", 1, true) ~= nil and um.desc ~= nil
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    lsp.report(P .. "markdown", present and mv_off and mp_off and extras_ok and keys_ok and vim.g.autoformat == false,
      ("render-markdown present %s; markview disabled %s; markdown-preview disabled %s; extras markdown+prettier %s; <leader>cp in markdown buffer: buffer=%s rhs=%s; <leader>um desc=%s; vim.g.autoformat=%s")
        :format(tostring(present), tostring(mv_off), tostring(mp_off), tostring(extras_ok ~= nil), tostring(cp.buffer), tostring(cp.rhs),
          tostring(um.desc), tostring(vim.g.autoformat)))
  end)
  if not ok_all then lsp.report(P .. "markdown", false, "error: " .. tostring(err)) end
end

-- ── not_ported ───────────────────────────────────────────────────────────────────────────────────
do
  local found = {}
  for _, name in ipairs(plugin_names()) do
    local l = name:lower()
    if l:find("smear", 1, true) or l:find("mini.animate", 1, true) or l:find("vtsls", 1, true) then found[#found + 1] = name end
  end
  local so = plugin_opts("snacks.nvim") or {}
  if so.image and so.image.enabled then found[#found + 1] = "snacks image enabled" end
  local nl = plugin_opts("nvim-lint") or {}
  for ft, linters in pairs(nl.linters_by_ft or {}) do
    if vim.tbl_contains(linters, "luacheck") then found[#found + 1] = "nvim-lint luacheck for " .. ft end
  end
  local lc = plugin_opts("nvim-lspconfig") or {}
  if lc.servers and lc.servers.vtsls then found[#found + 1] = "vtsls server" end
  local lj = table.concat(vim.fn.readfile(ROOT .. "/nvim/lazyvim.json"), "\n")
  if lj:find("typescript", 1, true) or lj:find("mini-animate", 1, true) then found[#found + 1] = "lazyvim.json extra" end
  local at = require("lazy.core.config").plugins["nvim-ts-autotag"]
  local at_ft = at and at.ft or {}
  local ft_ok = #at_ft == 2 and vim.tbl_contains(at_ft, "html") and vim.tbl_contains(at_ft, "xml")
  lsp.report(P .. "not_ported", #found == 0 and ft_ok,
    ("found (want none): %s; nvim-ts-autotag ft = %s (want html, xml)"):format(#found == 0 and "none" or table.concat(found, ", "), table.concat(at_ft, ",")))
end

-- ── startup (report-only) ────────────────────────────────────────────────────────────────────────
do
  -- a plain text file: a Java file would start jdt.ls in each child nvim and could leave a process behind
  local file = "/tmp/nv4j/65-startup-" .. vim.fn.getpid() .. ".txt"
  vim.fn.writefile({ "startup probe" }, file)
  local out = "/tmp/nv4j/logs/65-startuptime-" .. vim.fn.getpid() .. ".txt"
  local ms = {}
  for _ = 1, 3 do
    vim.fn.delete(out)
    pcall(vim.fn.system, { "nvim", "--headless", "--startuptime", out, file, "+qa!" })
    local lines = vim.fn.filereadable(out) == 1 and vim.fn.readfile(out) or {}
    for j = #lines, 1, -1 do
      local t = lines[j]:match("^%s*(%d+%.%d+)")
      if t then ms[#ms + 1] = tonumber(t) break end
    end
  end
  vim.fn.delete(out)
  vim.fn.delete(file)
  table.sort(ms)
  local med = ms[2]
  lsp.report(P .. "startup", med ~= nil and #ms == 3,
    ("median %s ms of %d runs (%s), report-only; new plugins loaded at startup of this session: %s"):format(tostring(med), #ms,
      table.concat(vim.tbl_map(function(x) return ("%.0f"):format(x) end, ms), "/"), #loaded0 == 0 and "none" or table.concat(loaded0, ",")))
end

-- ── claude_restore ───────────────────────────────────────────────────────────────────────────────
do
  local ok_all, err = pcall(function()
    pcall(require, "config.autocmds")
    local ai = require("util.ai")
    local sf = ai.state_file()
    local under_state = vim.startswith(sf, vim.fn.stdpath("state") .. "/")
    -- the user's real state file is never touched: the state path is moved to a temp dir under /tmp/nv4j
    local tmpdir = "/tmp/nv4j/65-state-" .. vim.fn.getpid()
    vim.fn.mkdir(tmpdir, "p")
    ai.state_path = tmpdir .. "/claudecode_sessions.json"
    local real_sf = sf
    sf = ai.state_file()
    local au = vim.api.nvim_get_autocmds({ event = "VimLeavePre", group = "nv4j_claude_panel" })
    local cwd = vim.fn.getcwd()
    local function state() return ai.read_state()[cwd] end
    -- save side: stubbed claudecode.terminal
    local orig_term = package.loaded["claudecode.terminal"]
    package.loaded["claudecode.terminal"] = { get_active_terminal_bufnr = function() return 7 end }
    vim.api.nvim_exec_autocmds("VimLeavePre", { group = "nv4j_claude_panel" })
    local s_open = state()
    package.loaded["claudecode.terminal"] = { get_active_terminal_bufnr = function() return nil end }
    vim.api.nvim_exec_autocmds("VimLeavePre", { group = "nv4j_claude_panel" })
    local s_closed = state()
    package.loaded["claudecode.terminal"] = orig_term
    -- restore side: stubbed :ClaudeCodeOpen
    local calls = 0
    vim.api.nvim_create_user_command("ClaudeCodeOpen", function() calls = calls + 1 end, { force = true })
    ai.write_state({ [cwd] = true })
    ai.restore_panel()
    vim.wait(1000, function() return calls > 0 end, 10)
    local with_true = calls
    ai.write_state({ [cwd] = false })
    ai.restore_panel()
    vim.wait(200)
    local with_false = calls - with_true
    -- a failing :ClaudeCodeOpen (plugin missing) must not raise at startup
    vim.api.nvim_create_user_command("ClaudeCodeOpen", function() error("boom") end, { force = true })
    ai.write_state({ [cwd] = true })
    vim.v.errmsg = ""
    local raised_ok = pcall(ai.restore_panel)
    vim.wait(300)
    local quiet = raised_ok and vim.v.errmsg == ""
    local temp_ok = vim.startswith(sf, "/tmp/nv4j/") and sf ~= real_sf
    ai.state_path = nil
    vim.fn.delete(tmpdir, "rf")
    local detail = ("autocmd nv4j_claude_panel VimLeavePre registered %s; default state file %s (under stdpath state %s), test used %s; saved open=%s closed=%s; restore with cwd=true calls ClaudeCodeOpen %d x (want 1), cwd=false %d x (want 0)")
      :format(tostring(#au == 1), real_sf, tostring(under_state), sf, tostring(s_open), tostring(s_closed), with_true, with_false)
    lsp.report(P .. "claude_restore", #au == 1 and under_state and s_open == true and s_closed == false and with_true == 1 and with_false == 0 and quiet and temp_ok, detail .. ("; failing ClaudeCodeOpen raises nothing %s (errmsg %q)"):format(tostring(quiet), vim.v.errmsg))
  end)
  if not ok_all then lsp.report(P .. "claude_restore", false, "error: " .. tostring(err)) end
end

lsp.finish()
