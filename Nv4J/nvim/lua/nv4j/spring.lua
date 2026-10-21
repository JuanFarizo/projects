-- Spring Boot language server (decision D14, specs/features/spring-language-server.md):
-- JavaHello/spring-boot.nvim (pinned in plugins/spring.lua) does the LSP protocol glue (sts/* forwarders
-- to jdt.ls, classpath listener, language ids); nv4j decides where and how it runs:
--  * only for Spring Boot projects (nv4j/root.lua boot_project, the same rule as run: at the project root or
--    in a module below it); plain Maven/Gradle projects and loose files get no client and no process;
--  * the same project root as jdt.ls (nv4j/root.lua), not the plugin's .git/mvnw markers;
--  * on a JDK >= 21 from nv4j.jdk (never PATH or a stale $JAVA_HOME);
--  * the server jar and the jdt.ls extension bundles from the Mason package `vscode-spring-boot-tools`
--    (no version in any path: share/ links and the package's own package.json).
-- vim.g.nv4j_spring = false turns it off: set at startup (options.lua) the plugin never loads (plugins/spring.lua
-- cond); set later, it is checked whenever a buffer would attach and when jdt.ls starts.
local M = {}

local PKG = "vscode-spring-boot-tools"
-- The five jars the VS Code extension lists in package.json `contributes.javaExtensions` (fallback when
-- that file cannot be read).
local FALLBACK_JARS = {
  "io.projectreactor.reactor-core.jar",
  "org.reactivestreams.reactive-streams.jar",
  "jdt-ls-commons.jar",
  "jdt-ls-extension.jar",
  "sts-gradle-tooling.jar",
}

function M.enabled() return vim.g.nv4j_spring ~= false end

local function mason() return vim.fn.stdpath("data") .. "/mason" end

--- The server jar (Mason link to the version-named exec jar), or nil when the package is missing.
function M.ls_jar()
  local p = mason() .. "/share/" .. PKG .. "/language-server.jar"
  return vim.uv.fs_stat(p) and p or nil
end

local jars_cache
--- jdt.ls extension bundles the Spring Boot LS needs (absolute paths, all existing), or {}.
function M.jars()
  if jars_cache then return jars_cache end
  local ext = mason() .. "/packages/" .. PKG .. "/extension"
  local list = {}
  local f = io.open(ext .. "/package.json", "r")
  if f then
    local ok, pkg = pcall(vim.json.decode, f:read("*a"))
    f:close()
    local rel = ok and type(pkg) == "table" and pkg.contributes and pkg.contributes.javaExtensions or {}
    for _, r in ipairs(rel) do
      list[#list + 1] = vim.fs.normalize(ext .. "/" .. r:gsub("^%./", ""))
    end
  end
  if #list == 0 then
    for _, name in ipairs(FALLBACK_JARS) do
      list[#list + 1] = mason() .. "/share/" .. PKG .. "/jdtls/" .. name
    end
  end
  local out = vim.tbl_filter(function(p) return vim.uv.fs_stat(p) ~= nil end, list)
  if #out == #list then jars_cache = out end -- a partial install is not cached
  return out
end

local boot_cache = {}
--- Whether `root` is a Spring Boot project (nv4j/root.lua boot_project: the shared rule, root and modules
--- 2 levels down). Memoized per root for the session.
function M.is_boot(root)
  if not root then return false end
  if boot_cache[root] == nil then boot_cache[root] = require("nv4j.root").boot_project(root) end
  return boot_cache[root]
end

--- The Spring Boot project root for a file, or nil (no build file above it, not Spring Boot, or off).
function M.boot_root(path)
  if not M.enabled() or not path or path == "" then return nil end
  local root, has_marker = require("nv4j.root").project(path)
  if has_marker and M.is_boot(root) then return root end
end

--- Extension jars to add to jdt.ls's bundles for this jdt.ls root ({} unless it is a Spring Boot project
--- and the server is installed).
function M.bundles_for(root)
  if not M.enabled() or not root or not M.ls_jar() or not M.is_boot(root) then return {} end
  return M.jars()
end

local function is_config_file(name, ft)
  local base = vim.fs.basename(name)
  if ft == "yaml" then return base:match("^application.*%.ya?ml$") or base:match("^bootstrap.*%.ya?ml$") end
  if ft == "jproperties" then
    return base:match("^application.*%.properties$") or base:match("^bootstrap.*%.properties$")
  end
  return ft == "java"
end

--- root_dir for the `spring-boot` client: on_dir is only called for Java files and Spring config files
--- (application*/bootstrap* .properties/.yml) of a Spring Boot project.
function M.root_dir(bufnr, on_dir)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or vim.bo[bufnr].buftype ~= "" or not is_config_file(name, vim.bo[bufnr].filetype) then return end
  local root = M.boot_root(name)
  if root then on_dir(root) end
end

local warned
--- Called by plugins/spring.lua when the plugin loads (first java/yaml/properties buffer).
function M.setup()
  local jar = M.ls_jar()
  if not jar then
    -- Say so once, and only when a Spring Boot file is opened.
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "java", "yaml", "jproperties" },
      callback = function(ev)
        if warned or not M.boot_root(vim.api.nvim_buf_get_name(ev.buf)) then return end
        warned = true
        vim.notify("nv4j: Spring Boot LS not installed: run :MasonInstall " .. PKG, vim.log.levels.WARN)
        return true
      end,
    })
    return
  end
  require("spring_boot").setup({
    ls_path = jar,
    jars = M.jars(),
    java_cmd = require("nv4j.jdk").server_home() .. "/bin/java",
    log_file = require("nv4j.paths").logs .. "/spring-boot-ls.log",
    log_level = "warn",
    -- Same as the VS Code client (vscode-spring-boot Main.ts): no web server in the LS process,
    -- and Boot's nested jars open on newer JDKs.
    jvm_args = { "-Dspring.main.web-application-type=NONE", "-Djdk.util.zip.disableZip64ExtraFieldValidation=true" },
    jdtls_name = "jdtls",
    server = { root_dir = M.root_dir },
  })
end

return M
