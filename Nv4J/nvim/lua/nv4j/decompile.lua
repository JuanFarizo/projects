-- Library navigation into a class without sources: jdt.ls's bundled Fernflower is the primary decompiler (it fills every
-- `jdt://` buffer, nothing to configure). This module is the BACKUP: CFR, run only when Fernflower gave nothing (empty
-- content) or marked a method it could not decompile (`// $FF: Couldn't be decompiled`), and on demand (:Nv4JDecompile cfr).
-- Costs nothing at startup and when idle: it is required the first time a `jdt://` buffer opens (plugins/java.lua wraps
-- nvim-jdtls's open_classfile), CFR is never loaded into jdt.ls, it runs as a separate short-lived `java -jar` (vim.system,
-- 20 s timeout) on the JDK nv4j.jdk found for jdt.ls, output cached in memory per jar!class for the session.
-- The jar is one pinned release from Maven Central (CFR below), downloaded once, on first need or by :Nv4JInstallCfr, into
-- stdpath("data")/nv4j/tools/, SHA-256 checked against the value recorded here before it is kept. Upgrading = edit CFR.
-- Spec: specs/features/library-navigation.md. Check: tests/checks/95_library_nav.lua.
local M = {}

--- One pinned release. Checksum = the `cfr-<version>.jar.sha256` Maven Central publishes next to the jar, verified on
--- 2026-11-10 against a fresh download (sha1 48ef4892cfe8feffddbbd0ff077735140557db74 as well). Licence from its POM: MIT.
M.CFR = {
  version = "0.152",
  sha256 = "f686e8f3ded377d7bc87d216a90e9e9512df4156e75b06c655a16648ae8765b2",
  url = "https://repo1.maven.org/maven2/org/benf/cfr/0.152/cfr-0.152.jar",
  licence = "MIT",
}

M.FERNFLOWER_HEADER = "// Source code is decompiled from a .class file using FernFlower decompiler (from Intellij IDEA)."
--- What Fernflower (this jdt.ls's 253.x) writes into a method body it could not decompile; the rest of the class is fine.
M.FF_FAILED = "// $FF: Couldn't be decompiled"
M.TIMEOUT_MS = 20000

--- Where the jar lives (same data dir as Mason, own folder).
function M.tools_dir() return vim.fn.stdpath("data") .. "/nv4j/tools" end
function M.jar_path() return M.tools_dir() .. "/cfr-" .. M.CFR.version .. ".jar" end

--- `java` of the JDK jdt.ls runs on (nv4j.jdk, never PATH). nil when there is none (jdk.server_home raises).
function M.java()
  local ok, home = pcall(function() return require("nv4j.jdk").server_home() end)
  return ok and (home .. "/bin/java") or nil
end

-- Replaceable in tests: the spawn (vim.system), the installer, the notifier.
M.spawn = function(cmd, opts, on_exit) return vim.system(cmd, opts, on_exit) end
M.notify = function(msg, level) vim.notify(msg, level or vim.log.levels.WARN, { title = "Nv4J" }) end

local cache = {} -- "jar!class" -> text
local warned_jar = false -- the "CFR jar missing" warning, once per session
local install_state -- nil | "running" | "done" | "failed"

function M.reset_for_tests() cache = {}; warned_jar = false; install_state = nil end

--- Is this buffer content a Fernflower failure? Empty (no non-blank line) or a `// $FF: Couldn't be decompiled` marker.
---@param lines string[]
---@return boolean, string|nil reason
function M.needs_fallback(lines)
  local blank = true
  for _, l in ipairs(lines or {}) do
    if l:find("%S") then blank = false end
    if l:find(M.FF_FAILED, 1, true) then return true, "Fernflower marked a method it could not decompile" end
  end
  if blank then return true, "jdt.ls returned no content" end
  return false
end

--- Jar path and binary class name out of a `jdt://contents/...` URI (no network, no jdt.ls). The URI ends with the JDT
--- handle: `...=/<jar path with \/>=/...=/%3Cpackage%28Name.class` (`<` = package fragment, `(` = class file). Returns nil
--- for a class that is not in a jar (JDK modules, folders).
---@param uri string
---@return { jar: string, class: string, name: string }|nil
function M.parse_uri(uri)
  if type(uri) ~= "string" or not uri:find("^jdt://contents/") then return nil end
  local q = uri:match("%?=(.*)$")
  if not q then return nil end
  q = q:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  -- segments separated by "=/": the first is "<project>/<escaped jar path>", the last "<pkg(Name.class"
  local first = q:match("^(.-)=/") or q
  local jar = first:match("^[^/]*/(.*)$")
  if not jar then return nil end
  jar = jar:gsub("\\/", "/")
  if not jar:find("%.jar$") then return nil end
  local pkg, file = q:match("<([^<(]*)%(([^(]+)%.class$")
  if not file then return nil end
  local class = (pkg ~= "" and (pkg .. ".") or "") .. file
  return { jar = jar, class = class, name = file }
end

--- The CFR command line for one class of a jar: CFR reads the jar itself and decompiles only the classes whose binary
--- name matches the filter (the class and its nested `Name$...` classes, which CFR folds into the outer one), to stdout.
function M.command(java, jar, class)
  local pat = "^" .. class:gsub("[%.%$]", "\\%0") .. "(\\$.*)?$"
  return { java, "-jar", M.jar_path(), jar, "--jarfilter", pat, "--silent", "true" }
end

--- Downloads the pinned jar once (curl, SHA-256 checked, then moved into place). cb(ok, msg). Never blocks, never
--- retries: a failed download in this session leaves install_state = "failed" and later needs just warn.
---@param cb? fun(ok: boolean, msg: string)
function M.install(cb)
  cb = cb or function() end
  local jar = M.jar_path()
  if vim.uv.fs_stat(jar) then install_state = "done"; return cb(true, "already installed: " .. jar) end
  if install_state == "running" then return cb(false, "download already running") end
  if install_state == "failed" then return cb(false, "download failed earlier in this session (restart to retry)") end
  if vim.fn.executable("curl") ~= 1 then install_state = "failed"; return cb(false, "curl not found") end
  install_state = "running"
  vim.fn.mkdir(M.tools_dir(), "p")
  local tmp = jar .. ".part"
  M.notify(("Downloading CFR %s (once, 2 MB, %s) to %s"):format(M.CFR.version, M.CFR.licence, M.tools_dir()), vim.log.levels.INFO)
  M.spawn({ "curl", "-fsSL", "--max-time", "120", "-o", tmp, M.CFR.url }, { timeout = 130000 }, function(out)
    vim.schedule(function()
      local function fail(msg)
        pcall(vim.uv.fs_unlink, tmp)
        install_state = "failed"
        M.notify("CFR not installed: " .. msg .. ". Retry with :Nv4JInstallCfr after a restart, or put the jar at " .. jar)
        cb(false, msg)
      end
      if out.code ~= 0 then return fail(("curl exit %d %s"):format(out.code, vim.trim(out.stderr or ""))) end
      local f = io.open(tmp, "rb")
      if not f then return fail("downloaded file unreadable") end
      local data = f:read("*a")
      f:close()
      local got = vim.fn.sha256(data)
      if got ~= M.CFR.sha256 then return fail(("SHA-256 mismatch (got %s, expected %s)"):format(got, M.CFR.sha256)) end
      local ok, err = os.rename(tmp, jar)
      if not ok then return fail("rename: " .. tostring(err)) end
      install_state = "done"
      M.notify("CFR " .. M.CFR.version .. " installed: " .. jar, vim.log.levels.INFO)
      cb(true, jar)
    end)
  end)
end

--- Decompiles `class` of `jar` with CFR, asynchronously. cb(text|nil, err|nil, how) where how = "cache" | "run".
--- A missing jar warns once (and starts the one-time download the first time; the result is not awaited: the user
--- re-runs :Nv4JDecompile cfr, or the next failing class gets it), no spawn. One process per call, never two for the
--- same class at once.
---@param jar string
---@param class string
---@param cb fun(text: string|nil, err: string|nil, how: string|nil)
function M.decompile(jar, class, cb)
  local key = jar .. "!" .. class
  if cache[key] then return cb(cache[key], nil, "cache") end
  local jarfile = M.jar_path()
  if not vim.uv.fs_stat(jarfile) then
    if not warned_jar then
      warned_jar = true
      M.notify(("CFR %s is not installed (%s): downloading it once in the background; nothing else happens until then"):format(M.CFR.version, jarfile))
      M.install()
    end
    return cb(nil, "CFR jar missing: " .. jarfile, nil)
  end
  local java = M.java()
  if not java then return cb(nil, "no JDK for CFR (nv4j.jdk found none)", nil) end
  if not vim.uv.fs_stat(jar) then return cb(nil, "jar not found: " .. jar, nil) end
  local t0 = vim.uv.hrtime()
  M.spawn(M.command(java, jar, class), { text = true, timeout = M.TIMEOUT_MS }, function(out)
    vim.schedule(function()
      local ms = (vim.uv.hrtime() - t0) / 1e6
      if out.code == 124 or out.signal == 15 then return cb(nil, ("CFR timed out after %d s"):format(M.TIMEOUT_MS / 1000), "run") end
      if out.code ~= 0 then return cb(nil, ("CFR exit %d: %s"):format(out.code, vim.trim(out.stderr or "")), "run") end
      local text = out.stdout or ""
      if not text:find("%S") then return cb(nil, "CFR produced no output for " .. class .. " (not in " .. jar .. "?)", "run") end
      cache[key] = text
      cb(text, nil, ("run %.0f ms"):format(ms))
    end)
  end)
end

--- Lines for the buffer: Nv4J's own first line, then CFR's output.
function M.header(reason) return ("// Decompiled with CFR %s (%s)"):format(M.CFR.version, reason) end
function M.lines_of(text, reason)
  local lines = vim.split((text:gsub("\r\n", "\n")), "\n", { plain = true })
  if lines[#lines] == "" then lines[#lines] = nil end
  table.insert(lines, 1, M.header(reason))
  return lines
end

local function set_lines(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

--- Replaces the buffer with CFR's output for the class of its `jdt://` name. cb(ok, msg) optional.
---@param buf integer
---@param reason string  "Fernflower failed" | "on demand"
---@param cb? fun(ok: boolean, msg: string)
function M.cfr_into(buf, reason, cb)
  cb = cb or function() end
  local uri = vim.api.nvim_buf_get_name(buf)
  local t = M.parse_uri(uri)
  if not t then return cb(false, "not a class in a jar: " .. uri) end
  M.decompile(t.jar, t.class, function(text, err, how)
    if not text then return cb(false, err) end
    set_lines(buf, M.lines_of(text, reason))
    cb(true, ("CFR %s: %s (%s)"):format(M.CFR.version, t.class, how))
  end)
end

--- After nvim-jdtls filled a `jdt://` buffer (plugins/java.lua wraps open_classfile): CFR only when Fernflower failed.
---@return boolean triggered
function M.after_open(buf, uri)
  if not (vim.api.nvim_buf_is_valid(buf) and type(uri) == "string" and uri:find("^jdt://")) then return false end
  local need, why = M.needs_fallback(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if not need then return false end
  if not M.parse_uri(uri) then return false end -- JDK module class: nothing CFR can read without the jar
  M.cfr_into(buf, "Fernflower failed", function(ok, msg)
    M.notify((ok and "%s: %s" or "CFR fallback failed: %s (%s)"):format(ok and why or msg, ok and msg or why), ok and vim.log.levels.INFO or vim.log.levels.WARN)
  end)
  return true
end

--- Asks jdt.ls for the content again (its own cache answers at once) and puts it in the buffer.
function M.fernflower_into(buf, cb)
  cb = cb or function() end
  local uri = vim.api.nvim_buf_get_name(buf)
  local client = vim.lsp.get_clients({ name = "jdtls" })[1]
  if not client then return cb(false, "no jdt.ls client") end
  client:request("java/classFileContents", { uri = uri }, function(err, result)
    if err or type(result) ~= "string" then return cb(false, "jdt.ls: " .. vim.inspect(err or result)) end
    local lines = vim.split((result:gsub("\r\n", "\n")), "\n", { plain = true })
    set_lines(buf, lines)
    cb(true, lines[1] and lines[1]:find("FernFlower", 1, true) and "Fernflower" or "jdt.ls content (sources)")
  end, buf)
end

--- :Nv4JDecompile [cfr|fernflower] on the current `jdt://` buffer.
function M.command_decompile(args)
  local which = args[1] or "cfr"
  local buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_get_name(buf):find("^jdt://") then return M.notify("Nv4JDecompile: not a jdt:// (library class) buffer") end
  local done = function(ok, msg) M.notify(msg, ok and vim.log.levels.INFO or vim.log.levels.WARN) end
  if which == "cfr" then
    M.cfr_into(buf, "on demand", done)
  elseif which == "fernflower" then
    M.fernflower_into(buf, done)
  else
    M.notify("Nv4JDecompile: cfr or fernflower")
  end
end

return M
