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

--- Comments removed from Groovy/Kotlin source, string literals kept. Returns the text and a table
--- `ins[i] = true` for bytes inside a string literal (so a keyword printed in a string is not a setting).
local function gradle_strip(src)
  local out, ins, n, i, len = {}, {}, 0, 1, #src
  local function push(ch, inside) n = n + 1; out[n] = ch; if inside then ins[n] = true end end
  while i <= len do
    local c, two, three = src:sub(i, i), src:sub(i, i + 1), src:sub(i, i + 2)
    if two == "//" then
      local e = src:find("\n", i, true)
      if not e then break end
      i = e
    elseif two == "/*" then
      local _, e = src:find("*/", i + 2, true)
      if not e then break end
      push(" ")
      i = e + 1
    elseif three == '"""' or three == "'''" then
      push(c); push(c); push(c)
      local _, e = src:find(three, i + 3, true)
      for j = i + 3, e and e - 3 or len do push(src:sub(j, j), true) end
      if not e then break end
      push(c); push(c); push(c)
      i = e + 1
    elseif c == '"' or c == "'" then
      push(c)
      local j = i + 1
      while j <= len do
        local d = src:sub(j, j)
        if d == "\\" then
          push(d, true); push(src:sub(j + 1, j + 1), true); j = j + 2
        elseif d == c then
          break
        elseif d == "\n" then
          j = j - 1 -- unterminated: a string does not span lines
          break
        else
          push(d, true); j = j + 1
        end
      end
      push(c)
      i = j + 1
    else
      push(c)
      i = i + 1
    end
  end
  return table.concat(out), ins
end

--- Calls fn(text after the name) for each code occurrence of identifier `name` (not inside a string,
--- not part of a longer word; `java.sourceCompatibility` counts).
local function gradle_after(text, ins, name, width, fn)
  local init = 1
  while true do
    local s, e = text:find(name, init, true)
    if not s then return end
    init = e + 1
    if not ins[s] and not text:sub(s - 1, s - 1):find("[%w_]") and not text:sub(e + 1, e + 1):find("[%w_]") then
      fn(text:sub(e + 1, e + width))
    end
  end
end

--- Version strings in one Gradle build file (Groovy or Kotlin DSL), text rules only, nothing is evaluated,
--- in order: `languageVersion = JavaLanguageVersion.of(N)` (java or kotlin toolchain), `jvmToolchain(N)`,
--- `sourceCompatibility`, `targetCompatibility` (`JavaVersion.VERSION_21`, `VERSION_1_8`, `toVersion("17")`,
--- `'21'`, `21`, `1.8`). A value that is not a literal (variable, version catalog, property) is skipped.
local function gradle_versions(src)
  local text, ins = gradle_strip(src)
  local vs = {}
  local function add(v) if v then vs[#vs + 1] = v end end
  gradle_after(text, ins, "languageVersion", 120, function(rest)
    add(rest:match("^[%s%.=%a%(]*JavaLanguageVersion%.of%(%s*[\"']?(%d+)"))
  end)
  gradle_after(text, ins, "jvmToolchain", 120, function(rest)
    add(rest:match("^%s*%(%s*(%d+)") or rest:match("^%s*%(%s*JavaLanguageVersion%.of%(%s*[\"']?(%d+)"))
  end)
  for _, name in ipairs({ "sourceCompatibility", "targetCompatibility" }) do
    gradle_after(text, ins, name, 80, function(rest)
      rest = rest:gsub("^[%s=%(]+", "")
      local v = rest:match("^JavaVersion%.VERSION_([%d_]+)")
      if v then v = v:gsub("_", ".") end
      add(v or rest:match("^JavaVersion%.toVersion%(%s*[\"']?(%d[%d%.]*)") or rest:match("^[\"']([%d%.]+)[\"']")
        or rest:match("^(%d[%d%.]*)"))
    end)
  end
  return vs
end

--- Directories of the projects a settings.gradle(.kts) `include`s (":app", ":libs:core" -> app, libs/core).
local function gradle_included(root)
  local dirs = {}
  for _, f in ipairs({ "settings.gradle", "settings.gradle.kts" }) do
    local src = read(root .. "/" .. f)
    if src then
      local text = gradle_strip("\n" .. src)
      local init = 1
      while #dirs < 50 do
        local _, e = text:find("\n[ \t]*include", init)
        if not e then break end
        init = e + 1
        local rest = text:sub(e + 1)
        local line = rest:match("^[ (][^\n]*") -- `include ...` but not includeBuild / includeFlat
        if line then
          while line:match(",%s*$") do -- a statement continues on the next line after a trailing comma
            local nl = rest:match("^\n[^\n]*", #line + 1)
            if not nl then break end
            line = line .. nl
          end
          for name in line:gmatch("[\"']([^\"']+)[\"']") do
            local rel = name:gsub("^:", ""):gsub(":", "/")
            if rel ~= "" and not rel:find("..", 1, true) and vim.fn.isdirectory(root .. "/" .. rel) == 1 then
              dirs[#dirs + 1] = rel
            end
          end
        end
      end
    end
  end
  return dirs
end

--- Majors from the Gradle build files: the root's build.gradle / build.gradle.kts, then those of the
--- sub-projects named by `include` in settings.gradle(.kts); duplicates removed. Out of scope: version
--- catalogs (libs.versions.toml), gradle.properties, values computed by code, convention plugins, buildSrc.
local function gradle_majors(root)
  local out, seen = {}, {}
  local function from(dir)
    for _, f in ipairs({ "build.gradle", "build.gradle.kts" }) do
      local src = read(dir .. "/" .. f)
      for _, v in ipairs(src and gradle_versions(src) or {}) do
        local m = v:match("^[%d%.]+$") and parse_version(v)
        if m and not seen[m] then
          seen[m] = true
          out[#out + 1] = m
        end
      end
    end
  end
  from(root)
  for _, rel in ipairs(gradle_included(root)) do from(root .. "/" .. rel) end
  return out
end

--- Java majors the project asks for, in priority order: .sdkmanrc java=, then pom
--- maven.compiler.release, plugin <release>, java.version, maven.compiler.source, <source>,
--- maven.compiler.target, <target>, then the Gradle build files (gradle_majors: toolchain, jvmToolchain,
--- sourceCompatibility, targetCompatibility). Only the project's own pom is read (no parent poms).
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
  if root then vim.list_extend(out, gradle_majors(root)) end -- NV4J:GRADLE
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
