-- Test runner (P3, decision D21, specs/features/tests-runner.md, check 60_tests_runner).
-- Launch path: the java-test bundle (test discovery, vscode.java.test.junit.argument) and nvim-dap with
-- P2's java adapter (nv4j/debug.lua: refresh + build before launch, JUnit launcher swap, jdtls client
-- lookup, JDT launching gate), the JDK from nv4j.jdk. Own result layer: the Eclipse RemoteTestRunner
-- stream is read here (counts incl. skipped, parameterized invocations and @Nested), failures go to
-- vim.diagnostic + sign extmarks in the test file and to a quickfix list (message, then the stack frames
-- that are project files: each jumps to its line), plus a summary notification.
--
-- require("nv4j.tests").run({ scope = "nearest"|"class"|"file"|"project"|"failed"|"last",
--   debug = boolean, bufnr = n, lnum = n, on_done = function(result) end })
-- result = { passed, failed, skipped, failures = { { name, message, filename, lnum, frames } },
--   tests = { { name, class, method, state } }, error = string|nil, ms = n }
--
-- Scopes: nearest = the test method at/above the cursor (a class when the cursor is above its first
-- method), class = the top-level test class around the cursor (nested classes included), file = every
-- top-level test class of the file, project = every test class of the project's jdt.ls Java projects
-- (one launch per project and test kind: java-test 0.43.1 refuses project/package levels, measured in
-- Task 2, but runs a list of classes in one JVM), failed = the failed tests of the last run (method level,
-- one launch), last = the last run again. TestNG is not handled (nvim-jdtls's <leader>tT runs it).
local M = {}

local NS = vim.api.nvim_create_namespace("nv4j_tests")
M.ns = NS
local LEVEL = { class = 5, method = 6 }
local KIND_NAMES = { [0] = "JUnit 5", [1] = "JUnit 4", [2] = "TestNG" }
-- Whole run (build, launch, results) bounded: a test JVM that never reports, a hung build or a launch
-- error that never closes the session ends the run with a visible message instead of a hang.
M.timeout_ms = 120000
M.last_request = nil -- { scope, launches, debug, label }
M.last_result = nil
local running = nil

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Tests" }) end

local function timeout_ms() return tonumber(vim.g.nv4j_test_timeout_ms) or M.timeout_ms end

--- jdt.ls client for a buffer (attached), else the one whose root holds the file.
local function client_for(bufnr)
  local c = vim.lsp.get_clients({ bufnr = bufnr, name = "jdtls" })[1]
  return c or require("nv4j.root").client_for_path(vim.api.nvim_buf_get_name(bufnr))
end

local function exec(client, command, arguments, bufnr, cb)
  local ok = client:request("workspace/executeCommand", { command = command, arguments = arguments }, function(err, res)
    cb(err, res)
  end, bufnr)
  if not ok then cb({ message = "jdtls client stopped" }) end
end

-- ── lenses ──────────────────────────────────────────────────────────────────────────────────────

local function contains(range, lnum0)
  return range and range.start.line <= lnum0 and lnum0 <= range["end"].line
end

--- Method lens at or above the cursor (deepest, nested classes included), else nil.
local function nearest_method(lenses, lnum0)
  local best
  local function walk(list)
    for _, l in ipairs(list or {}) do
      if l.testLevel == LEVEL.method and l.range and l.range.start.line <= lnum0
        and (not best or l.range.start.line > best.range.start.line) then
        best = l
      end
      walk(l.children)
    end
  end
  walk(lenses)
  return best
end

--- Top-level class lens around the cursor, else the first one.
local function class_at(lenses, lnum0)
  for _, l in ipairs(lenses) do
    if l.testLevel == LEVEL.class and contains(l.range, lnum0) then return l end
  end
  for _, l in ipairs(lenses) do
    if l.testLevel == LEVEL.class then return l end
  end
end

-- ── stream parser (Eclipse RemoteTestRunner protocol, version 3) ─────────────────────────────────

--- Split a %TSTTREE payload on commas not escaped with a backslash.
local function split_escaped(s)
  local parts, cur, i = {}, {}, 1
  while i <= #s do
    local ch = s:sub(i, i)
    if ch == "\\" and i < #s then
      cur[#cur + 1] = s:sub(i + 1, i + 1)
      i = i + 2
    else
      if ch == "," then
        parts[#parts + 1] = table.concat(cur)
        cur = {}
      else
        cur[#cur + 1] = ch
      end
      i = i + 1
    end
  end
  parts[#parts + 1] = table.concat(cur)
  return parts
end

--- "method(fq.Class)" / "method(int)[1](fq.Class)" / "fq.Class" -> class, method (nil for a class).
local function split_name(name)
  local method, class = name:match("^([^(]+).*%(([^()]+)%)$")
  if method then return class, method end
  return name, nil
end

M._split_name = split_name

--- Parser state for one launch: feed(chunk), then nodes / order.
local function new_parser()
  local p = { nodes = {}, order = {}, buf = "", tracing = nil, done = false, raw = {} }
  local function node(id)
    local n = p.nodes[id]
    if not n then
      n = { id = id }
      p.nodes[id] = n
    end
    return n
  end
  local function line(l)
    p.raw[#p.raw + 1] = l
    local tag, rest = l:sub(1, 8), l:sub(9)
    if p.tracing and tag ~= "%TRACEE " then
      local t = p.tracing.trace
      t[#t + 1] = l
      return
    end
    if tag == "%TSTTREE" then
      local f = split_escaped(rest)
      local n = node(f[1])
      n.name, n.suite, n.parent, n.display = f[2], f[3] == "true", f[6], f[7]
      n.dynamic = f[5] == "true"
      if not n.suite then p.order[#p.order + 1] = n.id end
    elseif tag == "%TESTS  " then
      local id, name = rest:match("^([^,]*),(.*)$")
      if not id then return end
      local n = node(id)
      if not n.name then
        n.name = name:gsub("^@Ignore: ", ""):gsub("^@AssumptionFailure: ", "")
        p.order[#p.order + 1] = id
      end
      n.started = true
      if name:find("^@Ignore: ") or name:find("^@AssumptionFailure: ") then n.state = "skipped" end
    elseif tag == "%TESTE  " then
      local id = rest:match("^([^,]*),")
      if id then
        local n = node(id)
        n.ended = true
        n.state = n.state or "passed"
      end
    elseif tag == "%FAILED " or tag == "%ERROR  " then
      local id, name = rest:match("^([^,]*),(.*)$")
      if not id then return end
      local n = node(id)
      n.name = n.name or name
      n.state = "failed"
      n.failed = true
      p.last_failed = n
    elseif tag == "%TRACES " then
      p.tracing = p.last_failed or { trace = {} }
      p.tracing.trace = p.tracing.trace or {}
    elseif tag == "%TRACEE " then
      p.tracing = nil
    elseif tag == "%RUNTIME" then
      p.done = true
    end
  end
  function p.feed(chunk)
    p.buf = p.buf .. chunk
    while true do
      local nl = p.buf:find("\n", 1, true)
      if not nl then break end
      local l = p.buf:sub(1, nl - 1):gsub("\r$", "")
      p.buf = p.buf:sub(nl + 1)
      line(l)
    end
  end
  function p.flush()
    if p.buf ~= "" then
      line(p.buf)
      p.buf = ""
    end
  end
  return p
end

M._new_parser = new_parser

-- ── results ─────────────────────────────────────────────────────────────────────────────────────

local function top_class(fq) return (fq:gsub("%$.*$", "")) end

--- File of a project class: the lens index first, then src/*/java (and one module level down) under root.
local function class_file(fq, ctx)
  fq = top_class(fq)
  if ctx.files[fq] ~= nil then return ctx.files[fq] or nil end
  local rel = fq:gsub("%.", "/") .. ".java"
  local found
  for _, root in ipairs(ctx.roots) do
    found = vim.fn.glob(root .. "/src/*/java/" .. rel, false, true)[1] or vim.fn.glob(root .. "/*/src/*/java/" .. rel, false, true)[1]
    if found then break end
  end
  ctx.files[fq] = found or false
  return found
end

--- A stack frame line "\tat pkg.Class.method(File.java:12)" -> class, method, line.
local function parse_frame(l)
  local cls, meth, ln = l:match("^%s*at%s+([%w_.$]+)%.([%w_$<>]+)%([^:()]*:(%d+)%)")
  return cls, meth, tonumber(ln)
end

--- Failure details of a failed node: message, the location in the test class, project frames.
local function failure_of(n, ctx)
  local trace = n.trace or {}
  local msg = {}
  for _, l in ipairs(trace) do
    if l:find("^%s*at ") then break end
    msg[#msg + 1] = l
  end
  local message = vim.trim(table.concat(msg, "\n"))
  if message == "" then message = "failed (no message)" end
  local cls, method = split_name(n.name or "")
  local test_top = top_class(cls or "")
  local frames, loc = {}, nil
  for _, l in ipairs(trace) do
    local fc, fm, ln = parse_frame(l)
    if fc then
      local file = class_file(fc, ctx)
      if file then
        frames[#frames + 1] = { filename = file, lnum = ln, text = vim.trim(l) }
        if not loc and top_class(fc) == test_top then loc = frames[#frames] end
      end
    end
  end
  loc = loc or frames[1]
  local filename = loc and loc.filename or (test_top ~= "" and class_file(test_top, ctx)) or nil
  local lnum = loc and loc.lnum or nil
  if not lnum and filename then
    local item = ctx.methods[(cls or "") .. "#" .. (method or "")] or ctx.classes[cls or ""]
    lnum = item and item.range and item.range.start.line + 1 or 1
  end
  return { name = n.name, class = cls, method = method, message = message, filename = filename, lnum = lnum, frames = frames }
end

local function short(name)
  local cls, method = split_name(name or "")
  local simple = (cls or ""):match("([^.]+)$") or cls
  return method and (simple .. "." .. method) or simple
end

--- Aggregate parsed launches into a result.
local function collect(parsers, ctx)
  local r = { passed = 0, failed = 0, skipped = 0, failures = {}, tests = {} }
  for _, p in ipairs(parsers) do
    local listed = {}
    for _, id in ipairs(p.order) do listed[id] = true end
    for _, id in ipairs(p.order) do
      local n = p.nodes[id]
      local leaf = not n.suite
      local state = n.state
      -- a test that started but never ended (JVM killed, timeout) is not counted as passed
      if (leaf and n.started and (n.ended or state)) or n.failed then
        state = state or "passed"
        local cls, method = split_name(n.name or "")
        r.tests[#r.tests + 1] = { name = n.name, display = n.display, class = cls, method = method, state = state }
        r[state] = r[state] + 1
        if state == "failed" then r.failures[#r.failures + 1] = failure_of(n, ctx) end
      end
    end
    -- class-level errors (e.g. a failing static initializer) reported on a suite that never started a leaf
    for id, n in pairs(p.nodes) do
      if n.failed and not listed[id] then
        r.failed = r.failed + 1
        local f = failure_of(n, ctx)
        r.failures[#r.failures + 1] = f
        r.tests[#r.tests + 1] = { name = n.name, class = f.class, state = "failed" }
      end
    end
  end
  return r
end

local function summary(r)
  local s = ("%d passed, %d failed, %d skipped"):format(r.passed, r.failed, r.skipped)
  return s
end

--- Signs (extmarks) on the method lines of loaded buffers, from lenses.
local function place_signs(r, lenses_by_file)
  local state_of = {}
  for _, t in ipairs(r.tests) do
    if t.method then
      local key = t.class .. "#" .. t.method
      local prev = state_of[key]
      -- a parameterized method: failed beats passed beats skipped
      if not prev or t.state == "failed" or (t.state == "passed" and prev == "skipped") then state_of[key] = t.state end
    end
  end
  local SIGN = { passed = { "✓", "DiagnosticOk" }, failed = { "✗", "DiagnosticError" }, skipped = { "○", "DiagnosticWarn" } }
  for file, lenses in pairs(lenses_by_file) do
    local b = vim.fn.bufnr(file)
    if b > 0 and vim.api.nvim_buf_is_loaded(b) then
      local function walk(list)
        for _, l in ipairs(list or {}) do
          if l.testLevel == LEVEL.method and l.range then
            local cls, mname = l.fullName:match("^([^#]+)#([^(]+)")
            local st = cls and state_of[cls .. "#" .. mname]
            if st and l.range.start.line < vim.api.nvim_buf_line_count(b) then
              pcall(vim.api.nvim_buf_set_extmark, b, NS, l.range.start.line, 0,
                { sign_text = SIGN[st][1], sign_hl_group = SIGN[st][2], invalidate = true, priority = 20 })
            end
          end
          walk(l.children)
        end
      end
      walk(lenses)
    end
  end
end

local function clear_marks()
  vim.diagnostic.reset(NS)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then vim.api.nvim_buf_clear_namespace(b, NS, 0, -1) end
  end
end

local QF_TITLE = "Nv4J tests"

--- Diagnostics, quickfix list and summary for a finished result.
local function show(r, ctx, label)
  local by_buf = {}
  local items = {}
  for _, f in ipairs(r.failures) do
    local first = f.message:match("[^\n]*")
    if f.filename then
      local b = vim.fn.bufadd(f.filename)
      by_buf[b] = by_buf[b] or {}
      table.insert(by_buf[b], { lnum = (f.lnum or 1) - 1, col = 0, severity = vim.diagnostic.severity.ERROR,
        source = "nv4j tests", message = short(f.name) .. ": " .. f.message })
      items[#items + 1] = { filename = f.filename, lnum = f.lnum or 1, col = 1, type = "E", text = short(f.name) .. ": " .. first }
    else
      items[#items + 1] = { text = short(f.name) .. ": " .. first, type = "E" }
    end
    for _, fr in ipairs(f.frames) do
      items[#items + 1] = { filename = fr.filename, lnum = fr.lnum, col = 1, text = "  " .. fr.text }
    end
  end
  for _, t in ipairs(r.tests) do
    if t.state == "skipped" then
      local file = t.class and class_file(t.class, ctx)
      local item = ctx.methods[(t.class or "") .. "#" .. (t.method or "")]
      items[#items + 1] = { filename = file, lnum = item and item.range and item.range.start.line + 1 or 1, col = 1, type = "W",
        text = short(t.name) .. ": skipped" }
    end
  end
  for b, ds in pairs(by_buf) do vim.diagnostic.set(NS, b, ds) end
  local title = ("%s: %s (%s)"):format(QF_TITLE, summary(r), label)
  local cur = vim.fn.getqflist({ title = 0 }).title or ""
  vim.fn.setqflist({}, cur:sub(1, #QF_TITLE) == QF_TITLE and "r" or " ", { title = title, items = items })
  local level = (r.failed > 0 or r.error) and vim.log.levels.ERROR or vim.log.levels.INFO
  local msg = ("%s: %s in %.1f s"):format(label, summary(r), (r.ms or 0) / 1000)
  if r.error then msg = msg .. "\n" .. r.error end
  if r.failed > 0 then msg = msg .. "\n<leader>to: failures in the quickfix list" end
  notify(msg, level)
end

-- ── launching ───────────────────────────────────────────────────────────────────────────────────

--- java-test launch arguments + the test-scope classpath (as nvim-jdtls's fetch_launch_args does: the
--- bundle's classpath can miss entries, vscode-java-test#1073).
local function launch_args(client, launch, cb)
  local req = { projectName = launch.projectName, testKind = launch.testKind, testLevel = launch.testLevel, testNames = launch.testNames }
  exec(client, "vscode.java.test.junit.argument", { vim.fn.json_encode(req) }, nil, function(err, la)
    if err then return cb(nil, "launch arguments: " .. tostring(err.message or vim.inspect(err))) end
    la = la and (la.body or la)
    if not la then return cb(nil, "launch arguments: no answer from jdt.ls (java-test bundle)") end
    if la.errorMessage then return cb(nil, la.errorMessage) end
    exec(client, "java.project.getClasspaths", { launch.uri, vim.fn.json_encode({ scope = "test" }) }, nil, function(err1, cp)
      if not err1 and cp and cp.classpaths then
        local seen, merged = {}, {}
        for _, x in ipairs(vim.list_extend(vim.list_extend({}, la.classpath or {}), cp.classpaths)) do
          if not seen[x] then seen[x], merged[#merged + 1] = true, x end
        end
        la.classpath = merged
      end
      cb(la)
    end)
  end)
end

local function java_home(root)
  local rts = require("nv4j.jdk").runtimes(root)
  for _, rt in ipairs(rts) do
    if rt.default then return rt.path end
  end
  return rts[1] and rts[1].path
end

--- One JVM: launch args, TCP server for the runner's stream, dap.run (P2's adapter builds first).
--- done(parser|nil, err|nil) once: the stream ended (%RUNTIME + EOF), or the session closed (a short
--- grace for the stream), or the run was cancelled.
local function launch_one(run, launch, done)
  local client = run.client
  launch_args(client, launch, function(la, err)
    if run.finished then return end
    if not la then return done(nil, err) end
    local uv = vim.uv
    local parser = new_parser()
    local server = assert(uv.new_tcp())
    local finished = false
    local socks = {}
    local function finish(e)
      if finished then return end
      finished = true
      for _, s in ipairs(socks) do pcall(function() if not s:is_closing() then s:disconnect({ terminateDebuggee = true }) end end) end
      pcall(function() server:close() end)
      run.cancel_launch = nil
      parser.flush()
      done(parser, e)
    end
    run.cancel_launch = function() finish("cancelled") end
    -- the JVM of a finished stream must not linger: its session is closed 3 s after the results
    local name = "Nv4J tests: " .. launch.label .. " #" .. run.id
    local function reap()
      vim.defer_fn(function()
        for _, sess in pairs(require("dap").sessions()) do
          if sess.config and sess.config.name == name then pcall(function() sess:disconnect({ terminateDebuggee = true }) end) end
        end
      end, 3000)
    end
    local inner = finish
    finish = function(e)
      if not finished then reap() end
      inner(e)
    end
    server:bind("127.0.0.1", 0)
    server:listen(8, function(lerr)
      if lerr then return end
      local sock = uv.new_tcp()
      server:accept(sock)
      socks[#socks + 1] = sock
      sock:read_start(vim.schedule_wrap(function(rerr, chunk)
        if chunk then
          parser.feed(chunk)
          -- %RUNTIME ends the stream: report now instead of waiting for EOF (defensive: no check case depends
          -- on it, control n60h)
          if parser.done then finish(nil) end
        else
          if not sock:is_closing() then sock:close() end
          if rerr then return finish("test stream: " .. tostring(rerr)) end
          finish(nil)
        end
      end))
    end)
    local port = server:getsockname().port
    local args = table.concat(la.programArguments or {}, " "):gsub("%-port %d+", "-port " .. port)
    local root = client.config.root_dir
    local home = java_home(launch.root or root)
    local config = {
      name = name,
      type = "java",
      request = "launch",
      mainClass = la.mainClass,
      projectName = la.projectName or launch.projectName,
      cwd = la.workingDirectory or root,
      classPaths = la.classpath,
      modulePaths = la.modulepath,
      vmArgs = table.concat(la.vmArguments or {}, " "),
      args = args,
      noDebug = not run.debug,
      nv4j_what = run.debug and "test debug" or "test run", -- build message (nv4j/debug.lua)
      console = "internalConsole",
      javaExec = home and (home .. "/bin/java") or nil,
    }
    local ok, derr = pcall(require("dap").run, config, {
      new = true,
      after = function()
        -- the stream normally ends before the session closes; give it a moment, then report
        vim.defer_fn(function()
          if not finished then
            finish(parser.done and nil or "the test JVM ended without (complete) results: see :DapShowLog, the dap-repl"
              .. " and the build warnings above")
          end
        end, 1500)
      end,
    })
    if not ok then finish("dap.run: " .. tostring(derr)) end
  end)
end

local next_id = 0
local index -- forward declaration (lens index, defined below)

local function finish_run(run, r)
  if run.finished then return end
  run.finished = true
  if run.timer then pcall(function() run.timer:stop(); run.timer:close() end) end
  running = nil
  r.ms = (vim.uv.hrtime() - run.t0) / 1e6
  M._last_raw = {} -- the runner stream of the last run, for diagnosis (:lua =require("nv4j.tests")._last_raw)
  for _, p in ipairs(run.parsers or {}) do vim.list_extend(M._last_raw, p.raw) end
  if not r.error or r.passed + r.failed + r.skipped > 0 then
    M.last_result = r
  end
  show(r, run.ctx, run.label)
  place_signs(r, run.lenses_by_file)
  -- a project run discovered classes only: method lines of the loaded test buffers come afterwards
  for file, lenses in pairs(run.lenses_by_file) do
    local b = vim.fn.bufnr(file)
    if #lenses == 0 and b > 0 and vim.api.nvim_buf_is_loaded(b) and not run.client:is_stopped() then
      exec(run.client, "vscode.java.test.findTestTypesAndMethods", { vim.uri_from_fname(file) }, nil, function(_, ls)
        if ls and #ls > 0 and M.last_result == r then
          run.lenses_by_file[file] = ls
          index({ classes = run.ctx.classes, methods = run.ctx.methods, files = run.ctx.files, lenses_by_file = {} }, ls)
          place_signs(r, { [file] = ls })
        end
      end)
    end
  end
  if run.on_done then pcall(run.on_done, r) end
end

local function empty_result(err) return { passed = 0, failed = 0, skipped = 0, failures = {}, tests = {}, error = err } end

--- Message-only end (nothing launched): visible notification, on_done with error.
local function refuse(opts, msg, level)
  notify(msg, level or vim.log.levels.WARN)
  if opts.on_done then pcall(opts.on_done, empty_result(msg)) end
end

--- Run the launches one after another, then show the aggregate.
local function start(req, opts)
  next_id = next_id + 1
  local run = { id = next_id, client = req.client, debug = req.debug, label = req.label, t0 = vim.uv.hrtime(),
    on_done = opts.on_done, lenses_by_file = req.lenses_by_file or {},
    ctx = { files = req.files or {}, roots = req.roots or {}, methods = req.methods or {}, classes = req.classes or {} } }
  running = run
  M.last_request = req
  clear_marks()
  notify(("%s: %s..."):format(req.debug and "Debugging" or "Running", req.label))
  run.timer = vim.uv.new_timer()
  run.timer:start(timeout_ms(), 0, vim.schedule_wrap(function()
    if run.finished then return end
    local cancel = run.cancel_launch
    local r = collect(run.parsers or {}, run.ctx)
    r.error = ("no result within %g s (build, launch or test JVM stuck): run stopped"):format(timeout_ms() / 1000)
    finish_run(run, r)
    if cancel then pcall(cancel) end
    pcall(function()
      for _, s in pairs(require("dap").sessions()) do
        if s.config and type(s.config.name) == "string" and s.config.name:find("#" .. run.id .. "$") then s:disconnect({ terminateDebuggee = true }) end
      end
    end)
  end))
  run.parsers = {}
  local errors = {}
  local i = 0
  local function step()
    if run.finished then return end
    i = i + 1
    local launch = req.launches[i]
    if not launch then
      local r = collect(run.parsers, run.ctx)
      if #errors > 0 then r.error = table.concat(errors, "\n") end
      return finish_run(run, r)
    end
    launch_one(run, launch, function(parser, err)
      if run.finished then return end
      if parser then run.parsers[#run.parsers + 1] = parser end
      if err then errors[#errors + 1] = launch.label .. ": " .. err end
      step()
    end)
  end
  step()
end

--- Launches for a list of lenses (classes or methods): grouped by project and test kind.
local function launches_for(items, level, label)
  local groups, order = {}, {}
  for _, it in ipairs(items) do
    local key = it.projectName .. "\0" .. tostring(it.testKind)
    if not groups[key] then
      groups[key] = { projectName = it.projectName, testKind = it.testKind, testLevel = level, testNames = {}, uri = it.uri, label = label }
      order[#order + 1] = key
    end
    local g = groups[key]
    g.testNames[#g.testNames + 1] = level == LEVEL.method and it.jdtHandler or it.fullName
  end
  local out, skipped = {}, {}
  for _, k in ipairs(order) do
    local g = groups[k]
    if g.testKind == 2 then skipped[#skipped + 1] = g.projectName else out[#out + 1] = g end
  end
  return out, skipped
end

--- Index lenses: method key "fq.Class#name" and class fullName -> item, top class -> file.
index = function(req, lenses)
  local function walk(list)
    for _, l in ipairs(list or {}) do
      local file = l.uri and vim.uri_to_fname(l.uri)
      if l.testLevel == LEVEL.class then
        req.classes[l.fullName] = l
        if file then
          req.files[top_class(l.fullName)] = file
          req.lenses_by_file[file] = req.lenses_by_file[file] or {}
        end
      elseif l.testLevel == LEVEL.method then
        local cls, name = l.fullName:match("^([^#]+)#([^(]+)")
        if cls then req.methods[cls .. "#" .. name] = l end
      end
      walk(l.children)
    end
  end
  walk(lenses)
end

local function new_req(client, scope, debug, label)
  return { client = client, scope = scope, debug = debug, label = label, launches = {}, files = {}, methods = {},
    classes = {}, lenses_by_file = {}, roots = { client.config.root_dir } }
end

local function tkind_msg(skipped)
  return ("TestNG tests are not run by Nv4J's runner (%s): use <leader>tT (nvim-jdtls)"):format(table.concat(skipped, ", "))
end

local function from_buffer(opts, scope)
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if vim.bo[bufnr].filetype ~= "java" or name == "" then
    return refuse(opts, "Not a Java file: open a test class (or use <leader>tp for the whole project)")
  end
  local client = client_for(bufnr)
  if not client then return refuse(opts, "jdt.ls is not attached to this buffer yet: no tests to run") end
  local lnum0 = (opts.lnum or vim.api.nvim_win_get_cursor(0)[1]) - 1
  exec(client, "vscode.java.test.findTestTypesAndMethods", { vim.uri_from_bufnr(bufnr) }, bufnr, function(err, lenses)
    if err then return refuse(opts, "Test discovery failed: " .. tostring(err.message), vim.log.levels.ERROR) end
    lenses = lenses or {}
    local file = vim.fs.basename(name)
    if #lenses == 0 then
      return refuse(opts, ("No tests found in %s (no JUnit test there, JUnit not on the test classpath, or the file is not"
        .. " under a test source folder)"):format(file))
    end
    local label, items, level
    if scope == "nearest" then
      local m = nearest_method(lenses, lnum0)
      if m then
        local cls, mname = m.fullName:match("^([^#]+)#([^(]+)")
        items, level, label = { m }, LEVEL.method, short(cls) .. "." .. mname
      end
    end
    if not items then
      if scope == "file" then
        items = vim.tbl_filter(function(l) return l.testLevel == LEVEL.class end, lenses)
        label = file
      else
        local c = class_at(lenses, lnum0)
        items, label = { c }, c and short(c.fullName)
      end
      level = LEVEL.class
    end
    if not items or #items == 0 then return refuse(opts, "No test class found in " .. file) end
    local req = new_req(client, scope, opts.debug, label)
    index(req, lenses)
    req.lenses_by_file[name] = lenses
    local skipped
    req.launches, skipped = launches_for(items, level, label)
    if #req.launches == 0 then return refuse(opts, tkind_msg(skipped)) end
    start(req, opts)
  end)
end

local function from_project(opts)
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  local path = vim.api.nvim_buf_get_name(bufnr)
  local client = client_for(bufnr) or require("nv4j.root").client_for_path(path ~= "" and path or vim.fn.getcwd())
  if not client then
    local c = vim.lsp.get_clients({ name = "jdtls" })
    client = #c == 1 and c[1] or nil
  end
  if not client then return refuse(opts, "No jdt.ls project here: open a Java file of the project first") end
  local root = client.config.root_dir
  exec(client, "vscode.java.test.findJavaProjects", { vim.uri_from_fname(root) }, nil, function(err, projects)
    if err then return refuse(opts, "Test discovery failed: " .. tostring(err.message), vim.log.levels.ERROR) end
    projects = projects or {}
    local req = new_req(client, "project", opts.debug, "all tests in " .. vim.fs.basename(root))
    local classes = {}
    local pending = #projects
    local function done()
      if #classes == 0 then
        return refuse(opts, ("No JUnit tests found in %s (no test classes, or JUnit not on the test classpath)"):format(vim.fs.basename(root)))
      end
      local skipped
      req.launches, skipped = launches_for(classes, LEVEL.class, req.label)
      if #skipped > 0 then notify(tkind_msg(skipped), vim.log.levels.WARN) end
      if #req.launches == 0 then return refuse(opts, tkind_msg(skipped)) end
      start(req, opts)
    end
    if pending == 0 then return done() end
    for _, p in ipairs(projects) do
      exec(client, "vscode.java.test.findTestPackagesAndTypes", { p.jdtHandler }, nil, function(err1, tree)
        if not err1 then
          index(req, tree or {})
          -- top-level classes only (a class run includes its @Nested classes)
          local function walk(list, parent_is_class)
            for _, l in ipairs(list or {}) do
              if l.testLevel == LEVEL.class then
                if not parent_is_class then classes[#classes + 1] = l end
                walk(l.children, true)
              else
                walk(l.children, false)
              end
            end
          end
          walk(tree, false)
        end
        pending = pending - 1
        if pending == 0 then done() end
      end)
    end
  end)
end

--- Failed tests of the last run, rerun at method level (a parameterized method reruns all its
--- invocations; a class-level error reruns the class). Method lenses of failing files that the last
--- run did not fetch (a project run discovers classes only) are fetched first.
local function from_failed(opts)
  local r, req0 = M.last_result, M.last_request
  if not r or not req0 or #r.failures == 0 then
    return refuse(opts, "No failed tests in the last run", vim.log.levels.INFO)
  end
  local client = req0.client
  if client:is_stopped() then return refuse(opts, "jdt.ls of the last run stopped: run the tests again") end
  local req = new_req(client, "failed", opts.debug == nil and req0.debug or opts.debug, "failed tests")
  req.files, req.methods, req.classes, req.lenses_by_file, req.roots = req0.files, req0.methods, req0.classes,
    req0.lenses_by_file, req0.roots
  local function build()
    local methods, classes, seen = {}, {}, {}
    for _, f in ipairs(r.failures) do
      local m = f.class and f.method and req.methods[f.class .. "#" .. f.method]
      local c = not m and f.class and (req.classes[f.class] or req.classes[top_class(f.class)])
      local key = m and m.jdtHandler or (c and c.fullName)
      if key and not seen[key] then
        seen[key] = true
        if m then methods[#methods + 1] = m else classes[#classes + 1] = c end
      end
    end
    vim.list_extend(req.launches, (launches_for(methods, LEVEL.method, req.label)))
    vim.list_extend(req.launches, (launches_for(classes, LEVEL.class, req.label)))
    if #req.launches == 0 then return refuse(opts, "The failed tests of the last run cannot be located") end
    start(req, opts)
  end
  local missing = {}
  for _, f in ipairs(r.failures) do
    if f.method and f.class and not req.methods[f.class .. "#" .. f.method] then
      local file = class_file(f.class, { files = req.files, roots = req.roots })
      if file then missing[file] = true end
    end
  end
  local pending = vim.tbl_count(missing)
  if pending == 0 then return build() end
  for file in pairs(missing) do
    exec(client, "vscode.java.test.findTestTypesAndMethods", { vim.uri_from_fname(file) }, nil, function(_, lenses)
      index(req, lenses or {})
      req.lenses_by_file[file] = lenses or {}
      pending = pending - 1
      if pending == 0 then build() end
    end)
  end
end

--- Entry point (see the header).
function M.run(opts)
  opts = opts or {}
  local scope = opts.scope or "nearest"
  if running then
    return refuse(opts, ("A test run is in progress (%s): wait for it (it stops after %g s at most)"):format(running.label,
      timeout_ms() / 1000))
  end
  if scope == "nearest" or scope == "class" or scope == "file" then return from_buffer(opts, scope) end
  if scope == "project" then return from_project(opts) end
  if scope == "failed" then return from_failed(opts) end
  if scope == "last" then
    local req = M.last_request
    if not req then return refuse(opts, "No test run yet in this session", vim.log.levels.INFO) end
    if req.client:is_stopped() then return refuse(opts, "jdt.ls of the last run stopped: run the tests again") end
    req = vim.tbl_extend("force", {}, req)
    if opts.debug ~= nil then req.debug = opts.debug end
    return start(req, opts)
  end
  refuse(opts, "Unknown test scope: " .. tostring(scope), vim.log.levels.ERROR)
end

--- <leader>to: the results (quickfix list of the last run; a summary when nothing failed).
function M.results()
  local r = M.last_result
  if not r then return notify("No test results yet in this session") end
  local cur = vim.fn.getqflist({ title = 0 }).title or ""
  if cur:sub(1, #QF_TITLE) ~= QF_TITLE then
    -- another list became current since: go back to ours in the quickfix history
    local nr = vim.fn.getqflist({ nr = "$" }).nr
    for i = nr, 1, -1 do
      local t = vim.fn.getqflist({ nr = i, title = 0 }).title or ""
      if t:sub(1, #QF_TITLE) == QF_TITLE then
        vim.cmd("silent chistory " .. i)
        break
      end
    end
  end
  vim.cmd("copen")
end

-- Keys (D21, specs/005): plain vim.keymap.set, bound for real (no which-key queue).
M.keys = {
  { "<leader>tr", function() M.run({ scope = "nearest" }) end, "Test nearest" },
  { "<leader>tt", function() M.run({ scope = "class" }) end, "Test class" },
  { "<leader>tp", function() M.run({ scope = "project" }) end, "Test project (all tests, in the editor)" },
  { "<leader>tf", function() M.run({ scope = "failed" }) end, "Test failed again" },
  { "<leader>tl", function() M.run({ scope = "last" }) end, "Test last again" },
  { "<leader>to", function() M.results() end, "Test results (quickfix)" },
  { "<leader>td", function() M.run({ scope = "nearest", debug = true }) end, "Debug nearest test" },
}

--- Bind the keys globally (bufnr nil) or for one buffer. LazyVim's java extra adds <leader>tr/<leader>tt
--- per Java buffer through which-key on LspAttach, then calls the user's on_attach, where
--- plugins/java.lua calls this. Two orders exist:
---  - which-key already loaded (the usual case: jdt.ls attaches seconds after startup): its add() created
---    LazyVim's buffer keys synchronously, and the vim.keymap.set below replaces them.
---  - which-key not loaded yet (attach before VeryLazy, or headless): add() only queued the spec, and
---    which-key would create LazyVim's keys later, over Nv4J's. Those entries are taken out of the queue
---    (which-key 3aab214 `_queue`, pinned), so only Nv4J's keys exist once which-key loads.
local function strip_queued(bufnr)
  local ok, wk = pcall(require, "which-key")
  if not ok or type(wk._queue) ~= "table" then return 0 end
  local ours = {}
  for _, k in ipairs(M.keys) do ours[vim.keycode(k[1])] = true end
  local removed = 0
  local function walk(spec, buffer)
    if type(spec) ~= "table" then return end
    local b = spec.buffer or buffer
    for i = #spec, 1, -1 do
      local child = spec[i]
      if type(child) == "table" then
        local cb = child.buffer or b
        if type(child[1]) == "string" and child[2] ~= nil and ours[vim.keycode(child[1])] and (cb == bufnr or cb == 0) then
          table.remove(spec, i)
          removed = removed + 1
        else
          walk(child, b)
        end
      end
    end
  end
  for _, todo in ipairs(wk._queue) do walk(todo.spec, nil) end
  return removed
end
M._strip_queued = strip_queued

function M.bind(bufnr)
  if bufnr then strip_queued(bufnr) end
  for _, k in ipairs(M.keys) do
    vim.keymap.set("n", k[1], k[2], { desc = k[3], buffer = bufnr })
  end
end

return M
