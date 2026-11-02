-- Spring Boot language server (decision D14, specs/features/spring-language-server.md):
-- JavaHello/spring-boot.nvim (pinned in plugins/spring.lua) does the LSP protocol glue (sts/* forwarders
-- to jdt.ls, classpath listener, language ids); nv4j decides where and how it runs, and wraps the
-- plugin's first-jdtls-client lookup so two Boot projects share one Spring LS:
--  * only for Spring Boot projects (nv4j/root.lua boot_project, the same rule as run: at the project root or
--    in a module below it); plain Maven/Gradle projects and loose files get no client, no process, no plugin
--    load and no Mason install; a Boot file opened later installs the server once if it is missing;
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

--- Whether `root` is a Spring Boot project (nv4j/root.lua is_boot: the shared, memoized rule, root and
--- modules 2 levels down; nv4j/run.lua uses the same).
function M.is_boot(root) return require("nv4j.root").is_boot(root) end

--- The Spring Boot project root for a file, or nil (no build file above it, not Spring Boot, or off).
function M.boot_root(path)
  if not M.enabled() or not path or path == "" then return nil end
  local root, has_marker = require("nv4j.root").project(path)
  if has_marker and M.is_boot(root) then return root end
end

--- Mason `ensure_installed` only when the opened folder is already a Boot project.
function M.want_install()
  return M.enabled() and M.is_boot(vim.fn.getcwd()) or false
end

--- spring-boot.nvim loads only for a Boot Java / application* / bootstrap* buffer.
function M.should_load(path)
  return M.boot_root(path) ~= nil
end

local function as_path(path)
  if type(path) == "table" then
    path = path.projectUri or path.uri or (type(path.projectUris) == "table" and path.projectUris[1])
  end
  if type(path) ~= "string" or path == "" then return nil end
  if path:find("://", 1, true) then
    local ok, fname = pcall(vim.uri_to_fname, path)
    return ok and fname or path
  end
  return path
end

--- jdt.ls client that owns `path` (file, file URI, or sts/* params with projectUri). `clients` for tests.
function M.jdtls_for(path, clients)
  path = as_path(path)
  if not path then
    local buf = vim.api.nvim_buf_get_name(0)
    if buf ~= "" then path = as_path(buf) or buf end
  end
  return require("nv4j.root").client_for_path(path, clients)
end

local function live(c)
  return c ~= nil and not (type(c.is_stopped) == "function" and c:is_stopped())
end

--- Live jdt.ls clients (`clients` for tests; default: vim.lsp.get_clients).
local function jdtls_clients(clients)
  return vim.tbl_filter(live, clients or vim.lsp.get_clients({ name = "jdtls" }))
end

--- Live jdt.ls clients whose root is a Spring Boot project: only those have the Spring extension bundles
--- (nv4j/spring.lua bundles_for), so only they know the sts.* commands.
local function boot_clients(clients)
  return vim.tbl_filter(function(c)
    return c.config and c.config.root_dir and M.is_boot(c.config.root_dir)
  end, jdtls_clients(clients))
end

--- One line per routing decision that is not a plain match: <logs>/spring-route.log (debug aid).
function M.route_log(msg)
  local f = io.open(require("nv4j.paths").logs .. "/spring-route.log", "a")
  if f then
    f:write(os.date("%H:%M:%S "), msg, "\n")
    f:close()
  end
end

--- The jdt.ls client an sts/* request is about: the client whose root contains the param's projectUri
--- (paths compared after realpath, case folded only on case-insensitive file systems); only when NO client's
--- root contains it (or the param names no project) the current buffer's jdt.ls, then the first Boot jdt.ls.
--- Each fallback leaves a line in spring-route.log. `clients` for tests.
function M.route_client(param, clients)
  local root = require("nv4j.root")
  local all = jdtls_clients(clients)
  local path = as_path(param)
  if path then
    local c = root.client_for_path(path, all)
    if c then return c end
    M.route_log("no jdt.ls root contains " .. path .. ": current buffer's jdt.ls")
  end
  local boots = boot_clients(clients)
  local buf = vim.api.nvim_buf_get_name(0)
  local c = buf ~= "" and root.client_for_path(buf, all) or nil
  if c then return c end
  c = boots[1]
  if c then M.route_log("current buffer '" .. buf .. "' has no jdt.ls: first Boot jdt.ls (root " .. tostring(c.config.root_dir) .. ")") end
  return c
end

local notified
local function warn_once(msg)
  if notified then return end
  notified = true
  vim.notify(msg, vim.log.levels.WARN, { title = "Nv4J" })
end

--- spring_boot.jdtls.execute_command with an explicit client (same body as the plugin's, pinned commit):
--- no shared state between the pick and the send, so a request handled during the wait cannot see it.
local function run_on(client, command, param, timeout_ms)
  local util = require("spring_boot.util")
  if not timeout_ms then
    local err, resp = util.execute_command(client, command, param)
    if err then print("Error executeCommand: " .. command .. "\n" .. vim.inspect(err)) end
    return resp == nil and vim.NIL or resp
  end
  local done, err, resp = false, nil, nil
  util.execute_command(client, command, param, function(e, r) done, err, resp = true, e, r end)
  vim.wait(timeout_ms, function() return done end)
  if err then print("Error executeCommand: " .. command .. "\n" .. vim.inspect(err)) end
  return resp == nil and vim.NIL or resp
end

local ADD, REMOVE = "sts.java.addClasspathListener", "sts.java.removeClasspathListener"
-- client object -> callbackCommandId registered on it (weak: a restarted jdt.ls is a new object, unregistered)
local registered = setmetatable({}, { __mode = "k" })
-- classpath_args: the Spring LS's addClasspathListener arguments while a listener is wanted (tests read/restore it)
local state = { registered = registered }
M._state = state

--- Fire-and-forget (no wait, no UI block): listener (un)registration on a jdt.ls other than the one that answers.
local function send_async(c, command, param)
  local util = require("spring_boot.util")
  local id = param and param[1]
  if command == ADD then registered[c] = id else registered[c] = nil end
  util.execute_command(c, command, param, function(err)
    if err and command == ADD and registered[c] == id then registered[c] = nil end
  end)
end

--- After spring_boot.setup: sts/* go to the jdt.ls of the projectUri (route_client), not clients[1].
--- The classpath listener is registered on every Spring Boot jdt.ls: the ones running now (the first, the current
--- buffer's if Boot, answers the Spring LS; the others get it asynchronously) and the ones that start later
--- (LspAttach, once per client).
function M.route_jdtls()
  local ok, jdtls_mod = pcall(require, "spring_boot.jdtls")
  if not ok then
    warn_once("nv4j: spring_boot.jdtls not found (plugin changed?): sts/* requests are not routed per project")
    return
  end
  if jdtls_mod._nv4j_routed then return end -- already wrapped (this module reloaded)
  jdtls_mod._nv4j_routed = true
  jdtls_mod.get_jdtls_client = function(param) return M.route_client(param) end
  jdtls_mod.execute_command = function(command, param, timeout_ms)
    if command == ADD or command == REMOVE then
      state.classpath_args = command == ADD and param or nil
      local list = boot_clients()
      if #list == 0 then return vim.NIL end -- none yet: LspAttach registers each one as it starts
      local primary = M.route_client(nil)
      if not primary or not vim.tbl_contains(list, primary) then primary = list[1] end
      for _, c in ipairs(list) do
        if c ~= primary then send_async(c, command, param) end
      end
      if command == ADD then registered[primary] = param and param[1] else registered[primary] = nil end
      return run_on(primary, command, param, timeout_ms)
    end
    local client = jdtls_mod.get_jdtls_client(param)
    if not client then
      vim.notify("spring_boot: no jdtls client for " .. command, vim.log.levels.WARN)
      return
    end
    return run_on(client, command, param, timeout_ms)
  end
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("nv4j_spring_route", { clear = true }),
    callback = function(ev)
      local args = state.classpath_args
      if not args then return end
      local c = vim.lsp.get_client_by_id(ev.data.client_id)
      if not c or c.name ~= "jdtls" or not live(c) then return end
      if not (c.config and c.config.root_dir and M.is_boot(c.config.root_dir)) then return end
      if registered[c] == args[1] then return end -- LspAttach fires per buffer, register once per client
      send_async(c, ADD, args)
    end,
  })
end

--- Extension jars to add to jdt.ls's bundles for this jdt.ls root ({} unless it is a Spring Boot project
--- and the server is installed).
function M.bundles_for(root)
  if not M.enabled() or not root or not M.ls_jar() or not M.is_boot(root) then return {} end
  return M.jars()
end

-- Top-level namespaces Spring Boot itself owns. A project key outside them (`app.*`, `demo.*`) is the
-- project's own setting, the usual target of @Value; `server.port` set in the project is still a project key.
local BOOT_NS = { spring = true, server = true, management = true, logging = true, debug = true, trace = true, info = true }

--- Keys of a .properties file (comments, continuation lines and escapes are not interpreted beyond skipping).
local function props_keys(lines, out)
  local cont = false
  for _, l in ipairs(lines) do
    if not cont then
      local k = l:match("^%s*([^#!%s=:][^%s=:]*)%s*[=:]")
      if k then out[k] = true end
    end
    cont = l:match("\\$") ~= nil
  end
end

--- Leaf keys (with a value on the line) of a YAML file, dotted by indentation. Lists and documents are flattened.
local function yaml_keys(lines, out)
  local stack = {} -- { indent, name }
  for _, l in ipairs(lines) do
    local ind, k, rest = l:match("^(%s*)([%w_%.%-]+):%s*(.-)%s*$")
    if k then
      local n = #ind
      while #stack > 0 and stack[#stack][1] >= n do table.remove(stack) end
      local path = {}
      for _, s in ipairs(stack) do path[#path + 1] = s[2] end
      path[#path + 1] = k
      if rest ~= "" and not rest:match("^#") then out[table.concat(path, ".")] = true end
      stack[#stack + 1] = { n, k }
    elseif l:match("^%-%-%-") then
      stack = {}
    end
  end
end

local keys_cache = {} -- root -> { files, files_at, sig, keys }
--- The keys set in the project's own application*/bootstrap* .properties/.yml (src/main/resources of the root and of
--- modules up to 2 levels down), as key -> 2 (outside Boot's namespaces) or 1. Read from disk; the file list is
--- refreshed every 10 s and the keys whenever a file's mtime or size changes. Used by nv4j/completion.lua.
function M.project_keys(root)
  if not root then return {} end
  local e = keys_cache[root] or {}
  keys_cache[root] = e
  local now = vim.uv.now()
  if not e.files or now - e.files_at > 10000 then
    e.files, e.files_at = {}, now
    for _, dir in ipairs({ "", "*/", "*/*/" }) do
      for _, pat in ipairs({ "application*.properties", "application*.yml", "application*.yaml", "bootstrap*.properties", "bootstrap*.yml" }) do
        vim.list_extend(e.files, vim.fn.glob(root .. "/" .. dir .. "src/main/resources/" .. pat, true, true))
      end
    end
  end
  local sig = {}
  for _, f in ipairs(e.files) do
    local st = vim.uv.fs_stat(f)
    sig[#sig + 1] = st and (st.mtime.sec .. "." .. st.mtime.nsec .. ":" .. st.size) or "-"
  end
  sig = table.concat(sig, ",")
  if e.sig ~= sig then
    local set = {}
    for _, f in ipairs(e.files) do
      local ok, lines = pcall(vim.fn.readfile, f)
      if ok then
        if f:match("%.properties$") then props_keys(lines, set) else yaml_keys(lines, set) end
      end
    end
    e.keys = {}
    for k in pairs(set) do e.keys[k] = BOOT_NS[k:match("^[^%.]+")] and 1 or 2 end
    e.sig = sig
  end
  return e.keys
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

local started
local function start()
  if started then return end
  local jar = M.ls_jar()
  if not jar then return end
  started = true
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
    -- One Spring LS process for every Boot project in the session; sts/* pick jdt.ls by projectUri.
    server = {
      root_dir = M.root_dir,
      reuse_client = function(client) return client.name == "spring-boot" end,
    },
  })
  M.route_jdtls()
end

local installing
--- If the Mason package is missing, install it once, then start. Boot repos opened as cwd still use
--- ensure_installed (want_install); this is the path for a Boot file opened later in a non-Boot session.
function M.ensure_package()
  if M.ls_jar() then start() return end
  if installing or not M.enabled() then return end
  installing = true
  vim.notify("Installing Spring Boot LS (once, ~90 MB)...", vim.log.levels.INFO, { title = "Nv4J" })
  local ok, registry = pcall(require, "mason-registry")
  if not ok then
    installing = false
    vim.notify("nv4j: Spring Boot LS not installed: run :MasonInstall " .. PKG, vim.log.levels.WARN)
    return
  end
  local function go()
    local pkg = registry.get_package(PKG)
    if pkg:is_installed() then
      installing = false
      start()
      return
    end
    if pkg.is_installing and pkg:is_installing() then -- ensure_installed already runs it: wait, do not start twice
      vim.defer_fn(go, 2000)
      return
    end
    pkg:install():once("closed", function()
      vim.schedule(function()
        installing = false
        if M.ls_jar() then
          start()
          vim.notify("Spring Boot LS installed. Restart Neovim so jdt.ls loads the Spring bundles.",
            vim.log.levels.INFO, { title = "Nv4J" })
        else
          vim.notify("nv4j: Spring Boot LS not installed: run :MasonInstall " .. PKG, vim.log.levels.WARN)
        end
      end)
    end)
  end
  if registry.refresh then registry.refresh(go) else go() end
end

--- FileType watcher: load spring-boot.nvim only when the buffer is a Boot project file.
function M.watch()
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "java", "yaml", "jproperties" },
    callback = function(ev)
      if not M.should_load(vim.api.nvim_buf_get_name(ev.buf)) then return end
      local ok, err = pcall(function() require("lazy").load({ plugins = { "spring-boot.nvim" } }) end)
      if not ok then warn_once("nv4j: loading spring-boot.nvim failed: " .. tostring(err)) end
    end,
  })
end

--- Called by plugins/spring.lua when the plugin loads (first Boot java/yaml/properties buffer).
function M.setup()
  M.ensure_package()
end

return M
