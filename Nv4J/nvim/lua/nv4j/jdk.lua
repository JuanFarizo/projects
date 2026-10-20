-- JDK discovery for nv4j. Pure directory scan plus `release` files: never shells out to `java`
-- (here `java` is a lazy-loading SDKMAN shell function and JAVA_HOME is often empty).
local M = {}

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function real(p) return vim.uv.fs_realpath(p) or p end

--- Directories whose children are JDKs, in priority order. NV4J_JDK_ROOT (":"-separated, tests
--- only) replaces the whole list.
function M.roots()
  local env = vim.env.NV4J_JDK_ROOT
  if env and env ~= "" then return vim.split(env, ":", { plain = true, trimempty = true }) end
  local sdk = (vim.env.SDKMAN_DIR and vim.env.SDKMAN_DIR ~= "") and vim.env.SDKMAN_DIR or vim.fn.expand("~/.sdkman")
  return {
    sdk .. "/candidates/java",
    vim.fn.expand("~/Library/Java/JavaVirtualMachines"),
    "/Library/Java/JavaVirtualMachines",
  }
end

--- Parse "25.0.2" / "1.8.0_452" / "21" into major, version-key table.
local function parse_version(v)
  local key = {}
  for n in v:gmatch("%d+") do key[#key + 1] = tonumber(n) end
  if key[1] == 1 and key[2] then table.remove(key, 1) end -- 1.8.0 -> 8.0
  return key[1], key
end

--- Describe a JDK home dir, or nil if it is not one.
local function describe(home)
  if not vim.uv.fs_stat(home .. "/bin/java") then return nil end
  local rel = read(home .. "/release")
  local ver = rel and rel:match('JAVA_VERSION="([^"]+)"')
  if not ver then return nil end
  local major, key = parse_version(ver)
  if not major then return nil end
  return { home = home, real = real(home), major = major, version = ver, key = key }
end

local function newer(a, b)
  for i = 1, math.max(#a.key, #b.key) do
    local x, y = a.key[i] or 0, b.key[i] or 0
    if x ~= y then return x > y end
  end
  return a.home < b.home
end

--- All JDKs found, newest first (duplicates by real path removed). Each: {home, major, version, key}.
function M.discover()
  local out, seen = {}, {}
  for _, root in ipairs(M.roots()) do
    for name, kind in vim.fs.dir(root) do
      if name ~= "current" and (kind == "directory" or kind == "link") then
        local d = describe(root .. "/" .. name) or describe(root .. "/" .. name .. "/Contents/Home")
        if d and not seen[d.real] then
          seen[d.real] = true
          out[#out + 1] = d
        end
      end
    end
  end
  table.sort(out, newer)
  return out
end

local function java_home_jdk()
  local jh = vim.env.JAVA_HOME
  if jh and jh ~= "" then return describe(jh) end
end

local function sdkman_current_real()
  if vim.env.NV4J_JDK_ROOT and vim.env.NV4J_JDK_ROOT ~= "" then return nil end
  local sdk = (vim.env.SDKMAN_DIR and vim.env.SDKMAN_DIR ~= "") and vim.env.SDKMAN_DIR or vim.fn.expand("~/.sdkman")
  return vim.uv.fs_realpath(sdk .. "/candidates/java/current")
end

--- JDK jdtls itself runs on (needs >= 21): $JAVA_HOME if it is >= 21, else the newest >= 21.
--- Errors with an actionable message if there is none.
---@return string home
function M.server_home()
  local jh = java_home_jdk()
  if jh and jh.major >= 21 then return jh.home end
  for _, d in ipairs(M.discover()) do
    if d.major >= 21 then return d.home end
  end
  error(("nv4j: no JDK >= 21 found for jdtls. Searched: %s. JAVA_HOME=%s. Install one, e.g. `sdk install java 25-amzn` "
    .. "or the Corretto 25 pkg (~/Library/Java/JavaVirtualMachines)."):format(
    table.concat(M.roots(), ", "), tostring(vim.env.JAVA_HOME)), 0)
end

--- Java major the project asks for: .sdkmanrc java=, then pom release / java.version / source.
function M.project_major(root)
  local rc = root and read(root .. "/.sdkmanrc")
  local v = rc and rc:match("\njava%s*=%s*([%d%.]+)") or (rc and rc:match("^java%s*=%s*([%d%.]+)"))
  if v then return (parse_version(v)), ".sdkmanrc" end
  local pom = root and read(root .. "/pom.xml")
  if pom then
    pom = pom:gsub("<!%-%-.-%-%->", "")
    local function prop(name)
      local val = pom:match("<" .. name:gsub("%.", "%%.") .. ">%s*([^<%s]+)%s*</")
      if val and val:match("^%${(.+)}$") then val = prop(val:match("^%${(.+)}$")) end
      return val
    end
    for _, name in ipairs({ "maven.compiler.release", "java.version", "maven.compiler.source" }) do
      local val = prop(name)
      if val and val:match("^[%d%.]+$") then return (parse_version(val)), "pom " .. name end
    end
  end
end

local function rt_name(major) return major == 8 and "JavaSE-1.8" or ("JavaSE-" .. major) end

--- java.configuration.runtimes for a project root: one entry per discovered major (>= 8),
--- JAVA_HOME's / SDKMAN current's JDK preferred for its major, `default=true` on the project's
--- requested major, else JAVA_HOME's, else the newest.
---@return table[] runtimes, number|nil default_major
function M.runtimes(root)
  local all = M.discover()
  if #all == 0 then M.server_home() end -- raises the clear error
  local jh, cur = java_home_jdk(), sdkman_current_real()
  local by_major, order = {}, {}
  for _, d in ipairs(all) do
    if d.major >= 8 then
      local prefer = (jh and d.real == jh.real) or (cur and d.real == cur)
      local have = by_major[d.major]
      if not have then
        by_major[d.major] = d
        order[#order + 1] = d.major
      elseif prefer and not (have.preferred) then
        by_major[d.major] = d
      end
      if prefer then by_major[d.major].preferred = true end
    end
  end
  local want = M.project_major(root)
  local default = (want and by_major[want] and want) or (jh and by_major[jh.major] and jh.major) or order[1]
  local rts = {}
  for _, m in ipairs(order) do
    rts[#rts + 1] = { name = rt_name(m), path = by_major[m].home, default = (m == default) or nil }
  end
  return rts, default
end

return M
