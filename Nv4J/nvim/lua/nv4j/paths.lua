-- Central runtime paths for nv4j.
-- Logs and temp output live under /tmp/nv4j (disposable). The jdt.ls workspace (-data: project
-- index, build state) and its writable -configuration copy are not disposable: losing them forces a
-- full re-import, and macOS empties /tmp on reboot and after 3 days, possibly while jdt.ls runs.
-- They live under stdpath("cache") (~/.cache/nv4j with NVIM_APPNAME=nv4j).
local root = "/tmp/nv4j"
local cache = vim.fn.stdpath("cache")
local M = {
  root = root,
  logs = root .. "/logs",
  cache = cache,
  jdtls_data = cache .. "/jdtls-data",
  jdtls_config = cache .. "/jdtls-config",
}

--- Name of the Neovim LSP client log: one file per Neovim process and project, `lsp-<project>-<pid>.log`, so `:LspLog` shows
--- only this session (one shared file mixed every project and every open Neovim). The project is the nearest dir with a build
--- file, `.git` or `.nv4j` above `path` (the first file argument, else the cwd), else that dir's own name.
--- The test runner (NV4J_RUNNER) keeps the fixed `lsp.log` the checks read.
---@param path? string
---@param runner? boolean
function M.lsp_log(path, runner)
  if runner == nil then runner = vim.env.NV4J_RUNNER ~= nil end
  if runner then return M.logs .. "/lsp.log" end
  path = path or vim.uv.cwd() or "."
  local root = vim.fs.root(path, { ".nv4j", ".git", "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts" })
  local dir = root or (vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path))
  local name = vim.fs.basename(dir):gsub("[^%w%._-]", "_")
  if name == "" then name = "root" end
  return ("%s/lsp-%s-%d.log"):format(M.logs, name, vim.uv.os_getpid())
end

for _, dir in ipairs({ M.root, M.logs, M.jdtls_data, M.jdtls_config }) do
  vim.fn.mkdir(dir, "p")
end

return M
