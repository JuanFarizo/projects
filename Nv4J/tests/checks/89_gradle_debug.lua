-- Breakpoint hit in a Gradle Spring Boot app (specs/features/debug-run.md, Gradle; twin of 40_debug.breakpoint_hit on Maven).
-- Run via tests/run.sh (needs NV4J_GRADLE_FIXTURE = tests/fixtures/gradle-boot; skipped like 67 when Gradle cannot resolve it).
-- HEAVY: real jdt.ls with a Gradle import (slower than Maven). The fixture is COPIED to /tmp/nv4j (the fixture stays clean) with
-- an ApplicationRunner planted in the copy BEFORE jdt.ls starts and build.gradle set to Java 25 (the hostile case: run.sh puts
-- JDK 21 first on PATH, so only the project JDK from nv4j.jdk can make the debuggee report 25).
--  attached        : jdt.ls ready on the copy (Gradle import done), root_dir is the copy.
--  configs         : fetch_main_configs lists gradleboot.GradleBootApplication with a classpath that has the Boot jars.
--  breakpoint_hit  : GradleBootApplication launched through nvim-dap (the config jdt.ls resolved, as <leader>rd) stops at the
--                    breakpoint in GradleRunner<N>.run <= 20 s after dap.run (measured about 2 s; Maven check 40 uses 20 s too), reason "breakpoint", right line.
--  variable        : at that stop, `text` evaluates to "late".
--  debuggee_jdk    : the debuggee's java.version is 25 (project JDK) although JDK 21 is first on PATH.
--  one_jdtls       : no jdt.ls start/attach with another root than the copy.
--  no_orphan       : the marked debuggee JVM is seen alive before dap.terminate() and is gone <= 10 s after.
-- Timings: /tmp/nv4j/logs/latency.jsonl (gradle_debug_breakpoint_hit).
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local P = "89_gradle_debug."
local BREAK_BUDGET_MS, ORPHAN_WAIT_MS = 20000, 10000
local CONTROL = vim.env.NV4J_89_CONTROL or "" -- nobp: no breakpoint set; jdk21: the project keeps Java 21 (debuggee_jdk must then FAIL)
local MARKER = "nv4j.check=89_gradle_debug" -- -D<MARKER> in the debuggee's command line, to find (and always kill) it
local MAIN = "gradleboot.GradleBootApplication"

local fixture = vim.env.NV4J_GRADLE_FIXTURE
if not fixture or vim.fn.isdirectory(fixture) == 0 then
  lsp.report(P .. "attached", false, "NV4J_GRADLE_FIXTURE not set or not a directory (run through tests/run.sh)")
  return lsp.finish()
end
local TMP = "/tmp/nv4j/gradle89-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
for _, name in ipairs({ "src", "gradle", "gradlew", "build.gradle", "settings.gradle" }) do
  vim.fn.system({ "cp", "-R", fixture .. "/" .. name, TMP .. "/" })
end
TMP = vim.uv.fs_realpath(TMP)
local function cleanup()
  vim.fn.system({ "pkill", "-f", MARKER })
  vim.fn.delete(TMP, "rf")
end
vim.fn.system({ "pkill", "-f", MARKER }) -- leftovers of an aborted run

-- Hostile JDK: the project asks for 25; the JDK on PATH is 21.
local bg = CONTROL:find("jdk21", 1, true) and "" or table.concat(vim.fn.readfile(TMP .. "/build.gradle"), "\n"):gsub("JavaVersion%.VERSION_21", "JavaVersion.VERSION_25")
if bg ~= "" then vim.fn.writefile(vim.split(bg, "\n", { plain = true }), TMP .. "/build.gradle") end

local src = TMP .. "/src/main/java/gradleboot/"
local N = tostring(os.time())
local runner = "GradleRunner" .. N
vim.fn.writefile({
  "package gradleboot;",
  "",
  "import org.springframework.boot.ApplicationArguments;",
  "import org.springframework.boot.ApplicationRunner;",
  "import org.springframework.stereotype.Component;",
  "",
  "@Component",
  "public class " .. runner .. " implements ApplicationRunner {",
  "    @Override",
  "    public void run(ApplicationArguments args) {",
  "        String text = \"late\";",
  "        System.out.println(text);",
  "    }",
  "}",
}, src .. runner .. ".java")

-- Waits until pred() is true or ms passed; a real sleep per round (vim.wait with a callback that answers instantly
-- can spin forever in Neovim 0.12, same as G6 in tests/lib/lsp.lua).
local errs = {}
local function wait_until(ms, pred)
  local deadline = E.now() + ms
  while E.now() < deadline do
    local ok, r = pcall(pred)
    if ok and r then return true end
    if not ok then errs[#errs + 1] = tostring(r):gsub("\n.*", "") end
    vim.wait(50)
  end
  local ok, r = pcall(pred)
  return ok and r or false
end

-- Every jdt.ls start/attach request, by root: a debug launch must not start a second jdt.ls.
local starts = {}
local orig_start = vim.lsp.start
vim.lsp.start = function(config, ...)
  if config and config.name == "jdtls" then starts[#starts + 1] = tostring(config.root_dir) end
  return orig_start(config, ...)
end

local buf = lsp.open(src .. "GradleBootApplication.java")
local client, why = lsp.wait_ready(buf, 300000)
lsp.report(P .. "attached", client ~= nil and vim.uv.fs_realpath(client.config.root_dir or "") == TMP,
  client and ("jdtls ready, root_dir %s (want %s)"):format(tostring(client.config.root_dir), TMP) or tostring(why))
if not client then
  cleanup()
  return lsp.finish()
end

local dap = require("dap")
dap.listeners.on_config["nv4j_89"] = function(c)
  c = vim.deepcopy(c)
  if c.type == "java" then c.vmArgs = ((c.vmArgs and (c.vmArgs .. " ")) or "") .. "-D" .. MARKER end
  return c
end
local function alive() return vim.fn.system({ "pgrep", "-f", MARKER }) ~= "" end
local function pids() return (vim.trim(vim.fn.system({ "pgrep", "-f", MARKER })):gsub("\n", " ")) end
local function dap_req(cmd, args)
  local session = dap.session()
  if not session then return nil end
  local res
  session:request(cmd, args, function(e, r) res = e and false or r end)
  wait_until(5000, function() return res ~= nil end)
  return res or nil
end
local function terminal_text()
  local log = ""
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buftype == "terminal" then log = log .. table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "") end
  end
  return log
end

local ok_all, err = pcall(function()
  local configs
  local ready = wait_until(120000, function()
    configs = nil
    require("jdtls.dap").fetch_main_configs({}, function(c) configs = c or false end)
    wait_until(20000, function() return configs ~= nil end)
    for _, c in ipairs(configs or {}) do if c.mainClass == MAIN then return true end end
    return false
  end)
  local cfg
  for _, c in ipairs(configs or {}) do if c.mainClass == MAIN then cfg = vim.deepcopy(c) end end
  local boot = 0
  for _, p in ipairs(cfg and cfg.classPaths or {}) do if p:find("spring-boot", 1, true) then boot = boot + 1 end end
  lsp.report(P .. "configs", ready and cfg ~= nil and boot > 0,
    cfg and ("%d classpath entries, %d spring-boot"):format(#cfg.classPaths, boot) or "no launch config for " .. MAIN)
  if not cfg then
    for _, n in ipairs({ "breakpoint_hit", "variable", "debuggee_jdk", "one_jdtls", "no_orphan" }) do
      lsp.report(P .. n, false, "no launch config for " .. MAIN)
    end
    return
  end
  cfg.args = "--server.port=0"

  local rbuf = lsp.open(src .. runner .. ".java")
  local lnum = E.line_of(rbuf, "System%.out%.println%(text%);") + 1
  vim.api.nvim_set_current_buf(buf) -- launch from the main class, as a user would
  if not CONTROL:find("nobp", 1, true) then require("dap.breakpoints").set({}, rbuf, lnum) end
  local r = {}
  dap.listeners.after.event_stopped["nv4j_89"] = function(_, body) r.stopped = r.stopped or body end
  local t0 = E.now()
  dap.run(cfg)
  local started = false
  wait_until(BREAK_BUDGET_MS + 20000, function()
    started = started or dap.session() ~= nil
    return r.stopped ~= nil or (started and dap.session() == nil) -- the app ended without stopping: no point in waiting
  end)
  r.ms = E.now() - t0
  dap.listeners.after.event_stopped["nv4j_89"] = nil
  if r.stopped and dap.session() then
    local st = dap_req("stackTrace", { threadId = r.stopped.threadId, levels = 1 })
    r.frame = st and st.stackFrames and st.stackFrames[1]
    local function eval(expr)
      local e = r.frame and dap_req("evaluate", { expression = expr, frameId = r.frame.id, context = "repl" })
      return e and (e.result:gsub('^"(.*)"$', "%1")) or nil
    end
    r.text = eval("text")
    r.jdk = eval('System.getProperty("java.version")')
  end
  E.log("gradle_debug_breakpoint_hit", r.stopped and r.ms or -1, 1)
  local at = r.frame and ("%s line %s"):format(r.frame.name, tostring(r.frame.line)) or "no frame"
  local hit = r.stopped ~= nil and r.stopped.reason == "breakpoint" and r.ms <= BREAK_BUDGET_MS and r.frame ~= nil
    and r.frame.line == lnum and r.frame.name:find(runner, 1, true) ~= nil
  lsp.report(P .. "breakpoint_hit", hit, r.stopped
    and ("stopped (%s) after %.0f ms (budget %d) at %s (want %s line %d)"):format(r.stopped.reason, r.ms, BREAK_BUDGET_MS, at, runner, lnum)
    or ("no stop within %.0f ms; terminal: %s"):format(r.ms, terminal_text():gsub("%s+", " "):sub(-400)))
  lsp.report(P .. "variable", r.text == "late", ("text = %s (want late)"):format(tostring(r.text)))
  lsp.report(P .. "debuggee_jdk", r.jdk ~= nil and r.jdk:match("^25[%.%-+]?") ~= nil,
    ("debuggee java.version = %s (want 25; java on PATH: %s, JAVA_HOME %s)"):format(tostring(r.jdk),
      vim.trim(vim.fn.system({ "sh", "-c", "java -version 2>&1 | head -1" })), vim.env.JAVA_HOME and "set" or "unset"))
  local other = vim.tbl_filter(function(x) return vim.uv.fs_realpath(x) ~= TMP end, starts)
  lsp.report(P .. "one_jdtls", #starts > 0 and #other == 0,
    ("%d jdtls start/attach calls, %d with another root than the project%s"):format(#starts, #other,
      other[1] and (": " .. table.concat(other, ", ")) or ""))

  -- no_orphan: the marked JVM must be seen alive before terminate (else the check is vacuous)
  if dap.session() then dap.continue() end
  local was_alive = wait_until(3000, alive)
  dap.terminate()
  wait_until(ORPHAN_WAIT_MS, function() return dap.session() == nil end)
  local gone = wait_until(ORPHAN_WAIT_MS, function() return not alive() end)
  lsp.report(P .. "no_orphan", was_alive and gone,
    not was_alive and "debuggee JVM not running before terminate (died by itself: nothing proven)"
      or gone and "debuggee JVM alive before terminate, gone after"
      or ("debuggee JVM still running %d s after terminate: pid %s"):format(ORPHAN_WAIT_MS / 1000, pids()))
  require("dap.breakpoints").clear()
end)
if not ok_all then lsp.report(P .. "error", false, tostring(err)) end
if #errs > 0 then io.stdout:write("\nnote: errors raised while waiting: " .. table.concat(errs, " | "):sub(1, 400) .. "\n") end
pcall(function() dap.terminate() end)
cleanup()
lsp.finish()
