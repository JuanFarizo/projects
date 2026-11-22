-- Test results model (nv4j/testresults.lua) and the runner stream parser's new data (nv4j/tests.lua _new_parser): pure, headless,
-- no jdt.ls (tests/lib/run1.sh 93_testresults_unit). The live twin is 94_testresults_live. Controls: tests/lib/control_93.sh.
--  frame_parse     : "at pkg.C.m(F.java:12)", module/loader prefixes, lambda names, native frames.
--  trace_classify  : message = lines before the first frame; frames resolving to a project file are project (file, line), the rest
--                    library (no file); Caused by / ... N more classified; first_project_frame.
--  order_failed_first: failed tests first, the others keep run order.
--  summary_text    : "2 passed, 1 failed, 1 skipped in 1.23 s", aborted only when present, <1 ms, seconds.
--  merge           : a rerun replaces the test with the same key and keeps the others; a class run drops that class's tests that
--                    are gone; a project run replaces all.
--  render_collapsed: header, summary, failed rows first, no detail lines.
--  render_expanded : message, frames (project ones carry file+lnum in meta, library ones none), output lines, run output.
--  parser_data     : a canned RemoteTestRunner stream: per-test time measured between start and end lines, stdout attached to the
--                    running test and orphan otherwise, runtime, aborted, error vs failure, trace lines.
--  store           : per project in memory; a second project does not touch the first.
local lsp = require("lsp")
local tr = require("nv4j.testresults")
local P = "93_testresults_unit."

local function rep(name, ok, detail) lsp.report(P .. name, ok and true or false, detail) end

-- frame_parse
do
  local c1, m1, f1, l1 = tr.parse_frame("\tat demo.billing.PriceCalculatorTest.failsOnPurpose(PriceCalculatorTest.java:22)")
  local c2, m2, f2, l2 = tr.parse_frame("\tat java.base/java.lang.reflect.Method.invoke(Method.java:580)")
  local c3, m3 = tr.parse_frame("\tat demo.X.lambda$run$0(X.java:9)")
  local c4, m4, f4, l4 = tr.parse_frame("\tat java.base/jdk.internal.misc.Unsafe.park(Native Method)")
  local c5 = tr.parse_frame("java.lang.IllegalStateException: boom")
  local c6, _, _, l6 = tr.parse_frame("\tat app//demo.Y.go(Y.java:3)")
  rep("frame_parse", c1 == "demo.billing.PriceCalculatorTest" and m1 == "failsOnPurpose" and f1 == "PriceCalculatorTest.java" and l1 == 22
    and c2 == "java.lang.reflect.Method" and m2 == "invoke" and l2 == 580 and c3 == "demo.X" and m3 == "lambda$run$0"
    and c4 == "jdk.internal.misc.Unsafe" and m4 == "park" and l4 == nil and c5 == nil and c6 == "demo.Y" and l6 == 3,
    ("%s.%s:%s | %s.%s:%s | %s.%s | native %s.%s line %s | non-frame %s | loader prefix %s:%s"):format(c1, m1, l1, c2, m2, l2, c3, m3, c4, m4,
      tostring(l4), tostring(c5), c6, tostring(l6)))
end

local TRACE = {
  "org.opentest4j.AssertionFailedError: expected: <7> but was: <6>",
  "\tat org.junit.jupiter.api.AssertionUtils.fail(AssertionUtils.java:55)",
  "\tat org.junit.jupiter.api.Assertions.assertEquals(Assertions.java:166)",
  "\tat demo.billing.PriceCalculatorFailingTest.failsOnPurpose(PriceCalculatorFailingTest.java:22)",
  "\tat java.base/java.lang.reflect.Method.invoke(Method.java:580)",
  "Caused by: java.lang.RuntimeException: inner",
  "\tat demo.billing.PriceCalculator.total(PriceCalculator.java:11)",
  "\t... 3 more",
}
local function resolve(cls)
  if cls:find("^demo%.") then return "/proj/src/" .. cls:gsub("%.", "/") .. ".java" end
end

-- trace_classify
do
  local p = tr.parse_trace(TRACE, resolve)
  local kinds = {}
  for _, l in ipairs(p.lines) do kinds[#kinds + 1] = l.kind .. (l.kind == "frame" and (l.project and ":P" or ":L") or "") end
  local first = tr.first_project_frame(p.lines)
  rep("trace_classify", p.message == "org.opentest4j.AssertionFailedError: expected: <7> but was: <6>"
    and table.concat(kinds, ",") == "msg,frame:L,frame:L,frame:P,frame:L,cause,frame:P,more"
    and first and first.lnum == 22 and first.file == "/proj/src/demo/billing/PriceCalculatorFailingTest.java"
    and p.lines[2].file == nil and p.lines[2].lnum == nil,
    ("message '%s'; kinds %s; first project frame %s:%s"):format(tostring(p.message), table.concat(kinds, ","), first and first.file or "-",
      first and first.lnum or "-"))
  local np = tr.parse_trace(TRACE, nil)
  rep("trace_no_resolver", tr.first_project_frame(np.lines) == nil, "no resolver: every frame is a library frame")
end

local function t(key, state, ms, extra)
  return vim.tbl_extend("force", { key = key, class = "demo.A", method = key, state = state, ms = ms, lines = {}, output = {} }, extra or {})
end

-- order_failed_first
do
  local o = tr.order({ t("a", "passed"), t("b", "failed"), t("c", "skipped"), t("d", "failed"), t("e", "passed") })
  local names = {}
  for _, x in ipairs(o) do names[#names + 1] = x.key end
  rep("order_failed_first", table.concat(names, "") == "bdace", table.concat(names, " "))
end

-- summary_text
do
  local m1 = { tests = { t("a", "passed", 5), t("b", "passed", 5), t("c", "failed", 5), t("d", "skipped") }, ms = 1234 }
  local m2 = { tests = { t("a", "passed", 0.2), t("b", "skipped", nil, { aborted = true }) } }
  local m3 = { tests = { t("a", "aborted"), t("b", "passed") }, ms = 80 }
  local s1, s2, s3 = tr.summary(m1), tr.summary(m2), tr.summary(m3)
  rep("summary_text", s1 == "2 passed, 1 failed, 1 skipped in 1.23 s" and s2 == "1 passed, 0 failed, 1 skipped in 0 s"
    and s3 == "1 passed, 0 failed, 0 skipped, 1 aborted in 80 ms" and tr.duration(0.2) == "<1 ms" and tr.duration(42) == "42 ms",
    s1 .. " | " .. s2 .. " | " .. s3)
end

-- merge
do
  local old = { tests = { t("a", "passed", 1), t("b", "failed", 2, { class = "demo.A" }), t("c", "passed", 3, { class = "demo.B" }) }, ms = 500 }
  local rerun = { tests = { t("b", "passed", 9, { class = "demo.A" }) } }
  local m = tr.merge(old, rerun, {})
  local s = {}
  for _, x in ipairs(m.tests) do s[#s + 1] = x.key .. "=" .. x.state end
  local cls = tr.merge(old, { tests = { t("a", "passed", 1) } }, { replace_classes = true })
  local cs = {}
  for _, x in ipairs(cls.tests) do cs[#cs + 1] = x.key end
  local all = tr.merge(old, rerun, { replace_all = true })
  local first = tr.merge(nil, rerun, {})
  rep("merge", table.concat(s, ",") == "a=passed,b=passed,c=passed" and m.tests[2].ms == 9 and m.ms == nil
    and table.concat(cs, ",") == "a,c" and #all.tests == 1 and #first.tests == 1,
    ("rerun %s; class run keeps %s; project run %d test(s)"):format(table.concat(s, ","), table.concat(cs, ","), #all.tests))
end

local MODEL = {
  label = "demo run", at = "10:00:00", ms = 250,
  tests = {
    t("ok", "passed", 3, { class = "demo.billing.PriceCalculatorTest", method = "ok" }),
    t("bad", "failed", 12, { class = "demo.billing.PriceCalculatorFailingTest", method = "bad", message = "boom: expected 7",
      lines = tr.parse_trace(TRACE, resolve).lines, output = { "hello from bad" } }),
    t("later", "skipped", nil, { class = "demo.billing.PriceCalculatorTest", method = "later" }),
  },
  output = { "stray jvm line" },
}

-- render_collapsed
do
  local lines, meta = tr.render(MODEL, {})
  local rows = vim.tbl_filter(function(m) return m.kind == "test" end, meta)
  local first_test
  for i, m in ipairs(meta) do if m.kind == "test" then first_test = i; break end end
  local detail = false
  for i, m in ipairs(meta) do if m.kind == "detail" or m.kind == "frame" then detail = true end end
  rep("render_collapsed", lines[2] == "1 passed, 1 failed, 1 skipped in 250 ms" and #rows == 3 and lines[first_test]:find("bad", 1, true)
    and lines[first_test - 1]:find("PriceCalculatorFailingTest", 1, true) and lines[first_test]:find("✗", 1, true)
    and lines[first_test]:find("12 ms", 1, true) and not detail
    and lines[first_test + 1]:find("PriceCalculatorTest", 1, true) and lines[first_test + 2]:find("ok", 1, true),
    table.concat(vim.list_slice(lines, 1, 8), " / "))
end

-- render_expanded
do
  local lines, meta = tr.render(MODEL, { bad = true })
  local text = table.concat(lines, "\n")
  local proj_frames, lib_frames = 0, 0
  local jump
  for i, m in ipairs(meta) do
    if m.kind == "frame" then
      if m.file then proj_frames = proj_frames + 1; jump = jump or m else lib_frames = lib_frames + 1 end
    end
  end
  rep("render_expanded", text:find("Message:", 1, true) and text:find("boom: expected 7", 1, true) and text:find("Trace:", 1, true)
    and proj_frames == 2 and lib_frames == 3 and jump.lnum == 22 and jump.file:find("PriceCalculatorFailingTest.java$")
    and text:find("| hello from bad", 1, true) and text:find("Run output (not tied to a test)", 1, true) and text:find("| stray jvm line", 1, true)
    and text:find("Caused by: java.lang.RuntimeException: inner", 1, true) and #lines > 12,
    ("%d lines; project frames %d (first %s:%s), library frames %d"):format(#lines, proj_frames, jump and jump.file or "-", jump and jump.lnum or "-", lib_frames))
end

-- parser_data
do
  local tests = require("nv4j.tests")
  local p = tests._new_parser()
  p.output("startup noise before any test")
  p.feed("%TESTC  3 v2\n%TSTTREE1,demo.X,true,3,false,-1,X,,\n%TSTTREE2,slow(demo.X),false,1,false,1,slow(),,\n")
  p.feed("%TSTTREE3,boom(demo.X),false,1,false,1,boom(),,\n%TSTTREE4,assume(demo.X),false,1,false,1,assume(),,\n")
  p.feed("%TESTS  2,slow(demo.X)\n")
  vim.uv.sleep(40)
  p.output("printed in slow")
  vim.uv.sleep(10)
  p.feed("%TESTE  2,slow(demo.X)\n")
  p.output("after the test")
  p.feed("%TESTS  3,boom(demo.X)\n")
  p.feed("%ERROR  3,boom(demo.X)\n%TRACES \njava.lang.IllegalStateException: boom\n\tat demo.X.boom(X.java:7)\n%TRACEE \n%TESTE  3,boom(demo.X)\n")
  p.feed("%TESTS  4,@AssumptionFailure: assume(demo.X)\n%TESTE  4,@AssumptionFailure: assume(demo.X)\n%RUNTIME123\n")
  local s, b, a = p.nodes["2"], p.nodes["3"], p.nodes["4"]
  rep("parser_data", s.state == "passed" and s.ms and s.ms >= 45 and s.ms < 1000 and s.output and #s.output == 1 and s.output[1] == "printed in slow"
    and #p.orphan == 2 and p.orphan[1] == "startup noise before any test" and p.orphan[2] == "after the test"
    and b.state == "failed" and b.is_error == true and b.trace[1] == "java.lang.IllegalStateException: boom"
    and a.state == "skipped" and a.aborted == true and p.runtime_ms == 123 and p.done,
    ("slow: %s %.0f ms output %s; orphans %d; boom: %s error=%s; assume: %s aborted=%s; runtime %s"):format(s.state, s.ms or -1,
      s.output and table.concat(s.output, "|") or "none", #p.orphan, b.state, tostring(b.is_error), a.state, tostring(a.aborted), tostring(p.runtime_ms)))
end

-- tree_classes
do
  local m = { tests = {
    t("a1", "passed", 1, { class = "demo.B", method = "a1" }), t("a2", "passed", 1, { class = "demo.B", method = "a2" }),
    t("b1", "passed", 1, { class = "demo.A", method = "b1" }), t("b2", "failed", 1, { class = "demo.A", method = "b2" }),
  } }
  local lines, meta = tr.render(m, {})
  local classes, tests_rows = {}, 0
  for i, mm in ipairs(meta) do
    if mm.kind == "class" then classes[#classes + 1] = i end
    if mm.kind == "test" then tests_rows = tests_rows + 1 end
  end
  local folded_lines, folded_meta = tr.render(m, {}, { ["c:demo.A"] = true })
  local ft = 0
  for _, mm in ipairs(folded_meta) do if mm.kind == "test" then ft = ft + 1 end end
  rep("tree_classes", #classes == 2 and tests_rows == 4 and lines[classes[1]]:find("^▾ ✗ demo.A   %(1 passed, 1 failed%)") ~= nil
    and lines[classes[2]]:find("^▾ ✓ demo.B   %(2 passed%)") ~= nil and lines[classes[1] + 1]:find("^  ▸ ✗ b2") ~= nil
    and lines[classes[1] + 2]:find("^  ▸ ✓ b1") ~= nil and meta[classes[1]].id == "c:demo.A"
    and ft == 2 and folded_lines[classes[1]]:find("^▸ ✗ demo.A") ~= nil,
    ("class rows %d; %s | %s; failing class first, its failed test first; folding demo.A leaves %d test rows"):format(#classes,
      lines[classes[1]] or "-", lines[classes[2]] or "-", ft))
end

-- tree_params: a parameterized method is a group row (counts) with its invocations under it, a plain method is not
do
  local C = "demo.P"
  local m = { tests = {
    t("one", "passed", 1, { class = C, method = "plain" }),
    t("p1", "passed", 1, { class = C, method = "param", invocation = true, display = "[1] a" }),
    t("p2", "failed", 1, { class = C, method = "param", invocation = true, display = "[2] b" }),
    t("p3", "passed", 1, { class = C, method = "param", invocation = true, display = "[3] c" }),
    t("q1", "passed", 1, { class = C, method = "single", invocation = true, display = "[1] only" }),
  } }
  local lines, meta = tr.render(m, {})
  local rows = {}
  for i, mm in ipairs(meta) do if mm.kind == "method" or mm.kind == "test" then rows[#rows + 1] = i end end
  local mrows = vim.tbl_filter(function(i) return meta[i].kind == "method" end, rows)
  local fl, fm = tr.render(m, {}, { ["m:demo.P#param"] = true })
  local ft = 0
  for _, mm in ipairs(fm) do if mm.kind == "test" then ft = ft + 1 end end
  local nm = #mrows
  mrows[1], mrows[2] = mrows[1] or 1, mrows[2] or 1 -- a missing group row fails the case below, it does not crash the check
  rep("tree_params", nm == 2 and lines[mrows[1]]:find("^  ▾ ✗ param   %(2 passed, 1 failed%)") ~= nil
    and lines[mrows[1] + 1]:find("^    ▸ ✗ %[2%] b") ~= nil and lines[mrows[1] + 2]:find("^    ▸ ✓ %[1%] a") ~= nil
    and lines[mrows[2]]:find("^  ▾ ✓ single") ~= nil and lines[mrows[2] + 1]:find("^    ▸ ✓ %[1%] only") ~= nil
    and meta[mrows[1]].method == "param" and #meta[mrows[1]].tests == 3 and ft == 2 and lines[mrows[1]]:find("^  ▸") ~= nil == false,
    ("method rows %d: %s | %s; folding param leaves %d test rows (the plain test and single's invocation)"):format(#mrows, lines[mrows[1]] or "-",
      lines[mrows[1] + 1] or "-", ft))
end

-- states_pending: running and not run are states of their own (marks, counts, summary), never counted as results
do
  local m = { tests = { t("a", "passed", 2), t("b", "running"), t("c", "notrun"), t("d", "notrun") } }
  local lines = tr.render(m, {})
  local c = tr.counts(m)
  rep("states_pending", c.running == 1 and c.notrun == 2 and c.passed == 1 and c.failed == 0
    and tr.summary(m) == "1 passed, 0 failed, 0 skipped, 1 running, 2 not run in 2 ms"
    and lines[5]:find("^▶ demo.A   %(1 passed, 1 running, 2 not run%)") == nil and lines[5]:find("^▾ ▶ demo.A   %(1 passed, 1 running, 2 not run%)") ~= nil
    and lines[7]:find("^  ▸ ▶ b   running") ~= nil and lines[8]:find("^  ▸ · c   not run") ~= nil
    and tr.summary({ tests = { t("a", "passed") }, ms = 5 }):find("running") == nil,
    lines[2] .. " | " .. (lines[5] or "-") .. " | " .. (lines[7] or "-") .. " | " .. (lines[8] or "-"))
end

-- seed_tsttree: the tree is known from %TSTTREE before any test reports; a started test is running; a run that ends with tests
-- that never finished shows them as not run; none of these are counted as results
do
  local tests = require("nv4j.tests")
  local p = tests._new_parser()
  p.feed("%TESTC  4 v2\n%TSTTREE1,demo.X,true,4,false,-1,X,,\n%TSTTREE2,one(demo.X),false,1,false,1,one(),,\n")
  p.feed("%TSTTREE3,two(demo.X),false,1,false,1,two(),,\n%TSTTREE4,par(demo.X),true,2,false,1,par(),,\n")
  p.feed("%TSTTREE5,par(int)[1](demo.X),false,1,true,4,[1] 1,,\n")
  local r0 = tests._collect({ p }, { files = {}, roots = {}, methods = {}, classes = {} }, true)
  local seeded_ok = #r0.tests == 0 and #r0.notrun == 3 and r0.passed == 0 and r0.notrun[1].state == "notrun" and r0.notrun[1].class == "demo.X"
    and r0.notrun[1].method == "one" and r0.notrun[3].invocation == true and r0.notrun[3].method == "par"
  p.feed("%TESTS  2,one(demo.X)\n")
  local r1 = tests._collect({ p }, { files = {}, roots = {}, methods = {}, classes = {} }, true)
  local running_ok = #r1.notrun == 3 and r1.notrun[1].state == "running" and r1.notrun[1].method == "one" and r1.notrun[2].state == "notrun"
  p.feed("%TESTE  2,one(demo.X)\n%TESTS  3,two(demo.X)\n")
  local r2 = tests._collect({ p }, { files = {}, roots = {}, methods = {}, classes = {} }, false) -- the run ended: two never finished
  local ended_ok = r2.passed == 1 and #r2.tests == 1 and #r2.notrun == 2 and r2.notrun[1].state == "notrun" and r2.notrun[2].state == "notrun"
  rep("seed_tsttree", seeded_ok and running_ok and ended_ok,
    ("seeded: %d results, %d not run (first %s); one started: %d pending, first %s; ended with two unfinished: passed %d, not run %d (%s)"):format(
      #r0.tests, #r0.notrun, r0.notrun[1] and r0.notrun[1].state or "-", #r1.notrun, r1.notrun[1] and r1.notrun[1].state or "-", r2.passed,
      #r2.notrun, r2.notrun[1] and r2.notrun[1].state or "-"))
end

-- ui helpers for the view cases: a live source whose model is a function of a counter
local ui = require("nv4j.testresultsui")
local function open_view(root)
  vim.cmd("only")
  tr.clear()
  ui._state.expanded, ui._state.folded, ui._state.last_draw, ui._state.root = {}, {}, nil, nil
  ui.min_ms = 100
  return root
end
local function close_view() if ui._state.win and vim.api.nvim_win_is_valid(ui._state.win) then ui.close() end end

-- throttle: 200 events in about a second redraw at most ~10 times, the model is built per redraw (not per event), nothing is built
-- while the view is closed, the last event is drawn
do
  open_view("/thr")
  local builds, n = 0, 0
  local function model() builds = builds + 1; return { label = "n=" .. n, tests = { t("a", "running"), t("b", "notrun") } } end
  tr.set_live_source("/thr", model)
  for _ = 1, 50 do n = n + 1; ui.request() end
  local closed_builds = builds
  ui.open()
  local d0, b0 = ui._draws, builds
  local t0 = vim.uv.now()
  for _ = 1, 200 do
    n = n + 1
    ui.request()
    vim.wait(5)
  end
  local ms = vim.uv.now() - t0
  vim.wait(250) -- the trailing redraw
  local drawn = ui._draws - d0
  local last = (vim.api.nvim_buf_get_lines(ui._state.buf, 0, 1, false)[1] or "")
  rep("throttle", closed_builds == 0 and drawn >= 4 and drawn <= (ms / 100) + 3 and builds - b0 == drawn and last:find("n=" .. n, 1, true) ~= nil,
    ("view closed: %d builds for 50 events; open: 200 events in %d ms = %d redraws, %d builds; last drawn: %s"):format(closed_builds, ms, drawn,
      builds - b0, last))
  close_view()
  tr.clear()
end

-- cursor_first_failure: the cursor goes to the first failed test once, only if the user has not moved it
do
  open_view("/cur")
  local state = { failed = false, second = false }
  local function model()
    local x = { t("a", "passed", 1, { class = "demo.C", method = "a" }), t("b", "running", nil, { class = "demo.C", method = "b" }),
      t("c", "notrun", nil, { class = "demo.C", method = "c" }) }
    if state.failed then x[2] = t("b", "failed", 3, { class = "demo.C", method = "b" }) end
    if state.second then x[#x + 1] = t("z", "failed", 3, { class = "demo.Z", method = "z" }) end
    return { label = "cur", tests = x }
  end
  tr.set_live_source("/cur", model)
  ui.open()
  local function cur_text() return vim.api.nvim_buf_get_lines(0, vim.api.nvim_win_get_cursor(0)[1] - 1, vim.api.nvim_win_get_cursor(0)[1], false)[1] end
  local at_open = cur_text()
  state.failed = true
  ui.flush()
  local at_fail = cur_text()
  state.second = true -- a second failing class sorts first: the cursor stays on the first failure it was placed on
  ui.flush()
  local at_second = cur_text()
  close_view()
  -- the user moved the cursor: a failure arriving later does not take it
  open_view("/cur2")
  state.failed, state.second = false, false
  tr.set_live_source("/cur2", model)
  ui.open()
  vim.api.nvim_win_set_cursor(0, { 8, 0 }) -- the "c" row, moved by the user
  state.failed = true
  ui.flush()
  local moved = cur_text()
  rep("cursor_first_failure", at_open:find("demo.C", 1, true) ~= nil and at_fail:find("✗ b", 1, true) ~= nil and at_second:find("✗ b", 1, true) ~= nil
    and moved:find("· c", 1, true) ~= nil,
    ("open (no failure): '%s'; failure arrives: '%s'; a second failure: '%s'; user moved to c, failure arrives: '%s'"):format(at_open, at_fail,
      at_second, moved))
  close_view()
  tr.clear()
end

-- rerun_class_level: a class-level failure (setup error, no leaf) is rerun as its class; R lists it once and not the failed methods
-- of that class; once the class ran again its stale class-level entry is gone
do
  local S, T = "demo.S", "demo.T"
  local function class_level(c) local x = t(c, "failed", nil, { class = c, name = c }); x.method = nil; return x end
  local old = { tests = { class_level(S), t("s#m", "failed", 1, { class = S, method = "m" }),
    t("t#x", "failed", 1, { class = T, method = "x" }), t("t#y", "passed", 1, { class = T, method = "y" }) } }
  local set = tr.rerun_set(old)
  local keys = {}
  for _, x in ipairs(set) do keys[#keys + 1] = x.key end
  table.sort(keys)
  local after = tr.merge(old, { tests = { t("s#a", "passed", 1, { class = S, method = "a" }) } }, {})
  local still = tr.merge(old, { tests = { class_level(S) } }, {})
  local ak = {}
  for _, x in ipairs(after.tests) do ak[#ak + 1] = x.key end
  local sk = 0
  for _, x in ipairs(still.tests) do if x.key == "demo.S" then sk = sk + 1 end end
  rep("rerun_class_level", table.concat(keys, ",") == "demo.S,t#x" and table.concat(ak, ",") == "s#m,t#x,t#y,s#a" and sk == 1 and #still.tests == 4,
    ("R reruns %s; after the class ran again: %s; class error again: %d entry"):format(table.concat(keys, ","), table.concat(ak, ","), sk))
end

-- store
do
  tr.clear()
  tr.store("/a", { label = "A", tests = { t("x", "passed"), t("z", "passed") } }, { replace_all = true })
  tr.store("/b", { label = "B", tests = { t("y", "failed") } }, { replace_all = true })
  tr.store("/a", { label = "A2", tests = { t("x", "failed") } }, {})
  rep("store", tr.get("/a").tests[1].state == "failed" and #tr.get("/a").tests == 2 and tr.get("/b").tests[1].state == "failed"
    and tr.last_root == "/a" and #tr.failed(tr.get("/b")) == 1, "two projects kept apart, /a merged in place")
  tr.clear()
end

return lsp.finish()
