-- Run Spring Boot (specs/features/run.md, check 41_run).
--  - Boot is detected from the build file with the rule shared with the Spring Boot LS (nv4j/root.lua
--    boot_build: Boot groupId/starter/plugin/BOM in pom.xml, Boot plugin, starters or catalog aliases in Gradle).
--  - With jdt.ls attached (the normal case) the app runs as `java -cp <jdt.ls classpath> <main class>`
--    after the same source refresh + incremental build as a debug launch (nv4j.debug). Measured faster
--    than `mvn spring-boot:run` (2.5 s vs 5 to 7 s to "Started", and Maven had to resolve its plugin
--    over the network first: run.md, trials m1 to j2) and works the same for Maven and Gradle.
--    Without jdt.ls it falls back to the build tool: Maven first (mvnw/mvn spring-boot:run), then
--    Gradle (gradlew/gradle bootRun). The build tool can be forced (it applies the
--    spring-boot-maven-plugin <configuration>, pom profiles and process-classes plugins, which the
--    `java -cp` path skips): vim.g.nv4j_run_tool = "maven" (Maven first) or "gradle" (Gradle first),
--    or <leader>rS for one run.
--  - JAVA_HOME (and the java binary) for the app come from nv4j.jdk's project runtime, never PATH.
--  - Debug (opts.debug) is Task 1's nvim-dap launch of the same main class config (build before
--    launch, no orphan), with the profile, env and VM args added.
--  - Output goes to a terminal split: `<C-c>` (normal mode) stops, `q` stops and closes. Stopping
--    kills the whole process tree (SIGTERM, SIGKILL after KILL_GRACE_MS). Boot's "Started ... in",
--    the port and its failure analysis ("APPLICATION FAILED TO START", e.g. "Port 8080 was already in
--    use") become notifications.
local M = {}

---@class nv4j.RunSession
---@field id integer
---@field name string
---@field buf integer|nil terminal buffer
---@field job integer|nil terminal job (run mode)
---@field pid integer|nil
---@field state "starting"|"running"|"failed"|"exited"|"stopped"
---@field port integer|nil
---@field debug boolean
M.sessions = {} ---@type nv4j.RunSession[]
M.HEIGHT = 15
M.KILL_GRACE_MS = nil -- default 5000; the check lowers it

local FINAL = { failed = true, exited = true, stopped = true }
local TITLE = { title = "Spring Boot" }
local BUILD_MARKERS = { "pom.xml", "build.gradle", "build.gradle.kts", "mvnw", "gradlew" }

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, TITLE) end

--- Is the project at `root` a Spring Boot project (its build file or a module up to 2 levels down)? The
--- detector shared with the Spring Boot LS: nv4j/root.lua is_boot (memoized).
function M.is_boot(root) return require("nv4j.root").is_boot(root) end

--- The command that runs the app through the build tool (no jdt.ls needed). Maven first.
---@return string[]|nil cmd, table env extra environment
--- `root` is the Boot module to run (the command's cwd); the wrapper (mvnw/gradlew) is looked up in it,
--- then in its parents up to `project` (a multi-module project keeps it at the top).
function M.build_tool_command(root, opts, project)
  opts = opts or {}
  local env = {}
  local function exe(wrapper, tool)
    local dir = root
    while dir do
      local w = dir .. "/" .. wrapper
      if vim.fn.executable(w) == 1 then return w end
      if not project or dir == project or #dir <= #project then break end
      local up = vim.fs.dirname(dir)
      dir = up ~= dir and up or nil
    end
    return tool
  end
  local has_pom = vim.uv.fs_stat(root .. "/pom.xml") ~= nil
  local has_gradle = vim.uv.fs_stat(root .. "/build.gradle") ~= nil or vim.uv.fs_stat(root .. "/build.gradle.kts") ~= nil
  if has_pom and not (opts.prefer == "gradle" and has_gradle) then
    local cmd = { exe("mvnw", "mvn"), "spring-boot:run" }
    if opts.profile then cmd[#cmd + 1] = "-Dspring-boot.run.profiles=" .. opts.profile end
    if opts.vm_args and #opts.vm_args > 0 then
      cmd[#cmd + 1] = "-Dspring-boot.run.jvmArguments=" .. table.concat(opts.vm_args, " ")
    end
    if opts.args and #opts.args > 0 then cmd[#cmd + 1] = "-Dspring-boot.run.arguments=" .. table.concat(opts.args, " ") end
    return cmd, env
  end
  if has_gradle then
    local cmd = { exe("gradlew", "gradle"), "bootRun" }
    if opts.profile then env.SPRING_PROFILES_ACTIVE = opts.profile end
    if opts.args and #opts.args > 0 then cmd[#cmd + 1] = "--args=" .. table.concat(opts.args, " ") end
    return cmd, env
  end
end

--- Is the session's process still running? Decided by its job, not by its state: a JVM that printed
--- Boot's failure analysis ("failed") but did not exit is still running and still stoppable. A debug
--- session before nvim-dap started its terminal has no job yet and counts while not final.
function M.is_alive(s)
  if s.job and s.job > 0 then return vim.fn.jobwait({ s.job }, 0)[1] == -1 end
  return s.debug == true and not FINAL[s.state]
end

--- Sessions whose process is still running (or starting).
function M.running()
  return vim.tbl_filter(M.is_alive, M.sessions)
end

-- ── output scanning ───────────────────────────────────────────────────────────────────────────
local function strip(line)
  return (line:gsub("\27%[[%d;?]*[%a]", ""):gsub("\27%][^\7]*\7", ""):gsub("\r", ""))
end

--- One output line of the app (ANSI codes and CR removed).
local function feed(s, line)
  if FINAL[s.state] and s.state ~= "failed" then return end
  local port = line:match("started on port%(?s?%)?:? (%d+)")
  if port then s.port = tonumber(port) end
  local secs = line:match("Started %S+ in ([%d%.]+) seconds")
  if secs and s.state == "starting" then
    s.state = "running"
    s.boot_seconds = tonumber(secs)
    notify(("%s started%s in %s s"):format(s.name, s.port and (" on port " .. s.port) or "", secs))
    return
  end
  if line:find("APPLICATION FAILED TO START", 1, true) then
    s.fa = { stage = "head", desc = {} }
    return
  end
  local fa = s.fa
  if fa and not fa.done then
    local t = vim.trim(line)
    if t == "Description:" then
      fa.stage = "desc"
    elseif t == "Action:" then
      fa.stage = "action"
    elseif t ~= "" and fa.stage == "desc" then
      fa.desc[#fa.desc + 1] = t
    elseif t ~= "" and fa.stage == "action" then
      fa.done = true
      s.state = "failed"
      s.failure = table.concat(fa.desc, " ")
      notify(("%s failed to start: %s\nAction: %s"):format(s.name, s.failure, t), vim.log.levels.ERROR)
    end
    return
  end
  if line:find("Exception", 1, true) or line:find("ERROR", 1, true) then s.last_error = vim.trim(line):sub(1, 300) end
end

local function feed_chunk(s, data)
  -- on_stdout chunks end mid-line: keep the partial last element for the next call
  data[1] = (s.partial or "") .. data[1]
  s.partial = table.remove(data)
  for _, l in ipairs(data) do feed(s, strip(l)) end
end

local function on_exit(s, code)
  if s.partial and s.partial ~= "" then feed(s, strip(s.partial)) end
  s.partial = nil
  s.exit_code = code
  if s.stopping or code == 130 or code == 143 then
    s.state = "stopped"
    notify(s.name .. " stopped")
  elseif s.state == "failed" then
    -- failure analysis already notified
  elseif code ~= 0 then
    s.state = "failed"
    notify(("%s exited with code %d%s"):format(s.name, code, s.last_error and (": " .. s.last_error) or ""), vim.log.levels.ERROR)
  else
    s.state = "exited"
    notify(s.name .. " exited")
  end
end

-- ── process tree ──────────────────────────────────────────────────────────────────────────────
local function descendants(pid, out)
  local r = vim.system({ "pgrep", "-P", tostring(pid) }, { text = true }):wait()
  for c in (r.stdout or ""):gmatch("%d+") do
    local n = tonumber(c)
    out[#out + 1] = n
    descendants(n, out)
  end
  return out
end

--- pid -> { pgid, start } for the live ones among `pids` (`start` = ps lstart: tells a pid apart from
--- a later process that reused it).
local function proc_info(pids)
  local out = {}
  if #pids == 0 then return out end
  local r = vim.system({ "ps", "-o", "pid=,pgid=,lstart=", "-p", table.concat(pids, ",") }, { text = true }):wait()
  for line in (r.stdout or ""):gmatch("[^\n]+") do
    local pid, pgid, start = line:match("^%s*(%d+)%s+(%d+)%s+(.-)%s*$")
    if pid then out[tonumber(pid)] = { pgid = tonumber(pgid), start = start } end
  end
  return out
end

local own_pgid
local function group_of(pid)
  own_pgid = own_pgid or (proc_info({ vim.fn.getpid() })[vim.fn.getpid()] or {}).pgid
  local info = proc_info({ pid })[pid]
  local g = info and info.pgid
  -- only a group the job leads (jobstart(term) does setsid), never Neovim's own group
  if g and g == pid and g ~= own_pgid then return g end
end

M.kill_mode = nil -- tests only: "root" (control: only the root pid), "nogroup", "nosnapshot"

--- Stop the process tree of `pid` (a terminal job: jobstart(term) runs it as the leader of its own
--- session and process group). SIGTERM to the group and to every descendant found now (`pgrep -P`,
--- recursive, collected before anything dies: an orphan is re-parented and cannot be found later;
--- this also reaches a child that left the group with setsid/setpgrp). After `grace_ms`, SIGKILL to
--- the group if it still has members, and to the snapshot pids still alive with the same start time
--- (so a pid reused by an unrelated process is never signalled).
---@return { pids: integer[], force: fun(), done: fun(): boolean }
function M.kill_tree(pid, grace_ms)
  local mode = M.kill_mode
  local snap = mode == "root" and { pid } or descendants(pid, { pid })
  local info = proc_info(snap)
  local pgid = (mode == nil or mode == "nosnapshot") and group_of(pid) or nil
  local use_snap = mode ~= "nosnapshot"
  local function same(now)
    local out = {}
    for p, i in pairs(now) do
      if info[p] and info[p].start == i.start then out[#out + 1] = p end
    end
    return out
  end
  local function signal(sig)
    if pgid and vim.uv.kill(-pgid, 0) == 0 then pcall(vim.uv.kill, -pgid, sig) end
    if use_snap then
      for _, p in ipairs(same(sig == "sigterm" and info or proc_info(vim.tbl_keys(info)))) do pcall(vim.uv.kill, p, sig) end
    end
  end
  signal("sigterm")
  local forced = false
  local function force()
    if forced then return end
    forced = true
    signal("sigkill")
  end
  vim.defer_fn(force, grace_ms or M.KILL_GRACE_MS or 5000)
  local function done()
    if pgid and vim.uv.kill(-pgid, 0) == 0 then return false end
    return not use_snap or #same(proc_info(vim.tbl_keys(info))) == 0
  end
  return { pids = vim.tbl_keys(info), force = force, done = done }
end

--- Stop a session: its whole process tree (run mode) or its nvim-dap session (debug mode).
function M.stop(s)
  if not s or not M.is_alive(s) then return end
  s.stopping = true
  if s.dap then pcall(function() s.dap:disconnect({ terminateDebuggee = true }) end) end
  if s.pid then M.kill_tree(s.pid) end
end

function M.stop_all()
  for _, s in ipairs(M.running()) do M.stop(s) end
end

--- `q`: stop if still running, close the window, wipe the buffer.
function M.close(s)
  M.stop(s)
  if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    s.closing = true
    pcall(vim.api.nvim_buf_delete, s.buf, { force = true })
  end
end

local augroup
local function setup_autocmds()
  if augroup then return end
  augroup = vim.api.nvim_create_augroup("nv4j_run", { clear = true })
  -- No app left behind when Neovim quits: TERM every tree, wait up to 3 s, KILL what is left.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      local trees = {}
      for _, s in ipairs(M.running()) do
        if s.pid then trees[#trees + 1] = M.kill_tree(s.pid, 60000) end
      end
      if #trees == 0 then return end
      vim.wait(3000, function()
        for _, t in ipairs(trees) do if not t.done() then return false end end
        return true
      end, 50)
      for _, t in ipairs(trees) do t.force() end
    end,
  })
end

-- ── terminal ──────────────────────────────────────────────────────────────────────────────────
--- Start `o.cmd` in a new terminal split at the bottom (focus stays where it was).
---@param o { cmd: string[], cwd: string, env: table|nil, name: string, profile: string|nil }
---@return nv4j.RunSession
function M.start_terminal(o)
  setup_autocmds()
  local s = { id = #M.sessions + 1, name = o.name, state = "starting", debug = false, profile = o.profile, env = o.env, cmd = o.cmd, cwd = o.cwd }
  local prev = vim.api.nvim_get_current_win()
  vim.cmd("botright " .. M.HEIGHT .. "split")
  local win = vim.api.nvim_get_current_win()
  s.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, s.buf)
  s.job = vim.fn.jobstart(o.cmd, {
    term = true,
    cwd = o.cwd,
    env = o.env,
    on_stdout = function(_, data) feed_chunk(s, data) end,
    on_exit = function(_, code) on_exit(s, code) end,
  })
  if s.job <= 0 then
    s.state = "failed"
    notify(("%s: could not start %s"):format(s.name, o.cmd[1]), vim.log.levels.ERROR)
  else
    s.pid = vim.fn.jobpid(s.job)
  end
  pcall(vim.api.nvim_buf_set_name, s.buf, ("nv4j-run://%s#%d"):format(s.name, s.id))
  local function map(lhs, fn, desc) vim.keymap.set("n", lhs, fn, { buffer = s.buf, desc = desc, nowait = true }) end
  map("<C-c>", function() M.stop(s) end, "Stop the app (whole process tree)")
  map("q", function() M.close(s) end, "Stop the app and close its output")
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = vim.api.nvim_create_augroup("nv4j_run_buf" .. s.buf, { clear = true }),
    buffer = s.buf,
    callback = function() M.stop(s) end,
  })
  vim.cmd("normal! G") -- the terminal follows its output
  if vim.api.nvim_win_is_valid(prev) then vim.api.nvim_set_current_win(prev) end
  M.sessions[#M.sessions + 1] = s
  return s
end

-- ── debug sessions (nvim-dap's terminal) ──────────────────────────────────────────────────────
local pending = {} -- run id -> session record, until nvim-dap initialized it

--- Boot's start and failure lines in terminal rows: { port, secs, failure = { desc, action } }. The
--- terminal's width is unknown (a hidden or pooled nvim-dap terminal is narrower than any window), so
--- start and port are read from all rows joined with "" (a wrapped line is whole again), and the
--- failure block row by row: its parts are separated by blank rows, wrapped rows are joined with " ".
local function scan_rows(rows)
  local flat = strip(table.concat(rows, ""))
  local r = { port = tonumber(flat:match("started on port%(?s?%)?:? (%d+)")), secs = flat:match("Started %S+ in ([%d%.]+) seconds") }
  local fa
  for _, row in ipairs(rows) do
    local t = vim.trim(strip(row))
    if t:find("APPLICATION FAILED TO START", 1, true) then
      fa = { stage = "head", desc = {}, action = {} }
    elseif fa and not fa.done then
      if t == "Description:" then
        fa.stage = "desc"
      elseif t == "Action:" then
        fa.stage = "action"
      elseif t == "" then
        fa.done = fa.stage == "action" and #fa.action > 0
      elseif fa.stage == "desc" or fa.stage == "action" then
        table.insert(fa[fa.stage], t)
      end
    end
  end
  if fa and fa.done then r.failure = { desc = table.concat(fa.desc, " "), action = table.concat(fa.action, " ") } end
  return r
end

--- nvim-dap's terminal for a debug session: its buffer is pooled (reused, content reset by the new
--- terminal) and a terminal fills pre-existing empty rows, so the whole buffer is rescanned (debounced)
--- and each transition (started, failed) is applied once.
local function watch_dap_terminal(s, session)
  local buf = session.term_buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  s.buf = buf
  s.job = vim.b[buf].terminal_job_id
  s.pid = s.job and vim.fn.jobpid(s.job) or nil
  local function rescan()
    if not vim.api.nvim_buf_is_valid(buf) or session.term_buf ~= buf then return end
    local r = scan_rows(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    if r.port then s.port = r.port end
    if r.secs and s.state == "starting" then
      s.state = "running"
      s.boot_seconds = tonumber(r.secs)
      notify(("%s started%s in %s s"):format(s.name, s.port and (" on port " .. s.port) or "", r.secs))
    end
    if r.failure and not s.failure then
      s.state = "failed"
      s.failure = r.failure.desc
      notify(("%s failed to start: %s\nAction: %s"):format(s.name, s.failure, r.failure.action), vim.log.levels.ERROR)
    end
  end
  rescan()
  local queued = false
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if s.state == "stopped" or s.state == "exited" or session.term_buf ~= buf then return true end
      if queued then return end
      queued = true
      vim.defer_fn(function()
        queued = false
        rescan()
      end, 150)
    end,
  })
end

M._scan_rows = scan_rows -- read by tests/checks/41_run.lua
local function setup_dap()
  if M._dap then return end
  M._dap = true
  local dap = require("dap")
  dap.listeners.after.event_initialized["nv4j_run"] = function(session)
    local s = pending[session.config.nv4j_run_id or -1]
    if not s then return end
    pending[s.id] = nil
    s.dap = session
    watch_dap_terminal(s, session)
    session.on_close["nv4j_run"] = function()
      if s.stopping or s.state ~= "failed" then s.state = "stopped" end
    end
  end
end

-- ── main class discovery ──────────────────────────────────────────────────────────────────────
--- The jdt.ls client whose root is `path` or an ancestor of it (the deepest one), or nil (nv4j/root.lua).
function M.client_for_path(path) return require("nv4j.root").client_for_path(path) end

local OUTER_MARKERS = { "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts" }
--- The project a file without jdt.ls belongs to: nv4j/root.lua project(), then up while the parent dir
--- has a build file too (an aggregator pom or settings.gradle above a module, also outside git).
local function outer_root(path)
  local root, has_marker = require("nv4j.root").project(path)
  if not has_marker then return nil end
  local home = vim.uv.os_homedir()
  while true do
    local up = vim.fs.dirname(root)
    if up == root or up == home then break end
    local found = false
    for _, m in ipairs(OUTER_MARKERS) do
      if vim.uv.fs_stat(up .. "/" .. m) then found = true break end
    end
    if not found then break end
    root = up
  end
  return root
end

--- Project root and its jdt.ls client for the current buffer: the buffer's own client, else the
--- client whose root contains the buffer's file (application.yml, a module's pom.xml) or, for a buffer
--- with no file, the current directory; else the project of that file or directory without a client
--- (the caller uses the build tool); else (a no-file buffer outside any project, e.g. a run terminal)
--- the only jdt.ls client.
function M.project_root()
  local c = vim.lsp.get_clients({ bufnr = 0, name = "jdtls" })[1]
  if c then return c.config.root_dir, c end
  local name = vim.api.nvim_buf_get_name(0)
  local is_file = name ~= "" and not name:find("^%a[%w+.-]*://")
  local path = is_file and name or vim.fn.getcwd()
  c = M.client_for_path(path)
  if c then return c.config.root_dir, c end
  local root = outer_root(is_file and path or (path .. "/x"))
  if root then return root, nil end
  local clients = vim.lsp.get_clients({ name = "jdtls" })
  if not is_file and #clients == 1 then return clients[1].config.root_dir, clients[1] end
  return nil, nil
end

local function project_root() return M.project_root() end

local function is_boot_main(file)
  local text = file and read(file)
  return text ~= nil and text:find("@SpringBootApplication", 1, true) ~= nil
end

--- Launch configs (nvim-jdtls's, as for <leader>dc) of the @SpringBootApplication main classes.
local function boot_configs(client, cb)
  local bufnr = vim.lsp.get_buffers_by_client_id(client.id)[1]
  if not bufnr then return cb(nil, "no buffer attached to jdt.ls") end
  local done = false
  local function finish(c, e)
    if done then return end
    done = true
    cb(c, e)
  end
  vim.defer_fn(function() finish(nil, "jdt.ls did not answer within 60 s") end, 60000)
  client:request("workspace/executeCommand", { command = "vscode.java.resolveMainClass" }, function(err, mains)
    if err then return finish(nil, "resolveMainClass: " .. tostring(err.message)) end
    local boot = {}
    for _, m in ipairs(mains or {}) do
      if is_boot_main(m.filePath) then boot[m.mainClass] = true end
    end
    if vim.tbl_isempty(boot) then return finish({}) end
    vim.api.nvim_buf_call(bufnr, function()
      require("jdtls.dap").fetch_main_configs({}, function(configs)
        finish(vim.tbl_filter(function(c) return boot[c.mainClass] end, configs or {}))
      end)
    end)
  end, bufnr)
end

local function java_home(root)
  local rts, default = require("nv4j.jdk").runtimes(root)
  for _, rt in ipairs(rts) do
    if rt.default then return rt.path, default end
  end
  return rts[1] and rts[1].path, default
end

local function short_main(c) return (c.mainClass:match("([^.]+)$")) end

local function launch_debug(cfg, opts, home, env)
  setup_dap()
  local s = { id = #M.sessions + 1, name = short_main(cfg) .. (opts.profile and (" [" .. opts.profile .. "]") or ""),
    state = "starting", debug = true, profile = opts.profile, env = env }
  cfg = vim.deepcopy(cfg)
  cfg.name = "Spring Boot: " .. s.name
  cfg.nv4j_run_id = s.id
  cfg.javaExec = home .. "/bin/java"
  local vm = { cfg.vmArgs }
  if opts.profile then vm[#vm + 1] = "-Dspring.profiles.active=" .. opts.profile end
  vim.list_extend(vm, opts.vm_args or {})
  cfg.vmArgs = vim.trim(table.concat(vim.tbl_filter(function(v) return v and v ~= "" end, vm), " "))
  cfg.env = env
  if opts.args and #opts.args > 0 then cfg.args = table.concat(opts.args, " ") end
  pending[s.id] = s
  M.sessions[#M.sessions + 1] = s
  setup_autocmds() -- VimLeavePre stops a debugged app too
  local ok, err = pcall(require("dap").run, cfg)
  if not ok then
    pending[s.id] = nil
    s.state = "failed"
    notify(("Could not start the debug session for %s: %s"):format(s.name, tostring(err)), vim.log.levels.ERROR)
  end
  return s
end

local function launch_run(cfg, opts, home, env, root)
  local cmd = { home .. "/bin/java" }
  if cfg.vmArgs and cfg.vmArgs ~= "" then vim.list_extend(cmd, vim.split(cfg.vmArgs, "%s+", { trimempty = true })) end
  if opts.profile then cmd[#cmd + 1] = "-Dspring.profiles.active=" .. opts.profile end
  vim.list_extend(cmd, opts.vm_args or {})
  if cfg.modulePaths and #cfg.modulePaths > 0 then vim.list_extend(cmd, { "--module-path", table.concat(cfg.modulePaths, ":") }) end
  if cfg.classPaths and #cfg.classPaths > 0 then vim.list_extend(cmd, { "-cp", table.concat(cfg.classPaths, ":") }) end
  cmd[#cmd + 1] = cfg.mainClass
  vim.list_extend(cmd, opts.args or {})
  local name = short_main(cfg) .. (opts.profile and (" [" .. opts.profile .. "]") or "")
  require("nv4j.debug").refresh_and_build(root, function()
    M.start_terminal({ cmd = cmd, cwd = cfg.cwd or root, env = env, name = name, profile = opts.profile })
  end, "run")
end

--- Run (or debug) the Spring Boot app of the current project.
--- opts.tool ("maven" | "gradle" | "build", default vim.g.nv4j_run_tool) runs through the build tool
--- even with jdt.ls attached ("maven"/"build": Maven first, "gradle": Gradle first); debug ignores it.
---@param opts { debug: boolean|nil, profile: string|nil, env: table|nil, vm_args: string[]|nil, args: string[]|nil, tool: string|nil }|nil
function M.spring_boot(opts)
  opts = opts or {}
  if opts.profile == "" then opts.profile = nil end
  local root, client = project_root()
  if not root then return notify("No pom.xml or build.gradle above this buffer", vim.log.levels.WARN) end
  local bname = vim.api.nvim_buf_get_name(0)
  local module_root = bname ~= "" and not bname:find("^%a[%w+.-]*://") and vim.fs.root(0, BUILD_MARKERS) or nil
  if module_root and not (module_root == root or module_root:sub(1, #root + 1) == root .. "/") then module_root = nil end
  if not (M.is_boot(root) or M.is_boot(module_root)) then
    return notify(("Not a Spring Boot project (no org.springframework.boot in the build file of %s). "
      .. "<leader>rj runs a plain main class."):format(vim.fn.fnamemodify(root, ":~")), vim.log.levels.WARN)
  end
  local home = java_home(root)
  if not home then return notify("No JDK found for this project (nv4j.jdk)", vim.log.levels.ERROR) end
  local env = vim.tbl_extend("force", opts.env or {}, { JAVA_HOME = home })

  local tool = opts.tool or vim.g.nv4j_run_tool
  if tool == "build" then tool = "maven" end
  if client and tool and opts.debug then
    notify("Debug runs through jdt.ls (vim.g.nv4j_run_tool applies to run only)")
    tool = nil
  end
  if not client or tool then
    if opts.debug then
      return notify("Debug needs jdt.ls: open a Java file of the project first", vim.log.levels.WARN)
    end
    if not client then notify(("jdt.ls is not attached for %s: running with the build tool"):format(vim.fn.fnamemodify(root, ":~"))) end
    -- run in the Boot module, not at the aggregator: spring-boot:run / bootRun there would run the
    -- whole reactor (Maven needs the sibling modules installed: mvn install once)
    local module = require("nv4j.root").boot_module(root, module_root) or root
    local cmd, extra = M.build_tool_command(module, vim.tbl_extend("force", opts, { prefer = tool }), root)
    if not cmd then return notify("No pom.xml or build.gradle in " .. module, vim.log.levels.WARN) end
    env = vim.tbl_extend("force", env, extra, { PATH = home .. "/bin:" .. (vim.env.PATH or "") })
    return M.start_terminal({ cmd = cmd, cwd = module, env = env, profile = opts.profile,
      name = vim.fs.basename(module) .. " (" .. vim.fs.basename(cmd[1]) .. ")" .. (opts.profile and (" [" .. opts.profile .. "]") or "") })
  end

  boot_configs(client, function(configs, err)
    if not configs then return notify("Could not find the main class: " .. tostring(err), vim.log.levels.ERROR) end
    if #configs == 0 then
      return notify("No @SpringBootApplication main class found (jdt.ls). <leader>rj runs a plain main class.", vim.log.levels.WARN)
    end
    local function go(cfg)
      if not cfg then return end
      if opts.debug then return launch_debug(cfg, opts, home, env) end
      launch_run(cfg, opts, home, env, root)
    end
    if #configs == 1 then return go(configs[1]) end
    table.sort(configs, function(a, b) return a.mainClass < b.mainClass end)
    vim.ui.select(configs, { prompt = "Run which Spring Boot app?", format_item = function(c) return c.mainClass end }, go)
  end)
end

--- Profiles found as application-<profile>.properties/.yml/.yaml under src/main/resources of the project
--- and of the current module.
function M.profiles()
  local found, out = {}, {}
  for _, root in ipairs({ (project_root()), vim.fs.root(0, BUILD_MARKERS) }) do
    local dir = root and (root .. "/src/main/resources")
    for name in vim.fs.dir(dir or "") do
      local p = name:match("^application%-(.+)%.properties$") or name:match("^application%-(.+)%.ya?ml$")
      if p and not found[p] then
        found[p] = true
        out[#out + 1] = p
      end
    end
  end
  table.sort(out)
  return out
end

--- <leader>rp: pick a profile (found ones, or type one), then run.
function M.prompt_profile(opts)
  opts = opts or {}
  local function run(p)
    if not p or p == "" then return end
    M.last_profile = p
    M.spring_boot(vim.tbl_extend("force", opts, { profile = p }))
  end
  local items = M.profiles()
  local other = "Other..."
  local function ask() vim.ui.input({ prompt = "Spring profile(s), comma separated: ", default = M.last_profile }, run) end
  if #items == 0 then return ask() end
  items[#items + 1] = other
  vim.ui.select(items, { prompt = "Spring profile" }, function(choice)
    if choice == other then return ask() end
    run(choice)
  end)
end

return M
