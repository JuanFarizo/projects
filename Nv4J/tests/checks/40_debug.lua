-- P2 debug. Run via tests/run.sh. Spec: specs/features/debug-run.md.
--  classpath_first : no debug-classpath resolution fails in a fresh jdt.ls. nvim-jdtls's
--                    fetch_main_configs (LazyVim's main-class configs at attach, :JdtUpdateDebugConfig,
--                    <leader>rj) sends one vscode.java.resolveClasspath per main class in parallel; JDT
--                    launching publishes its lazy provider table (JavaRuntime.getClasspathProviders)
--                    before filling it, so a concurrent first call fails with "Referenced classpath
--                    provider does not exist: org.eclipse.m2e.launchconfig.classpathProvider", and
--                    nvim-jdtls then drops that main class (its callback never fires when the failed
--                    call is the last to answer). Here LazyVim's own call runs as in a user session,
--                    plus BURST more fetch_main_configs the moment jdt.ls attaches. The race is timing
--                    dependent: before the fix it failed in part of the runs only (debug-run.md).
--  configs         : every fetch_main_configs above calls back with all 3 main classes.
--  breakpoint_hit  : DemoApplication launched through nvim-dap (the user's config: integratedTerminal)
--                    stops at a breakpoint in LateRunner<N>.run <= 20 s after dap.run. LateRunner<N>
--                    and LateGreeting<N> (N new each run) are written by this check BEFORE jdt.ls starts,
--                    like files a `git pull` brings while Neovim is closed; only LateRunner<N> is opened
--                    (to set the breakpoint). Both are removed at the end, with their class files.
--  no_orphan       : after dap.terminate() the debuggee JVM is gone within 10 s.
-- Timings: /tmp/nv4j/logs/latency.jsonl (debug_breakpoint_hit).
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
local printed = {}
local orig_print = print
_G.print = function(...)
  local msg = table.concat(vim.tbl_map(tostring, { ... }), " ")
  if msg:find("classpath", 1, true) then printed[#printed + 1] = msg end
  return orig_print(...)
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
  end
  local configs = fetches[1] or nil
  for _, f in ipairs(fetches) do if not f or #f ~= #MAINS then configs = nil end end
  lsp.report(P .. "configs", configs ~= nil,
    ("main classes per fetch_main_configs (want %d each): %s"):format(#MAINS, table.concat(short, ", ")))
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
  if not cfg then
    lsp.report(P .. "breakpoint_hit", false, "no launch config for demo.DemoApplication")
    lsp.report(P .. "no_orphan", false, "nothing launched")
    return
  end
  cfg.args = "--server.port=0"
  cfg.vmArgs = ((cfg.vmArgs and (cfg.vmArgs .. " ")) or "") .. "-D" .. MARKER

  local rbuf = lsp.open(src .. runner .. ".java")
  local lnum = E.line_of(rbuf, "String text = greeting%.text%(%);") + 1
  local dap = require("dap")
  require("dap.breakpoints").set({}, rbuf, lnum)
  local stopped, output = nil, {}
  dap.listeners.after.event_stopped["nv4j_40"] = function(_, body) stopped = stopped or body end
  dap.listeners.after.event_output["nv4j_40"] = function(_, body) output[#output + 1] = body.output end
  local had_class = vim.uv.fs_stat(classes .. greeting .. ".class") ~= nil
  local t0 = E.now()
  dap.run(cfg)
  wait_until(BREAK_BUDGET_MS + 20000, function() return stopped ~= nil end, errs)
  local hit_ms = E.now() - t0
  local frame
  local session = dap.session()
  if stopped and session then
    session:request("stackTrace", { threadId = stopped.threadId, levels = 1 }, function(_, r)
      frame = r and r.stackFrames and r.stackFrames[1] or false
    end)
    wait_until(5000, function() return frame ~= nil end, errs)
  end
  -- the app's own output (integratedTerminal) explains a launch that never stops
  local term = ""
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buftype == "terminal" then term = term .. table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "") end
  end
  local log = term .. table.concat(output, "")
  local why = log:match("(Unresolved compilation problems?:.-cannot be resolved[%w ]-)%s%s") or log:match("(NoClassDefFoundError: [%w%.$/]+)")
    or log:match("([%w%.]*Exception: [%w%.$/]+)")
  local at = frame and ("%s line %s"):format(frame.name, tostring(frame.line)) or "no frame"
  E.log("debug_breakpoint_hit", stopped and hit_ms or -1, 1)
  lsp.report(P .. "breakpoint_hit", stopped ~= nil and stopped.reason == "breakpoint" and hit_ms <= BREAK_BUDGET_MS
      and frame and frame.name:find(runner, 1, true) ~= nil and frame.line == lnum,
    stopped and ("stopped (%s) after %.0f ms (budget %d) at %s (want %s line %d)"):format(stopped.reason, hit_ms, BREAK_BUDGET_MS, at, runner, lnum)
      or ("no stop within %.0f ms; %s.class at launch: %s; app: %s"):format(hit_ms, greeting, had_class and "yes" or "MISSING", why or "no error captured"))

  dap.terminate()
  wait_until(ORPHAN_WAIT_MS, function() return dap.session() == nil end, errs)
  local gone = wait_until(ORPHAN_WAIT_MS, function() return vim.fn.system({ "pgrep", "-f", MARKER }) == "" end, errs)
  lsp.report(P .. "no_orphan", gone, gone and "debuggee JVM gone after terminate"
    or ("debuggee JVM still running %d s after terminate: pid %s"):format(ORPHAN_WAIT_MS / 1000, vim.trim(vim.fn.system({ "pgrep", "-f", MARKER })):gsub("\n", " ")))
end)
_G.print = orig_print
cleanup()
if #errs > 0 then io.stdout:write("\nerrors while waiting: " .. table.concat(errs, " | "):sub(1, 600) .. "\n") end
if not ok_all then lsp.report(P .. "debug", false, "error: " .. tostring(err)) end
lsp.finish()
