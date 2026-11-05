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

local function has_build(dir)
  if not dir then return false end
  for _, marker in ipairs(M.build_markers) do
    if vim.uv.fs_stat(dir .. "/" .. marker) then return true end
  end
  return false
end

local function under(parent, dir)
  parent, dir = vim.fs.normalize(parent), vim.fs.normalize(dir)
  return dir == parent or dir:sub(1, #parent + 1) == parent .. "/"
end

local SETTINGS = { "settings.gradle", "settings.gradle.kts" }
local function has_settings(dir)
  for _, f in ipairs(SETTINGS) do
    if vim.uv.fs_stat(dir .. "/" .. f) then return true end
  end
  return false
end

--- D29: a Gradle sub-project (`dir` has build.gradle(.kts), no pom.xml, no settings file of its own) belongs
--- to the build of the NEAREST settings.gradle(.kts) in a parent directory, so one jdt.ls (and one `<leader>tp`)
--- covers the whole multi-project build. The search stops at the git root (inclusive), at the `.nv4j` dir
--- (inclusive; `.nv4j` overrides) and never reaches $HOME or above. Maven and standalone projects: nil.
---@return string? root
function M.gradle_settings_root(dir, git_root, nv4j_root)
  if not dir or has_settings(dir) or vim.uv.fs_stat(dir .. "/pom.xml") then return nil end
  if not (vim.uv.fs_stat(dir .. "/build.gradle") or vim.uv.fs_stat(dir .. "/build.gradle.kts")) then return nil end
  local cur = vim.fs.dirname(dir)
  while cur and cur ~= dir and not M.home_or_above(cur) do
    if has_settings(cur) then return cur end
    if (git_root and cur == git_root) or (nv4j_root and cur == nv4j_root) then return nil end
    dir, cur = cur, vim.fs.dirname(cur)
  end
  return nil
end

--- Project root of `path`, first rule that applies:
---  1. the nearest dir with a `.nv4j` file (D25), so every directory below it shares one jdt.ls,
---     except: a `.nv4j` with no build file of its own does not steal a Maven/Gradle module sitting
---     under it (jdt.ls has no pom at that root, so the child's pom would be ignored);
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
  -- ONE list entry = equal priority: the NEAREST dir holding any build marker (G7). A flat list is a priority
  -- order (a pom.xml two levels up beat a nearer build.gradle.kts).
  local marker_root = vim.fs.root(path, { M.build_markers })
  if nv4j_root then
    if M.home_or_above(nv4j_root) then warn_broad(nv4j_root) end
    -- pom next to the marker: aggregator / normal Maven project.
    if has_build(nv4j_root) then return nv4j_root, true, "nv4j" end
    -- no pom beside it: still the root for loose files. Do not swallow a child module's pom
    -- (one jdt.ls at a folder with no pom.xml is an invisible project: Maven classpath dies).
    local child_build = marker_root and marker_root ~= nv4j_root and under(nv4j_root, marker_root)
    if not child_build then return nv4j_root, false, "nv4j" end
  end
  if not marker_root then
    return vim.fs.dirname(path), false, "loose"
  end
  local git_root = vim.fs.root(path, { ".git" })
  if git_root then
    if has_build(git_root) then return git_root, true, "build" end
  end
  return M.gradle_settings_root(marker_root, git_root, nv4j_root) or marker_root, true, "build"
end

local warned_loose = {} -- canon root -> true once its refusal/warning was shown
local refused_roots = {} -- canon root -> raw root: refused by the cap, waiting for the blocking jdt.ls to stop
local function running(c)
  if c.is_stopped and c:is_stopped() then return false end
  if c.is_stopping and c:is_stopping() then return false end
  return true
end
--- D25 cap: when a jdt.ls is about to start for a loose-file root (no build marker, no `.nv4j`) and
--- `vim.g.nv4j_loose_max` (default 1; 0 = no cap) loose-root jdt.ls already run for other roots, the start is
--- refused (second return value true; plugins/java.lua's start_or_attach guard honours it) and a WARN says so,
--- once per root. Below the cap (or cap 0) it only warns once, never blocks. Roots of kind "nv4j"/"build" and
--- attaching to a running client of the same root are never capped. Stopped/stopping clients do not count, and
--- nothing is remembered about a refusal except that its warning was shown. Called by opts.jdtls on each Java
--- buffer attach; `clients` defaults to the live jdtls clients (tests pass stubs). Roots are compared with
--- M.canon (symlinks, trailing slash, case on a case-insensitive FS), the warning text keeps the raw paths.
---@return string? msg the warning text when one was shown now (nil on a repeat), boolean refused
function M.warn_loose(root, clients)
  if not root then return nil, false end
  clients = clients or vim.lsp.get_clients({ name = "jdtls" })
  local croot = M.canon(root)
  local others, other = 0, nil
  for _, c in ipairs(clients) do
    if running(c) then
      local r = c.config and c.config.root_dir
      if r and M.canon(r) == croot then warned_loose[croot] = nil return nil, false end -- attaching to a running client, nothing starts
      if r and select(3, M.project(r .. "/x.java")) == "loose" then
        others = others + 1
        other = other or r
      end
    end
  end
  if not other or select(3, M.project(root .. "/x.java")) ~= "loose" then
    warned_loose[croot] = nil -- nothing blocks this root now: a later refusal warns again
    return nil, false
  end
  local max = vim.g.nv4j_loose_max
  if type(max) ~= "number" then max = 1 end
  local refused = max > 0 and others >= max
  if warned_loose[croot] then return nil, refused end
  warned_loose[croot] = true
  local parent, cother = root, M.canon(other)
  while parent ~= "/" and cother:sub(1, #M.canon(parent) + 1) ~= M.canon(parent) .. "/" do parent = vim.fs.dirname(parent) end
  local where = M.too_broad(parent) and "the project folder that holds both" or ("their common parent (" .. parent .. ")")
  local msg
  if refused then
    msg = ("Not starting a second jdt.ls (about 1 GB or more) for loose Java files in %s: one already runs for %s, "
      .. "so this file opens without LSP. To use one jdt.ls for both, create an empty .nv4j file in %s and restart Neovim "
      .. "(or raise vim.g.nv4j_loose_max). It starts by itself when %s stops."):format(root, other, where, other)
  else
    msg = ("Starting a second jdt.ls (about 1 GB or more) for loose Java files in %s while one runs for %s. "
      .. "To use one jdt.ls for both, create an empty .nv4j file in %s and restart Neovim."):format(root, other, where)
  end
  vim.notify(msg, vim.log.levels.WARN, { title = "Nv4J" })
  return msg, refused
end

--- Remember that the cap refused a jdt.ls start for `root` (called by the start_or_attach guard).
function M.note_refused(root)
  if root then refused_roots[M.canon(root)] = root end
end

--- Roots refused by the cap and not started since (canon -> raw), for tests.
function M.refused() return vim.deepcopy(refused_roots) end

--- Forget refused roots (tests).
function M.clear_refused() refused_roots = {} warned_loose = {} stream_restarted = {} end

--- Called when a jdt.ls client has exited: every root the cap refused that still has a loaded, named, not
--- attached Java buffer gets its jdt.ls started if warn_loose now allows it (cap checked again, root by root,
--- clients re-read after each start). `start(buf)` re-fires FileType with the buffer current (default), which goes through
--- opts.jdtls and the start_or_attach guard again. A root whose start is refused again stays remembered
--- (note_refused), a root with no loaded buffer left is forgotten. Runs once per exit, never loops: a start
--- only causes another release when that jdt.ls exits.
---@param get_clients? fun(): table[] default: live jdtls clients
---@param start? fun(buf: integer)
---@return string[] started the raw roots started now
function M.release_refused(get_clients, start)
  get_clients = get_clients or function() return vim.lsp.get_clients({ name = "jdtls" }) end
  start = start or function(buf)
    -- LazyVim's attach reads the CURRENT buffer (name, root), not the autocmd's: run it with `buf` current.
    vim.api.nvim_buf_call(buf, function() vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false }) end)
  end
  local started = {}
  for croot, raw in pairs(vim.deepcopy(refused_roots)) do
    local bufs = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "java" and vim.bo[b].buftype == "" then
        local name = vim.api.nvim_buf_get_name(b)
        if name ~= "" and M.canon(M.project(name)) == croot then
          local attached = false
          for _, c in ipairs(vim.lsp.get_clients({ bufnr = b, name = "jdtls" })) do
            if running(c) then attached = true end
          end
          if not attached then bufs[#bufs + 1] = b end
        end
      end
    end
    if #bufs == 0 then
      refused_roots[croot] = nil
    else
      local _, refused = M.warn_loose(raw, get_clients())
      if not refused then
        refused_roots[croot] = nil
        started[#started + 1] = raw
        for _, b in ipairs(bufs) do pcall(start, b) end
      end
    end
  end
  return started
end

local stream_restarted = {} -- canon root -> true: its jdt.ls was already restarted once after a corrupt stream
--- A jdt.ls client whose stdout stream broke (`INVALID_SERVER_JSON` / `INVALID_SERVER_MESSAGE`, flake A in docs/HANDOFF-p3.md:
--- jdt.ls wrote two messages into one, about 64 KB in) is deaf from then on: Neovim's parser stops, the client stays listed,
--- answers nothing, and no Java feature works until the user restarts by hand. Called from the client's `on_error`: the first
--- time per root and Neovim session it WARNs, stops that client for good (`stop(true)`) and remembers the root as refused, so
--- the exit hook in plugins/java.lua (release_refused) starts a fresh jdt.ls for the still-loaded buffers. A second break in
--- the same root only WARNs (no restart loop). Other error codes do nothing.
---@param root? string the client's root_dir
---@param code integer vim.lsp.rpc.client_errors value
---@param get_clients? fun(): table[] default: live jdtls clients (tests pass stubs)
---@return string action "restart" | "again" | "ignored" | "no client"
function M.recover_stream(root, code, get_clients)
  local codes = vim.lsp.rpc.client_errors
  if not root or (code ~= codes.INVALID_SERVER_JSON and code ~= codes.INVALID_SERVER_MESSAGE) then return "ignored" end
  get_clients = get_clients or function() return vim.lsp.get_clients({ name = "jdtls" }) end
  local croot = M.canon(root)
  local client
  for _, c in ipairs(get_clients()) do
    local r = c.config and c.config.root_dir
    if running(c) and r and M.canon(r) == croot then client = c end
  end
  if not client then return "no client" end
  if stream_restarted[croot] then
    vim.notify(("jdt.ls for %s sent a corrupt message again; not restarting it a second time. Restart it with :LspRestart.")
      :format(root), vim.log.levels.WARN, { title = "Nv4J" })
    return "again"
  end
  stream_restarted[croot] = true
  M.note_refused(root)
  vim.notify(("jdt.ls for %s sent a corrupt message and no longer answers; restarting it (Java features return in a few seconds).")
    :format(root), vim.log.levels.WARN, { title = "Nv4J" })
  vim.schedule(function() pcall(client.stop, client, true) end)
  return "restart"
end

--- Idempotent guard on `mod.start_or_attach` (nvim-jdtls): a config that opts.jdtls marked `nv4j_refused` (cap)
--- is not started and its root is remembered (note_refused). Safe to call before every start: a reloaded jdtls
--- module is a new table without the guard, and this puts it back; an already guarded module is left alone.
---@param mod table the jdtls module
---@return boolean wrapped true when the guard was installed now
function M.guard_start(mod)
  if type(mod) ~= "table" or mod._nv4j_cap or type(mod.start_or_attach) ~= "function" then return false end
  mod._nv4j_cap = true
  local orig = mod.start_or_attach
  mod.start_or_attach = function(config, ...)
    if type(config) == "table" and config.nv4j_refused then
      M.note_refused(config.root_dir)
      return
    end
    return orig(config, ...)
  end
  return true
end

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local GRADLE_FILES = { "build.gradle", "build.gradle.kts" }

local function gradle_strip(s) return (s:gsub("/%*.-%*/", ""):gsub("\n%s*//[^\n]*", "\n")) end

--- Ancestors of `dir` (itself first) up to the first one with a settings file, at most 6, never $HOME or above: where a Gradle build keeps its catalog and
--- its convention plugins (buildSrc, an included build-logic) for a sub-project below.
local function gradle_ancestors(dir)
  local out, home = {}, M.home()
  local d = dir
  while d and #out < 6 do
    if d == home or M.home_or_above(d) then break end
    out[#out + 1] = d
    if has_settings(d) then break end -- the build's root: a catalog or buildSrc above it belongs to another build
    local p = vim.fs.dirname(d)
    if p == d then break end
    d = p
  end
  return out
end

--- The version catalog of a Gradle project (G8/G9, specs/006 T7): the nearest gradle/libs.versions.toml at `dir` or
--- above it (bounded like gradle_ancestors). Line-based reading of [plugins] and [libraries] (inline tables only, as
--- TOML wants them on one line): plugins key -> plugin id, libraries key -> "group:name". Keys are returned as the
--- Gradle accessor (`spring-boot` / `spring_boot` -> `spring.boot`). nil when there is no catalog.
---@return { plugins: table<string,string>, libraries: table<string,string> }?
function M.gradle_catalog(dir)
  if not dir then return nil end
  for _, d in ipairs(gradle_ancestors(dir)) do
    local toml = read(d .. "/gradle/libs.versions.toml")
    if toml then
      local cat, section = { plugins = {}, libraries = {} }, nil
      for line in (toml .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("%s#.*$", ""):gsub("^%s*#.*$", "")
        local sec = line:match("^%s*%[([%w_%-]+)%]")
        if sec then
          section = sec
        elseif section == "plugins" or section == "libraries" then
          local key, rest = line:match("^%s*([%w_%-%.]+)%s*=%s*(.-)%s*$")
          if key then
            local acc = key:gsub("[%-_]", ".")
            if section == "plugins" then
              local id = rest:match("id%s*=%s*[\"']([^\"']+)") or rest:match("^[\"']([^:\"']+)")
              if id then cat.plugins[acc] = id end
            else
              local coord = rest:match("module%s*=%s*[\"']([^\"']+)")
              if not coord then
                local g, n = rest:match("group%s*=%s*[\"']([^\"']+)"), rest:match("name%s*=%s*[\"']([^\"']+)")
                coord = g and n and (g .. ":" .. n) or rest:match("^[\"']([^:\"']+:[^:\"']+)")
              end
              if coord then cat.libraries[acc] = coord end
            end
          end
        end
      end
      return cat
    end
  end
end

--- Whether build text `s` uses a catalog accessor of `section` (plugins: libs.plugins.<acc>, libraries: libs.<acc>)
--- whose entry satisfies pred(value).
function M.catalog_uses(s, cat, section, pred)
  if not (s and cat) then return false end
  local prefix = section == "plugins" and "libs%.plugins%." or "libs%."
  for acc, v in pairs(cat[section]) do
    if pred(v) then
      local pat = prefix .. vim.pesc(acc)
      local from = 1
      while true do
        local a, b = s:find(pat, from)
        if not a then break end
        local nxt = s:sub(b + 1, b + 1)
        if not nxt:match("[%w_%.]") then return true end
        from = b + 1
      end
    end
  end
  return false
end

local function boot_id(id) return id == "org.springframework.boot" end
local function boot_lib(c) return c:find("^org%.springframework%.boot:") ~= nil end

--- Base directories (buildSrc, an included build such as build-logic or one level below it) of `dir` or above that can hold
--- convention plugins.
local function convention_bases(dir)
  local out = {}
  for _, a in ipairs(gradle_ancestors(dir)) do
    out[#out + 1] = a .. "/buildSrc"
    -- included builds are declared by a settings file: list children only there (no wide scan of e.g. ~/code)
    for name, kind in has_settings(a) and vim.fs.dir(a) or function() end do
      local sub = a .. "/" .. name
      if kind == "directory" and name:sub(1, 1) ~= "." and name ~= "buildSrc" and name ~= "src"
        and (vim.uv.fs_stat(sub .. "/settings.gradle") or vim.uv.fs_stat(sub .. "/settings.gradle.kts")) then
        out[#out + 1] = sub
        for n2, k2 in vim.fs.dir(sub) do
          if k2 == "directory" and n2:sub(1, 1) ~= "." and n2 ~= "src" and n2 ~= "build" then out[#out + 1] = sub .. "/" .. n2 end
        end
      end
    end
  end
  return out
end

--- Precompiled script plugin files (Groovy `<id>.gradle`, Kotlin `<id>.gradle.kts`) a build might apply, in buildSrc
--- or an included build (a folder with a settings file, like build-logic, or one level below it) of `dir` or above.
--- Also used by nv4j/jdk.lua (project JDK from a convention plugin).
function M.convention_files(dir, id)
  local out = {}
  for _, base in ipairs(convention_bases(dir)) do
    for _, lang in ipairs({ "groovy", "kotlin" }) do
      for _, ext in ipairs({ ".gradle", ".gradle.kts" }) do
        local f = base .. "/src/main/" .. lang .. "/" .. id .. ext
        if vim.uv.fs_stat(f) then out[#out + 1] = f end
      end
    end
  end
  return out
end

--- Source files of the binary (class) plugin registered under `id`: buildSrc / build-logic build.gradle(.kts) with
--- `gradlePlugin { plugins { create("x") { id = "acme.boot"; implementationClass = "com.acme.BootPlugin" } } }`, the class
--- found by its full name under src/main/{java,kotlin,groovy}. Text rules only; a plugin from a jar or a repository, or
--- a class whose file name differs from its name, is not found.
local function binary_plugin_files(dir, id)
  local out = {}
  for _, base in ipairs(convention_bases(dir)) do
    for _, bf in ipairs(GRADLE_FILES) do
      local b = read(base .. "/" .. bf)
      if b then
        b = gradle_strip(b)
        local init = 1
        while true do
          local _, e, got = b:find("%f[%w]id%s*=?%s*%(?%s*[\"']([%w%._%-]+)[\"']", init)
          if not e then break end
          init = e + 1
          if got == id then
            local nxt = b:find("%f[%w]id%s*=?%s*%(?%s*[\"']", init) or #b
            local cls = b:sub(init, nxt):match("implementationClass%s*=?%s*%(?%s*[\"']([%w%._$]+)[\"']")
            if cls then
              local rel = cls:gsub("%.", "/")
              for _, lang in ipairs({ "java", "kotlin", "groovy" }) do
                for _, ext in ipairs({ ".java", ".kt", ".groovy" }) do
                  local f = base .. "/src/main/" .. lang .. "/" .. rel .. ext
                  if vim.uv.fs_stat(f) then out[#out + 1] = f end
                end
              end
            end
          end
        end
      end
    end
  end
  return out
end

local CORE_PLUGINS = { java = true, ["java-library"] = true, application = true, ["java-platform"] = true, groovy = true }

--- Plugin ids a Gradle build text applies (`id("x")`, `apply plugin: 'x'`), Gradle's own (java, org.gradle.*) left out:
--- the ones that may be convention plugins. Also used by nv4j/jdk.lua.
---@return string[]
function M.gradle_plugin_ids(s)
  local ids = {}
  local function add(id)
    if not CORE_PLUGINS[id] and not id:find("^org%.gradle%.") then ids[#ids + 1] = id end
  end
  for id in s:gmatch("id%s*%(?%s*[\"']([%w%._%-]+)[\"']") do add(id) end
  for id in s:gmatch("apply%s*%(?%s*plugin%s*[:=]%s*[\"']([%w%._%-]+)[\"']") do add(id) end
  return ids
end

--- A class source file (binary plugin) applies Spring Boot: the plugin id string or SpringBootPlugin (imports left out).
local function class_applies_boot(t)
  t = gradle_strip(t):gsub("\n%s*import[^\n]*", "\n")
  return t:find("org%.springframework%.boot") ~= nil or t:find("SpringBootPlugin") ~= nil
end

--- The `{ ... }` body that opens right after the end of the match `head` found from `init`: its text and the
--- position to continue from, nil when there is no more.
local function brace_body(g, head, init)
  local _, e = g:find(head, init)
  if not e then return nil end
  local depth = 1
  for j = e + 1, #g do
    local c = g:sub(j, j)
    if c == "{" then depth = depth + 1 elseif c == "}" then depth = depth - 1 end
    if depth == 0 then return g:sub(e + 1, j - 1), j end
  end
  return "", #g + 1
end

--- Whether project `dir` below a Gradle settings root gets Spring Boot from the root script: `subprojects { ... }` or
--- `allprojects { ... }` (every project) or `project(":x") { ... }` (that project) whose block applies the Boot plugin. A block
--- with a condition (`if`, `when`, `name ==`, `project(`) is not read: which sub-project it reaches is code, not text.
local function root_block_boot(dir)
  local anc = gradle_ancestors(dir)
  local a = anc[#anc]
  if #anc < 2 or not has_settings(a) then return false end
  local rel = dir:sub(#a + 2)
  if rel:match("^buildSrc") or rel:match("^%.") then return false end
  local path = ":" .. rel:gsub("/", ":")
  local heads = { "%f[%w]subprojects%s*{", "%f[%w]allprojects%s*{", "%f[%w]project%s*%(%s*[\"']" .. vim.pesc(path) .. "[\"']%s*%)%s*{" }
  for _, f in ipairs(GRADLE_FILES) do
    local g = read(a .. "/" .. f)
    if g then
      g = gradle_strip(g)
      for _, head in ipairs(heads) do
        local init = 1
        while true do
          local body, nxt = brace_body(g, head, init)
          if not body then break end
          init = nxt
          if body:find("org%.springframework%.boot")
            and not (body:find("%f[%w]if%f[%W]") or body:find("%f[%w]when%f[%W]") or body:find("name%s*==") or body:find("project%s*%(")) then
            return true
          end
        end
      end
    end
  end
  return false
end

--- Gradle build text names Spring Boot: directly, through the catalog (an alias of plugin org.springframework.boot or
--- of a library of group org.springframework.boot), or through a convention plugin applied by id: a precompiled script plugin whose own text names it (2 levels deep), or a
--- class registered in buildSrc / build-logic (`gradlePlugin { ... implementationClass }`) whose source applies it. A plugin from
--- a jar or repository is opaque (the `.nv4j` spring_boot field covers it).
local function gradle_boot_text(s, dir, depth, seen)
  if s:find("org%.springframework%.boot") or s:find("spring%-boot%-starter")
    or s:find("libs%.plugins%.spring%.boot") or s:find("libs%.spring%.boot%.starter") then
    return true
  end
  local cat = M.gradle_catalog(dir)
  if M.catalog_uses(s, cat, "plugins", boot_id) or M.catalog_uses(s, cat, "libraries", boot_lib) then return true end
  if depth >= 2 then return false end
  for _, id in ipairs(M.gradle_plugin_ids(s)) do
    if not seen[id] then
      seen[id] = true
      for _, f in ipairs(M.convention_files(dir, id)) do
        local t = read(f)
        if t and gradle_boot_text(gradle_strip(t), vim.fs.dirname(f), depth + 1, seen) then return true end
      end
      for _, f in ipairs(binary_plugin_files(dir, id)) do
        local t = read(f)
        if t and class_applies_boot(t) then return true end
      end
    end
  end
  return false
end

--- Spring Boot detection, one rule for run (nv4j/run.lua) and the Spring Boot LS (nv4j/spring.lua), reading
--- the build files of `dir` itself (Gradle: plus its catalog and the convention plugins it applies, see gradle_boot_text):
---  Maven (pom.xml, comments stripped): groupId org.springframework.boot (parent, plugin, starter, BOM), or an
---    artifactId spring-boot-starter*, spring-boot-maven-plugin, spring-boot-dependencies.
---  Gradle (build.gradle(.kts), comment lines stripped): org.springframework.boot (plugin id or dependency
---    group), a spring-boot-starter* dependency, any catalog alias of the Boot plugin or of a Boot-group library,
---    a precompiled convention plugin (buildSrc, build-logic) applying it, or gradle/libs.versions.toml naming
---    org.springframework.boot next to a Gradle build/settings file, or the root script's `subprojects {}` / `allprojects {}` /
---    `project(":x") {}` block applying the plugin (root_block_boot).
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
      if gradle_boot_text(gradle_strip(g), dir, 0, {}) then return true, "gradle" end
    end
  end
  if gradle and root_block_boot(dir) then return true, "gradle" end
  gradle = gradle or vim.uv.fs_stat(dir .. "/settings.gradle") ~= nil or vim.uv.fs_stat(dir .. "/settings.gradle.kts") ~= nil
  if gradle then
    local toml = read(dir .. "/gradle/libs.versions.toml")
    if toml and toml:gsub("\n%s*#[^\n]*", "\n"):find("org%.springframework%.boot") then return true, "gradle" end
  end
  return false
end

local SKIP_DIRS = { target = true, build = true, out = true, bin = true, node_modules = true, src = true, gradle = true,
  buildSrc = true } -- buildSrc is Gradle build logic, never the app to run (it may name the Boot Gradle plugin)

--- The directory the user marked as Spring Boot in `<root>/.nv4j`: `{"spring_boot": true}` is `root` itself,
--- `{"spring_boot": "app"}` is the sub-directory `root/app` (a relative path, no `..`). For what detection cannot see
--- (a plugin from a jar or a repository). nil when not set or not a directory.
---@return string?
function M.boot_override(root)
  if not root then return nil end
  local v = require("nv4j.settings").load(root).spring_boot
  if v == true then return root end
  if type(v) == "string" and v ~= "" and not v:find("..", 1, true) and not v:find("^[/~]") then
    local d = vim.fs.normalize(root .. "/" .. v)
    if vim.fn.isdirectory(d) == 1 then return d end
  end
end

--- The directories among `root` and its modules up to 2 levels down (at most 60 directories looked at,
--- breadth first, root first) whose own build file is Spring Boot (boot_build): an aggregator pom often
--- only lists <modules>.
---@return string[]
function M.boot_dirs(root)
  local out = {}
  if not root then return out end
  local override = M.boot_override(root)
  if override then out[1] = override end
  local queue, i = { { root, 0 } }, 1
  while i <= #queue and i <= 60 do
    local dir, depth = queue[i][1], queue[i][2]
    i = i + 1
    if dir ~= override and M.boot_build(dir) then out[#out + 1] = dir end
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
  if module and (M.boot_build(module) or module == M.boot_override(root)) and not aggregator(module) then return module end
  local dirs = M.boot_dirs(root)
  for _, d in ipairs(dirs) do
    if not aggregator(d) then return d end
  end
  return dirs[1]
end

--- Whether paths compare case-insensitively (macOS and Windows file systems; vim.g.nv4j_case_fold = true|false
--- forces it, for tests).
function M.case_insensitive()
  if vim.g.nv4j_case_fold ~= nil then return vim.g.nv4j_case_fold == true end
  return vim.fn.has("mac") == 1 or vim.fn.has("win32") == 1
end

--- Canonical form for comparing paths: normalised, symlinks resolved (vim.uv.fs_realpath of the deepest
--- existing ancestor, so a path that does not exist yet still resolves), case folded only where the FS is
--- case-insensitive.
function M.canon(path)
  local p = vim.fs.normalize(path)
  local rest = ""
  local cur = p
  while cur ~= "" do
    local rp = vim.uv.fs_realpath(cur)
    if rp then
      rp = vim.fs.normalize(rp)
      p = (rp == "/" and "" or rp) .. rest
      if p == "" then p = "/" end
      break
    end
    local parent = vim.fs.dirname(cur)
    if not parent or parent == cur then break end
    rest = "/" .. vim.fs.basename(cur) .. rest
    cur = parent
  end
  if p ~= "/" then p = p:gsub("/+$", "") end
  return M.case_insensitive() and p:lower() or p
end

--- The jdt.ls client whose root is `path` or its deepest ancestor, or nil. `clients` defaults to the
--- live jdtls clients (tests pass stubs). Shared by nv4j/run.lua and nv4j/debug.lua.
function M.client_for_path(path, clients)
  if not path or path == "" then return nil end
  path = M.canon(path)
  local best, best_len
  for _, c in ipairs(clients or vim.lsp.get_clients({ name = "jdtls" })) do
    local r = c.config and c.config.root_dir and M.canon(c.config.root_dir)
    if r and (path == r or path:sub(1, #r + 1) == r .. "/") and (not best_len or #r > best_len) then
      best, best_len = c, #r
    end
  end
  return best
end

return M
