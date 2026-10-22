-- P3 test runner. Run via tests/run.sh. Spec: specs/features/tests-runner.md (decision D21 in
-- specs/001-architecture.md). Product: nvim/lua/nv4j/tests.lua (P3 Task 2).
-- Budget (P3 plan, not weakened): a run of the nearest test shows its result <= 10 s after the key
-- press, warm (the second run of the session; the first run is logged as info).
-- API under test: require("nv4j.tests").run({ scope = "nearest"|"class"|"file"|"project"|"failed"|"last",
-- debug = bool, bufnr = ..., lnum = ..., on_done = function(result) end }), result = { passed, failed,
-- skipped, failures = { { name, message, filename, lnum, frames } }, tests = { { name, display, class,
-- method, state } }, error }; failures also go to the quickfix list (title "Nv4J tests: ...", jump to the
-- assertion line) and to vim.diagnostic (namespace nv4j.tests.ns) in the test buffer.
-- Every timed case goes through nv4j.tests and also asserts evidence a stub cannot fake: a RemoteTestRunner
-- launch seen by nvim-dap (on_config listener) during the run, and Nv4J's own result layer (quickfix
-- title "Nv4J tests", nv4j_tests diagnostics/signs). Negative controls (specs/features/tests-runner.md):
-- n60b fabricated on_done stub, n60c stub delegating to nvim-jdtls, n60d @Disabled counted as passed,
-- n60e failed-only reruns the whole class, n60f bind() a no-op, n60g no which-key queue strip, n60j no
-- timeout, n60k refusals without a message, n60l failure message dropped, n60m results() without copen,
-- n60n nearest always the class, n60o last refused.
-- Fixture (src/test/java): demo.billing.PriceCalculatorTest (5 passing runs: 1 plain, 3 parameterized,
-- 1 nested; 1 @Disabled), demo.billing.PriceCalculatorFailingTest (1 pass, 1 failure on purpose,
-- tagged nv4j-failing so `mvn test` skips it), demo.GreetingPropertiesTest (1 pass).
--  api              : nv4j.tests.run exists.
--  keys             : in a test buffer <leader>tr nearest, <leader>tt class, <leader>tp project,
--                     <leader>tf failed, <leader>tl last, <leader>to results, <leader>td debug nearest,
--                     each bound for real (E.keymap queued == false, not which-key's queue);
--                     <leader>tn stays "New terminal in a tab".
--  nearest_warm     : nearest = totalMultiplies, run twice: second result <= 10 s, 1 passed, a ✓ sign
--                     on the method line.
--  class_counts     : PriceCalculatorTest: 5/0/1, the 3 parameterized invocations, the nested test, notYet skipped.
--  file_scope       : scope "file" on the same file: 5/0/1.
--  nearest_param    : cursor in the parameterized method: 3 passed.
--  nearest_nested   : cursor in the @Nested class's method: totalIsZero, 1 passed.
--  failure_shown    : PriceCalculatorFailingTest: 1/1; quickfix entry at the `assertEquals(7` line with the
--                     message, nv4j_tests diagnostic on that line.
--  project_counts   : the whole project: 7/1/1.
--  failed_only      : scope "failed" after the project run: only failsOnPurpose, 0/1.
--  last_again       : scope "last": the failed-only run again, 0/1.
--  results_panel    : results() (<leader>to) opens the quickfix window on the Nv4J list.
--  debug_nearest    : debug = true (<leader>td): P2 adapter build ("test debug"), noDebug false, a breakpoint
--                     in totalMultiplies stops once, then the result 1 passed.
--  broken_class     : a test class that does not compile: a result (failure "Unresolved compilation"), no hang.
--  no_tests_file    : nearest in a main class: visible "No tests found" message, quickly.
--  no_junit_project : a Maven project without JUnit (generated under /tmp/nv4j): visible message for
--                     nearest and project, quickly.
--  timeout_bounded  : product timeout set to 300 ms: the run ends with "no result within", the next run works.
--  keys_after_whichkey: which-key loaded and VimEnter fired (which-key then creates every queued mapping):
--                     Nv4J's keys are still the bound ones (LazyVim's queued <leader>tr/<leader>tt for the
--                     buffer were taken out of the queue at attach).
--  fixture_restored : the fixture is unchanged on disk afterwards.
-- Timings: /tmp/nv4j/logs/latency.jsonl (tests_*).
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local F = require("fixture")
local P = "60_tests_runner."
local WARM_BUDGET_MS, RUN_TIMEOUT_MS = 10000, 150000 -- the check waits longer than the product's 120 s bound
local RUNNER = "org.eclipse.jdt.internal.junit.runner.RemoteTestRunner"

local fixture = vim.env.NV4J_FIXTURE
local tdir = fixture .. "/src/test/java/demo/billing/"
local PASSING, FAILING = tdir .. "PriceCalculatorTest.java", tdir .. "PriceCalculatorFailingTest.java"
local BROKEN = tdir .. "BrokenTest.java"
local snap = F.snapshot()

local buf = lsp.open(PASSING)
local client = lsp.wait_ready(buf, 120000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready" or "jdtls not ready")
if not client then return lsp.finish() end
pcall(require, "config.keymaps")

local ok_mod, tests = pcall(require, "nv4j.tests")
local api = ok_mod and type(tests) == "table" and type(tests.run) == "function"
lsp.report(P .. "api", api, api and "nv4j.tests.run" or ("nv4j.tests missing: " .. tostring(tests):gsub("\n.*", "")))
if not api then return lsp.finish() end

local notes = E.capture_notify()
local launches = {}
local dap = require("dap")
dap.listeners.on_config["n60"] = function(c)
  if c.mainClass == RUNNER then launches[#launches + 1] = c end
  return c
end

local KEYS = { ["<leader>tr"] = "[Nn]earest", ["<leader>tt"] = "[Cc]lass", ["<leader>tp"] = "[Pp]roject",
  ["<leader>tf"] = "[Ff]ailed", ["<leader>tl"] = "[Ll]ast", ["<leader>to"] = "[Rr]esults", ["<leader>td"] = "[Dd]ebug" }
-- Nv4J's own descs (LazyVim's "Run Nearest Test" also matches [Nn]earest: the desc must be Nv4J's exactly)
local OWN = {}
for _, k in ipairs(tests.keys or {}) do OWN[k[1]] = k[3] end
local function check_keys(b)
  vim.api.nvim_set_current_buf(b)
  local bad = {}
  for lhs, pat in pairs(KEYS) do
    local m = E.keymap(lhs, b)
    local d = m and (m.desc or "no desc") or "unmapped"
    if not d:find(pat) or d ~= OWN[lhs] or not m or m.queued ~= false then
      bad[#bad + 1] = lhs .. "=" .. d .. (m and m.queued and " (queued in which-key, not bound)" or "")
    end
  end
  table.sort(bad)
  return bad
end

-- keys: LazyVim adds its jdtls test keys through which-key on LspAttach; Nv4J's are bound right after
vim.wait(10000, function() return E.keymap("<leader>tr", buf) ~= nil end, 50)
do
  local bad = check_keys(buf)
  local tn = vim.fn.maparg("<leader>tn", "n", false, true)
  local tn_ok = (tn.desc or ""):find("terminal") ~= nil
  lsp.report(P .. "keys", #bad == 0 and tn_ok, ("%s; <leader>tn=%s"):format(#bad == 0 and "all 7 bound (queued=false)" or
    ("wrong: " .. table.concat(bad, ", ")), tostring(tn.desc)))
end

--- One run through nv4j.tests; returns result (or nil), ms, evidence { launches, cfg, title }.
local function run(scope, b, lnum, extra)
  local result
  local opts = vim.tbl_extend("force", { scope = scope, bufnr = b, lnum = lnum, on_done = function(r) result = r end }, extra or {})
  vim.api.nvim_set_current_buf(b)
  if lnum then vim.api.nvim_win_set_cursor(0, { lnum, 0 }) end
  local before = #launches
  vim.uv.update_time()
  local t0 = E.now()
  local ok, why = pcall(tests.run, opts)
  if not ok then return nil, 0, { err = tostring(why), launches = 0 } end
  vim.wait(RUN_TIMEOUT_MS, function() return result ~= nil end, 20)
  local ms = E.now() - t0
  local ev = { launches = #launches - before, cfg = launches[#launches], title = vim.fn.getqflist({ title = 0 }).title or "" }
  if not result then ev.err = "no result within " .. RUN_TIMEOUT_MS / 1000 .. " s" end
  vim.wait(300) -- the session tear-down settles before the next run
  return result, ms, ev
end

local function fmt(r, ev)
  if not r then return "no result" .. (ev and ev.err and (": " .. ev.err) or "") end
  return ("passed %s, failed %s, skipped %s%s; launches %d; qf '%s'"):format(tostring(r.passed), tostring(r.failed),
    tostring(r.skipped), r.error and (", error: " .. r.error:gsub("\n", " ")) or "", ev.launches, ev.title:sub(1, 70))
end

--- Evidence that the run went through the real runner and Nv4J's result layer.
local function real(r, ev, want_title)
  return r ~= nil and ev.launches >= 1 and ev.title:find("^Nv4J tests: " .. vim.pesc(want_title)) ~= nil
end

local function counts(r, p, f, s) return r and r.passed == p and r.failed == f and r.skipped == s end
local function title_of(p, f, s) return ("%d passed, %d failed, %d skipped"):format(p, f, s) end

local ok_all, err = pcall(function()
  -- nearest, twice (first = cold info, second = warm budget)
  local l = E.line_of(buf, "void totalMultiplies") + 1
  local r1, ms1, ev1 = run("nearest", buf, l)
  E.log("tests_nearest_first", r1 and ms1 or -1, 1)
  local r2, ms2, ev2 = run("nearest", buf, l)
  E.log("tests_nearest_warm", r2 and ms2 or -1, 1)
  local sign = false
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, tests.ns, { l - 1, 0 }, { l - 1, -1 }, { details = true })) do
    if (m[4].sign_text or ""):find("✓") then sign = true end
  end
  local name_ok = r2 and r2.tests[1] and (r2.tests[1].method == "totalMultiplies")
  lsp.report(P .. "nearest_warm", counts(r2, 1, 0, 0) and real(r2, ev2, title_of(1, 0, 0)) and name_ok and sign and ms2 <= WARM_BUDGET_MS,
    ("warm %.0f ms (budget %d), %s, test %s, ✓ sign %s; first run %.0f ms, %s"):format(ms2, WARM_BUDGET_MS, fmt(r2, ev2),
      r2 and r2.tests[1] and tostring(r2.tests[1].method) or "-", sign and "on line " .. l or "MISSING", ms1, fmt(r1, ev1)))

  -- class with parameterized, nested and disabled tests
  local rc, msc, evc = run("class", buf, 1)
  E.log("tests_class", rc and msc or -1, 1)
  local inv, nested, skipped_name = 0, false, false
  for _, t in ipairs(rc and rc.tests or {}) do
    if t.method == "totalOfOneUnit" and t.state == "passed" and (t.display or ""):find("^%[%d%]") then inv = inv + 1 end
    if t.method == "totalIsZero" and (t.class or ""):find("%$WhenEmpty$") and t.state == "passed" then nested = true end
    if t.method == "notYet" and t.state == "skipped" then skipped_name = true end
  end
  lsp.report(P .. "class_counts", counts(rc, 5, 0, 1) and real(rc, evc, title_of(5, 0, 1)) and inv == 3 and nested and skipped_name,
    ("%.0f ms, %s (want 5/0/1); parameterized invocations %d/3, nested %s, notYet skipped %s"):format(msc, fmt(rc, evc), inv,
      tostring(nested), tostring(skipped_name)))

  local rfs, msfs, evfs = run("file", buf, 1)
  lsp.report(P .. "file_scope", counts(rfs, 5, 0, 1) and real(rfs, evfs, title_of(5, 0, 1)),
    ("%.0f ms, %s (want 5/0/1)"):format(msfs, fmt(rfs, evfs)))

  local rpa, mspa, evpa = run("nearest", buf, E.line_of(buf, "void totalOfOneUnit") + 1)
  lsp.report(P .. "nearest_param", counts(rpa, 3, 0, 0) and real(rpa, evpa, title_of(3, 0, 0)),
    ("%.0f ms, %s (want 3/0/0)"):format(mspa, fmt(rpa, evpa)))

  local rne, msne, evne = run("nearest", buf, E.line_of(buf, "void totalIsZero") + 1)
  local ne_ok = rne and rne.tests[1] and rne.tests[1].method == "totalIsZero"
  lsp.report(P .. "nearest_nested", counts(rne, 1, 0, 0) and real(rne, evne, title_of(1, 0, 0)) and ne_ok,
    ("%.0f ms, %s (want totalIsZero 1/0/0)"):format(msne, fmt(rne, evne)))

  -- a failing assertion: message, quickfix jump target, diagnostic on the line
  local fbuf = lsp.open(FAILING)
  lsp.wait_ready(fbuf, 30000)
  local fl = E.line_of(fbuf, "assertEquals%(7, total") + 1
  vim.fn.setqflist({}, "r", { title = "", items = {} })
  local rf, msf, evf = run("class", fbuf, 1)
  E.log("tests_failure", rf and msf or -1, 1)
  local qf = vim.fn.getqflist()
  local hit
  for _, q in ipairs(qf) do
    if q.bufnr ~= 0 and vim.api.nvim_buf_get_name(q.bufnr) == FAILING and q.lnum == fl and q.text:find("fails on purpose", 1, true) then hit = q end
  end
  local diag
  for _, d in ipairs(vim.diagnostic.get(fbuf, { namespace = tests.ns })) do
    if d.lnum == fl - 1 and d.message:find("fails on purpose", 1, true) then diag = d end
  end
  lsp.report(P .. "failure_shown", counts(rf, 1, 1, 0) and real(rf, evf, title_of(1, 1, 0)) and hit ~= nil and diag ~= nil,
    ("%.0f ms, %s (want 1/1); quickfix %s (%d item(s): %s); nv4j diagnostic on line %d %s"):format(msf, fmt(rf, evf),
      hit and ("entry at line " .. fl) or ("NO entry at line " .. fl .. " with the message"), #qf,
      table.concat(vim.tbl_map(function(q) return ("L%d %s"):format(q.lnum, (q.text or ""):gsub("%s+", " "):sub(1, 60)) end, qf), " | "),
      fl, diag and "present" or "MISSING"))

  -- project, failed only, last
  local rp, msp, evp = run("project", buf, nil)
  E.log("tests_project", rp and msp or -1, 1)
  lsp.report(P .. "project_counts", counts(rp, 7, 1, 1) and real(rp, evp, title_of(7, 1, 1)),
    ("%.0f ms, %s (want 7/1/1)"):format(msp, fmt(rp, evp)))
  local rx, msx, evx = run("failed", buf, nil)
  E.log("tests_failed_only", rx and msx or -1, 1)
  local only = rx and #rx.tests == 1 and rx.tests[1].method == "failsOnPurpose"
  lsp.report(P .. "failed_only", counts(rx, 0, 1, 0) and real(rx, evx, title_of(0, 1, 0)) and only,
    ("%.0f ms, %s (want 0/1, only failsOnPurpose)"):format(msx, fmt(rx, evx)))
  local rl, msl, evl = run("last", buf, nil)
  lsp.report(P .. "last_again", counts(rl, 0, 1, 0) and real(rl, evl, title_of(0, 1, 0)),
    ("%.0f ms, %s (want 0/1)"):format(msl, fmt(rl, evl)))

  -- results panel
  vim.cmd("cclose")
  vim.fn.setqflist({}, " ", { title = "other list", items = {} }) -- another list became current meanwhile
  tests.results()
  local qwin
  for _, w in ipairs(vim.fn.getwininfo()) do if w.quickfix == 1 and w.loclist == 0 then qwin = w end end
  local qt = vim.fn.getqflist({ title = 0 }).title or ""
  lsp.report(P .. "results_panel", qwin ~= nil and qt:find("^Nv4J tests: ") ~= nil,
    ("quickfix window %s, current list '%s'"):format(qwin and "open" or "NOT open", qt:sub(1, 70)))
  vim.cmd("cclose")

  -- debug nearest through the P2 adapter, with a breakpoint
  local stopped = 0
  -- continue once nvim-dap has taken the stop (its stopped handler fetches threads/frames first)
  local function continue_when_stopped(tries)
    local s = dap.session()
    if s and s.stopped_thread_id then return dap.continue() end
    if tries > 0 then vim.defer_fn(function() continue_when_stopped(tries - 1) end, 100) end
  end
  dap.listeners.after.event_stopped["n60"] = function()
    stopped = stopped + 1
    vim.defer_fn(function() continue_when_stopped(50) end, 100)
  end
  local bl = E.line_of(buf, "void totalMultiplies") + 2
  require("dap.breakpoints").set({}, buf, bl)
  local n0 = #notes
  local rd, msd, evd = run("nearest", buf, bl, { debug = true })
  require("dap.breakpoints").clear()
  dap.listeners.after.event_stopped["n60"] = nil
  local built = false
  for i = n0 + 1, #notes do if notes[i].msg:find("Building before test debug", 1, true) then built = true end end
  local nodebug = evd.cfg and evd.cfg.noDebug
  lsp.report(P .. "debug_nearest", counts(rd, 1, 0, 0) and not (rd and rd.error) and real(rd, evd, title_of(1, 0, 0)) and stopped == 1
    and nodebug == false and built,
    ("%.0f ms, %s; breakpoint line %d stopped %d time(s), noDebug %s, P2 build message %s"):format(msd, fmt(rd, evd), bl, stopped,
      tostring(nodebug), built and "seen" or "MISSING"))

  -- a test class that does not compile
  local f = assert(io.open(BROKEN, "w"))
  f:write('package demo.billing;\n\nimport org.junit.jupiter.api.Test;\n\nclass BrokenTest {\n    @Test\n    void broken() {\n'
    .. '        int x = "text";\n    }\n}\n')
  f:close()
  local bb = lsp.open(BROKEN)
  vim.wait(20000, function()
    for _, d in ipairs(vim.diagnostic.get(bb)) do if d.severity == vim.diagnostic.severity.ERROR then return true end end
    return false
  end, 100)
  local rb, msb, evb = run("class", bb, 7)
  local unresolved = rb and rb.failures[1] and rb.failures[1].message:find("Unresolved compilation", 1, true)
  lsp.report(P .. "broken_class", rb ~= nil and rb.failed == 1 and unresolved ~= nil and evb.launches >= 1 and msb < 30000,
    ("%.0f ms, %s; failure message: %s"):format(msb, fmt(rb, evb), rb and rb.failures[1] and rb.failures[1].message:gsub("\n.*", "") or "-"))

  -- no tests in the file
  local mb = lsp.open(fixture .. "/src/main/java/demo/billing/PriceCalculator.java")
  lsp.wait_ready(mb, 30000)
  n0 = #notes
  local rm, msm, evm = run("nearest", mb, 1)
  local seen
  for i = n0 + 1, #notes do if notes[i].msg:find("No tests found in PriceCalculator.java", 1, true) then seen = notes[i].msg end end
  lsp.report(P .. "no_tests_file", rm ~= nil and rm.error ~= nil and seen ~= nil and evm.launches == 0 and msm < 5000,
    ("%.0f ms, message %s"):format(msm, seen and ("'" .. seen:sub(1, 60) .. "...'") or "MISSING"))

  F.restore(snap, client) -- drops the fixture buffers
  buf = lsp.open(PASSING)
  lsp.wait_ready(buf, 30000)

  -- a project without JUnit
  local nj = "/tmp/nv4j/nojunit-" .. vim.fn.getpid()
  vim.fn.mkdir(nj .. "/src/test/java/x", "p")
  vim.fn.writefile({ '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>',
    "<groupId>x</groupId><artifactId>nojunit</artifactId><version>1</version>",
    "<properties><maven.compiler.release>21</maven.compiler.release></properties></project>" }, nj .. "/pom.xml")
  vim.fn.writefile({ "package x;", "", "class PlainTest {", "    void check() {", "    }", "}" }, nj .. "/src/test/java/x/PlainTest.java")
  local nb = lsp.open(nj .. "/src/test/java/x/PlainTest.java")
  local c2 = lsp.wait_ready(nb, 120000)
  if not c2 then
    lsp.report(P .. "no_junit_project", false, "jdt.ls did not import " .. nj)
  else
    n0 = #notes
    local rn, msn = run("nearest", nb, 4)
    local rnp, msnp, evnp = run("project", nb, nil)
    local m1, m2
    for i = n0 + 1, #notes do
      if notes[i].msg:find("No tests found in PlainTest.java", 1, true) then m1 = true end
      if notes[i].msg:find("No JUnit tests found in nojunit", 1, true) then m2 = true end
    end
    lsp.report(P .. "no_junit_project", rn and rn.error and rnp and rnp.error and m1 and m2 and evnp.launches == 0
      and msn < 10000 and msnp < 10000,
      ("nearest %.0f ms (message %s), project %.0f ms (message %s)"):format(msn, m1 and "seen" or "MISSING", msnp, m2 and "seen" or "MISSING"))
    vim.lsp.stop_client(c2.id, true)
  end
  vim.fn.delete(nj, "rf")

  -- bounded run time: product timeout 300 ms
  vim.g.nv4j_test_timeout_ms = 300
  local rt, mst = run("class", buf, 1)
  vim.g.nv4j_test_timeout_ms = nil
  vim.wait(4000) -- the abandoned launch is reaped
  local ra, msa, eva = run("nearest", buf, l)
  lsp.report(P .. "timeout_bounded", rt ~= nil and (rt.error or ""):find("no result within", 1, true) ~= nil and mst < 3000
    and counts(ra, 1, 0, 0) and real(ra, eva, title_of(1, 0, 0)),
    ("timed-out run ended after %.0f ms (%s); next run %.0f ms, %s"):format(mst, rt and tostring(rt.error) or "no result", msa, fmt(ra, eva)))
end)
if not ok_all then lsp.report(P .. "error", false, tostring(err)) end
pcall(function() require("dap").terminate() end)

-- which-key at VimEnter creates LazyVim's queued buffer keys; Nv4J's must be rebound over them
do
  vim.api.nvim_set_current_buf(buf)
  -- as a real session: lazy loads which-key (setup defers its load to VimEnter headless), then VimEnter
  -- makes it create every queued mapping (LazyVim's java buffer keys included)
  -- Queued specs of buffers this check wiped (F.restore drops the fixture buffers) would make which-key's
  -- queue processing fail ("Invalid buffer id") and abort its load: a headless artifact (a real session
  -- loads which-key at VeryLazy, before such buffers exist), so they are dropped first.
  pcall(function()
    local wk = require("which-key")
    local function prune(spec)
      for i = #spec, 1, -1 do
        local c = spec[i]
        if type(c) == "table" then
          if type(c.buffer) == "number" and c.buffer ~= 0 and not vim.api.nvim_buf_is_valid(c.buffer) then table.remove(spec, i) else prune(c) end
        end
      end
    end
    for i = #wk._queue, 1, -1 do
      local sp = wk._queue[i].spec
      if type(sp) == "table" and type(sp.buffer) == "number" and not vim.api.nvim_buf_is_valid(sp.buffer) then table.remove(wk._queue, i)
      elseif type(sp) == "table" then prune(sp) end
    end
  end)
  pcall(function() require("lazy").load({ plugins = { "which-key.nvim" } }) end)
  pcall(vim.api.nvim_exec_autocmds, "VimEnter", {})
  local wk_loaded = vim.wait(5000, function()
    local okc, cfg = pcall(require, "which-key.config")
    return okc and rawget(cfg, "loaded") == true
  end, 50)
  vim.wait(500)
  local bad = check_keys(buf)
  lsp.report(P .. "keys_after_whichkey", wk_loaded and #bad == 0, ("which-key %s; %s"):format(wk_loaded and "loaded (queue processed)" or "NOT loaded",
    #bad == 0 and "all 7 still Nv4J's" or ("overridden: " .. table.concat(bad, ", "))))
end

local d = F.diff(snap)
if #d.added + #d.changed + #d.missing > 0 then F.restore(snap, client) end
d = F.diff(snap)
lsp.report(P .. "fixture_restored", #d.added + #d.changed + #d.missing == 0, F.fmt(d))
lsp.finish()
