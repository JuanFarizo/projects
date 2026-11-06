-- Client side of the Spring Data AOT lens (specs/features/jpa.md, J5). The Spring LS needs the AOT metadata of a repository
-- (`target/spring-aot/.../<Repository>.json`, written by `spring-boot:process-aot`) to show the generated query over a query
-- method and to offer "Add `@Query`". It does not run the build itself for this client: the lens "Show AOT-generated
-- Implementation, Query, etc..." and "Refresh AOT Metadata" carry the VS Code commands
--   maven.goal.custom(pom, goals, env)          gradle.runBuild(buildFile, tasks, env, {refreshJavaProject})
-- and Neovim answers them with nothing unless a handler exists. This registers both: it runs the build in the background in
-- the project's folder with the env the server sent (JAVA_HOME of the project), says when it starts and ends, and asks for the
-- code lenses again. Probe: tests/checks/82_jpa4_spring.lua.
local M = {}

local running = {} -- build file -> true while its build runs

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Nv4J AOT" }) end

--- First executable `name` (mvnw / gradlew) from `dir` up to the filesystem root, else nil.
local function wrapper(dir, name)
  while dir and dir ~= "/" do
    local w = dir .. "/" .. name
    if vim.fn.executable(w) == 1 then return w end
    local up = vim.fs.dirname(dir)
    if up == dir then break end
    dir = up
  end
end

--- The command line for a build: { cmd..., } cwd. `tool` = "maven" | "gradle". nil, reason when no tool is found.
function M.command(tool, build_file, goals)
  local dir = vim.fs.dirname(build_file)
  local words = vim.split(vim.trim(goals or ""), "%s+", { trimempty = true })
  if #words == 0 then return nil, "no goal" end
  local exe
  if tool == "maven" then
    exe = wrapper(dir, "mvnw") or (vim.fn.executable("mvn") == 1 and "mvn" or nil)
  else
    exe = wrapper(dir, "gradlew") or (vim.fn.executable("gradle") == 1 and "gradle" or nil)
  end
  if not exe then return nil, "no " .. (tool == "maven" and "mvnw or mvn" or "gradlew or gradle") .. " found for " .. dir end
  local cmd = { exe }
  if tool == "maven" then cmd[#cmd + 1] = "-q" end
  vim.list_extend(cmd, words)
  return cmd, dir
end

local function relens()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "java" then
      pcall(vim.lsp.codelens.refresh, { bufnr = b })
    end
  end
end

--- Run the build for `args` = { build_file, goals, env }. `on_done(code)` (tests).
function M.run(tool, args, on_done)
  local build_file, goals, env = args and args[1], args and args[2], args and args[3]
  if type(build_file) ~= "string" or type(goals) ~= "string" then
    notify("AOT: unexpected command arguments", vim.log.levels.WARN)
    return false
  end
  if running[build_file] then
    notify("AOT metadata is already being generated for " .. vim.fn.fnamemodify(build_file, ":~:h"))
    return false
  end
  local cmd, cwd = M.command(tool, build_file, goals)
  if not cmd then
    notify("AOT: " .. cwd, vim.log.levels.ERROR)
    return false
  end
  local e = {}
  for k, v in pairs(type(env) == "table" and env or {}) do
    if type(k) == "string" and type(v) == "string" then e[k] = v end
  end
  if not e.JAVA_HOME then
    -- the server sent no JDK: use the one jdt.ls runs the project with (nv4j.jdk), not whatever `java` is first on PATH
    local ok_rt, rts = pcall(function() return (require("nv4j.jdk").runtimes(cwd)) end)
    for _, rt in ipairs(ok_rt and rts or {}) do
      if rt.default then e.JAVA_HOME = rt.path break end
    end
  end
  if e.JAVA_HOME then e.PATH = e.JAVA_HOME .. "/bin:" .. (vim.env.PATH or "") end
  running[build_file] = true
  local name = vim.fn.fnamemodify(cwd, ":t")
  notify(("AOT metadata for %s: %s%s"):format(name, table.concat(cmd, " "), e.JAVA_HOME and (" (JAVA_HOME " .. e.JAVA_HOME .. ")") or ""))
  local ok, err = pcall(vim.system, cmd, { cwd = cwd, env = e, text = true }, function(r)
    vim.schedule(function()
      running[build_file] = nil
      if r.code == 0 then
        notify(("AOT metadata for %s is ready"):format(name))
        relens()
      else
        local tail = vim.trim((r.stdout or "") .. "\n" .. (r.stderr or "")):sub(-1800)
        notify(("AOT metadata for %s failed (exit %d)\n%s"):format(name, r.code, tail), vim.log.levels.ERROR)
      end
      if on_done then on_done(r.code) end
    end)
  end)
  if not ok then
    running[build_file] = nil
    notify("AOT: could not start the build: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.setup()
  vim.lsp.commands["maven.goal.custom"] = function(cmd) M.run("maven", cmd.arguments) end
  vim.lsp.commands["gradle.runBuild"] = function(cmd) M.run("gradle", cmd.arguments) end
end

return M
