-- :Nv4JSpringUpdate [version|latest|prerelease] [--check] [--verify] : install a Spring Boot language server version
-- from OpenVSX without Mason (Mason pins the registry's 2.2.0, and cannot install a pre-release: see
-- specs/features/spring-language-server.md "Updating the server"). Loaded only when the command runs (never at startup,
-- never from :Nv4JHealth, which only reads the cache file this module writes). The network is `curl` run in the
-- background with timeouts: the editor never blocks, a failure is one message.
-- Installs go side by side into <data>/spring-ls/<version>/ (nv4j/spring.lua managed_*), the old one stays: switching
-- back is `:Nv4JSpringUpdate <old>` (no download). Check: tests/checks/114_spring_update.lua.
local M = {}

M.API = "https://open-vsx.org/api/VMware/vscode-spring-boot"
M.CURL_TIMEOUT = 30 -- seconds, API calls
M.DOWNLOAD_TIMEOUT = 600 -- seconds, the 80 MB vsix

-- ── versions ──────────────────────────────────────────────────────────────

--- "2.5.2026111900" -> { 2, 5, 2026111900 }; nil when it is not dotted numbers (aliases like "latest").
function M.parse(v)
  if type(v) ~= "string" then return nil end
  local out = {}
  for part in v:gmatch("[^%.]+") do
    if not part:match("^%d+$") then return nil end
    out[#out + 1] = tonumber(part)
  end
  return #out >= 2 and out or nil
end

--- Numeric ordering; -1, 0, 1, or nil when either is not a version.
function M.compare(a, b)
  local pa, pb = M.parse(a), M.parse(b)
  if not pa or not pb then return nil end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x < y and -1 or 1 end
  end
  return 0
end

--- Spring Tools names its pre-releases <major>.<minor>.<yyyymmddhh>: a 10-digit third part. Only a cheap first filter:
--- the API's `preRelease` flag decides (stable_from).
function M.looks_prerelease(v)
  local p = M.parse(v)
  return p ~= nil and (p[3] or 0) >= 1000000
end

--- Versions of the API answer (`allVersions` keys minus the aliases), newest first.
function M.versions(api)
  local out = {}
  for k in pairs(type(api) == "table" and type(api.allVersions) == "table" and api.allVersions or {}) do
    if M.parse(k) then out[#out + 1] = k end
  end
  table.sort(out, function(a, b) return M.compare(a, b) == 1 end)
  return out
end

--- Newest version including pre-releases: the answer's own `version` (OpenVSX's `latest` alias already is that).
function M.newest(api)
  local v = type(api) == "table" and api.version
  if M.parse(v) then return v end
  return M.versions(api)[1]
end

--- Newest stable version. `flag(v)` returns the `preRelease` flag of one version (the caller fetched it; nil = not
--- fetched yet). Returns the version, or nil plus the next candidate to look up (the caller fetches it and calls again).
function M.stable_from(api, flag)
  if type(api) == "table" and api.preRelease == false and M.parse(api.version) then return api.version end
  for _, v in ipairs(M.versions(api)) do
    if not M.looks_prerelease(v) then
      local f = flag(v)
      if f == false then return v end
      if f == nil then return nil, v end
    end
  end
end

--- Reads a target word: "latest" (newest stable), "prerelease", "2.4.1" (exact); empty = `g` (vim.g.nv4j_spring_version) or latest.
function M.channel(arg, g)
  arg = (arg and arg ~= "") and arg or g
  if arg == nil or arg == "" or arg == "latest" then return "latest" end
  if arg == "prerelease" then return "prerelease" end
  if M.parse(arg) then return "exact", arg end
  return nil
end

-- ── command lines (pure) ──────────────────────────────────────────────────

function M.api_url(version) return M.API .. (version and ("/" .. version) or "") end
function M.vsix_url(v) return ("%s/%s/file/VMware.vscode-spring-boot-%s.vsix"):format(M.API, v, v) end
function M.sha_url(v) return ("%s/%s/file/VMware.vscode-spring-boot-%s.sha256"):format(M.API, v, v) end

function M.curl_cmd(url, out)
  local c = { "curl", "-fsSL", "--connect-timeout", "10", "--max-time", tostring(out and M.DOWNLOAD_TIMEOUT or M.CURL_TIMEOUT) }
  if out then vim.list_extend(c, { "-o", out }) end
  c[#c + 1] = url
  return c
end

function M.unzip_cmd(vsix, dest) return { "unzip", "-q", "-o", vsix, "-d", dest } end

-- ── state files ───────────────────────────────────────────────────────────

--- Replaceable in checks.
function M.state_file() return vim.fn.stdpath("state") .. "/spring-ls-lookup.json" end

--- Cached lookup written by the last :Nv4JSpringUpdate: { checked = os.time(), stable = , prerelease = } or nil.
function M.cached()
  local f = io.open(M.state_file(), "r")
  if not f then return nil end
  local ok, d = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and type(d) == "table" and d or nil
end

local function save_cache(stable, pre)
  vim.fn.mkdir(vim.fn.fnamemodify(M.state_file(), ":h"), "p")
  local f = io.open(M.state_file(), "w")
  if f then f:write(vim.json.encode({ checked = os.time(), stable = stable, prerelease = pre })) f:close() end
end

-- ── async plumbing ────────────────────────────────────────────────────────

--- Replaceable in checks: run(argv, cb(code, stdout, stderr)); vim.system with a timeout, never blocks.
function M.run(argv, cb)
  local ok, err = pcall(vim.system, argv, { text = true, timeout = (M.DOWNLOAD_TIMEOUT + 30) * 1000 }, vim.schedule_wrap(function(r)
    cb(r.code, r.stdout or "", r.stderr or "")
  end))
  if not ok then vim.schedule(function() cb(127, "", tostring(err)) end) end
end

--- Replaceable in checks.
function M.notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Nv4J" }) end

--- One error message; the existing install and the `current` pointer are untouched by every failure path.
local function fail(what, code, err)
  local why = vim.trim(err or ""):sub(1, 200)
  if code == 28 then why = "timed out" end
  if code == 127 then why = "curl, unzip or sha256sum is not installed" end
  M.notify(("Spring LS update failed: %s (exit %s%s). Nothing was changed."):format(what, tostring(code), why ~= "" and (": " .. why) or ""), vim.log.levels.ERROR)
end

--- GET one API document as a table: cb(table); on failure the message is printed and cb is not called.
local function get_json(url, what, cb)
  M.run(M.curl_cmd(url), function(code, out, err)
    if code ~= 0 then return fail("cannot reach OpenVSX for " .. what, code, err) end
    local ok, d = pcall(vim.json.decode, out)
    if not ok or type(d) ~= "table" then return fail("OpenVSX answered something that is not JSON for " .. what, code, out:sub(1, 80)) end
    cb(d)
  end)
end

--- Looks up the newest stable and pre-release version; cb(stable, prerelease). Caches both.
function M.lookup(cb)
  get_json(M.api_url(), "the version list", function(api)
    local pre = M.newest(api)
    local flags, offset = {}, 100
    local function step()
      local v, ask = M.stable_from(api, function(x) return flags[x] end)
      if not v and not ask and offset < 500 then
        -- `allVersions` is only the newest 100 and the pre-releases come every few days: older pages (max 100 each), a few at most
        local at = offset
        offset = offset + 100
        return get_json(M.api_url() .. "/versions?size=100&offset=" .. at, "the older version list", function(d)
          local list = type(d.versions) == "table" and d.versions or {}
          api.allVersions = vim.tbl_extend("force", api.allVersions or {}, list)
          if next(list) == nil then offset = 500 end
          step()
        end)
      end
      if v or not ask then
        save_cache(v, pre)
        return cb(v, pre)
      end
      get_json(M.api_url(ask), "version " .. ask, function(d)
        flags[ask] = d.preRelease == true
        step()
      end)
    end
    step()
  end)
end

-- ── install ───────────────────────────────────────────────────────────────

--- A vsix unzipped at `dir` must hold the server jar and the bundles listed in its package.json. Returns ok, reason.
function M.valid_extension(dir)
  local jar = vim.fn.glob(dir .. "/extension/language-server/*-exec.jar", false, true)[1]
  if not jar then return false, "no language-server/*-exec.jar in the package" end
  local f = io.open(dir .. "/extension/package.json", "r")
  if not f then return false, "no extension/package.json in the package" end
  local ok, pkg = pcall(vim.json.decode, f:read("*a"))
  f:close()
  local rel = ok and type(pkg) == "table" and pkg.contributes and pkg.contributes.javaExtensions
  if type(rel) ~= "table" or #rel == 0 then return false, "package.json lists no javaExtensions" end
  for _, r in ipairs(rel) do
    if not vim.uv.fs_stat(dir .. "/extension/" .. r:gsub("^%./", "")) then return false, "missing bundle " .. r end
  end
  return true
end

--- Download, SHA-256 check, unzip into <root>/<v>.part, validate, rename to <root>/<v>. The existing installs and the
--- `current` pointer are never touched; any failure removes the partial files. cb(ok).
function M.install(version, cb)
  local root = require("nv4j.spring").managed_root()
  local dest, part, vsix = root .. "/" .. version, root .. "/" .. version .. ".part", root .. "/" .. version .. ".vsix"
  if vim.uv.fs_stat(dest .. "/extension") then return cb(true) end
  vim.fn.mkdir(root, "p")
  local function clean() vim.fn.delete(part, "rf") vim.fn.delete(vsix) end
  local function stop(...) clean() fail(...) cb(false) end
  clean()
  M.notify(("Spring LS %s: downloading (about 80 MB) in the background..."):format(version))
  M.run(M.curl_cmd(M.vsix_url(version), vsix), function(code, _, err)
    if code ~= 0 then return stop("download of " .. version, code, err) end
    M.run(M.curl_cmd(M.sha_url(version)), function(c2, out)
      local want = c2 == 0 and out:match("%f[%x]" .. ("%x"):rep(64) .. "%f[%X]") or nil
      local function unpack()
        M.run(M.unzip_cmd(vsix, part), function(c3, _, e3)
          if c3 ~= 0 then return stop("unzip of " .. version, c3, e3) end
          local ok, why = M.valid_extension(part)
          if not ok then return stop(version .. " is not a usable Spring LS (" .. why .. ")", 1) end
          if not vim.uv.fs_rename(part, dest) then return stop("could not move the install into place", 1) end
          vim.fn.delete(vsix)
          cb(true)
        end)
      end
      if not want then return unpack() end -- no checksum published: the HTTPS download stands
      M.run({ "sha256sum", vsix }, function(c4, o4)
        if c4 ~= 0 or not o4:lower():find(want:lower(), 1, true) then
          return stop(("SHA-256 of %s does not match OpenVSX's"):format(version), c4 == 0 and 1 or c4)
        end
        unpack()
      end)
    end)
  end)
end

--- Makes `version` the one Neovim uses at its next start.
function M.activate(version)
  local root = require("nv4j.spring").managed_root()
  vim.fn.mkdir(root, "p")
  local f = assert(io.open(root .. "/current", "w"))
  f:write(version .. "\n")
  f:close()
end

--- tests/lib/verify_spring.sh in the repo that holds the config (nvim/ is the repo's nvim dir), or nil.
function M.verify_script()
  local cfg = vim.uv.fs_realpath(vim.fn.stdpath("config")) or vim.fn.stdpath("config")
  local p = vim.fs.normalize(cfg .. "/../tests/lib/verify_spring.sh")
  return vim.uv.fs_stat(p) and p or nil
end

-- ── the command ───────────────────────────────────────────────────────────

local function switch(old, new, old_source)
  M.activate(new)
  M.notify(("Spring LS %s -> %s. Restart Neovim to use it (the Spring LS and its jdt.ls bundles load once per session). Back: :Nv4JSpringUpdate %s")
    :format(old or "none", new, old_source == "mason" and "mason" or old or "mason"))
end

--- `:Nv4JSpringUpdate mason`: use the Mason package again (removes the `current` pointer; managed installs stay on disk).
function M.use_mason()
  local root = require("nv4j.spring").managed_root()
  vim.fn.delete(root .. "/current")
  M.notify("Spring LS: back to the Mason package. Restart Neovim to use it.")
end

M.VERIFY_MINUTES = "15 to 25"

--- args: the command's fargs.
function M.run_command(args)
  local sp = require("nv4j.spring")
  local target, verify, check
  for _, a in ipairs(args or {}) do
    if a == "--verify" then verify = true
    elseif a == "--check" then check = true
    elseif a:sub(1, 2) == "--" then return M.notify("Nv4JSpringUpdate: unknown flag " .. a .. " (--check, --verify)", vim.log.levels.WARN)
    else target = a end
  end
  if target == "mason" then return M.use_mason() end
  local cur = sp.installed_version()
  local old = cur and cur.version
  local kind, exact = M.channel(target, vim.g.nv4j_spring_version)
  if not kind then
    return M.notify("Nv4JSpringUpdate: use a version like 2.4.1, or latest (newest stable), or prerelease (newest incl. pre-release)", vim.log.levels.WARN)
  end

  local function go(version)
    if version == old then return M.notify("Spring LS " .. version .. " is already the one in use.") end
    if not verify then
      if M.looks_prerelease(version) then
        M.notify(("%s is a pre-release and is installed without the Spring checks (--verify runs them first: %s minutes)"):format(version, M.VERIFY_MINUTES), vim.log.levels.WARN)
      end
      return M.install(version, function(ok)
        if ok then switch(old, version, cur and cur.source) end
      end)
    end
    local script = M.verify_script()
    if not script then
      return M.notify("Nv4JSpringUpdate --verify needs the Nv4J repo (tests/lib/verify_spring.sh next to nvim/): not found. Update without --verify.", vim.log.levels.ERROR)
    end
    M.notify(("Verifying Spring LS %s with checks 50, 51, 52, 80, 82 in the background (%s minutes; the editor stays usable)..."):format(version, M.VERIFY_MINUTES))
    M.run({ script, version }, function(code, out)
      if code == 0 then
        M.notify("Spring LS " .. version .. " passed the Spring checks.")
        switch(old, version, cur and cur.source)
      else
        local lines = vim.tbl_filter(function(l) return l:match("^FAIL") or l:match("^DONE") end, vim.split(out, "\n"))
        M.notify(("Spring LS %s FAILED verification: not switched, %s stays.\n%s"):format(version, old or "the previous server", table.concat(vim.list_slice(lines, 1, 8), "\n")), vim.log.levels.ERROR)
      end
    end)
  end

  if kind == "exact" and not check then return go(exact) end -- no lookup needed
  M.lookup(function(stable, pre)
    M.notify(("Spring LS: installed %s%s; newest stable %s; newest pre-release %s"):format(old or "none", cur and (" (" .. cur.source .. ")") or "", stable or "?", pre or "?"))
    if check then return end
    local v = kind == "exact" and exact or (kind == "latest" and stable or pre)
    if not v then return fail("no " .. kind .. " version found in the OpenVSX answer", 1) end
    go(v)
  end)
end

return M
