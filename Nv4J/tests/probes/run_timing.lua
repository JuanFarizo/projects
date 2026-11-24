-- Timing probe for run / debug / test run start (not a check; specs/features/run-speed.md).
-- Run: tests/probes/run_timing.sh <maven|gradle> <scenario list, e.g. run,run,debug,debug_bp,test,test>
-- Copies the fixture to /tmp/nv4j/probe-<pid> (planted ApplicationRunner for the breakpoint), waits for jdt.ls,
-- then runs the scenarios in order in ONE nvim and prints one `T <proj> <scenario>#n key=value ...` line each.
-- Steps (ms from the key press): main = until the build starts (main class + launch config: resolveMainClass +
-- fetch_main_configs), build = nv4j.debug.refresh_and_build (refresh + builds), start = process/session started,
-- out = first output line, up = "Started ... in" (run, debug), breakpoint stop (debug_bp) or test run end (test).
vim.o.confirm = false
vim.o.columns = 300
local lsp = require("lsp")
local E = require("edit")
local proj = vim.env.PROBE_PROJECT or "maven"
local scenarios = vim.split(vim.env.PROBE_SCENARIOS or "run,run", ",")
local hr = function() return vim.uv.hrtime() / 1e6 end
local function out(line) io.stdout:write(line .. "\n") end

local TMP = "/tmp/nv4j/probe-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
local fixture, mainfile, testfile, pkg, mainclass
if proj == "maven" then
  fixture = vim.env.NV4J_FIXTURE
  for _, n in ipairs({ "src", "pom.xml" }) do vim.fn.system({ "cp", "-R", fixture .. "/" .. n, TMP .. "/" }) end
  pkg, mainclass, mainfile = "demo", "DemoApplication", "DemoApplication.java"
  testfile = "src/test/java/demo/GreetingPropertiesTest.java"
else
  fixture = vim.env.NV4J_GRADLE_FIXTURE
  for _, n in ipairs({ "src", "gradle", "gradlew", "build.gradle", "settings.gradle" }) do vim.fn.system({ "cp", "-R", fixture .. "/" .. n, TMP .. "/" }) end
  vim.fn.writefile(vim.split((table.concat(vim.fn.readfile(TMP .. "/build.gradle"), "\n"):gsub("JavaVersion%.VERSION_21", "JavaVersion.VERSION_25")), "\n", { plain = true }), TMP .. "/build.gradle")
  pkg, mainclass, mainfile = "gradleboot", "GradleBootApplication", "GradleBootApplication.java"
  testfile = "src/test/java/gradleboot/CalculatorTest.java"
end
TMP = vim.uv.fs_realpath(TMP)
local src = TMP .. "/src/main/java/" .. pkg .. "/"
local runner = "ProbeRunner" .. os.time()
vim.fn.writefile({ "package " .. pkg .. ";", "import org.springframework.boot.ApplicationArguments;", "import org.springframework.boot.ApplicationRunner;",
  "import org.springframework.stereotype.Component;", "@Component", "public class " .. runner .. " implements ApplicationRunner {",
  "    @Override", "    public void run(ApplicationArguments args) {", "        String text = \"late\";", "        System.out.println(text);", "    }", "}" },
  src .. runner .. ".java")
local MARK = "nv4j.probe=" .. vim.fn.getpid()

local buf = lsp.open(src .. mainfile)
local client, why = lsp.wait_ready(buf, 300000)
if not client then out("T " .. proj .. " NOT READY " .. tostring(why)) return lsp.finish() end
out(("# jdtls root %s ready"):format(client.config.root_dir))

local R = require("nv4j.run")
local D = require("nv4j.debug")
local dap = require("dap")
local ev -- current event timeline
local t0
local function mark(name) if ev and not ev[name] then ev[name] = hr() - t0 end end

-- wrap: every executeCommand (time to answer), java/buildWorkspace, fetch_main_configs, refresh_and_build, start_terminal
local req = client.request
client.request = function(self, method, params, handler, bufnr)
  if ev and method == "workspace/executeCommand" and type(handler) == "function" then
    local c, s = (params.command or "?"):gsub("^vscode%.java%.", ""), hr()
    ev.cmds[#ev.cmds + 1] = c
    return req(self, method, params, function(...)
      ev.cmdms[c] = (ev.cmdms[c] or 0) + (hr() - s)
      return handler(...)
    end, bufnr)
  end
  if ev and method == "java/buildWorkspace" and type(handler) == "function" then
    local s = hr()
    return req(self, method, params, function(...)
      ev.builds[#ev.builds + 1] = hr() - s
      return handler(...)
    end, bufnr)
  end
  return req(self, method, params, handler, bufnr)
end
local jd = require("jdtls.dap")
local fmc = jd.fetch_main_configs
jd.fetch_main_configs = function(o, cb)
  local s = hr()
  return fmc(o, function(...) if ev then ev.fmc = (ev.fmc or 0) + (hr() - s) end cb(...) end)
end
local rb = D.refresh_and_build
D.refresh_and_build = function(root, done, what)
  local s = hr()
  mark("build_start")
  return rb(root, function() if ev then ev.build = hr() - s end mark("build_end") done() end, what)
end
local st = R.start_terminal
R.start_terminal = function(o) mark("start") return st(o) end
dap.listeners.after.event_initialized["probe"] = function() mark("start") end

local function wait_until(ms, pred)
  local deadline = E.now() + ms
  while E.now() < deadline do
    if pred() then return true end
    vim.wait(5)
  end
  return pred()
end
local function text(b)
  if not (b and vim.api.nvim_buf_is_valid(b)) then return "" end
  return table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
end
local function stop_all()
  pcall(function() dap.terminate() end)
  R.stop_all()
  wait_until(15000, function() return vim.fn.system({ "pgrep", "-f", MARK }) == "" end)
  vim.wait(500)
  for _, s in ipairs(R.sessions) do pcall(R.close, s) end
end
local function report(name, i)
  local f = {}
  for _, k in ipairs({ "main", "build", "start", "out", "up" }) do f[#f + 1] = ("%s=%s"):format(k, ev[k] and ("%.0f"):format(ev[k]) or "-") end
  local cm = {}
  for c, ms in pairs(ev.cmdms) do cm[#cm + 1] = ("%s:%.0f"):format(c, ms) end
  table.sort(cm)
  local b = vim.tbl_map(function(x) return ("%.0f"):format(x) end, ev.builds)
  out(("T %s %s#%d %s | fmc=%s builds=[%s] cmds{%s}"):format(proj, name, i, table.concat(f, " "), ev.fmc and ("%.0f"):format(ev.fmc) or "-",
    table.concat(b, ","), table.concat(cm, " ")))
end

dap.listeners.on_config["probe"] = function(c)
  c = vim.deepcopy(c)
  if c.type == "java" then c.vmArgs = ((c.vmArgs and (c.vmArgs .. " ")) or "") .. "-D" .. MARK end
  return c
end
local rbuf = lsp.open(src .. runner .. ".java")
local lnum = E.line_of(rbuf, "System%.out%.println%(text%);") + 1
vim.api.nvim_set_current_buf(buf)
local env = { SERVER_PORT = "0" }

local seen = {}
for _, sc in ipairs(scenarios) do
  seen[sc] = (seen[sc] or 0) + 1
  ev = { cmds = {}, cmdms = {}, builds = {} }
  require("dap.breakpoints").clear()
  vim.api.nvim_set_current_buf(buf)
  t0 = hr()
  if sc == "run" then
    local n = #R.sessions
    R.spring_boot({ env = env, vm_args = { "-D" .. MARK } })
    wait_until(60000, function() return #R.sessions > n end)
    mark("session")
    local s = R.sessions[n + 1]
    if s then
      wait_until(90000, function()
        local t = text(s.buf)
        if not ev.out and t:find("%S") then mark("out") end
        if t:find("Started " .. mainclass .. " in", 1, true) then mark("up") return true end
      end)
    end
  elseif sc == "debug" or sc == "debug_bp" then
    local stopped
    if sc == "debug_bp" then require("dap.breakpoints").set({}, rbuf, lnum) end
    dap.listeners.after.event_stopped["probe"] = function() stopped = true mark("stop") end
    local n = #R.sessions
    R.spring_boot({ debug = true, env = env, vm_args = { "-D" .. MARK } })
    wait_until(60000, function() return #R.sessions > n end)
    mark("session")
    wait_until(90000, function()
      local sess = dap.session()
      local t = text(sess and sess.term_buf)
      if not ev.out and t:find("%S") then mark("out") end
      if t:find("Started " .. mainclass .. " in", 1, true) then mark("up") end
      if sc == "debug_bp" then return stopped end
      return ev.up ~= nil
    end)
    if sc == "debug_bp" then ev.up = ev.stop end
    dap.listeners.after.event_stopped["probe"] = nil
  elseif sc == "test" then
    local tb = lsp.open(TMP .. "/" .. testfile)
    local done
    require("nv4j.tests").run({ scope = "file", bufnr = tb, on_done = function(r) done = r mark("up") end })
    wait_until(120000, function() return done ~= nil end)
    ev.out = ev.start
    vim.api.nvim_set_current_buf(buf)
  end
  ev.main = ev.build_start or 0
  report(sc, seen[sc])
  stop_all()
  vim.wait(1500)
end
vim.fn.system({ "pkill", "-f", MARK })
vim.fn.delete(TMP, "rf")
lsp.finish()
