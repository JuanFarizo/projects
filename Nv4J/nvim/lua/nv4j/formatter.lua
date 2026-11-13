-- Java formatter profiles + :Nv4JFormatter (specs/features/formatter.md). Formatting stays on demand (<leader>cf, jdt.ls); this
-- module only chooses WHICH Eclipse formatter XML jdt.ls uses (java.format.settings.url). Every profile is an Eclipse XML:
--   intellij (default) : an approximation of IntelliJ's defaults, the Lua table below, written to stdpath("data")/nv4j/formatter/
--   eclipse            : no url = jdt.ls's built-in profile
--   google             : Google's eclipse-java-google-style.xml, pinned, downloaded once into stdpath("data")/nv4j/formatter/
--   <path>             : the user's own XML (absolute, ~, or relative to the project root)
-- Precedence: `format_profile` in the project's .nv4j > the choice saved by :Nv4JFormatter (global) > vim.g.nv4j_format_profile > "intellij".
-- `:Nv4JFormatter <profile> --project` writes .nv4j (asks before creating it), `--global` (default) the state file.
-- Zero startup cost: required when a jdt.ls config is built (first Java file) or when the command runs. No process, no network
-- except the one-time google download (curl, SHA-256 checked, same pattern as nv4j/decompile.lua).
local M = {}

M.DEFAULT = "intellij"
M.NAMES = { "intellij", "eclipse", "google" }

--- Google's file: dropped from google/styleguide on 2026-10-14 (commit 355ad72, "use google-java-format plugins"), so the URL is the
--- last commit that still had it (eaa0a05). SHA-256 computed on a real download 2026-11-13. Licence: CC-BY 3.0 (the repo's LICENSE).
M.GOOGLE = {
  sha256 = "e75524bb67e3ffc88d5c680ed75254e072e3dbccbb91c4a0c708dcfabf2bdf91",
  url = "https://raw.githubusercontent.com/google/styleguide/eaa0a05ec282e893ba314f1e6aeb9ef9f6674249/eclipse-java-google-style.xml",
  profile = "GoogleStyle",
  licence = "CC-BY 3.0",
}

--- The few settings of the intellij profile that differ from jdt.ls's built-in one (everything else stays at the Eclipse default).
M.INTELLIJ_NAME = "Nv4J-IntelliJ"
M.INTELLIJ = {
  ["tabulation.char"] = "space",
  ["tabulation.size"] = "4",
  ["indentation.size"] = "4",
  ["lineSplit"] = "120",
  ["comment.line_length"] = "120",
  ["continuation_indentation"] = "2", -- 2 x 4 = 8 spaces, IntelliJ's continuation indent
  ["continuation_indentation_for_array_initializer"] = "2",
  ["number_of_empty_lines_to_preserve"] = "2", -- IntelliJ keeps up to 2 blank lines
  ["join_wrapped_lines"] = "true", -- re-wrap at the margin, as IntelliJ does
  ["comment.format_javadoc_comments"] = "true",
  ["comment.format_block_comments"] = "false", -- IntelliJ does not re-wrap block or line comments by default
  ["comment.format_line_comments"] = "false",
  ["alignment_for_arguments_in_method_invocation"] = "16", -- wrap where necessary
  ["alignment_for_parameters_in_method_declaration"] = "16",
  ["alignment_for_binary_expression"] = "16",
  ["alignment_for_conditional_expression"] = "80",
  ["alignment_for_selector_in_method_invocation"] = "80", -- chained calls: wrap all elements except the first, if needed
}

-- Replaceable in tests.
M.spawn = function(cmd, opts, on_exit) return vim.system(cmd, opts, on_exit) end
M.notify = function(msg, level) vim.notify(msg, level or vim.log.levels.WARN, { title = "Nv4J" }) end
M.data_dir = function() return vim.fn.stdpath("data") .. "/nv4j/formatter" end
M.state_file = function() return vim.fn.stdpath("state") .. "/nv4j/formatter.json" end
function M.intellij_path() return M.data_dir() .. "/intellij.xml" end
function M.google_path() return M.data_dir() .. "/eclipse-java-google-style.xml" end

local install_state

function M.reset_for_tests() install_state = nil end

--- The intellij profile as Eclipse formatter XML.
function M.xml()
  local keys = vim.tbl_keys(M.INTELLIJ)
  table.sort(keys)
  local out = { '<?xml version="1.0" encoding="UTF-8" standalone="no"?>', '<profiles version="21">',
    ('<profile kind="CodeFormatterProfile" name="%s" version="21">'):format(M.INTELLIJ_NAME) }
  for _, k in ipairs(keys) do
    out[#out + 1] = ('<setting id="org.eclipse.jdt.core.formatter.%s" value="%s"/>'):format(k, M.INTELLIJ[k])
  end
  out[#out + 1] = "</profile>"
  out[#out + 1] = "</profiles>"
  return table.concat(out, "\n") .. "\n"
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

--- Writes the intellij XML when missing or different. Returns the path.
function M.ensure_intellij()
  local p, want = M.intellij_path(), M.xml()
  if read(p) ~= want then
    vim.fn.mkdir(M.data_dir(), "p")
    local f = assert(io.open(p, "wb"))
    f:write(want)
    f:close()
  end
  return p
end

--- Saved choice (global), or nil.
function M.saved()
  local s = read(M.state_file())
  if not s then return nil end
  local ok, d = pcall(vim.json.decode, s)
  if ok and type(d) == "table" and type(d.profile) == "string" and d.profile ~= "" then return d.profile end
end

function M.save(profile)
  vim.fn.mkdir(vim.fs.dirname(M.state_file()), "p")
  local f = assert(io.open(M.state_file(), "wb"))
  f:write(vim.json.encode({ profile = profile }))
  f:close()
end

--- Effective profile for a project root, where it came from, and the file that holds it (nil for default / vim.g).
---@return string profile, string source ".nv4j" | "saved" | "vim.g.nv4j_format_profile" | "default", string|nil file
function M.resolve(root)
  local fp = root and require("nv4j.settings").load(root).format_profile
  if type(fp) == "string" and fp ~= "" then return fp, ".nv4j", root .. "/" .. require("nv4j.root").project_marker end
  local s = M.saved()
  if s then return s, "saved", M.state_file() end
  local g = vim.g.nv4j_format_profile
  if type(g) == "string" and g ~= "" then return g, "vim.g.nv4j_format_profile" end
  return M.DEFAULT, "default"
end

--- Absolute path of a user profile: `~` expanded, absolute kept, relative joined to the project root (cwd when none).
--- No vim.fn.expand: it would also expand `#`, `%` and wildcards of a file name.
function M.path_of(profile, root)
  local p = vim.trim(profile):gsub("^[\"'](.*)[\"']$", "%1")
  p = vim.fs.normalize(p)
  if p:sub(1, 1) ~= "/" then p = (root or vim.fn.getcwd()) .. "/" .. p end
  return vim.fs.normalize(p)
end

--- First profile name and the value of one setting of an Eclipse formatter XML text.
local function xml_info(text)
  local name = text:match('<profile[^>]-name="([^"]*)"')
  local function get(k) return text:match('id="org%.eclipse%.jdt%.core%.formatter%.' .. k:gsub("%.", "%%.") .. '"%s+value="([^"]*)"') end
  return name, get
end

--- The jdt.ls `java.format.settings` table of a profile: { url = <file URL>|nil, profile = <name>|nil }. url nil = built-in.
--- nil, reason when the profile cannot be used (google not downloaded, path missing, a directory, not an Eclipse formatter XML).
--- The table also carries `indent` = { size, expandtab } when the XML says so (see M.sync_indent).
function M.settings_of(profile, root)
  if profile == "eclipse" then return { url = nil, profile = nil } end
  if profile == "intellij" then
    return { url = vim.uri_from_fname(M.ensure_intellij()), profile = M.INTELLIJ_NAME, indent = { size = 4, expandtab = true } }
  end
  local p, name = nil, nil
  if profile == "google" then
    p, name = M.google_path(), M.GOOGLE.profile
    if not vim.uv.fs_stat(p) then return nil, "google profile not downloaded yet (" .. p .. ")" end
  else
    p = M.path_of(profile, root)
    local st = vim.uv.fs_stat(p)
    if not st then return nil, "formatter file not found: " .. p end
    if st.type ~= "file" then return nil, "not a file (" .. st.type .. "): " .. p end
  end
  local text = read(p)
  if not text then return nil, "cannot read " .. p end
  local fname, get = xml_info(text)
  if profile ~= "google" then
    if not fname then return nil, "not an Eclipse formatter XML (no <profile name=...>): " .. p end
    name = fname
  end
  local s = { url = vim.uri_from_fname(p), profile = name }
  local size = tonumber(get("tabulation.size") or "")
  local char = get("tabulation.char")
  if size and char then s.indent = { size = size, expandtab = char == "space" } end
  return s
end

--- jdt.ls formats with the indent the CLIENT sends (textDocument/formatting options.tabSize / insertSpaces, from the buffer's
--- 'shiftwidth' and 'expandtab'), and those override the profile's tabulation settings: Google's 2 spaces came out as 4. So Java
--- buffers attached to jdt.ls follow the profile's indent. eclipse (no indent in the profile) puts the buffer's own values back.
function M.sync_buffer(buf, profile_settings)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local bo = vim.bo[buf]
  local orig = vim.b[buf].nv4j_indent_orig
  local ind = profile_settings and profile_settings.indent
  if ind then
    if not orig then
      vim.b[buf].nv4j_indent_orig = { sw = bo.shiftwidth, ts = bo.tabstop, sts = bo.softtabstop, et = bo.expandtab }
    end
    bo.shiftwidth, bo.tabstop, bo.softtabstop, bo.expandtab = ind.size, ind.size, ind.size, ind.expandtab
  elseif orig then
    bo.shiftwidth, bo.tabstop, bo.softtabstop, bo.expandtab = orig.sw, orig.ts, orig.sts, orig.et
    vim.b[buf].nv4j_indent_orig = nil
  end
end

--- Value for config.settings.java.format.settings when a jdt.ls starts: falls back to the built-in profile with a warning.
function M.start_settings(root)
  local profile, source = M.resolve(root)
  local s, why = M.settings_of(profile, root)
  if not s then
    M.notify(("Formatter profile '%s' (%s) unusable: %s. jdt.ls uses its built-in profile."):format(profile, source, why))
    if profile == "google" then M.install() end
    s = { url = nil, profile = nil }
  end
  return s
end

--- Called from the jdt.ls LspAttach: the buffer's indent follows the effective profile.
function M.on_attach(buf, client)
  local profile = M.resolve(client.config.root_dir)
  local s = M.settings_of(profile, client.config.root_dir)
  if s then M.sync_buffer(buf, s) end
end

--- Downloads the pinned google XML once. cb(ok, msg).
function M.install(cb)
  cb = cb or function() end
  local p = M.google_path()
  if vim.uv.fs_stat(p) then install_state = "done"; return cb(true, "already installed: " .. p) end
  if install_state == "running" then return cb(false, "download already running") end
  if install_state == "failed" then return cb(false, "download failed earlier in this session (restart to retry)") end
  if vim.fn.executable("curl") ~= 1 then install_state = "failed"; return cb(false, "curl not found") end
  install_state = "running"
  vim.fn.mkdir(M.data_dir(), "p")
  local tmp = p .. ".part"
  M.notify(("Downloading Google's Java formatter profile (once, 36 KB, %s) to %s"):format(M.GOOGLE.licence, M.data_dir()), vim.log.levels.INFO)
  M.spawn({ "curl", "-fsSL", "--max-time", "60", "-o", tmp, M.GOOGLE.url }, { timeout = 70000 }, function(out)
    vim.schedule(function()
      local function fail(msg)
        pcall(vim.uv.fs_unlink, tmp)
        install_state = "failed"
        M.notify("Google formatter profile not installed: " .. msg)
        cb(false, msg)
      end
      if out.code ~= 0 then return fail(("curl exit %d %s"):format(out.code, vim.trim(out.stderr or ""))) end
      local data = read(tmp)
      if not data then return fail("downloaded file unreadable") end
      local got = vim.fn.sha256(data)
      if got ~= M.GOOGLE.sha256 then return fail(("SHA-256 mismatch (got %s, expected %s)"):format(got, M.GOOGLE.sha256)) end
      local ok, err = os.rename(tmp, p)
      if not ok then return fail("rename: " .. tostring(err)) end
      install_state = "done"
      cb(true, p)
    end)
  end)
end

local function jdtls_clients() return vim.lsp.get_clients({ name = "jdtls" }) end

--- Pushes the effective profile of every running jdt.ls (its own project root) with workspace/didChangeConfiguration, no restart,
--- and syncs the indent of the Java buffers attached to it. Returns the number of clients notified.
function M.apply()
  local n = 0
  for _, c in ipairs(jdtls_clients()) do
    local root = c.config.root_dir
    local profile = M.resolve(root)
    local s, why = M.settings_of(profile, root)
    if not s then
      M.notify(("%s: %s; formatter unchanged"):format(profile, why))
    else
      local st = c.config.settings or {}
      st.java = st.java or {}
      st.java.format = st.java.format or {}
      -- vim.NIL is sent as null: back to jdt.ls's default for that key
      st.java.format.settings = { url = s.url or vim.NIL, profile = s.profile or vim.NIL }
      c.config.settings = st
      c:notify("workspace/didChangeConfiguration", { settings = st })
      for b in pairs(vim.lsp.get_buffers_by_client_id(c.id)) do M.sync_buffer(b, s) end
      n = n + 1
    end
  end
  return n
end

local NAMES_HINT = "intellij, eclipse, google or an Eclipse XML path"

--- The project root of the current buffer (a real file), else of the cwd. nil when none.
local function current_root()
  local b = vim.api.nvim_buf_get_name(0)
  local real = b ~= "" and vim.bo.buftype == "" and not b:find("^%w[%w+.-]*://")
  local path = real and b or vim.fn.getcwd()
  local ok, r = pcall(function() return (require("nv4j.root").project(path)) end)
  return ok and r or nil
end

--- One line saying what is effective and where it comes from (and the global choice when another source wins).
function M.status(root)
  local profile, source, file = M.resolve(root)
  local line = ("Java formatter: %s (from %s%s)"):format(profile, source, file and (": " .. file) or "")
  local g = M.saved()
  if g and source ~= "saved" then line = line .. ("; global choice %s in %s"):format(g, M.state_file()) end
  return line
end

--- The save step: scope "project" writes `format_profile` into root/.nv4j (asks before creating the file), "global" writes
--- the state file. Then applies to running jdt.ls and says exactly where it was saved.
function M.finish(choice, scope, root)
  local function done()
    local n = M.apply()
    local profile, source, file = M.resolve(root)
    local where
    if scope == "project" then
      where = ("saved to %s (this project only)"):format(root .. "/" .. require("nv4j.root").project_marker)
    else
      where = ("saved globally in %s (every project without its own format_profile)"):format(M.state_file())
    end
    local msg = ("Formatter profile '%s' %s. Effective here: %s (from %s%s). %s"):format(choice, where, profile, source,
      file and (": " .. file) or "", n > 0 and ("%d jdt.ls updated, no restart."):format(n) or "No jdt.ls running: applies when one starts.")
    if scope == "global" and source == ".nv4j" then
      msg = msg .. (" NOTE: this project's .nv4j sets format_profile=%s and wins; use `:Nv4JFormatter %s --project` to change it."):format(profile, choice)
    end
    M.notify(msg, vim.log.levels.INFO)
  end
  if scope == "project" then
    if not root then return M.notify("--project: no project root (open a file of the project first)") end
    if require("nv4j.root").home_or_above(root) then return M.notify("--project refused: the project root is home or above: " .. root) end
    local marker = root .. "/" .. require("nv4j.root").project_marker
    local function write(create)
      local _, err = require("nv4j.settings").set(root, "format_profile", choice, create)
      if err then return M.notify("Formatter profile not saved: " .. err) end
      done()
    end
    if vim.uv.fs_stat(marker) then return write(false) end
    return vim.ui.select({ "Yes, create " .. marker, "No" }, { prompt = (".nv4j does not exist in this project. Create it with format_profile=%s?"):format(choice) }, function(item)
      if item and item:sub(1, 3) == "Yes" then write(true) else M.notify("Formatter profile not saved (no .nv4j created).") end
    end)
  end
  local ok, err = pcall(M.save, choice)
  if not ok then return M.notify("Formatter profile not saved: " .. tostring(err)) end
  done()
end

--- Validates a profile (downloading google when needed) and saves it. cb-free; every failure is one notification.
function M.switch(choice, scope, root)
  choice = vim.trim(choice or "")
  if choice == "" then return M.notify("No formatter profile given: " .. NAMES_HINT) end
  local store = choice
  local s, why = M.settings_of(choice, root)
  if not s and choice == "google" then
    return M.install(function(ok, msg)
      if ok then M.switch(choice, scope, root) else M.notify("google: " .. msg) end
    end)
  end
  if not s then
    if not vim.tbl_contains(M.NAMES, choice) and not choice:find("[/\\.~]") then
      why = ("unknown profile '%s': use %s (%s)"):format(choice, NAMES_HINT, why)
    end
    return M.notify(why)
  end
  -- a path saved globally is stored absolute (a relative one would resolve against whichever project is open); in .nv4j it stays as typed
  if not vim.tbl_contains(M.NAMES, choice) and scope ~= "project" then store = M.path_of(choice, root) end
  M.finish(store, scope, root)
end

local function pick_scope(root, cb)
  local marker = root and (root .. "/" .. require("nv4j.root").project_marker)
  local items = {}
  if marker then items[#items + 1] = "This project (.nv4j): " .. marker end
  items[#items + 1] = "Global (all projects): " .. M.state_file()
  vim.ui.select(items, { prompt = "Save the choice where?" }, function(item)
    if not item then return end
    cb(item:sub(1, 4) == "This" and "project" or "global")
  end)
end

--- Feeds the cmdline so the path is typed with the native file completion (Enter always submits; the ui.input popup swallowed it).
M.feed = function(text) vim.api.nvim_feedkeys(vim.keycode(":" .. text), "n", false) end

--- :Nv4JFormatter [profile] [--project|--global]
--- no args: shows the current profile + source + file, then two steps: where to save (project .nv4j / global), which profile.
function M.command(args)
  args = args or {}
  local root = current_root()
  local scope, prof
  for _, a in ipairs(args) do
    if a == "--project" or a == "-p" then scope = "project"
    elseif a == "--global" or a == "-g" then scope = "global"
    elseif a:sub(1, 2) == "--" then return M.notify(("unknown option %s (use --project or --global)"):format(a))
    elseif not prof then prof = a
    else prof = prof .. " " .. a end -- an unquoted path with spaces
  end
  if prof then return M.switch(prof, scope or "global", root) end
  M.notify(M.status(root), vim.log.levels.INFO)
  local function choose_profile(sc)
    vim.ui.select(vim.list_extend(vim.deepcopy(M.NAMES), { "path" }), {
      prompt = ("Java formatter profile (save: %s):"):format(sc == "project" and ".nv4j" or "global"),
    }, function(choice)
      if not choice then return end
      if choice == "path" then
        -- scheduled: the picker that called us is still closing
        return vim.schedule(function() M.feed(("Nv4JFormatter --%s "):format(sc)) end)
      end
      M.switch(choice, sc, root)
    end)
  end
  if scope then return choose_profile(scope) end
  pick_scope(root, choose_profile)
end

return M
