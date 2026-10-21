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

--- Nearest build-marker dir, or the repo's .git root when that root has a build marker itself
--- (multi-module Maven: prefer the repo root over a submodule's own pom.xml). A loose file (no
--- marker above it) gets its own dir, never an unrelated enclosing git repo: that would break
--- jdt.ls's invisible-project support. Second value: false for that loose-file fallback.
---@return string root, boolean has_marker
function M.project(path)
  local marker_root = vim.fs.root(path, M.build_markers)
  if not marker_root then
    return vim.fs.dirname(path), false
  end
  local git_root = vim.fs.root(path, { ".git" })
  if git_root then
    for _, marker in ipairs(M.build_markers) do
      if vim.uv.fs_stat(git_root .. "/" .. marker) then
        return git_root, true
      end
    end
  end
  return marker_root, true
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

--- boot_build on `root` and on its modules up to 2 levels down (at most 60 directories looked at): an
--- aggregator pom often only lists <modules>.
function M.boot_project(root)
  if not root then return false end
  local queue, i = { { root, 0 } }, 1
  while i <= #queue and i <= 60 do
    local dir, depth = queue[i][1], queue[i][2]
    i = i + 1
    if M.boot_build(dir) then return true end
    if depth < 2 then
      for name, kind in vim.fs.dir(dir) do
        if kind == "directory" and name:sub(1, 1) ~= "." and not SKIP_DIRS[name] then
          queue[#queue + 1] = { dir .. "/" .. name, depth + 1 }
        end
      end
    end
  end
  return false
end

return M
