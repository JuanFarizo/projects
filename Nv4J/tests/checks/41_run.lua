-- P2 run Spring Boot. Run via tests/run.sh. Spec: specs/features/run.md. Code: nvim/lua/nv4j/run.lua.
--  started        : require("nv4j.run").spring_boot{} (<leader>rs) on the fixture prints "Started
--                   DemoApplication in" in its terminal within START_TIMEOUT_MS (hard limit; the start
--                   time itself is info, logged as run_started in latency.jsonl). SERVER_PORT=0 (env).
--  started_notice : a notification says it started, with the port read from "Tomcat started on port".
--  java25         : the app runs on the project JDK 25 (nv4j.jdk) although run.sh puts JDK 21 first on PATH.
--  env            : env from the call reaches the app (DEMO_GREETING_TEXT -> "nv4j-started from env").
--  terminal       : output in a terminal split (not a float), buffer-local `q` and `<C-c>`, focus stays
--                   in the source window.
--  port_in_use    : a second run on the first run's port (env SERVER_PORT) gives an ERROR notification
--                   with Boot's failure analysis ("Port N was already in use") and session state "failed".
--  no_hung        : after that, the second job has exited, it is not listed as running, and the only
--                   marked JVM alive is the first run's.
--  stop_no_orphan : the run buffer's stop key (<C-c>) ends the first run: no marked JVM left <= 10 s,
--                   state "stopped", output kept.
--  close          : `q` closes the run window and wipes its buffer.
--  profile        : spring_boot{ profile = "dev" } activates application-dev.yml ("Hello dev").
--  tree_kill      : stop kills the whole process tree, also processes that ignore SIGTERM/SIGHUP
--                   (a shell with two children in its process group plus a perl child that left the
--                   group with setpgrp, all ignoring TERM: group kill, snapshot kill, SIGKILL escalation).
--                   Stands in for `mvn spring-boot:run` + its forked JVM, which cannot run offline here
--                   (run.md m1). NV4J_41_KILL_MODE=root|nogroup|nosnapshot runs it as a control.
--  failed_alive   : a process that printed Boot's failure analysis but keeps running ("failed") is still
--                   listed as running and the stop key ends it.
--  force_tool     : vim.g.nv4j_run_tool = "maven" runs `mvn spring-boot:run` although jdt.ls is attached.
--  client_lookup  : the jdt.ls client is found from application.properties and a module path (root is
--                   an ancestor); a project without jdt.ls gets an INFO notice and the build tool.
--  debug_*        : spring_boot{ debug = true, profile = "dev", env } (<leader>rd) goes through nvim-dap
--                   (Task 1 path): stops at the breakpoint in StartupRunner.run <= 20 s, `started` =
--                   "nv4j-started Hello dev", System.getenv("SERVER_PORT") = "0" (env), and no JVM is left
--                   <= 10 s after terminate.
--  detect         : Boot detection from pom.xml (groupId org.springframework.boot outside comments) and
--                   Gradle (org.springframework.boot plugin); a plain pom is not Boot.
--  build_tool_cmd : the fallback command without jdt.ls: Maven first (mvnw spring-boot:run with
--                   profiles and jvmArguments), Gradle second (gradlew bootRun, profile through env).
--  keymaps        : <leader>rs, <leader>rS, <leader>rd, <leader>rp, <leader>rx and P1's <leader>rj exist
--                   with a desc.
vim.o.confirm = false
vim.o.columns = 300 -- terminal rows as wide as possible: Boot log lines are not wrapped in the buffer
local lsp = require("lsp")
local E = require("edit")
local P = "41_run."
local START_TIMEOUT_MS, ORPHAN_WAIT_MS, BREAK_BUDGET_MS = 60000, 10000, 20000
local MARKER = "nv4j.check=41_run"
local TREE = "nv4j-41-tree"

local fixture = vim.env.NV4J_FIXTURE
local src = fixture .. "/src/main/java/demo/"

local function cleanup()
  vim.fn.system({ "pkill", "-9", "-f", MARKER })
  vim.fn.system({ "pkill", "-9", "-f", TREE })
  vim.fn.system({ "pkill", "-9", "-f", "^sleep 6041" })
  vim.fn.system({ "pkill", "-9", "-f", "^perl .*6042" })
  vim.fn.system({ "pkill", "-9", "-f", "^sleep 6043" })
end
cleanup()

local notes = {}
local orig_notify = vim.notify
vim.notify = function(msg, level, ...)
  notes[#notes + 1] = { msg = tostring(msg), level = level or vim.log.levels.INFO }
  return orig_notify(msg, level, ...)
end
local function notes_since(n)
  local out = {}
  for i = n + 1, #notes do out[#out + 1] = notes[i] end
  return out
end
local function short_notes(list)
  return table.concat(vim.tbl_map(function(n) return n.msg:gsub("\n", " / ") end, list), " | "):sub(1, 400)
end

local function pids_of(pat)
  local out = {}
  for p in vim.fn.system({ "pgrep", "-f", pat }):gmatch("%d+") do out[#out + 1] = tonumber(p) end
  return out
end

local buf = lsp.open(src .. "DemoApplication.java")
local client = lsp.wait_ready(buf, 120000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready" or "jdtls not ready")
if not client then
  cleanup()
  return lsp.finish()
end

local errs = {}
local function wait_until(ms, pred)
  local deadline = E.now() + ms
  while E.now() < deadline do
    local ok, r = pcall(vim.wait, math.max(1, deadline - E.now()), pred, 20)
    if ok then return r end
    errs[#errs + 1] = tostring(r):gsub("\n.*", "")
  end
  return pred()
end

local CASES = { "started", "started_notice", "java25", "env", "terminal", "port_in_use", "no_hung", "stop_no_orphan",
  "close", "profile", "tree_kill", "failed_alive", "force_tool", "debug_stop", "debug_profile", "debug_env", "debug_no_orphan",
  "detect", "client_lookup", "build_tool_cmd", "keymaps" }
local ok_mod, R = pcall(require, "nv4j.run")
if not ok_mod then
  for _, c in ipairs(CASES) do lsp.report(P .. c, false, "nv4j.run not loadable: " .. tostring(R):gsub("\n.*", "")) end
  cleanup()
  return lsp.finish()
end

local function text(b)
  if not (b and vim.api.nvim_buf_is_valid(b)) then return "" end
  return table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "")
end
local function job_running(job) return job ~= nil and vim.fn.jobwait({ job }, 0)[1] == -1 end

-- Start a run, return its session record (R.sessions grows by one) and the ms until it was created.
local function start(opts)
  local n = #R.sessions
  local t0 = E.now()
  R.spring_boot(opts)
  wait_until(60000, function() return #R.sessions > n end)
  return R.sessions[n + 1], t0
end

local ok_all, err = pcall(function()
  local src_win = vim.api.nvim_get_current_win()
  -- 1. run (rs): env reaches the app, project JDK, terminal split, start time (info)
  local n0 = #notes
  local s1, t0 = start({ env = { SERVER_PORT = "0", DEMO_GREETING_TEXT = "from env" }, vm_args = { "-D" .. MARKER } })
  local seen = s1 and wait_until(START_TIMEOUT_MS, function() return text(s1.buf):find("Started DemoApplication in", 1, true) ~= nil end)
  local ms = E.now() - t0
  E.log("run_started", seen and ms or -1, 1)
  local t1 = s1 and text(s1.buf) or ""
  local port = t1:match("started on port (%d+)")
  lsp.report(P .. "started", seen == true, seen and ("Started after %.0f ms (info; Boot says %s s), port %s"):format(ms,
    tostring(t1:match("Started DemoApplication in ([%d%.]+) seconds")), tostring(port))
    or ("no 'Started DemoApplication in' within %d ms; session %s; terminal: %s; notes: %s"):format(START_TIMEOUT_MS,
      s1 and "created" or "none", t1:gsub("%s+", " "):sub(-400), short_notes(notes_since(n0))))
  wait_until(2000, function() return s1 and s1.state == "running" end)
  local notice
  for _, n in ipairs(notes_since(n0)) do
    if port and n.msg:find("started", 1, true) and n.msg:find(port, 1, true) then notice = n.msg end
  end
  lsp.report(P .. "started_notice", notice ~= nil and s1.state == "running" and tostring(s1.port) == port,
    ("notice: %s; state %s, session port %s (terminal %s)"):format(tostring(notice), tostring(s1 and s1.state),
      tostring(s1 and s1.port), tostring(port)))
  lsp.report(P .. "java25", t1:find("using Java 25", 1, true) ~= nil,
    ("app says: %s (java on PATH: %s)"):format(tostring(t1:match("Starting DemoApplication using Java [%d%.]+")),
      vim.trim(vim.fn.system({ "sh", "-c", "java -version 2>&1 | head -1" }))))
  lsp.report(P .. "env", t1:find("nv4j-started from env", 1, true) ~= nil,
    ("StartupRunner printed: %s"):format(tostring(t1:match("nv4j%-started [%w ]-%d%d%d%d%-") or t1:match("nv4j%-started %w+ ?%w*"))))
  local win = s1 and vim.fn.bufwinid(s1.buf) or -1
  local wcfg = win ~= -1 and vim.api.nvim_win_get_config(win) or {}
  local function has_map(lhs)
    for _, m in ipairs(s1 and vim.api.nvim_buf_is_valid(s1.buf) and vim.api.nvim_buf_get_keymap(s1.buf, "n") or {}) do
      if m.lhs == lhs or vim.api.nvim_replace_termcodes(m.lhs, true, true, true) == vim.api.nvim_replace_termcodes(lhs, true, true, true) then return m end
    end
  end
  local qmap, cmap = has_map("q"), has_map("<C-C>")
  lsp.report(P .. "terminal", s1 ~= nil and vim.bo[s1.buf].buftype == "terminal" and win ~= -1 and wcfg.relative == ""
      and qmap ~= nil and cmap ~= nil and vim.api.nvim_get_current_win() == src_win,
    ("buftype %s, window %s (%s), q %s, <C-c> %s, focus in source window %s"):format(s1 and vim.bo[s1.buf].buftype or "?",
      tostring(win), wcfg.relative == "" and "split" or "float", qmap and "mapped" or "missing", cmap and "mapped" or "missing",
      tostring(vim.api.nvim_get_current_win() == src_win)))

  -- 2. second run on the same port (Review Focus 4): visible failure, nothing hangs
  if not (s1 and port) then
    for _, c in ipairs({ "port_in_use", "no_hung", "stop_no_orphan", "close" }) do lsp.report(P .. c, false, "first run did not start") end
  else
    local n1 = #notes
    local s2 = start({ env = { SERVER_PORT = port }, vm_args = { "-D" .. MARKER } })
    local want = ("Port %s was already in use"):format(port)
    local err_note
    wait_until(START_TIMEOUT_MS, function()
      for _, n in ipairs(notes_since(n1)) do
        if n.level == vim.log.levels.ERROR and n.msg:find(want, 1, true) then err_note = n.msg return true end
      end
    end)
    lsp.report(P .. "port_in_use", err_note ~= nil and s2 ~= nil and s2.state == "failed",
      ("ERROR notice: %s; second session state %s; notes: %s"):format(tostring(err_note and err_note:gsub("\n", " / ")),
        tostring(s2 and s2.state), err_note and "" or short_notes(notes_since(n1))))
    local exited = s2 and wait_until(15000, function() return not job_running(s2.job) end)
    local listed = s2 and vim.tbl_contains(R.running(), s2)
    local alive = pids_of(MARKER)
    lsp.report(P .. "no_hung", exited == true and not listed and #alive == 1 and alive[1] == s1.pid and s1.state == "running",
      ("second job exited %s, still listed as running %s, marked JVMs %s (first run pid %s, state %s)"):format(tostring(exited),
        tostring(listed), table.concat(alive, " "), tostring(s1.pid), tostring(s1.state)))

    -- stop key, then q
    cmap.callback()
    local gone = wait_until(ORPHAN_WAIT_MS, function() return #pids_of(MARKER) == 0 end)
    wait_until(3000, function() return s1.state == "stopped" end)
    lsp.report(P .. "stop_no_orphan", gone and s1.state == "stopped" and vim.api.nvim_buf_is_valid(s1.buf)
        and text(s1.buf):find("Started DemoApplication", 1, true) ~= nil,
      ("marked JVMs after <C-c>: %s; state %s; output kept %s"):format(gone and "none" or table.concat(pids_of(MARKER), " "),
        tostring(s1.state), tostring(vim.api.nvim_buf_is_valid(s1.buf))))
    local b1 = s1.buf
    qmap.callback()
    wait_until(2000, function() return not vim.api.nvim_buf_is_valid(b1) end)
    lsp.report(P .. "close", not vim.api.nvim_buf_is_valid(b1) and vim.fn.bufwinid(b1) == -1,
      ("run buffer after q: %s"):format(vim.api.nvim_buf_is_valid(b1) and "still there" or "wiped"))
    if s2 and s2.buf and vim.api.nvim_buf_is_valid(s2.buf) then pcall(vim.api.nvim_buf_delete, s2.buf, { force = true }) end
  end

  -- 3. profile (rp picks it; here passed directly)
  local s3 = start({ profile = "dev", env = { SERVER_PORT = "0" }, vm_args = { "-D" .. MARKER } })
  local hello = s3 and wait_until(START_TIMEOUT_MS, function() return text(s3.buf):find("Started DemoApplication in", 1, true) ~= nil end)
  local t3 = s3 and text(s3.buf) or ""
  lsp.report(P .. "profile", hello and t3:find("nv4j-started Hello dev", 1, true) ~= nil and t3:find('"dev"', 1, true) ~= nil,
    ("started %s; profile line %s; runner printed %s"):format(tostring(hello), tostring(t3:match('profiles? (i?s?a?r?e? ?active: [^%d]-"dev")')),
      tostring(t3:find("nv4j-started Hello dev", 1, true) ~= nil)))
  if s3 then R.stop(s3) end
  wait_until(ORPHAN_WAIT_MS, function() return #pids_of(MARKER) == 0 end)
  if s3 and vim.api.nvim_buf_is_valid(s3.buf) then pcall(vim.api.nvim_buf_delete, s3.buf, { force = true }) end

  -- 4. whole process tree, children ignoring SIGTERM/SIGHUP
  R.KILL_GRACE_MS = 1500
  R.kill_mode = vim.env.NV4J_41_KILL_MODE -- control runs only
  local PERL = "^perl .*6042"
  local s4 = R.start_terminal({ cmd = { "sh", "-c", "trap '' TERM HUP INT; sleep 6041 & sleep 6041 & "
    .. "perl -e 'setpgrp(0,0); $SIG{TERM}=$SIG{HUP}=$SIG{INT}=q(IGNORE); sleep 6042' & wait", TREE }, cwd = fixture, name = "tree" })
  local function tree_left() return vim.list_extend(vim.list_extend(pids_of("^sleep 6041"), pids_of(PERL)), pids_of(TREE)) end
  local up = wait_until(5000, function() return #pids_of("^sleep 6041") == 2 and #pids_of(PERL) == 1 and #pids_of(TREE) >= 1 end)
  local t_stop = E.now()
  R.stop(s4)
  local all_gone = wait_until(ORPHAN_WAIT_MS, function() return #tree_left() == 0 end)
  lsp.report(P .. "tree_kill", up and all_gone,
    ("tree up (sh + 2 children in its group + 1 child in its own group) %s; all gone after stop %s in %.0f ms; left: %s%s"):format(
      tostring(up), tostring(all_gone), E.now() - t_stop, table.concat(tree_left(), " "),
      R.kill_mode and (" (CONTROL kill_mode=" .. R.kill_mode .. ")") or ""))
  if s4 and vim.api.nvim_buf_is_valid(s4.buf) then pcall(vim.api.nvim_buf_delete, s4.buf, { force = true }) end
  R.kill_mode = nil
  vim.fn.system({ "pkill", "-9", "-f", "^perl .*6042" })

  -- 4b. failed but still running: stoppable (state "failed" must not hide a live process)
  local nf = #notes
  local s5 = R.start_terminal({ cmd = { "sh", "-c", "printf '\\n***************************\\nAPPLICATION FAILED TO START\\n"
    .. "***************************\\n\\nDescription:\\n\\nWeb server failed to start. Port 1 was already in use.\\n\\n"
    .. "Action:\\n\\nStop it.\\n'; exec sleep 6043" }, cwd = fixture, name = "failing" })
  local failed = wait_until(5000, function() return s5.state == "failed" end)
  local fnote = false
  for _, n in ipairs(notes_since(nf)) do
    if n.level == vim.log.levels.ERROR and n.msg:find("Port 1 was already in use", 1, true) then fnote = true end
  end
  local listed5 = vim.tbl_contains(R.running(), s5)
  local live5 = #pids_of("^sleep 6043") == 1
  local stopkey
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(s5.buf, "n")) do
    if vim.api.nvim_replace_termcodes(m.lhs, true, true, true) == vim.api.nvim_replace_termcodes("<C-c>", true, true, true) then stopkey = m end
  end
  if stopkey then stopkey.callback() end
  local gone5 = wait_until(ORPHAN_WAIT_MS, function() return #pids_of("^sleep 6043") == 0 end)
  wait_until(2000, function() return s5.state == "stopped" end)
  lsp.report(P .. "failed_alive", failed and fnote and listed5 and live5 and gone5 and s5.state == "stopped",
    ("state failed %s, ERROR notice %s, still running and listed %s/%s, gone after <C-c> %s, final state %s"):format(
      tostring(failed), tostring(fnote), tostring(live5), tostring(listed5), tostring(gone5), tostring(s5.state)))
  if vim.api.nvim_buf_is_valid(s5.buf) then pcall(vim.api.nvim_buf_delete, s5.buf, { force = true }) end

  -- 4c. vim.g.nv4j_run_tool = "maven": the build tool although jdt.ls is attached (stopped right away:
  --     Maven cannot resolve its plugin offline here)
  vim.api.nvim_set_current_buf(buf)
  vim.g.nv4j_run_tool = "maven"
  local s6 = start({ env = { SERVER_PORT = "0" }, vm_args = { "-D" .. MARKER } })
  vim.g.nv4j_run_tool = nil
  local c6 = s6 and s6.cmd or {}
  local tool_ok = c6[1] ~= nil and vim.fs.basename(c6[1]):match("^mvnw?$") ~= nil and c6[2] == "spring-boot:run"
    and vim.tbl_contains(c6, "-Dspring-boot.run.jvmArguments=-D" .. MARKER)
  if s6 then R.stop(s6) end
  local gone6 = s6 and wait_until(ORPHAN_WAIT_MS, function() return not R.is_alive(s6) end)
  lsp.report(P .. "force_tool", tool_ok and gone6,
    ("command %s; stopped %s"):format(table.concat(c6, " "):sub(1, 200), tostring(gone6)))
  if s6 and vim.api.nvim_buf_is_valid(s6.buf) then pcall(vim.api.nvim_buf_delete, s6.buf, { force = true }) end

  -- 5. debug (rd): Task 1's nvim-dap launch with profile and env
  local dap = require("dap")
  local rbuf = lsp.open(src .. "StartupRunner.java")
  local lnum = E.line_of(rbuf, "System%.out%.println%(started%);") + 1
  vim.api.nvim_set_current_buf(buf)
  require("dap.breakpoints").set({}, rbuf, lnum)
  local stopped
  dap.listeners.after.event_stopped["nv4j_41"] = function(_, body) stopped = stopped or body end
  local td = E.now()
  R.spring_boot({ debug = true, profile = "dev", env = { SERVER_PORT = "0" }, vm_args = { "-D" .. MARKER } })
  wait_until(BREAK_BUDGET_MS + 20000, function() return stopped ~= nil end)
  local dms = E.now() - td
  E.log("run_debug_breakpoint_hit", stopped and dms or -1, 1)
  local frame, value, env_value
  if stopped and dap.session() then
    local res
    dap.session():request("stackTrace", { threadId = stopped.threadId, levels = 1 }, function(e, r) res = e and false or r end)
    wait_until(5000, function() return res ~= nil end)
    frame = res and res.stackFrames and res.stackFrames[1]
    if frame then
      local ev
      dap.session():request("evaluate", { expression = "started", frameId = frame.id, context = "repl" }, function(e, r) ev = e and false or r end)
      wait_until(5000, function() return ev ~= nil end)
      value = ev and (ev.result:gsub('^"(.*)"$', "%1"))
      local ev2
      dap.session():request("evaluate", { expression = 'System.getenv("SERVER_PORT")', frameId = frame.id, context = "repl" },
        function(e, r) ev2 = e and false or r end)
      wait_until(5000, function() return ev2 ~= nil end)
      env_value = ev2 and (ev2.result:gsub('^"(.*)"$', "%1"))
    end
  end
  lsp.report(P .. "debug_stop", stopped ~= nil and dms <= BREAK_BUDGET_MS and frame ~= nil and frame.line == lnum,
    ("stopped %s after %.0f ms (budget %d) at %s; notes: %s"):format(tostring(stopped and stopped.reason), dms, BREAK_BUDGET_MS,
      frame and (frame.name .. " line " .. frame.line) or "no frame", stopped and "" or short_notes(notes)))
  lsp.report(P .. "debug_profile", value == "nv4j-started Hello dev", ("started = %s (want nv4j-started Hello dev)"):format(tostring(value)))
  lsp.report(P .. "debug_env", env_value == "0", ("System.getenv(\"SERVER_PORT\") = %s (want 0)"):format(tostring(env_value)))
  local was_alive = #pids_of(MARKER) > 0
  if dap.session() then dap.terminate() end
  wait_until(ORPHAN_WAIT_MS, function() return dap.session() == nil end)
  local dgone = wait_until(ORPHAN_WAIT_MS, function() return #pids_of(MARKER) == 0 end)
  lsp.report(P .. "debug_no_orphan", was_alive and dgone,
    ("JVM alive at the stop %s, gone after terminate %s"):format(tostring(was_alive), tostring(dgone)))
  dap.listeners.after.event_stopped["nv4j_41"] = nil
  require("dap.breakpoints").clear()

  -- 6. detection and fallback command (pure)
  local tmp = "/tmp/nv4j/41_run"
  vim.fn.delete(tmp, "rf")
  local function project(name, files)
    local d = tmp .. "/" .. name
    vim.fn.mkdir(d, "p")
    for f, body in pairs(files) do vim.fn.writefile(vim.split(body, "\n"), d .. "/" .. f) end
    return d
  end
  local plain = project("plain", { ["pom.xml"] = "<project><!-- <groupId>org.springframework.boot</groupId> --><groupId>x</groupId></project>" })
  local mvnboot = project("mvnboot", { ["pom.xml"] = "<project><parent>\n<groupId>org.springframework.boot</groupId>\n<artifactId>spring-boot-starter-parent</artifactId></parent></project>", mvnw = "#!/bin/sh" })
  vim.fn.setfperm(mvnboot .. "/mvnw", "rwxr-xr-x")
  local gboot = project("gboot", { ["build.gradle.kts"] = 'plugins {\n  id("org.springframework.boot") version "3.5.13"\n}', gradlew = "#!/bin/sh" })
  vim.fn.setfperm(gboot .. "/gradlew", "rwxr-xr-x")
  local d1, d2, d3, d4 = R.is_boot(fixture), R.is_boot(plain), R.is_boot(mvnboot), R.is_boot(gboot)
  lsp.report(P .. "detect", d1 == true and d2 == false and d3 == true and d4 == true,
    ("fixture %s, plain pom (boot only in a comment) %s, maven parent %s, gradle plugin %s"):format(tostring(d1), tostring(d2), tostring(d3), tostring(d4)))
  -- jdt.ls client lookup by ancestor root; no client: INFO notice and the build tool (mvnboot/mvnw is a stub)
  local props = fixture .. "/src/main/resources/application.properties"
  local c_props, c_mod, c_out = R.client_for_path(props), R.client_for_path(fixture .. "/sub/pom.xml"), R.client_for_path(mvnboot .. "/pom.xml")
  vim.cmd("edit " .. vim.fn.fnameescape(props))
  local pr_root, pr_client = R.project_root()
  vim.cmd("edit " .. vim.fn.fnameescape(mvnboot .. "/pom.xml"))
  local nb = #notes
  local nsess = #R.sessions
  R.spring_boot({})
  local ninfo
  for _, n in ipairs(notes_since(nb)) do
    if n.msg:find("jdt.ls is not attached", 1, true) then ninfo = n end
  end
  local s7 = R.sessions[nsess + 1]
  lsp.report(P .. "client_lookup", c_props == client and c_mod == client and c_out == nil and pr_root == fixture and pr_client == client
      and ninfo ~= nil and ninfo.level == vim.log.levels.INFO and s7 ~= nil and vim.uv.fs_realpath(s7.cmd[1]) == vim.uv.fs_realpath(mvnboot .. "/mvnw"),
    ("application.properties -> %s, module path -> %s, other project -> %s; project_root from properties %s (client %s); "
      .. "no-jdt.ls notice %s, command %s"):format(c_props and "jdtls" or "nil", c_mod and "jdtls" or "nil", c_out and "jdtls" or "nil",
      tostring(pr_root), tostring(pr_client ~= nil), ninfo and ninfo.msg or "none", s7 and table.concat(s7.cmd, " ") or "none"))
  if s7 then wait_until(5000, function() return not R.is_alive(s7) end) end
  if s7 and vim.api.nvim_buf_is_valid(s7.buf) then pcall(vim.api.nvim_buf_delete, s7.buf, { force = true }) end
  vim.api.nvim_set_current_buf(buf)
  local mc = R.build_tool_command(mvnboot, { profile = "dev", vm_args = { "-Dx=1", "-Dy=2" } })
  local gc, genv = R.build_tool_command(gboot, { profile = "dev" })
  local want_m = { mvnboot .. "/mvnw", "spring-boot:run", "-Dspring-boot.run.profiles=dev", "-Dspring-boot.run.jvmArguments=-Dx=1 -Dy=2" }
  local want_g = { gboot .. "/gradlew", "bootRun" }
  lsp.report(P .. "build_tool_cmd", vim.deep_equal(mc, want_m) and vim.deep_equal(gc, want_g) and genv and genv.SPRING_PROFILES_ACTIVE == "dev",
    ("maven %s; gradle %s env %s"):format(vim.inspect(mc), vim.inspect(gc), vim.inspect(genv)):gsub("\n%s*", " "))
  vim.fn.delete(tmp, "rf")

  -- 7. keys
  pcall(require, "config.keymaps")
  local missing = {}
  for _, lhs in ipairs({ "<leader>rs", "<leader>rS", "<leader>rd", "<leader>rp", "<leader>rx", "<leader>rj" }) do
    local m = vim.fn.maparg(lhs, "n", false, true)
    if not m.lhs or (m.desc or "") == "" then missing[#missing + 1] = lhs end
  end
  lsp.report(P .. "keymaps", #missing == 0, #missing == 0 and "all mapped with a description" or ("missing: " .. table.concat(missing, " ")))
end)
pcall(function() R.stop_all() end)
cleanup()
if #errs > 0 then io.stdout:write("\nerrors while waiting: " .. table.concat(errs, " | "):sub(1, 600) .. "\n") end
if not ok_all then lsp.report(P .. "run", false, "error: " .. tostring(err)) end
lsp.finish()
