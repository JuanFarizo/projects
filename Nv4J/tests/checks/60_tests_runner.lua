-- P3 test runner. Run via tests/run.sh. Spec: specs/features/tests-runner.md (decision D21 in
-- specs/001-architecture.md). Product: nvim/lua/nv4j/tests.lua (P3 Task 2).
-- Budget (P3 plan, not weakened): a run of the nearest test shows its result <= 10 s after the key
-- press, warm (the second run of the session; the first run is logged as info).
-- API under test (Task 2): require("nv4j.tests").run({ scope = "nearest"|"class"|"project"|"failed"|"last",
-- bufnr = ..., lnum = ..., on_done = function(result) end }), result = { passed = n, failed = n,
-- skipped = n, failures = { { name, message, filename, lnum } } }; failures also go to the quickfix
-- list (jump to the assertion line) and to vim.diagnostic in the test buffer.
-- Fixture (src/test/java): demo.billing.PriceCalculatorTest (5 passing runs: 1 plain, 3 parameterized,
-- 1 nested; 1 @Disabled), demo.billing.PriceCalculatorFailingTest (1 pass, 1 failure on purpose,
-- tagged nv4j-failing so `mvn test` skips it), demo.GreetingPropertiesTest (1 pass).
--  api            : nv4j.tests.run exists.
--  keys           : in a test buffer <leader>tr nearest, <leader>tt class, <leader>tp project,
--                   <leader>tf failed, <leader>tl last, <leader>to results, <leader>td debug nearest;
--                   <leader>tn stays "New terminal in a tab" (no collision).
--  nearest_warm   : nearest = PriceCalculatorTest.totalMultiplies, run twice: second result <= 10 s,
--                   1 passed, 0 failed.
--  class_counts   : PriceCalculatorTest: 5 passed, 0 failed, 1 skipped (parameterized and nested counted).
--  failure_shown  : PriceCalculatorFailingTest: 1 passed, 1 failed; the quickfix list has the failure at
--                   the `assertEquals(7` line of PriceCalculatorFailingTest.java with the message, and the
--                   buffer has a diagnostic on that line.
--  project_counts : the whole project: 7 passed, 1 failed, 1 skipped.
--  failed_only    : after project_counts, scope "failed" reruns only failsOnPurpose: 0 passed, 1 failed.
-- Baseline (P3 Task 0): today's keys are LazyVim's (<leader>tr nvim-jdtls test_nearest_method,
-- <leader>tt test_class, <leader>tT pick_test) and Nv4J's <leader>tp (`mvn test` in a terminal, no
-- results in the editor). nearest/class are measured through nvim-jdtls with its after_test callback
-- (results it gives: parsed tests and quickfix items; it does not count skipped tests).
-- Timings: /tmp/nv4j/logs/latency.jsonl (tests_*).
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local P = "60_tests_runner."
local WARM_BUDGET_MS, RUN_TIMEOUT_MS = 10000, 90000

local fixture = vim.env.NV4J_FIXTURE
local tdir = fixture .. "/src/test/java/demo/billing/"
local PASSING, FAILING = tdir .. "PriceCalculatorTest.java", tdir .. "PriceCalculatorFailingTest.java"

local buf = lsp.open(PASSING)
local client = lsp.wait_ready(buf, 120000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready" or "jdtls not ready")
if not client then return lsp.finish() end
pcall(require, "config.keymaps")

local ok_mod, tests = pcall(require, "nv4j.tests")
local api = ok_mod and type(tests) == "table" and type(tests.run) == "function"
lsp.report(P .. "api", api, api and "nv4j.tests.run" or ("nv4j.tests missing: " .. tostring(tests):gsub("\n.*", "")))

-- keys: LazyVim adds the jdtls test keys through which-key on LspAttach (E.keymap reads them from
-- which-key's queue in a headless run); wait for them
vim.wait(10000, function() return E.keymap("<leader>tr", buf) ~= nil end, 50)
do
  vim.api.nvim_set_current_buf(buf)
  local want = { ["<leader>tr"] = "[Nn]earest", ["<leader>tt"] = "[Cc]lass", ["<leader>tp"] = "[Pp]roject",
    ["<leader>tf"] = "[Ff]ailed", ["<leader>tl"] = "[Ll]ast", ["<leader>to"] = "[Rr]esults", ["<leader>td"] = "[Dd]ebug" }
  local bad, seen = {}, {}
  for lhs, pat in pairs(want) do
    local m = E.keymap(lhs, buf)
    local d = m and (m.desc or "no desc") or "unmapped"
    seen[#seen + 1] = lhs .. "=" .. d
    -- a key still running `mvn test` in a terminal (today's <leader>tp) shows no results in the editor
    if not d:find(pat) or d:find("build tool", 1, true) then bad[#bad + 1] = lhs .. "=" .. d end
  end
  local tn = vim.fn.maparg("<leader>tn", "n", false, true)
  local tn_ok = (tn.desc or ""):find("terminal") ~= nil
  table.sort(bad)
  lsp.report(P .. "keys", #bad == 0 and tn_ok, ("%s; <leader>tn=%s"):format(#bad == 0 and "all mapped" or ("wrong: " .. table.concat(bad, ", ")),
    tostring(tn.desc)))
end

--- Baseline runner: nvim-jdtls (what <leader>tr / <leader>tt call), result from its after_test.
local function jdtls_run(scope, b, lnum, on_done)
  local dapj = require("jdtls.dap")
  local opts = { bufnr = b, lnum = lnum, after_test = function(items, ts)
    items, ts = items or {}, ts or {}
    local failed = 0
    for _, t in ipairs(ts) do if t.failed then failed = failed + 1 end end
    local failures = {}
    for _, it in ipairs(items) do
      failures[#failures + 1] = { name = it.text, message = it.text, filename = it.bufnr and vim.api.nvim_buf_get_name(it.bufnr), lnum = tonumber(it.lnum) }
    end
    on_done({ passed = #ts - failed, failed = failed, skipped = nil, failures = failures,
      names = table.concat(vim.tbl_map(function(t) return tostring(t.method) end, ts), ",") })
  end }
  if scope == "nearest" then dapj.test_nearest_method(opts)
  elseif scope == "class" then dapj.test_class(opts)
  else return false, "no in-editor run for scope '" .. scope .. "' today (<leader>tp runs `mvn test` in a terminal)" end
  return true
end

--- One run; returns result (or nil), ms, how.
local function run(scope, b, lnum)
  local result
  local done = function(r) result = r end
  vim.api.nvim_set_current_buf(b)
  if lnum then vim.api.nvim_win_set_cursor(0, { lnum, 0 }) end
  vim.uv.update_time()
  local t0 = E.now()
  local ok, why
  local how = api and "nv4j.tests" or "nvim-jdtls (LazyVim <leader>tr/<leader>tt)"
  if api then
    ok, why = pcall(tests.run, { scope = scope, bufnr = b, lnum = lnum, on_done = done })
    why = why and tostring(why)
  else
    ok, why = jdtls_run(scope, b, lnum, done)
  end
  if not ok then return nil, 0, how .. ": " .. tostring(why) end
  vim.wait(RUN_TIMEOUT_MS, function() return result ~= nil end, 20)
  local ms = E.now() - t0
  if not result then return nil, ms, how .. ": no result within " .. RUN_TIMEOUT_MS / 1000 .. " s" end
  vim.wait(300) -- the session tear-down (terminal, dap) settles before the next run
  return result, ms, how
end

local function fmt(r)
  if not r then return "no result" end
  return ("passed %s, failed %s, skipped %s"):format(tostring(r.passed), tostring(r.failed), r.skipped == nil and "not counted" or tostring(r.skipped))
end

local ok_all, err = pcall(function()
  -- nearest, twice (first = cold info, second = warm budget)
  local l = E.line_of(buf, "void totalMultiplies") + 1
  local r1, ms1, how1 = run("nearest", buf, l)
  E.log("tests_nearest_first", r1 and ms1 or -1, 1)
  local r2, ms2, how2 = run("nearest", buf, l)
  E.log("tests_nearest_warm", r2 and ms2 or -1, 1)
  lsp.report(P .. "nearest_warm", r2 ~= nil and r2.passed == 1 and r2.failed == 0 and ms2 <= WARM_BUDGET_MS,
    ("%s: warm %.0f ms (budget %d), %s; first run %.0f ms, %s"):format(how2, ms2, WARM_BUDGET_MS, fmt(r2), ms1, fmt(r1) .. (r1 and "" or (" " .. how1))))

  -- class with parameterized, nested and disabled tests
  local rc, msc, howc = run("class", buf, 1)
  E.log("tests_class", rc and msc or -1, 1)
  lsp.report(P .. "class_counts", rc ~= nil and rc.passed == 5 and rc.failed == 0 and rc.skipped == 1,
    ("%s: %.0f ms, %s (want 5/0/1)%s"):format(howc, msc, fmt(rc), rc and rc.names and (" tests: " .. rc.names) or ""))

  -- a failing assertion: message, quickfix jump target, diagnostic on the line
  local fbuf = lsp.open(FAILING)
  lsp.wait_ready(fbuf, 30000)
  local fl = E.line_of(fbuf, "assertEquals%(7, total") + 1
  vim.fn.setqflist({}, "r", { title = "", items = {} })
  local rf, msf, howf = run("class", fbuf, 1)
  E.log("tests_failure", rf and msf or -1, 1)
  local qf = vim.fn.getqflist()
  local hit
  for _, q in ipairs(qf) do
    if q.bufnr ~= 0 and vim.api.nvim_buf_get_name(q.bufnr) == FAILING and q.lnum == fl and q.text:find("fails on purpose", 1, true) then hit = q end
  end
  local diag
  for _, d in ipairs(vim.diagnostic.get(fbuf)) do
    if d.lnum == fl - 1 and d.message:find("fails on purpose", 1, true) then diag = d end
  end
  lsp.report(P .. "failure_shown", rf ~= nil and rf.passed == 1 and rf.failed == 1 and hit ~= nil and diag ~= nil,
    ("%s: %.0f ms, %s (want 1/1); quickfix %s (%d item(s): %s); diagnostic on line %d %s"):format(howf, msf, fmt(rf),
      hit and ("entry at line " .. fl) or ("NO entry at line " .. fl .. " with the message"), #qf,
      table.concat(vim.tbl_map(function(q) return ("L%d %s"):format(q.lnum, (q.text or ""):gsub("%s+", " "):sub(1, 60)) end, qf), " | "),
      fl, diag and "present" or "MISSING"))

  -- project, then failed only
  local rp, msp, howp = run("project", buf, nil)
  E.log("tests_project", rp and msp or -1, 1)
  lsp.report(P .. "project_counts", rp ~= nil and rp.passed == 7 and rp.failed == 1 and rp.skipped == 1,
    ("%s: %.0f ms, %s (want 7/1/1)"):format(howp, msp, rp and fmt(rp) or ""))
  local rx, msx, howx = run("failed", buf, nil)
  E.log("tests_failed_only", rx and msx or -1, 1)
  lsp.report(P .. "failed_only", rx ~= nil and rx.passed == 0 and rx.failed == 1,
    ("%s: %.0f ms, %s (want 0/1)"):format(howx, msx, rx and fmt(rx) or ""))
end)
if not ok_all then lsp.report(P .. "error", false, tostring(err)) end
pcall(function() require("dap").terminate() end)
lsp.finish()
