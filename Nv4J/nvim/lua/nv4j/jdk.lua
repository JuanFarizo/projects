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

--- Describe a JDK home dir, or nil if it is not one. The version comes from the `release` file;
--- JDKs without one (SDKMAN 8.x) fall back to the leading number of the directory name.
local function describe(home)
  if not vim.uv.fs_stat(home .. "/bin/java") then return nil end
  local rel = read(home .. "/release")
  local ver = rel and rel:match('JAVA_VERSION="([^"]+)"')
  if not ver then
    local name = vim.fs.basename(home)
    if name == "Home" then name = vim.fs.basename(vim.fs.dirname(vim.fs.dirname(home))) end
    ver = name:match("^%a*[%-_]?(%d+[%d%._]*)")
  end
  if not ver then return nil end
  local major, key = parse_version(ver)
  if not major then return nil end
  local ea = ver:lower():find("ea") ~= nil or vim.fs.basename(home):lower():find("[%-_.]ea") ~= nil
  return { home = home, real = real(home), major = major, version = ver, key = key, ea = ea }
end

local function newer(a, b)
  if a.ea ~= b.ea then return not a.ea end -- early-access builds sort last
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
  -- $JAVA_HOME's JDK counts even when it lives outside the scan roots (Homebrew, asdf, mise).
  local jh = vim.env.JAVA_HOME
  local d = jh and jh ~= "" and describe(jh)
  if d and not seen[d.real] then out[#out + 1] = d end
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
    if d.major >= 21 and not d.ea then return d.home end
  end
  error(("nv4j: no JDK >= 21 found for jdtls. Searched: %s. JAVA_HOME=%s. Install one, e.g. `sdk install java 25-amzn`."):format(
    table.concat(M.roots(), ", "), tostring(vim.env.JAVA_HOME)), 0)
end

--- Java majors the project asks for, in priority order: .sdkmanrc java=, then pom
--- maven.compiler.release, plugin <release>, java.version, maven.compiler.source, <source>,
--- maven.compiler.target, <target>. Only the project's own pom is read (no parent poms).
---@return integer[]
function M.project_majors(root)
  local out = {}
  local function add(v)
    local m = v and v:match("^[%d%.]+$") and parse_version(v)
    if m then out[#out + 1] = m end
  end
  local rc = root and read(root .. "/.sdkmanrc")
  if rc then add(("\n" .. rc):match("\njava%s*=%s*([%d%.]+)")) end
  local pom = root and read(root .. "/pom.xml")
  if pom then
    pom = pom:gsub("<!%-%-.-%-%->", "")
    local function prop(name, depth)
      if depth > 5 then return nil end
      local val = pom:match("<" .. name:gsub("%.", "%%.") .. ">%s*([^<%s]+)%s*</")
      local ref = val and val:match("^%${(.+)}$")
      if ref then return prop(ref, depth + 1) end
      return val
    end
    for _, name in ipairs({ "maven.compiler.release", "release", "java.version", "maven.compiler.source", "source",
      "maven.compiler.target", "target" }) do
      add(prop(name, 0))
    end
  end
  return out
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
  local default
  for _, want in ipairs(M.project_majors(root)) do
    if by_major[want] then default = want; break end
  end
  default = default or (jh and by_major[jh.major] and jh.major) or order[1]
  local rts = {}
  for _, m in ipairs(order) do
    rts[#rts + 1] = { name = rt_name(m), path = by_major[m].home, default = (m == default) or nil }
  end
  return rts, default
end

return M
