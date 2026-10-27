-- Project root of a file, shared by jdt.ls (plugins/java.lua) and the Spring Boot LS (nv4j/spring.lua)
-- so both servers see the same project.
local M = {}

M.build_markers = {
  "pom.xml",
  "build.gradle",
  "build.gradle.kts",
  "settings.gradle",
  "settings.gradle.kts",
  "mvnw",
  "gradlew",
  "build.xml",
}

--- Project marker file (D25): the nearest directory above a file holding a `.nv4j` file is the
--- project root, before any build marker. Empty is enough (no format yet).
M.project_marker = ".nv4j"

--- $HOME (a function so checks can point it at a temp dir).
function M.home() return vim.fs.normalize(vim.uv.os_homedir()) end

--- true for `/`, $HOME and any ancestor of $HOME: a `.nv4j` there would make everything below one project.
function M.home_or_above(dir)
  if not dir then return false end
  dir = vim.fs.normalize(dir)
  local home = M.home()
  return dir == "/" or dir == home or home:sub(1, #dir + 1) == dir .. "/"
end

--- true when `dir` is too broad to suggest for a `.nv4j`: home_or_above, or fewer than 3 path segments.
function M.too_broad(dir)
  local n = select(2, vim.fs.normalize(dir):gsub("/[^/]+", ""))
  return M.home_or_above(dir) or n < 3
end

local warned_broad = {}
--- Once per dir: a `.nv4j` at $HOME or above is honoured (the user put it there) but said out loud.
local function warn_broad(dir)
  if warned_broad[dir] then return end
  warned_broad[dir] = true
  vim.schedule(function()
    vim.notify(("A .nv4j file in %s makes every Java file below it one jdt.ls project (usage counts are off there). "
      .. "Move it to the project folder if that is not what you want."):format(dir), vim.log.levels.WARN, { title = "Nv4J" })
  end)
end

--- Project root of `path`, first rule that applies:
---  1. the nearest dir with a `.nv4j` file (D25), so every directory below it shares one jdt.ls;
---  2. the nearest build-marker dir, or the repo's .git root when that root has a build marker itself
---     (multi-module Maven: prefer the repo root over a submodule's own pom.xml);
---  3. a loose file (nothing above it) gets its own dir, never an unrelated enclosing git repo: that
---     would break jdt.ls's invisible-project support.
--- Second value has_marker: whether the root holds a build file (rule 2; rule 1 only when the `.nv4j`
--- dir has a build marker of its own), i.e. whether build-tool features (Spring Boot, mvn/gradle run)
--- apply. Third value: "nv4j", "build" or "loose".
---@return string root, boolean has_marker, "nv4j"|"build"|"loose" kind
function M.project(path)
  local nv4j_root = vim.fs.root(path, { M.project_marker })
  if nv4j_root then
    if M.home_or_above(nv4j_root) then warn_broad(nv4j_root) end
    for _, marker in ipairs(M.build_markers) do
      if vim.uv.fs_stat(nv4j_root .. "/" .. marker) then return nv4j_root, true, "nv4j" end
    end
    return nv4j_root, false, "nv4j"
  end
  local marker_root = vim.fs.root(path, M.build_markers)
  if not marker_root then
    return vim.fs.dirname(path), false, "loose"
  end
  local git_root = vim.fs.root(path, { ".git" })
  if git_root then
    for _, marker in ipairs(M.build_markers) do
      if vim.uv.fs_stat(git_root .. "/" .. marker) then
        return git_root, true, "build"
      end
    end
  end
  return marker_root, true, "build"
end

local warned_loose = {}
--- D25 visibility: once per root, a WARN when a jdt.ls is about to start for a loose-file root (no
--- build marker, no `.nv4j`) while a jdt.ls for another loose-file root is running. Never blocks the
--- start. Called by plugins/java.lua's opts.jdtls (each Java buffer attach); `clients` defaults to the
--- live jdtls clients (tests pass stubs). Returns the message when it warned.
function M.warn_loose(root, clients)
  if not root or warned_loose[root] then return nil end
  clients = clients or vim.lsp.get_clients({ name = "jdtls" })
  local other
  for _, c in ipairs(clients) do
    local r = c.config and c.config.root_dir
    if r == root then return nil end -- attaching to a running client, nothing starts
    if r and not other and select(3, M.project(r .. "/x.java")) == "loose" then other = r end
  end
  if not other or select(3, M.project(root .. "/x.java")) ~= "loose" then return nil end
  warned_loose[root] = true
  local parent = root
  while parent ~= "/" and other:sub(1, #parent + 1) ~= parent .. "/" do parent = vim.fs.dirname(parent) end
  local msg = ("Starting a second jdt.ls (about 1 GB or more) for loose Java files in %s while one runs for %s. "
    .. "To use one jdt.ls for both, create an empty .nv4j file in %s and restart Neovim.")
    :format(root, other, M.too_broad(parent) and "the project folder that holds both"
      or ("their common parent (" .. parent .. ")"))
  vim.notify(msg, vim.log.levels.WARN, { title = "Nv4J" })
  return msg
end

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local GRADLE_FILES = { "build.gradle", "build.gradle.kts" }

--- Spring Boot detection, one rule for run (nv4j/run.lua) and the Spring Boot LS (nv4j/spring.lua), reading
--- only the build files of `dir` itself:
---  Maven (pom.xml, comments stripped): groupId org.springframework.boot (parent, plugin, starter, BOM), or an
---    artifactId spring-boot-starter*, spring-boot-maven-plugin, spring-boot-dependencies.
---  Gradle (build.gradle(.kts), comment lines stripped): org.springframework.boot (plugin id or dependency
---    group), a spring-boot-starter* dependency, catalog aliases libs.plugins.spring.boot / libs.spring.boot.starter*,
---    or gradle/libs.versions.toml naming org.springframework.boot next to a Gradle build/settings file.
--- A bare "spring-boot" (e.g. a <spring-boot.version> property alone) does not count.
---@return boolean, "maven"|"gradle"|nil
function M.boot_build(dir)
  if not dir then return false end
  local pom = read(dir .. "/pom.xml")
  if pom then
    pom = pom:gsub("<!%-%-.-%-%->", "")
    if pom:find("<groupId>%s*org%.springframework%.boot%s*</groupId>")
      or pom:find("<artifactId>%s*spring%-boot%-starter[%w%-]*%s*</artifactId>")
      or pom:find("<artifactId>%s*spring%-boot%-maven%-plugin%s*</artifactId>")
      or pom:find("<artifactId>%s*spring%-boot%-dependencies%s*</artifactId>") then
      return true, "maven"
    end
  end
  local gradle = false
  for _, f in ipairs(GRADLE_FILES) do
    local g = read(dir .. "/" .. f)
    if g then
      gradle = true
      g = g:gsub("/%*.-%*/", ""):gsub("\n%s*//[^\n]*", "\n")
      if g:find("org%.springframework%.boot") or g:find("spring%-boot%-starter")
        or g:find("libs%.plugins%.spring%.boot") or g:find("libs%.spring%.boot%.starter") then
        return true, "gradle"
      end
    end
  end
  gradle = gradle or vim.uv.fs_stat(dir .. "/settings.gradle") ~= nil or vim.uv.fs_stat(dir .. "/settings.gradle.kts") ~= nil
  if gradle then
    local toml = read(dir .. "/gradle/libs.versions.toml")
    if toml and toml:gsub("\n%s*#[^\n]*", "\n"):find("org%.springframework%.boot") then return true, "gradle" end
  end
  return false
end

local SKIP_DIRS = { target = true, build = true, out = true, bin = true, node_modules = true, src = true, gradle = true }

--- The directories among `root` and its modules up to 2 levels down (at most 60 directories looked at,
--- breadth first, root first) whose own build file is Spring Boot (boot_build): an aggregator pom often
--- only lists <modules>.
---@return string[]
function M.boot_dirs(root)
  local out = {}
  if not root then return out end
  local queue, i = { { root, 0 } }, 1
  while i <= #queue and i <= 60 do
    local dir, depth = queue[i][1], queue[i][2]
    i = i + 1
    if M.boot_build(dir) then out[#out + 1] = dir end
    if depth < 2 then
      for name, kind in vim.fs.dir(dir) do
        if kind == "directory" and name:sub(1, 1) ~= "." and not SKIP_DIRS[name] then
          queue[#queue + 1] = { dir .. "/" .. name, depth + 1 }
        end
      end
    end
  end
  return out
end

function M.boot_project(root) return M.boot_dirs(root)[1] ~= nil end

local boot_cache = {}
--- boot_project memoized per root for the session: the one detector of run (nv4j/run.lua) and the
--- Spring Boot LS (nv4j/spring.lua).
function M.is_boot(root)
  if not root then return false end
  if boot_cache[root] == nil then boot_cache[root] = M.boot_project(root) end
  return boot_cache[root]
end

local function aggregator(dir)
  local pom = read(dir .. "/pom.xml")
  if pom and pom:gsub("<!%-%-.-%-%->", ""):find("<modules>") then return true end
  return vim.uv.fs_stat(dir .. "/settings.gradle") ~= nil or vim.uv.fs_stat(dir .. "/settings.gradle.kts") ~= nil
end

--- The Spring Boot module to run with the build tool for project `root`: `module` (the buffer's own
--- build dir) when its build file is Boot and it is not an aggregator, else the first Boot dir found that
--- is not an aggregator (so `spring-boot:run` / `bootRun` does not run the whole reactor), else the
--- first Boot dir, else nil.
function M.boot_module(root, module)
  if module and M.boot_build(module) and not aggregator(module) then return module end
  local dirs = M.boot_dirs(root)
  for _, d in ipairs(dirs) do
    if not aggregator(d) then return d end
  end
  return dirs[1]
end

--- The jdt.ls client whose root is `path` or its deepest ancestor, or nil. `clients` defaults to the
--- live jdtls clients (tests pass stubs). Shared by nv4j/run.lua and nv4j/debug.lua.
function M.client_for_path(path, clients)
  if not path or path == "" then return nil end
  path = vim.fs.normalize(path)
  local best, best_len
  for _, c in ipairs(clients or vim.lsp.get_clients({ name = "jdtls" })) do
    local r = c.config and c.config.root_dir and vim.fs.normalize(c.config.root_dir)
    if r and (path == r or path:sub(1, #r + 1) == r .. "/") and (not best_len or #r > best_len) then
      best, best_len = c, #r
    end
  end
  return best
end

return M
