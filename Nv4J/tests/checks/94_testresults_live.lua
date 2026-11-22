-- Test results view, live (nv4j/testresultsui.lua, nv4j/testresults.lua, nv4j/tests.lua) on the Maven fixture: a temporary
-- test class demo.results.ResultsViewTest (one passing, one failing assertion, one throwing, one printing to stdout) is run through
-- the real runner with the real <leader>tt key; the model, the drawn buffer and the keys are asserted. Pure twin: 93_testresults_unit.
-- Waits are manual deadline loops with a real sleep per round (vim.wait(50) without a callback): no vim.wait callback doing requests.
--  run_model       : the stored model has each of the 4 tests with status, failure message, the first project frame (file:line of the
--                    assertEquals / the throw), duration > 0 for the sleeping tests, and the stdout of printsOut on that test only.
--  quickfix_marks  : the existing result layer is unchanged: quickfix "Nv4J tests: 2 passed, 2 failed, 0 skipped", an nv4j_tests
--                    diagnostic on the assertion line, a ✓ sign.
--  notify_key      : after the failing run one notification names <leader>tv.
--  view_lines      : <leader>tv (feedkeys) opens the view: summary line, failed tests first, then the passing ones, durations.
--  expand_detail   : <CR> on the throwing test: message, trace with the project frame and library frames, <CR> on printsOut: its output.
--  jump_frame      : <CR> on the project frame line: the test file is current and the cursor is on the throwing line.
--  library_frame   : <CR> on a library frame does not leave the view.
--  rerun_one       : `r` on failsAssertion: one launch, that test only (1 test in the run), the view still lists all 4.
--  rerun_failed    : `R`: one launch, exactly the 2 failed tests, the model still has 4 tests.
--  close_command   : `q` closes the view; :Nv4JTestResults opens it again.
--  fixture_restored: the fixture is unchanged afterwards.
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local F = require("fixture")
local P = "94_testresults_live."
local RUNNER = "org.eclipse.jdt.internal.junit.runner.RemoteTestRunner"

local fixture = vim.env.NV4J_FIXTURE
local snap = F.snapshot()
local TF = fixture .. "/src/test/java/demo/results/ResultsViewTest.java"
local SRC = {
  "package demo.results;", "",
  "import static org.junit.jupiter.api.Assertions.assertEquals;", "",
  "import org.junit.jupiter.api.Test;", "",
  "// Fixture of check 94_testresults_live (written by the check, removed afterwards).",
  "class ResultsViewTest {", "",
  "    @Test", "    void passes() throws Exception {", "        Thread.sleep(300);", "        assertEquals(4, 2 + 2);", "    }", "",
  "    @Test", "    void failsAssertion() {", '        assertEquals(7, 2 + 2, "results view: wrong sum");', "    }", "",
  "    @Test", "    void throwsOnPurpose() {", "        helper();", "    }", "",
  "    private void helper() {", '        throw new IllegalStateException("results view: boom");', "    }", "",
  "    @Test", "    void printsOut() throws Exception {", '        System.out.println("results view says hello");', "        Thread.sleep(250);", "    }",
  "}",
}
vim.fn.mkdir(vim.fs.dirname(TF), "p")
vim.fn.writefile(SRC, TF)

-- rows of the tree start with an arrow (3 bytes, so no character class): "  ▸ ✗ name"
local function is_row(l, indent) return l:find("^" .. indent .. "▸ ") ~= nil or l:find("^" .. indent .. "▾ ") ~= nil end
local function row_is(l, indent, rest) return l:find("^" .. indent .. "▸ " .. rest, 1) ~= nil or l:find("^" .. indent .. "▾ " .. rest, 1) ~= nil end

local function now_ms() vim.uv.update_time(); return vim.uv.hrtime() / 1e6 end
--- Manual deadline loop, a real 50 ms sleep per round.
local function waitfor(pred, ms)
  local dl = now_ms() + ms
  while now_ms() < dl do
    if pred() then return true end
    vim.wait(50)
  end
  return pred() and true or false
end
local function feed(keys) vim.api.nvim_feedkeys(vim.keycode(keys), "x", false) end
local function same_file(a, b) return vim.uv.fs_realpath(a) == vim.uv.fs_realpath(b) end

local jb = lsp.open(fixture .. "/src/test/java/demo/billing/PriceCalculatorTest.java")
local client = lsp.wait_ready(jb, 120000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready" or "jdtls not ready")
if not client then return lsp.finish() end
pcall(require, "config.keymaps")
local tests = require("nv4j.tests")
local tr = require("nv4j.testresults")
local ui = require("nv4j.testresultsui")
local dap = require("dap")
local notes = E.capture_notify()
local launches = {}
dap.listeners.on_config["n94"] = function(c)
  if c.mainClass == RUNNER then launches[#launches + 1] = c end
  return c
end
vim.wait(5000, function() return vim.fn.maparg("<leader>tr", "n", false, true).buffer == 1 end, 50)

local ok_all, err = pcall(function()
  local tb = lsp.open(TF)
  vim.api.nvim_set_current_buf(tb)
  vim.wait(3000)
  local l_assert = E.line_of(tb, "assertEquals%(7") + 1
  local l_throw = E.line_of(tb, "throw new IllegalState") + 1
  vim.api.nvim_win_set_cursor(0, { l_assert, 0 })

  -- run the class with the real key
  local prev = tests.last_result
  local n_launch = #launches
  feed("<leader>tt")
  waitfor(function() return tests.last_result ~= prev and tests._busy() == nil end, 150000)
  local r = tests.last_result
  local model = tr.get(client.config.root_dir)
  local by = {}
  for _, t in ipairs(model and model.tests or {}) do by[t.method or t.name] = t end
  local function pf(t)
    local f = t and tr.first_project_frame(t.lines)
    return f
  end
  local fa, ft = pf(by.failsAssertion), pf(by.throwsOnPurpose)
  local out_ok = by.printsOut and by.printsOut.output and table.concat(by.printsOut.output, "\n"):find("results view says hello", 1, true) ~= nil
  local out_clean = true
  for k, t in pairs(by) do
    if k ~= "printsOut" and #(t.output or {}) > 0 then out_clean = false end
  end
  local ok = model and #model.tests == 4 and by.passes and by.passes.state == "passed" and by.printsOut and by.printsOut.state == "passed"
    and by.failsAssertion and by.failsAssertion.state == "failed" and by.throwsOnPurpose and by.throwsOnPurpose.state == "failed"
    and (by.failsAssertion.message or ""):find("results view: wrong sum", 1, true) ~= nil
    and (by.throwsOnPurpose.message or ""):find("IllegalStateException: results view: boom", 1, true) ~= nil
    and by.failsAssertion.error ~= true and by.throwsOnPurpose.error == true
    and fa and fa.lnum == l_assert and same_file(fa.file, TF) and ft and ft.lnum == l_throw and same_file(ft.file, TF)
    and (by.passes.ms or 0) >= 250 and (by.printsOut.ms or 0) >= 200 and out_ok and out_clean and #launches == n_launch + 1
  lsp.report(P .. "run_model", ok, ("%d tests; passes %s %.0f ms; printsOut %s %.0f ms output %s; failsAssertion %s '%s' frame %s:%s (want %d); throws %s error=%s '%s' frame %s:%s (want %d); other tests' output clean %s; launches %d")
    :format(model and #model.tests or -1, by.passes and by.passes.state or "-", by.passes and by.passes.ms or -1, by.printsOut and by.printsOut.state or "-",
      by.printsOut and by.printsOut.ms or -1, out_ok and "has the text" or "MISSING", by.failsAssertion and by.failsAssertion.state or "-",
      by.failsAssertion and (by.failsAssertion.message or ""):sub(1, 60) or "-", fa and vim.fs.basename(fa.file) or "-", fa and fa.lnum or "-", l_assert,
      by.throwsOnPurpose and by.throwsOnPurpose.state or "-", by.throwsOnPurpose and tostring(by.throwsOnPurpose.error) or "-",
      by.throwsOnPurpose and (by.throwsOnPurpose.message or ""):sub(1, 60) or "-", ft and vim.fs.basename(ft.file) or "-", ft and ft.lnum or "-", l_throw,
      tostring(out_clean), #launches - n_launch))

  -- the existing marks and quickfix list stay
  local title = vim.fn.getqflist({ title = 0 }).title or ""
  local diag = vim.diagnostic.get(tb, { namespace = tests.ns })
  local diag_line = false
  for _, d in ipairs(diag) do if d.lnum + 1 == l_assert then diag_line = true end end
  local sign = false
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(tb, tests.ns, 0, -1, { details = true })) do
    if (m[4].sign_text or ""):find("✓") then sign = true end
  end
  lsp.report(P .. "quickfix_marks", title:find("^Nv4J tests: 2 passed, 2 failed, 0 skipped") ~= nil and diag_line and sign,
    ("qf '%s'; diagnostic on line %d: %s; ✓ sign %s"):format(title:sub(1, 70), l_assert, tostring(diag_line), tostring(sign)))
  local told = false
  for _, n in ipairs(notes) do if n.msg:find("<leader>tv", 1, true) and n.msg:find("2 failed", 1, true) then told = true end end
  lsp.report(P .. "notify_key", told, told and "the failing run's notification names <leader>tv" or "no notification with <leader>tv")

  -- open the view with the real key
  feed("<leader>tv")
  local vb = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(vb, 0, -1, false)
  local function row_of(pat)
    for i, l in ipairs(lines) do if l:find(pat, 1, true) then return i end end
  end
  local r_f1, r_f2 = row_of("failsAssertion"), row_of("throwsOnPurpose")
  local r_p1, r_p2 = row_of("passes"), row_of("printsOut")
  local r_class = row_of("demo.results.ResultsViewTest")
  local first_row
  for i, l in ipairs(lines) do if l:find("^  ▸") then first_row = i; break end end
  local view_ok = vim.bo[vb].filetype == "nv4jtests" and (lines[2] or ""):find("^2 passed, 2 failed, 0 skipped in ") ~= nil and r_f1 and r_f2 and r_p1 and r_p2
    and math.max(r_f1, r_f2) < math.min(r_p1, r_p2) and lines[r_f1]:find("✗", 1, true) and lines[r_p1]:find("✓", 1, true)
    and lines[r_p1]:find("%d+ ms") ~= nil and first_row == math.min(r_f1, r_f2)
    and r_class == 5 and lines[r_class]:find("^▾ ✗ demo.results.ResultsViewTest   %(2 passed, 2 failed%)") ~= nil
    and vim.api.nvim_win_get_cursor(0)[1] == first_row
  lsp.report(P .. "view_lines", view_ok, table.concat(vim.list_slice(lines, 1, 9), " / ") .. " | cursor row " .. vim.api.nvim_win_get_cursor(0)[1])

  -- tree: <CR> on the class row folds it (no test rows), again unfolds it
  vim.api.nvim_win_set_cursor(0, { r_class, 0 })
  feed("<CR>")
  local function test_rows() return #vim.tbl_filter(function(l) return is_row(l, "  ") end, vim.api.nvim_buf_get_lines(vb, 0, -1, false)) end
  local folded_rows = test_rows()
  local folded_class = vim.api.nvim_buf_get_lines(vb, r_class - 1, r_class, false)[1]
  feed("<CR>")
  local open_rows = test_rows()
  lsp.report(P .. "tree_fold", folded_rows == 0 and open_rows == 4 and folded_class:find("^▸ ✗ demo.results.ResultsViewTest") ~= nil,
    ("class row folded: %d test rows ('%s'); unfolded: %d"):format(folded_rows, folded_class, open_rows))

  -- <CR> on the throwing test: detail
  vim.api.nvim_win_set_cursor(0, { r_f2, 0 })
  feed("<CR>")
  lines = vim.api.nvim_buf_get_lines(vb, 0, -1, false)
  local text = table.concat(lines, "\n")
  local frame_row
  for i, l in ipairs(lines) do
    if l:find("demo.results.ResultsViewTest.helper", 1, true) and l:find("ResultsViewTest.java:" .. l_throw, 1, true) then frame_row = i end
  end
  local lib_row
  for i, l in ipairs(lines) do if l:find("at org.junit", 1, true) or l:find("at java.base", 1, true) then lib_row = i; break end end
  -- printsOut detail
  r_p2 = nil
  for i, l in ipairs(lines) do if row_is(l, "  ", "✓ printsOut") then r_p2 = i end end
  vim.api.nvim_win_set_cursor(0, { r_p2, 0 })
  feed("<CR>")
  lines = vim.api.nvim_buf_get_lines(vb, 0, -1, false)
  local text2 = table.concat(lines, "\n")
  -- highlight: the project frame uses the project group, a library frame the dim one
  local function hl_at(row)
    local ms = vim.api.nvim_buf_get_extmarks(vb, vim.api.nvim_create_namespace("nv4j_test_results"), { row - 1, 0 }, { row - 1, -1 }, { details = true })
    return ms[1] and ms[1][4].hl_group
  end
  frame_row = nil
  for i, l in ipairs(lines) do
    if l:find("demo.results.ResultsViewTest.helper", 1, true) and l:find("ResultsViewTest.java:" .. l_throw, 1, true) then frame_row = i end
  end
  for i, l in ipairs(lines) do if l:find("at org.junit", 1, true) or l:find("at java.base", 1, true) then lib_row = i; break end end
  lsp.report(P .. "expand_detail", text:find("Message:", 1, true) and text:find("java.lang.IllegalStateException: results view: boom", 1, true)
    and text:find("Trace:", 1, true) and frame_row and lib_row and text2:find("| results view says hello", 1, true) ~= nil
    and hl_at(frame_row) == "Nv4JTestProject" and hl_at(lib_row) == "Nv4JTestDim",
    ("message %s, trace %s, project frame row %s (%s), library frame row %s (%s), stdout line %s"):format(text:find("boom", 1, true) and "shown" or "MISSING",
      text:find("Trace:", 1, true) and "shown" or "MISSING", tostring(frame_row), tostring(frame_row and hl_at(frame_row)), tostring(lib_row),
      tostring(lib_row and hl_at(lib_row)), text2:find("| results view says hello", 1, true) and "shown" or "MISSING"))

  -- <CR> on a library frame stays in the view
  vim.api.nvim_win_set_cursor(0, { lib_row, 0 })
  feed("<CR>")
  local stayed = vim.api.nvim_get_current_buf() == vb

  -- <CR> on the project frame jumps
  vim.api.nvim_win_set_cursor(0, { frame_row, 0 })
  feed("<CR>")
  local cur = vim.api.nvim_buf_get_name(0)
  local cl = vim.api.nvim_win_get_cursor(0)[1]
  lsp.report(P .. "jump_frame", same_file(cur, TF) and cl == l_throw, ("current %s line %d (want %s line %d)"):format(vim.fs.basename(cur), cl,
    vim.fs.basename(TF), l_throw))
  lsp.report(P .. "library_frame", stayed, stayed and "stayed in the view" or "left the view")

  -- back to the view window
  local vwin
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do if vim.api.nvim_win_get_buf(w) == vb then vwin = w end end
  vim.api.nvim_set_current_win(vwin)

  -- r: rerun the test under the cursor (failsAssertion)
  lines = vim.api.nvim_buf_get_lines(vb, 0, -1, false)
  for i, l in ipairs(lines) do if row_is(l, "  ", "✗ failsAssertion") then r_f1 = i end end
  vim.api.nvim_win_set_cursor(0, { r_f1, 0 })
  prev = tests.last_result
  n_launch = #launches
  feed("r")
  waitfor(function() return tests.last_result ~= prev and tests._busy() == nil end, 150000)
  local r1 = tests.last_result
  local m1 = tr.get(client.config.root_dir)
  lines = vim.api.nvim_buf_get_lines(vb, 0, -1, false)
  local listed = 0
  for _, l in ipairs(lines) do if is_row(l, "  ") then listed = listed + 1 end end
  lsp.report(P .. "rerun_one", r1 ~= prev and #r1.tests == 1 and r1.tests[1].method == "failsAssertion" and r1.failed == 1 and #launches == n_launch + 1
    and #m1.tests == 4 and listed == 4,
    ("run tests %d (%s), launches %d, model %d tests, view rows %d"):format(r1 and #r1.tests or -1, r1 and r1.tests[1] and r1.tests[1].method or "-",
      #launches - n_launch, #m1.tests, listed))

  -- R: rerun the failed tests
  prev = tests.last_result
  n_launch = #launches
  feed("R")
  waitfor(function() return tests.last_result ~= prev and tests._busy() == nil end, 150000)
  local r2 = tests.last_result
  local m2 = tr.get(client.config.root_dir)
  local names = {}
  for _, t in ipairs(r2 and r2.tests or {}) do names[#names + 1] = t.method end
  table.sort(names)
  lsp.report(P .. "rerun_failed", r2 ~= prev and table.concat(names, ",") == "failsAssertion,throwsOnPurpose" and r2.failed == 2
    and #launches == n_launch + 1 and #m2.tests == 4, ("run tests %s, launches %d, model %d tests"):format(table.concat(names, ","),
    #launches - n_launch, #m2.tests))

  -- q closes, :Nv4JTestResults opens again
  feed("q")
  local closed = not vim.api.nvim_buf_is_valid(vb) or vim.fn.bufwinid(vb) == -1
  vim.api.nvim_set_current_buf(tb)
  vim.cmd("Nv4JTestResults")
  local reopened = vim.bo[vim.api.nvim_get_current_buf()].filetype == "nv4jtests"
  lsp.report(P .. "close_command", closed and reopened and vim.fn.exists(":Nv4JTestResults") == 2,
    ("q closed %s, :Nv4JTestResults reopened %s"):format(tostring(closed), tostring(reopened)))
  feed("q")

  -- live view: open while the class runs again. The tree is seeded from %TSTTREE (all four tests "not run" before any reports, over
  -- the older results), the started test is "running", redraws are throttled, the cursor goes to the first failure of the run once
  -- (the user had left it on the class row) and stays where the user put it in the next run.
  local function live_run(on_sample)
    vim.api.nvim_set_current_buf(tb)
    local origin_win = vim.api.nvim_get_current_win()
    local vb2 = vim.fn.bufnr("Nv4J test results")
    local vw
    if vb2 > 0 then vw = vim.fn.bufwinid(vb2) end
    if not vw or vw == -1 then
      feed("<leader>tv")
      vb2 = vim.api.nvim_get_current_buf()
      vw = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(origin_win)
    end
    local prev2 = tests.last_result
    local d0, t0 = ui._draws, now_ms()
    on_sample(vb2, vw, "before")
    feed("<leader>tt")
    local dl = now_ms() + 150000
    while now_ms() < dl and not (tests.last_result ~= prev2 and tests._busy() == nil) do
      on_sample(vb2, vw, "during")
      vim.wait(15)
    end
    vim.wait(300) -- the last redraw
    return vb2, vw, ui._draws - d0, now_ms() - t0
  end
  local seen = { notrun = false, running = false, seeded = false, summary = false }
  local function rows_text(vb2) return vim.api.nvim_buf_get_lines(vb2, 0, -1, false) end
  local vbA, vwA, drawsA, msA = live_run(function(vb2, vw, phase)
    if phase == "before" then vim.api.nvim_win_set_cursor(vw, { 5, 0 }); return end
    local lines2 = rows_text(vb2)
    local text2 = table.concat(lines2, "\n")
    local n_rows, n_pending = 0, 0
    for _, l in ipairs(lines2) do
      if is_row(l, "  ") then
        n_rows = n_rows + 1
        if l:find("not run", 1, true) or l:find("running", 1, true) then n_pending = n_pending + 1 end
      end
    end
    if text2:find("  ▸ · %w+   not run") then seen.notrun = true end
    if text2:find("  ▸ ▶ %w+   running") then seen.running = true end
    if n_rows == 4 and n_pending == 4 then seen.seeded = true end
    if (lines2[2] or ""):find("not run", 1, true) or (lines2[2] or ""):find(" running", 1, true) then seen.summary = true end
  end)
  local finalA = rows_text(vbA)
  local curA = vim.api.nvim_buf_get_lines(vbA, vim.api.nvim_win_get_cursor(vwA)[1] - 1, vim.api.nvim_win_get_cursor(vwA)[1], false)[1] or ""
  local pending_left = false
  for _, l in ipairs(finalA) do if l:find("not run", 1, true) or l:find("running", 1, true) then pending_left = true end end
  lsp.report(P .. "live_states", seen.notrun and seen.running and seen.seeded and seen.summary and not pending_left
    and (finalA[2] or ""):find("^2 passed, 2 failed, 0 skipped in ") ~= nil,
    ("seen: not run %s, running %s, all four seeded before a result %s, summary with pending counts %s; after the run pending rows left %s, summary '%s'")
    :format(tostring(seen.notrun), tostring(seen.running), tostring(seen.seeded), tostring(seen.summary), tostring(pending_left), finalA[2] or "-"))
  lsp.report(P .. "live_throttle", drawsA >= 3 and drawsA <= (msA / 100) + 3,
    ("%d redraws in %.0f ms of the run (at most about one per 100 ms)"):format(drawsA, msA))
  lsp.report(P .. "live_cursor_failure", row_is(curA, "  ", "✗ "),
    ("cursor left on the class row before the run; after it: '%s'"):format(curA))

  -- the next run: the user moves the cursor once the first live draw is there; no failure takes it afterwards
  local moved_to
  local vbB, vwB = live_run(function(vb2, vw, phase)
    if phase == "before" then return end
    if not moved_to and table.concat(rows_text(vb2), "\n"):find("not run", 1, true) then
      vim.api.nvim_win_set_cursor(vw, { 5, 0 })
      moved_to = 5
      vim.wait(30) -- let a redraw see the moved cursor
    end
  end)
  local curB = vim.api.nvim_buf_get_lines(vbB, vim.api.nvim_win_get_cursor(vwB)[1] - 1, vim.api.nvim_win_get_cursor(vwB)[1], false)[1] or ""
  lsp.report(P .. "live_cursor_kept", moved_to == 5 and row_is(curB, "", "✗ demo.results.ResultsViewTest"),
    ("user moved the cursor to the class row during the run (%s); after the run: '%s'"):format(tostring(moved_to), curB))
  vim.api.nvim_set_current_win(vwB)
  feed("q")

  -- rerun policy for a class-level failure (a @BeforeAll that throws: no test of the class ever starts): `R` reruns the class (not
  -- one test, there is no leaf), the model keeps exactly one class-level entry; once the class is fixed `r` on its row reruns it and
  -- the entry is gone.
  local SF = fixture .. "/src/test/java/demo/results/ResultsSetupTest.java"
  local SF_BAD = {
    "package demo.results;", "",
    "import org.junit.jupiter.api.BeforeAll;", "import org.junit.jupiter.api.Test;", "",
    "// Fixture of check 94_testresults_live (written by the check, removed afterwards).",
    "class ResultsSetupTest {", "",
    "    @BeforeAll", "    static void setUpAll() {", '        throw new IllegalStateException("results view: setup boom");', "    }", "",
    "    @Test", "    void neverRuns() {", "    }", "}",
  }
  vim.fn.writefile(SF_BAD, SF)
  local sb = lsp.open(SF)
  vim.api.nvim_set_current_buf(sb)
  vim.wait(3000)
  local prev3 = tests.last_result
  feed("<leader>tt")
  waitfor(function() return tests.last_result ~= prev3 and tests._busy() == nil end, 150000)
  local m3 = tr.get(client.config.root_dir)
  local function setup_entries(model)
    local n, e = 0, nil
    for _, x in ipairs(model and model.tests or {}) do
      if (x.class or ""):find("ResultsSetupTest", 1, true) and x.method == nil then n = n + 1; e = x end
    end
    return n, e
  end
  local n3, e3 = setup_entries(m3)
  lsp.report(P .. "class_level_failure", n3 == 1 and e3.state == "failed" and (e3.message or ""):find("setup boom", 1, true) ~= nil
    and #tr.rerun_set(m3) == 3,
    ("class-level entries %d (%s: %s); rerun set %d (the class + 2 failed tests of the other class)"):format(n3, e3 and e3.state or "-",
      e3 and (e3.message or ""):sub(1, 60) or "-", #tr.rerun_set(m3)))

  -- R from the view: the class-level failure is rerun as the class, the other failed class too; still one class-level entry
  vim.cmd("Nv4JTestResults")
  local vb3 = vim.api.nvim_get_current_buf()
  local prev4, n_launch4 = tests.last_result, #launches
  feed("R")
  waitfor(function() return tests.last_result ~= prev4 and tests._busy() == nil end, 150000)
  local m4 = tr.get(client.config.root_dir)
  local n4 = setup_entries(m4)
  local r4 = tests.last_result
  local ran_setup = false
  for _, x in ipairs(r4 and r4.tests or {}) do if (x.class or ""):find("ResultsSetupTest", 1, true) and x.method == nil then ran_setup = true end end
  lsp.report(P .. "class_level_rerun", ran_setup and n4 == 1 and r4.failed == 3 and #launches > n_launch4,
    ("rerun failed: the class ran again %s, failures %d (class + 2 tests), class-level entries still %d, launches %d"):format(tostring(ran_setup),
      r4 and r4.failed or -1, n4, #launches - n_launch4))

  -- the class is fixed: `r` on its row reruns the class; the class-level entry is replaced by the passing test
  vim.api.nvim_set_current_buf(sb)
  E.set(sb, vim.tbl_filter(function(l) return not l:find("throw new", 1, true) end, SF_BAD))
  vim.cmd("silent write")
  vim.wait(3000)
  vim.cmd("Nv4JTestResults")
  local lines3 = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local crow
  for i, l in ipairs(lines3) do if l:find("demo.results.ResultsSetupTest", 1, true) and is_row(l, "") then crow = i end end
  local prev5 = tests.last_result
  if crow then
    vim.api.nvim_win_set_cursor(0, { crow, 0 })
    feed("r")
    waitfor(function() return tests.last_result ~= prev5 and tests._busy() == nil end, 150000)
  end
  local m5 = tr.get(client.config.root_dir)
  local n5 = setup_entries(m5)
  local fixed
  for _, x in ipairs(m5 and m5.tests or {}) do if x.method == "neverRuns" then fixed = x end end
  lsp.report(P .. "class_level_fixed", crow ~= nil and n5 == 0 and fixed and fixed.state == "passed",
    ("class row %s; after fixing the class and `r` on its row: class-level entries %d, neverRuns %s"):format(tostring(crow), n5,
      fixed and fixed.state or "-"))
  feed("q")
  vim.cmd("silent! bwipeout! " .. sb)
end)
if not ok_all then lsp.report(P .. "check_error", false, tostring(err)) end

F.restore(snap, client)
local d = F.diff(snap)
lsp.report(P .. "fixture_restored", #d.added + #d.changed + #d.missing == 0, F.fmt(d))
return lsp.finish()
