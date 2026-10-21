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

return M
