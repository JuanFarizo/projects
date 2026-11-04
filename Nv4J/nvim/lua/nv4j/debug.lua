-- Debug fixes on top of nvim-jdtls + nvim-dap (specs/features/debug-run.md, check 40_debug).
--  1. serialize until warm: JDT launching builds its state lazily and not thread safe
--     (JavaRuntime.initializeProviders publishes the provider map before filling it). nvim-jdtls
--     sends resolveJavaExecutable / checkProjectSettings / resolveClasspath for every main class in
--     parallel, so the first burst after jdt.ls starts can fail with "Referenced classpath provider
--     does not exist: org.eclipse.m2e.launchconfig.classpathProvider" or answer a null java
--     executable (nvim-jdtls then drops that main class). Sequential calls never failed: these
--     commands go one at a time until a classpath resolved, then in parallel as before.
--  2. refresh + build before launch: jdt.ls does not see files added while it was down (Eclipse
--     never refreshed their folder) and nvim-jdtls does not build before a launch (VS Code does,
--     java.debug.settings.forceBuildBeforeLaunch). Before every Java launch the source folders are
--     refreshed, then incremental java/buildWorkspace runs (twice, see build()). A refresh at
--     ServiceReady was tried and dropped: resolveClasspath then returned classpaths without the
--     Maven dependencies.
--  3. no orphan: a debuggee started in nvim-dap's integrated terminal survives terminate/disconnect
--     (java-debug only drops its JDWP connection). Stop the terminal job when the session closes,
--     unless the user detached on purpose.
--  4. no stray jdt.ls: nvim-dap's terminal setup calls vim.filetype.get_option("java", "path"),
--     which fires FileType java on an unnamed scratch buffer, and LazyVim starts a jdt.ls for it
--     (root "."). jdtls.start_or_attach is skipped for unnamed buffers.
--  5. JUnit launcher version: see M.junit_launcher.
local M = {}

function M.setup()
  if M._setup then return end
  M._setup = true

  local jdtls = require("jdtls")
  local start_or_attach = jdtls.start_or_attach
  jdtls.start_or_attach = function(config, opts, start_opts)
    local buf = start_opts and start_opts.bufnr or vim.api.nvim_get_current_buf()
    if vim.api.nvim_buf_get_name(buf) == "" then return end
    return start_or_attach(config, opts, start_opts)
  end
end

--- The jdt.ls client of the project at `root` (deepest client root that is `root` or an ancestor of
--- it, nv4j/root.lua), or nil.
local function jdtls_client(root)
  return require("nv4j.root").client_for_path(root)
end
M.jdtls_client = jdtls_client -- read by tests/checks/41_run.lua

--- Source folders (`src`) of the project at `root` and of its modules (4 levels down), skipping
--- hidden, build output and node_modules folders.
local function source_dirs(root)
  local dirs = {}
  local function skip(rel)
    local b = vim.fs.basename(rel)
    return not (b == "src" or b:sub(1, 1) == "." or b == "target" or b == "build" or b == "node_modules")
  end
  for rel, kind in vim.fs.dir(root, { depth = 4, skip = skip }) do
    if kind == "directory" and vim.fs.basename(rel) == "src" then dirs[#dirs + 1] = root .. "/" .. rel end
  end
  return dirs
end

--- jdt.ls only sees files created while it was down once Eclipse refreshes their folder. A
--- didChangeWatchedFiles "Changed" event on a folder makes it run refreshLocal(DEPTH_INFINITE) on
--- that folder (IBuildSupport.refresh), on its own event thread, and autobuild compiles what it
--- finds.
local function refresh(root)
  local client = jdtls_client(root)
  root = client and client.config.root_dir
  if not root then return end
  local changes = vim.tbl_map(function(d) return { uri = vim.uri_from_fname(d), type = 2 } end, source_dirs(root))
  if #changes > 0 then client:notify("workspace/didChangeWatchedFiles", { changes = changes }) end
end

local BUILD_TIMEOUT_MS = 60000 -- for both builds together; a launch goes ahead after it, with a warning
local BUILD_STATUS = { [0] = "failed (jdt.ls build status FAILED, see :JdtShowLogs)", [2] = "has compile errors",
  [3] = "was cancelled" }

--- Two incremental builds on `client`, then done() (always, at most `timeout_ms` later). The refresh
--- runs on jdt.ls's own event thread and can take the workspace lock after the first build: then
--- that build misses the new files (or fails on a file deleted while jdt.ls was down: "The project
--- was not built since the source file ... could not be read"), and the second one, requested after
--- the refresh got in line, builds them. The second build is a no-op when nothing changed.
--- `what` names the launch in the messages ("debug" by default, "run" from nv4j.run).
function M.build(client, done, timeout_ms, what)
  timeout_ms = timeout_ms or BUILD_TIMEOUT_MS
  what = what or "debug"
  local finished = false
  local function finish(problem)
    if finished then return end
    finished = true
    if problem then vim.notify("Build before " .. what .. " " .. problem .. "; launching anyway", vim.log.levels.WARN) end
    done()
  end
  vim.notify("Building before " .. what .. "...", vim.log.levels.INFO)
  vim.uv.update_time() -- timers start from libuv's cached loop time; stale after a busy tick, the timeout fired ~330 ms early
  vim.defer_fn(function() finish(("timed out after %g s"):format(timeout_ms / 1000)) end, timeout_ms)
  local function once(try)
    local sent = client:request("java/buildWorkspace", false, function(err, status)
      if not err and try == 1 then return once(2) end
      if err then return finish("failed: " .. tostring(err.message)) end
      finish(status ~= 1 and (BUILD_STATUS[status] or ("ended with status " .. tostring(status))) or nil)
    end)
    if not sent then finish("could not be sent (jdtls client stopped)") end
  end
  once(1)
end

--- Refresh the source folders of the project at `root`, then M.build. Also used by nv4j.run.
function M.refresh_and_build(root, done, what)
  local client = jdtls_client(root)
  if not client then return done() end
  refresh(client.config.root_dir)
  M.build(client, done, nil, what)
end

local function terminal_job(session)
  local buf = session.term_buf
  return buf and vim.api.nvim_buf_is_valid(buf) and vim.b[buf].terminal_job_id or nil
end

-- Commands that go through JDT launching (java-debug's vscode.java.*, java-test's
-- vscode.java.test.*, jdt.ls's getClasspaths) and those whose success means its lazy state is built.
local function launching(cmd)
  return cmd:find("^vscode%.java%.") ~= nil or cmd == "java.project.getClasspaths"
end
local STOPPED = { code = -32603, message = "jdtls client stopped" }
local WARMS = {
  ["vscode.java.resolveClasspath"] = true,
  ["vscode.java.test.junit.argument"] = true,
  ["java.project.getClasspaths"] = true,
}

--- Item 1: until one classpath has been resolved, this client sends the JDT launching commands one
--- at a time (queued in order); after that they go out in parallel as before. Wraps the client's
--- request method, so nvim-jdtls's util.execute_command and its with_java_executable (which calls
--- client:request directly) are covered alike. A throwing handler or a stopped client never leaves
--- the gate busy or requests stranded in the queue (they are answered with an error).
function M.serialize_until_warm(client)
  if client.nv4j_gate then return end
  local gate = { warm = false, busy = false, queue = {} }
  client.nv4j_gate = gate
  local request = client.request
  local send
  local function drain()
    local queued = gate.queue
    if gate.warm then
      gate.queue = {}
      for _, q in ipairs(queued) do request(q[1], "workspace/executeCommand", q[2], q[3], q[4]) end
    elseif queued[1] and not gate.busy then
      local q = table.remove(queued, 1)
      send(q[1], q[2], q[3], q[4], true)
    end
  end
  -- `from_queue`: the caller already got `true`, so a send that fails must answer its handler.
  send = function(self, params, handler, bufnr, from_queue)
    gate.busy = true
    local ok, id = request(self, "workspace/executeCommand", params, function(err, result, ...)
      gate.busy = false
      if not err and WARMS[params.command] then gate.warm = true end
      local hok, herr = pcall(handler, err, result, ...) -- a throwing handler must not stall the queue
      drain()
      if not hok then error(herr, 0) end
    end, bufnr)
    if not ok then -- client stopped: nothing queued can be answered any more
      gate.busy = false
      local queued = gate.queue
      gate.queue = {}
      if from_queue then pcall(handler, STOPPED, nil) end
      for _, q in ipairs(queued) do pcall(q[3], STOPPED, nil) end
    end
    return ok, id
  end
  client.request = function(self, method, params, handler, bufnr)
    if gate.warm or method ~= "workspace/executeCommand" or type(handler) ~= "function"
      or not launching(params.command or "") then
      return request(self, method, params, handler, bufnr)
    end
    if gate.busy then
      gate.queue[#gate.queue + 1] = { self, params, handler, bufnr }
      return true
    end
    return send(self, params, handler, bufnr, false)
  end
end

--- Item 5: JDT's JUnit launch adds its own bundled junit-platform-launcher (1.14.x here) whenever
--- the project test classpath it computed has none, and that launcher needs the matching
--- junit-platform-engine: with Spring Boot 3.5's engine 1.12.2 the runner dies with
--- ClassNotFoundException: org.junit.platform.engine.OutputDirectoryCreator. In some jdt.ls
--- sessions the project classpath carries junit-platform-launcher, in others not (cause not found,
--- see debug-run.md). Fix: replace the bundled launcher (an extracted OSGi bundle folder) by the
--- launcher of the engine's own version from the local Maven repo (sibling folder) or, for a Gradle project, from
--- the Gradle cache (`.../org.junit.platform/junit-platform-engine/<ver>/<hash>/junit-platform-engine-<ver>.jar`, the
--- launcher is `.../junit-platform-launcher/<ver>/<hash>/junit-platform-launcher-<ver>.jar`; the hash folder differs
--- per jar, hence a glob). When that jar is not downloaded (or the engine is in neither layout) a one-time
--- warning says what is needed, instead of a silent ClassNotFoundException. A run that still dies is never
--- reported as 0 passed / 0 failed (nv4j/tests.lua, G1 in specs/006-p4-gradle.md).
local function bundle_name(path) -- Bundle-SymbolicName of an extracted OSGi bundle folder, or nil
  if vim.fn.isdirectory(path) == 0 then return nil end
  local ok, lines = pcall(vim.fn.readfile, path .. "/META-INF/MANIFEST.MF", "", 40)
  if not ok then return nil end
  for _, l in ipairs(lines) do
    local name = l:match("^Bundle%-SymbolicName: ([%w%.%-_]+)")
    if name then return name end
  end
end

local function is_bundled_launcher(path)
  return (bundle_name(path) or ""):find("^junit%-platform%-launcher") ~= nil
end

--- JDT also adds its own junit-jupiter-api/-engine (5.14.x) bundle folders when its view of the project
--- classpath lacks them. When the classpath has the project's jar of the same artifact as well, the bundle
--- is a second copy of other version and whichever comes first is loaded: Jupiter 5.14 on platform 1.12
--- dies with NoSuchMethodError in JupiterTestEngine.discover. The project's jar wins: the bundle is dropped.
local function drop_shadowing_bundles(config, seen)
  local have, drop = {}, {}
  for i, p in ipairs(config.classPaths) do
    local art = p:match("/(junit%-[%a%-]+)%-%d[^/]*%.jar$")
    if art then have[art] = true end
  end
  for i, p in ipairs(config.classPaths) do
    local name = bundle_name(p)
    if name and (name:find("^junit%-jupiter") or name:find("^junit%-platform")) and not name:find("^junit%-platform%-launcher") then
      seen.bundles[#seen.bundles + 1] = i .. ":" .. name
      if have[name] then drop[i] = true end
    end
  end
  if not next(drop) then return config end
  config = vim.deepcopy(config)
  local kept = {}
  for i, p in ipairs(config.classPaths) do
    if drop[i] then seen.dropped = (seen.dropped or 0) + 1 else kept[#kept + 1] = p end
  end
  config.classPaths = kept
  return config
end

local warned = {}
local function warn_once(key, msg)
  if warned[key] then return end
  warned[key] = true
  vim.notify(msg, vim.log.levels.WARN)
end

function M.junit_launcher(config)
  if config.mainClass ~= "org.eclipse.jdt.internal.junit.runner.RemoteTestRunner" or type(config.classPaths) ~= "table" then
    return config
  end
  local base, version, bundled, gradle
  -- what the hook saw, for the failure details of tests/checks/40_debug.lua (a mismatch shows up in some runs only)
  local seen = { junit = {}, bundles = {} }
  M.last_junit = seen
  config = drop_shadowing_bundles(config, seen)
  for i, p in ipairs(config.classPaths) do
    if p:find("junit-platform", 1, true) or p:find("junit-jupiter", 1, true) then seen.junit[#seen.junit + 1] = i .. ":" .. p end
    if p:find("/junit-platform-launcher-", 1, true) then seen.project_launcher = true; return config end -- the project has one
    if not base then
      base, version = p:match("^(.*)/junit%-platform%-engine/([^/]+)/junit%-platform%-engine%-[^/]+%.jar$") -- Maven repository
      if not base then
        base, version = p:match("^(.*)/junit%-platform%-engine/([^/]+)/[^/]+/junit%-platform%-engine%-[^/]+%.jar$") -- Gradle cache
        gradle = base ~= nil
      end
    end
    if not bundled and is_bundled_launcher(p) then bundled = i end
  end
  seen.engine, seen.bundled = version, bundled
  if not bundled then return config end
  if not base then
    warn_once("other", "JUnit: JDT adds its bundled junit-platform-launcher to this test run and no junit-platform-engine"
      .. " jar from a Maven repository or the Gradle cache is on the classpath. If the run fails with"
      .. " ClassNotFoundException or NoSuchMethodError in org.junit.platform, add junit-platform-launcher of your"
      .. " engine's version as a test dependency.")
    return config
  end
  local launcher
  if gradle then
    local dir = ("%s/junit-platform-launcher/%s"):format(base, version)
    launcher = vim.fn.glob(("%s/*/junit-platform-launcher-%s.jar"):format(dir, version), false, true)[1]
  else
    launcher = ("%s/junit-platform-launcher/%s/junit-platform-launcher-%s.jar"):format(base, version, version)
    if not vim.uv.fs_stat(launcher) then launcher = nil end
  end
  if not launcher then
    warn_once(version, ("JUnit: JDT adds its bundled junit-platform-launcher, which may not match junit-platform-engine %s"
      .. " (ClassNotFoundException/NoSuchMethodError in org.junit.platform). Needed: junit-platform-launcher-%s.jar in %s. Add it as"
      .. " a test dependency (Gradle: testRuntimeOnly 'org.junit.platform:junit-platform-launcher'; Maven: `mvn"
      .. " dependency:get -Dartifact=org.junit.platform:junit-platform-launcher:%s`)."):format(version, version, base, version))
    return config
  end
  config = vim.deepcopy(config)
  config.classPaths[bundled] = launcher
  seen.replaced_by = launcher
  -- the launcher is looked up by the engine's version, so those match; a Jupiter 5.x engine of another
  -- minor than the platform engine (5.N = platform 1.N) is what NoSuchMethodError in
  -- JupiterTestEngine.discover means, and is named instead of failing silently
  for _, p in ipairs(config.classPaths) do
    local jv = p:match("/junit%-jupiter%-engine%-(5%.%d+[%d%.]*)%.jar$")
    local want = jv and tonumber(jv:match("^5%.(%d+)"))
    local have = version and tonumber(version:match("^1%.(%d+)"))
    if want and have and want ~= have then
      seen.jupiter_mismatch = jv
      warn_once("jupiter" .. jv .. version, ("JUnit: junit-jupiter-engine %s needs junit-platform-engine 1.%d but the classpath has %s"
        .. " (NoSuchMethodError in JupiterTestEngine.discover): align the JUnit versions of the project."):format(jv, want, version))
    end
  end
  M.launchers_replaced = (M.launchers_replaced or 0) + 1 -- read by tests/checks/40_debug.lua
  return config
end

--- Called on every jdtls LspAttach (LazyVim's opts.on_attach), after nvim-jdtls's setup_dap
--- registered dap.adapters.java. LazyVim's own main-class discovery sent only its first request
--- (resolveMainClass) by now; the racy ones follow in its callback and go through M.serialize_until_warm.
function M.on_attach(client)
  if client then M.serialize_until_warm(client) end
  local ok, dap = pcall(require, "dap")
  if not ok or M._adapter or type(dap.adapters.java) ~= "function" then return end
  local adapter = dap.adapters.java
  M._adapter = function(callback, config, parent)
    if config.request ~= "launch" then return adapter(callback, config, parent) end
    -- config.nv4j_what names the launch in the build messages (nv4j.tests: "test run"/"test debug")
    M.refresh_and_build(config.cwd, function() adapter(callback, config, parent) end, config.nv4j_what)
  end
  dap.adapters.java = M._adapter
  dap.listeners.on_config["nv4j_junit_launcher"] = M.junit_launcher

  -- Whenever a Java launch session closes (terminate, disconnect, adapter gone), its terminal job
  -- is stopped; a finished debuggee makes this a no-op. Only an explicit detach
  -- (disconnect with terminateDebuggee = false) leaves the debuggee running.
  -- java-debug sends `initialized` after the debuggee started (runInTerminal answered), so the
  -- job is taken here: the terminal buffer is pooled and may hold another job by close time.
  dap.listeners.after.event_initialized["nv4j"] = function(session)
    if session.config.type ~= "java" or session.config.request ~= "launch" then return end
    local job = terminal_job(session)
    session.on_close["nv4j_debuggee"] = function(s)
      job = job or terminal_job(s)
      if job and not s.nv4j_detached then pcall(vim.fn.jobstop, job) end
    end
  end
  dap.listeners.before.disconnect["nv4j"] = function(session, _, _, args)
    session.nv4j_detached = type(args) == "table" and args.terminateDebuggee == false
  end
end

return M
