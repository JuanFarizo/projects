-- Java formatter profiles + :Nv4JFormatter (specs/features/formatter.md). Formatting stays on demand (<leader>cf, jdt.ls); this
-- module only chooses WHICH Eclipse formatter XML jdt.ls uses (java.format.settings.url). Every profile is an Eclipse XML:
--   intellij (default) : an approximation of IntelliJ's defaults, the Lua table below, written to stdpath("data")/nv4j/formatter/
--   eclipse            : no url = jdt.ls's built-in profile
--   google             : Google's eclipse-java-google-style.xml, pinned, downloaded once into stdpath("data")/nv4j/formatter/
--   <path>             : the user's own XML (absolute, or relative to the project root)
-- Precedence: `format_profile` in the project's .nv4j > the choice saved by :Nv4JFormatter > vim.g.nv4j_format_profile > "intellij".
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

--- Effective profile for a project root and where it came from.
---@return string profile, string source ".nv4j" | "saved" | "vim.g.nv4j_format_profile" | "default"
function M.resolve(root)
  local fp = root and require("nv4j.settings").load(root).format_profile
  if type(fp) == "string" and fp ~= "" then return fp, ".nv4j" end
  local s = M.saved()
  if s then return s, "saved" end
  local g = vim.g.nv4j_format_profile
  if type(g) == "string" and g ~= "" then return g, "vim.g.nv4j_format_profile" end
  return M.DEFAULT, "default"
end

--- Absolute path of a user profile (absolute, or relative to the project root).
function M.path_of(profile, root)
  local p = vim.fn.expand(profile)
  if p:sub(1, 1) ~= "/" then p = (root or vim.fn.getcwd()) .. "/" .. p end
  return vim.fs.normalize(p)
end

--- The jdt.ls `java.format.settings` table of a profile: { url = <file URL>|nil, profile = <name>|nil }. url nil = built-in.
--- nil, reason when the profile cannot be used yet (google not downloaded, path missing).
function M.settings_of(profile, root)
  if profile == "eclipse" then return { url = nil, profile = nil } end
  if profile == "intellij" then return { url = vim.uri_from_fname(M.ensure_intellij()), profile = M.INTELLIJ_NAME } end
  if profile == "google" then
    local p = M.google_path()
    if not vim.uv.fs_stat(p) then return nil, "google profile not downloaded yet (" .. p .. ")" end
    return { url = vim.uri_from_fname(p), profile = M.GOOGLE.profile }
  end
  local p = M.path_of(profile, root)
  if not vim.uv.fs_stat(p) then return nil, "formatter file not found: " .. p end
  return { url = vim.uri_from_fname(p), profile = nil }
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

--- Pushes the effective profile of every running jdt.ls (its own project root) with workspace/didChangeConfiguration, no restart.
--- Returns the number of clients notified.
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
      n = n + 1
    end
  end
  return n
end

--- :Nv4JFormatter [profile]
function M.command(args)
  local root
  local b = vim.api.nvim_buf_get_name(0)
  if b ~= "" then root = (require("nv4j.root").project(b)) end
  local function switch(choice)
    if choice == nil or choice == "" then return end
    if choice == "path" then
      return vim.ui.input({ prompt = "Eclipse formatter XML (absolute, or relative to the project root): ", completion = "file" }, function(p)
        if p and p ~= "" then switch(p) end
      end)
    end
    local s, why = M.settings_of(choice, root)
    local function finish()
      M.save(choice)
      local profile, source = M.resolve(root)
      local n = M.apply()
      M.notify(("Formatter profile: %s (saved). Effective here: %s from %s. %d jdt.ls updated, no restart."):format(choice, profile, source, n), vim.log.levels.INFO)
    end
    if s then return finish() end
    if choice == "google" then
      return M.install(function(ok, msg)
        if ok then finish() else M.notify("google: " .. msg) end
      end)
    end
    M.notify(why)
  end
  if args and args[1] and args[1] ~= "" then return switch(args[1]) end
  local profile, source = M.resolve(root)
  vim.ui.select(vim.list_extend(vim.deepcopy(M.NAMES), { "path" }), {
    prompt = ("Java formatter: %s (from %s). Choose:"):format(profile, source),
  }, switch)
end

return M
