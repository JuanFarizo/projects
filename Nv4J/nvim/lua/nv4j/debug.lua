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

local function jdtls_client(root)
  local clients = vim.lsp.get_clients({ name = "jdtls" })
  for _, c in ipairs(clients) do
    if c.config.root_dir == root then return c end
  end
  return clients[1]
end

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

--- Refresh the source folders, then two incremental builds. The refresh runs on jdt.ls's own
--- event thread and can take the workspace lock after the first build: then that build misses the
--- new files (or fails on a file deleted while jdt.ls was down: "The project was not built since
--- the source file ... could not be read"), and the second one, requested after the refresh got
--- in line, builds them. The second build is a no-op when nothing changed.
local function build(root, done)
  local client = jdtls_client(root)
  if not client then return done() end
  refresh(client.config.root_dir)
  local function once(try)
    client:request("java/buildWorkspace", false, function(err, status)
      -- BuildWorkspaceStatus: 0 failed, 1 succeeded, 2 with errors, 3 cancelled
      if not err and try == 1 then return once(2) end
      if err or status ~= 1 then
        vim.notify(("Build before debug %s; launching anyway"):format(
          err and ("failed: " .. tostring(err.message)) or (status == 2 and "has compile errors" or "did not finish")),
          vim.log.levels.WARN)
      end
      done()
    end)
  end
  once(1)
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
local WARMS = {
  ["vscode.java.resolveClasspath"] = true,
  ["vscode.java.test.junit.argument"] = true,
  ["java.project.getClasspaths"] = true,
}

--- Item 1: until one classpath has been resolved, this client sends the JDT launching commands one
--- at a time (queued in order); after that they go out in parallel as before. Wraps the client's
--- request method, so nvim-jdtls's util.execute_command and its with_java_executable (which calls
--- client:request directly) are covered alike.
local function serialize_until_warm(client)
  if client.nv4j_gate then return end
  local gate = { warm = false, busy = false, queue = {} }
  client.nv4j_gate = gate
  local request = client.request
  local function send(self, params, handler, bufnr)
    gate.busy = true
    return request(self, "workspace/executeCommand", params, function(err, result, ...)
      gate.busy = false
      if not err and WARMS[params.command] then gate.warm = true end
      handler(err, result, ...)
      local queued = gate.queue
      if gate.warm then
        gate.queue = {}
        for _, q in ipairs(queued) do request(q[1], "workspace/executeCommand", q[2], q[3], q[4]) end
      elseif queued[1] and not gate.busy then
        send(unpack(table.remove(queued, 1)))
      end
    end, bufnr)
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
    return send(self, params, handler, bufnr)
  end
end

--- Item 5: JDT's JUnit launch adds its own bundled junit-platform-launcher (1.14.x here) whenever
--- the project test classpath it computed has none, and that launcher needs the matching
--- junit-platform-engine: with Spring Boot 3.5's engine 1.12.2 the runner dies with
--- ClassNotFoundException: org.junit.platform.engine.OutputDirectoryCreator. In some jdt.ls
--- sessions the project classpath carries junit-platform-launcher, in others not (cause not found,
--- see debug-run.md). Fix: replace the bundled launcher (an extracted OSGi bundle folder) by the
--- launcher of the engine's own version from the local Maven repo (sibling folder), if downloaded.
local function is_bundled_launcher(path)
  if vim.fn.isdirectory(path) == 0 then return false end
  local ok, lines = pcall(vim.fn.readfile, path .. "/META-INF/MANIFEST.MF", "", 40)
  if not ok then return false end
  for _, l in ipairs(lines) do
    if l:match("^Bundle%-SymbolicName: junit%-platform%-launcher") then return true end
  end
  return false
end

function M.junit_launcher(config)
  if config.mainClass ~= "org.eclipse.jdt.internal.junit.runner.RemoteTestRunner" or type(config.classPaths) ~= "table" then
    return config
  end
  local base, version, bundled
  for i, p in ipairs(config.classPaths) do
    if p:find("/junit-platform-launcher-", 1, true) then return config end -- the project has one
    if not base then base, version = p:match("^(.*)/junit%-platform%-engine/([^/]+)/junit%-platform%-engine%-[^/]+%.jar$") end
    if not bundled and is_bundled_launcher(p) then bundled = i end
  end
  if not (base and bundled) then return config end
  local launcher = ("%s/junit-platform-launcher/%s/junit-platform-launcher-%s.jar"):format(base, version, version)
  if not vim.uv.fs_stat(launcher) then return config end
  config = vim.deepcopy(config)
  config.classPaths[bundled] = launcher
  M.launchers_replaced = (M.launchers_replaced or 0) + 1 -- read by tests/checks/40_debug.lua
  return config
end

--- Called on every jdtls LspAttach (LazyVim's opts.on_attach), after nvim-jdtls's setup_dap
--- registered dap.adapters.java. LazyVim's own main-class discovery sent only its first request
--- (resolveMainClass) by now; the racy ones follow in its callback and go through serialize_until_warm.
function M.on_attach(client)
  if client then serialize_until_warm(client) end
  local ok, dap = pcall(require, "dap")
  if not ok or M._adapter or type(dap.adapters.java) ~= "function" then return end
  local adapter = dap.adapters.java
  M._adapter = function(callback, config, parent)
    if config.request ~= "launch" then return adapter(callback, config, parent) end
    build(config.cwd, function() adapter(callback, config, parent) end)
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
