-- P2 debug. Run via tests/run.sh. Spec: specs/features/debug-run.md. Fixes: nvim/lua/nv4j/debug.lua.
--  classpath_first : no debug-classpath resolution fails in a fresh jdt.ls. nvim-jdtls's
--                    fetch_main_configs (LazyVim's main-class configs at attach, :JdtUpdateDebugConfig,
--                    <leader>rj) sends java executable / project settings / classpath requests per main
--                    class in parallel; JDT launching publishes its lazy provider table
--                    (JavaRuntime.getClasspathProviders) before filling it, so a concurrent first call
--                    fails with "Referenced classpath provider does not exist:
--                    org.eclipse.m2e.launchconfig.classpathProvider". Here LazyVim's own call runs as in
--                    a user session, plus BURST more fetch_main_configs the moment jdt.ls attaches. The
--                    race is timing dependent: before the fix it failed in part of the runs only.
--  configs         : every fetch_main_configs above calls back with all 3 main classes (a race loser is
--                    dropped by nvim-jdtls, or its callback never fires).
--  breakpoint_hit  : DemoApplication launched through nvim-dap (the user's config: integratedTerminal)
--                    stops at a breakpoint in LateRunner<N>.run <= 20 s after dap.run. LateRunner<N>
--                    and LateGreeting<N> (N new each run) are written by this check BEFORE jdt.ls starts,
--                    like files a `git pull` brings while Neovim is closed; only LateRunner<N> is opened
--                    (to set the breakpoint). Both are removed after the main-class cases, with their
--                    class files.
--  variable        : at that stop, `text` evaluates to "late".
--  debuggee_jdk    : the debuggee's java.version is 25 (project JDK, nv4j.jdk) although run.sh puts JDK
--                    21 first on PATH and unsets JAVA_HOME (the hostile case).
--  one_jdtls       : no jdt.ls start/attach with another root than the project (nvim-dap's terminal setup
--                    used to start a stray one with root ".").
--  no_orphan       : the marked debuggee JVM is seen alive before dap.terminate() and is gone <= 10 s after
--                    (a JVM that died by itself proves nothing and fails the case).
--  test_*          : the same for a JUnit 5 test method (java-test bundle) through nvim-jdtls's
--                    test_nearest_method (<leader>tr): stop at the breakpoint in
--                    GreetingPropertiesTest.keepsText <= 20 s, `text` = "hi", java.version 25, then continue:
--                    the run ends with 1 test, 0 failures and no JVM left.
--  junit_launcher  : nv4j.debug.junit_launcher on a synthetic classpath: JDT's bundled
--                    junit-platform-launcher is replaced by the engine-matching one from the Maven repo.
--  junit_launcher_missing : same, matching jar not downloaded: config unchanged, one warning naming it.
--  gate_robust     : the launching-command gate on a stub client: a throwing handler does not stall the
--                    queue; a stopped client answers every queued request with an error.
--  build_guard     : build before launch on stub clients: timeout, failed build (status 0) and stopped
--                    client each warn visibly and launch anyway.
-- Timings: /tmp/nv4j/logs/latency.jsonl (debug_breakpoint_hit, debug_test_breakpoint_hit).
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local P = "40_debug."
local BREAK_BUDGET_MS, ORPHAN_WAIT_MS, BURST = 20000, 10000, 3
local MARKER = "nv4j.check=40_debug" -- -D<MARKER> in the debuggee's command line, to find (and always kill) it
local MAINS = { "demo.App", "demo.DemoApplication", "demo.Modern" }

local fixture = vim.env.NV4J_FIXTURE
local src = fixture .. "/src/main/java/demo/"
local classes = fixture .. "/target/classes/demo/"

local function cleanup()
  vim.fn.system({ "pkill", "-f", MARKER })
  for _, f in ipairs(vim.fn.glob(src .. "Late*.java", false, true)) do os.remove(f) end
  for _, f in ipairs(vim.fn.glob(classes .. "Late*.class", false, true)) do os.remove(f) end
end
cleanup() -- leftovers of an aborted run

-- New class names every run: a name jdt.ls has seen before (even deleted) is not a new file to it.
local N = tostring(os.time())
local runner, greeting = "LateRunner" .. N, "LateGreeting" .. N
vim.fn.writefile({ "package demo;", "", "public record " .. greeting .. "(String text) {", "}" }, src .. greeting .. ".java")
vim.fn.writefile({
  "package demo;",
  "",
  "import org.springframework.boot.ApplicationArguments;",
  "import org.springframework.boot.ApplicationRunner;",
  "import org.springframework.stereotype.Component;",
  "",
  "@Component",
  "public class " .. runner .. " implements ApplicationRunner {",
  "    @Override",
  "    public void run(ApplicationArguments args) {",
  "        " .. greeting .. " greeting = new " .. greeting .. "(\"late\");",
  "        String text = greeting.text();",
  "        System.out.println(text);",
  "    }",
  "}",
}, src .. runner .. ".java")

-- Waits like vim.wait, but an error raised by some other callback while waiting (e.g. an LSP error
-- surfaced through vim.schedule) is recorded and the wait goes on.
local function wait_until(ms, pred, errs)
  local deadline = E.now() + ms
  while E.now() < deadline do
    local ok, r = pcall(vim.wait, math.max(1, deadline - E.now()), pred, 20)
    if ok then return r end
    errs[#errs + 1] = tostring(r):gsub("\n.*", "")
  end
  return pred()
end

-- nvim-jdtls reports a failed resolveClasspath only with print(): collect those.
local printed, all_printed = {}, {}
local orig_print = print
_G.print = function(...)
  local msg = table.concat(vim.tbl_map(tostring, { ... }), " ")
  if msg:find("classpath", 1, true) then printed[#printed + 1] = msg end
  all_printed[#all_printed + 1] = msg
  return orig_print(...)
end

-- Every jdt.ls start/attach request, by root: a debug launch must not start a second jdt.ls (nvim-dap's
-- terminal setup fires FileType java on an unnamed scratch buffer; that stray server dies in
-- `initialize`, so counting live clients would miss it).
local starts = {}
local orig_start = vim.lsp.start
vim.lsp.start = function(config, ...)
  if config and config.name == "jdtls" then starts[#starts + 1] = tostring(config.root_dir) end
  return orig_start(config, ...)
end

-- vim.notify messages (nvim-jdtls reports "No suitable test method found" and friends this way)
local notes = {}
local orig_notify = vim.notify
vim.notify = function(msg, ...)
  notes[#notes + 1] = tostring(msg):gsub("\n.*", "")
  return orig_notify(msg, ...)
end

-- BURST more fetch_main_configs the moment jdt.ls attaches, next to LazyVim's own.
local fetches = {}
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local c = vim.lsp.get_client_by_id(args.data.client_id)
    if not c or c.name ~= "jdtls" or #fetches > 0 then return end
    for i = 1, BURST do
      fetches[i] = false
      require("jdtls.dap").fetch_main_configs({}, function(configs) fetches[i] = configs end)
    end
    return true
  end,
})

local buf = lsp.open(src .. "DemoApplication.java")
local client = lsp.wait_ready(buf, 120000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready" or "jdtls not ready")
if not client then
  cleanup()
  return lsp.finish()
end

local errs = {}
local dap = require("dap")
-- Every Java launch (main class and test) gets the marker, so its JVM can be found and killed.
dap.listeners.on_config["nv4j_40"] = function(c)
  c = vim.deepcopy(c)
  if c.type == "java" then c.vmArgs = ((c.vmArgs and (c.vmArgs .. " ")) or "") .. "-D" .. MARKER end
  return c
end
local function alive() return vim.fn.system({ "pgrep", "-f", MARKER }) ~= "" end
local function pids() return (vim.trim(vim.fn.system({ "pgrep", "-f", MARKER })):gsub("\n", " ")) end

-- Synchronous DAP request on the current session (nil on error/timeout).
local function dap_req(cmd, args)
  local session = dap.session()
  if not session then return nil end
  local res
  session:request(cmd, args, function(e, r) res = e and false or r end)
  wait_until(5000, function() return res ~= nil end, errs)
  return res or nil
end

-- Breakpoint at buf:lnum, launch(), wait for `stopped`; then read the top frame, `var` and the
-- debuggee's java.version. Returns a table describing what was seen.
local function stop_at(buf, lnum, launch)
  require("dap.breakpoints").set({}, buf, lnum)
  local r = {}
  dap.listeners.after.event_stopped["nv4j_40"] = function(_, body) r.stopped = r.stopped or body end
  local t0 = E.now()
  launch()
  wait_until(BREAK_BUDGET_MS + 20000, function() return r.stopped ~= nil end, errs)
  r.ms = E.now() - t0
  dap.listeners.after.event_stopped["nv4j_40"] = nil
  if r.stopped and dap.session() then
    local st = dap_req("stackTrace", { threadId = r.stopped.threadId, levels = 1 })
    r.frame = st and st.stackFrames and st.stackFrames[1]
    local function eval(expr)
      local e = r.frame and dap_req("evaluate", { expression = expr, frameId = r.frame.id, context = "repl" })
      return e and (e.result:gsub('^"(.*)"$', "%1")) or nil
    end
    r.eval = eval
    r.jdk = eval('System.getProperty("java.version")')
  end
  r.at = r.frame and ("%s line %s"):format(r.frame.name, tostring(r.frame.line)) or "no frame"
  r.ok = r.stopped ~= nil and r.stopped.reason == "breakpoint" and r.ms <= BREAK_BUDGET_MS and r.frame ~= nil
    and r.frame.line == lnum
  return r
end

-- The debuggee's own output (integratedTerminal) explains a launch that never stops.
local function terminal_text()
  local log = ""
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buftype == "terminal" then log = log .. table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "") end
  end
  return log
end

local function report_stop(name, r, want_frame, lnum, explain)
  local ok = r.ok and r.frame.name:find(want_frame, 1, true) ~= nil
  lsp.report(P .. name, ok, r.stopped
    and ("stopped (%s) after %.0f ms (budget %d) at %s (want %s line %d)"):format(r.stopped.reason, r.ms, BREAK_BUDGET_MS, r.at, want_frame, lnum)
    or ("no stop within %.0f ms; %s"):format(r.ms, explain()))
end

local function report_value(name, r, var, want)
  local got = r.eval and r.eval(var)
  lsp.report(P .. name, got == want, ("%s = %s (want %s)"):format(var, tostring(got), want))
end

local function report_jdk(name, r)
  lsp.report(P .. name, r.jdk ~= nil and r.jdk:match("^25[%.%-+]?") ~= nil,
    ("debuggee java.version = %s (want 25; java on PATH: %s, JAVA_HOME %s)"):format(tostring(r.jdk),
      vim.trim(vim.fn.system({ "sh", "-c", "java -version 2>&1 | head -1" })), vim.env.JAVA_HOME and "set" or "unset"))
end

local ok_all, err = pcall(function()
  local function all_back()
    for _, f in ipairs(fetches) do if not f then return false end end
    return #fetches > 0
  end
  wait_until(30000, all_back, errs)
  lsp.report(P .. "classpath_first", #fetches > 0 and #printed == 0,
    #fetches == 0 and "no fetch sent (LspAttach not seen)"
      or ("%d classpath errors from nvim-jdtls%s"):format(#printed, printed[1] and (": " .. printed[1]:sub(1, 200)) or ""))
  local short = {}
  for i, f in ipairs(fetches) do
    short[#short + 1] = f and tostring(#f) or "no callback"
    if f and #f ~= #MAINS then short[i] = short[i] .. "!" end
    for _, c in ipairs(f or {}) do -- classpath size per main class: a short one misses the Maven deps
      short[i] = short[i] .. (" %s:%d"):format(c.mainClass:gsub("^demo%.", ""), #(c.classPaths or {}))
    end
  end
  local configs = fetches[1] or nil
  for _, f in ipairs(fetches) do if not f or #f ~= #MAINS then configs = nil end end
  lsp.report(P .. "configs", configs ~= nil,
    ("main classes per fetch_main_configs (want %d each): %s%s"):format(#MAINS, table.concat(short, ", "),
      (configs or not all_printed[1]) and "" or ("; printed: " .. table.concat(all_printed, " | "):sub(1, 300))))
  if not configs then
    -- launch with a fresh fetch (the table is warm now) so breakpoint_hit is still measured
    local again
    require("jdtls.dap").fetch_main_configs({}, function(c) again = c end)
    wait_until(20000, function() return again ~= nil end, errs)
    configs = again
  end
  local cfg
  for _, c in ipairs(configs or {}) do
    if c.mainClass == "demo.DemoApplication" then cfg = vim.deepcopy(c) end
  end

  -- 1. main class: DemoApplication, breakpoint in the planted LateRunner<N>
  if not cfg then
    for _, n in ipairs({ "breakpoint_hit", "variable", "debuggee_jdk", "one_jdtls", "no_orphan" }) do
      lsp.report(P .. n, false, "no launch config for demo.DemoApplication")
    end
  else
    cfg.args = "--server.port=0"
    local rbuf = lsp.open(src .. runner .. ".java")
    local lnum = E.line_of(rbuf, "System%.out%.println%(text%);") + 1
    vim.api.nvim_set_current_buf(buf) -- launch from DemoApplication.java, as a user would
    local had_class = vim.uv.fs_stat(classes .. greeting .. ".class") ~= nil
    local r = stop_at(rbuf, lnum, function() dap.run(cfg) end)
    E.log("debug_breakpoint_hit", r.stopped and r.ms or -1, 1)
    report_stop("breakpoint_hit", r, runner, lnum, function()
      local log = terminal_text()
      local why = log:match("(Unresolved compilation problems?:.-cannot be resolved[%w ]-)%s%s") or log:match("(NoClassDefFoundError: [%w%.$/]+)")
        or log:match("([%w%.]*Exception: [%w%.$/]+)")
      return ("%s.class at launch: %s; app: %s"):format(greeting, had_class and "yes" or "MISSING", why or "no error captured")
    end)
    report_value("variable", r, "text", "late")
    report_jdk("debuggee_jdk", r)
    local other = vim.tbl_filter(function(r) return r ~= fixture end, starts)
    lsp.report(P .. "one_jdtls", #starts > 0 and #other == 0,
      ("%d jdtls start/attach calls, %d with another root than the project%s"):format(#starts, #other,
        other[1] and (": " .. table.concat(other, ", ")) or ""))

    -- no_orphan: the marked JVM must be seen alive before terminate (else the check is vacuous)
    if dap.session() then dap.continue() end
    local was_alive = wait_until(3000, alive, errs)
    dap.terminate()
    wait_until(ORPHAN_WAIT_MS, function() return dap.session() == nil end, errs)
    local gone = wait_until(ORPHAN_WAIT_MS, function() return not alive() end, errs)
    lsp.report(P .. "no_orphan", was_alive and gone,
      not was_alive and "debuggee JVM not running before terminate (died by itself: nothing proven)"
        or gone and "debuggee JVM alive before terminate, gone after"
        or ("debuggee JVM still running %d s after terminate: pid %s"):format(ORPHAN_WAIT_MS / 1000, pids()))
    require("dap.breakpoints").clear()
  end
  cleanup()

  -- 2. JUnit test method (java-test bundle), through nvim-jdtls's test_nearest_method (<leader>tr)
  local tbuf = lsp.open(fixture .. "/src/test/java/demo/GreetingPropertiesTest.java")
  local tlnum = E.line_of(tbuf, 'assertEquals%("hi", text%);') + 1
  local test_done
  -- trace of the jdt.ls commands the test launch sends (explains a launch that never starts)
  local trace = {}
  local tclient = vim.lsp.get_clients({ name = "jdtls" })[1]
  local trequest = tclient.request
  tclient.request = function(self, method, params, handler, bufnr)
    if method ~= "workspace/executeCommand" or type(handler) ~= "function" then
      return trequest(self, method, params, handler, bufnr)
    end
    local i = #trace + 1
    trace[i] = (params.command or "?"):gsub("^vscode%.java%.", "") .. ":sent"
    return trequest(self, method, params, function(e, res, ...)
      trace[i] = trace[i]:gsub(":sent$", e and ":err" or res == nil and ":nil" or ":ok")
      return handler(e, res, ...)
    end, bufnr)
  end
  local r = stop_at(tbuf, tlnum, function()
    require("jdtls.dap").test_nearest_method({ bufnr = tbuf, lnum = tlnum,
      after_test = function(items, tests) test_done = { items = items or {}, tests = tests or {} } end })
  end)
  E.log("debug_test_breakpoint_hit", r.stopped and r.ms or -1, 1)
  report_stop("test_breakpoint_hit", r, "keepsText", tlnum, function()
    return ("test launch never stopped; commands: %s; notifications: %s; terminal: %s"):format(table.concat(trace, " "),
      notes[1] and table.concat(notes, " | "):sub(-300) or "none", terminal_text():gsub("%s+", " "):sub(-400))
  end)
  tclient.request = trequest
  report_value("test_variable", r, "text", "hi")
  report_jdk("test_debuggee_jdk", r)
  local test_alive = alive()
  if dap.session() then dap.continue() end
  wait_until(30000, function() return test_done ~= nil end, errs)
  local gone = wait_until(ORPHAN_WAIT_MS, function() return not alive() end, errs)
  lsp.report(P .. "test_finished", test_done ~= nil and #test_done.items == 0 and test_alive and gone,
    test_done and ("test run ended after continue: %d tests, %d failures; JVM alive at the stop: %s, gone after: %s; bundled JUnit launcher replaced: %s"):format(
      #test_done.tests, #test_done.items, tostring(test_alive), tostring(gone), (require("nv4j.debug").launchers_replaced or 0) > 0 and "yes" or "no")
      or "test run did not end within 30 s after continue")

  -- 3. the JUnit launcher fix itself, on a synthetic classpath (the real mismatch shows up in part
  --    of the jdt.ls sessions only): bundled launcher folder -> engine-matching launcher jar.
  local tmp = "/tmp/nv4j/40_debug_launcher"
  vim.fn.delete(tmp, "rf")
  local m2 = tmp .. "/m2/org/junit/platform"
  local engine = m2 .. "/junit-platform-engine/1.12.2/junit-platform-engine-1.12.2.jar"
  local launcher = m2 .. "/junit-platform-launcher/1.12.2/junit-platform-launcher-1.12.2.jar"
  local bundle = tmp .. "/org.eclipse.osgi/122/0/.cp"
  vim.fn.mkdir(vim.fs.dirname(engine), "p"); vim.fn.mkdir(vim.fs.dirname(launcher), "p"); vim.fn.mkdir(bundle .. "/META-INF", "p")
  vim.fn.writefile({}, engine); vim.fn.writefile({}, launcher)
  vim.fn.writefile({ "Manifest-Version: 1.0", "Bundle-SymbolicName: junit-platform-launcher", "Bundle-Version: 1.14.4" }, bundle .. "/META-INF/MANIFEST.MF")
  local junit = { mainClass = "org.eclipse.jdt.internal.junit.runner.RemoteTestRunner", classPaths = { "/x/test-classes", engine, bundle } }
  local fixed = require("nv4j.debug").junit_launcher(junit)
  local same = require("nv4j.debug").junit_launcher({ mainClass = junit.mainClass, classPaths = { engine, launcher, bundle } })
  lsp.report(P .. "junit_launcher", fixed.classPaths[3] == launcher and #fixed.classPaths == 3 and same.classPaths[3] == bundle,
    ("bundled launcher replaced by %s; untouched when the project has one: %s"):format(
      vim.fs.basename(fixed.classPaths[3]), tostring(same.classPaths[3] == bundle)))
  -- launcher jar not downloaded: config unchanged, one warning naming the jar (synthetic version)
  local engine9 = m2 .. "/junit-platform-engine/9.9.9/junit-platform-engine-9.9.9.jar"
  vim.fn.mkdir(vim.fs.dirname(engine9), "p"); vim.fn.writefile({}, engine9)
  local n0 = #notes
  local miss = { mainClass = junit.mainClass, classPaths = { engine9, bundle } }
  local kept = require("nv4j.debug").junit_launcher(miss)
  local n1 = #notes
  require("nv4j.debug").junit_launcher(miss)
  local warn = notes[n0 + 1] or ""
  lsp.report(P .. "junit_launcher_missing", kept.classPaths[2] == bundle and n1 == n0 + 1 and #notes == n1
      and warn:find("junit-platform-launcher-9.9.9.jar", 1, true) ~= nil and warn:find("mvn dependency:get", 1, true) ~= nil,
    ("bundled launcher kept: %s; warnings %d then %d (want 1, once): %s"):format(tostring(kept.classPaths[2] == bundle),
      n1 - n0, #notes - n1, warn:sub(1, 160)))
  vim.fn.delete(tmp, "rf")

  -- 4. the launching-command gate on a stub client: a throwing handler does not stall the queue, and
  --    when the client stops, every queued request is answered with an error (none stranded).
  local D = require("nv4j.debug")
  local sent, got = {}, {}
  local stub = { stopped = false }
  stub.request = function(self, _, params, handler)
    if self.stopped then return false end
    sent[#sent + 1] = { cmd = params.command, handler = handler }
    return true, #sent
  end
  D.serialize_until_warm(stub)
  local function ask(cmd, key)
    stub:request("workspace/executeCommand", { command = cmd }, function(e)
      if key == "A" then error("handler boom") end
      got[key] = e and e.message or "ok"
    end)
  end
  ask("vscode.java.resolveJavaExecutable", "A"); ask("vscode.java.checkProjectSettings", "B")
  ask("vscode.java.resolveClasspath", "C"); ask("vscode.java.resolveClasspath", "Dq")
  local queued_at_start = #sent
  local threw = not pcall(sent[1].handler, nil, "x") -- A answered, its handler throws
  local b_sent = #sent == 2 and sent[2].cmd == "vscode.java.checkProjectSettings"
  stub.stopped = true
  pcall(sent[2].handler, nil, true) -- B answered; sending C fails: C and Dq get the error
  local gate = stub.nv4j_gate
  lsp.report(P .. "gate_robust", queued_at_start == 1 and threw and b_sent and got.B == "ok"
      and got.C == "jdtls client stopped" and got.Dq == "jdtls client stopped" and not gate.busy and #gate.queue == 0,
    ("in flight at start %d (want 1); throwing handler rethrown %s, next sent %s; after stop: B=%s C=%s D=%s busy=%s queue=%d"):format(
      queued_at_start, tostring(threw), tostring(b_sent), tostring(got.B), tostring(got.C), tostring(got.Dq),
      tostring(gate.busy), #gate.queue))

  -- 5. build before launch on stub clients: timeout, failed build, client stopped. Each one launches
  --    anyway (done called) with a visible warning.
  local function run_build(reqfn, timeout)
    local before, t0, took = #notes, E.now(), nil
    D.build({ request = reqfn }, function() took = E.now() - t0 end, timeout)
    vim.wait(timeout + 2000, function() return took ~= nil end, 10)
    return took, table.concat(vim.list_slice(notes, before + 1), " | ")
  end
  -- (libuv timers run on the cached loop time, so the measured wait can be ~60 ms short of 1 s)
  local t_ms, t_msg = run_build(function() return true end, 1000)
  local f_ms, f_msg = run_build(function(_, _, _, h) vim.schedule(function() h(nil, 0) end) return true end, 5000)
  local s_ms, s_msg = run_build(function() return false end, 5000)
  lsp.report(P .. "build_guard", t_ms and t_ms >= 900 and t_ms < 2500 and t_msg:find("Building before debug", 1, true)
      and t_msg:find("timed out after 1 s", 1, true) and f_ms and f_ms < 1000 and f_msg:find("failed (jdt.ls build status FAILED", 1, true)
      and s_ms and s_ms < 1000 and s_msg:find("could not be sent", 1, true),
    ("timeout: %s ms '%s'; status 0: %s ms '%s'; stopped: %s ms '%s'"):format(tostring(t_ms and math.floor(t_ms)), t_msg:sub(-70),
      tostring(f_ms and math.floor(f_ms)), f_msg:sub(-80), tostring(s_ms and math.floor(s_ms)), s_msg:sub(-70)))
end)
_G.print = orig_print
cleanup()
if #errs > 0 then io.stdout:write("\nerrors while waiting: " .. table.concat(errs, " | "):sub(1, 600) .. "\n") end
if not ok_all then lsp.report(P .. "debug", false, "error: " .. tostring(err)) end
lsp.finish()
