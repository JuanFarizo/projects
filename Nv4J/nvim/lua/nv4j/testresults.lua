-- Test results model and tree text (pure: no jdt.ls, no UI; check 93_testresults_unit). The view that draws it is
-- nv4j/testresultsui.lua, the runner that feeds it is nv4j/tests.lua (specs/features/tests-runner.md "Results view").
--
-- Data source (one, real): the Eclipse RemoteTestRunner stream of the java-test launcher, which every run of Nv4J's runner
-- uses (JUnit 5/4, Maven and Gradle projects alike: the runner goes through jdt.ls, not through the build tool). It gives, per
-- test: class, method, display name, started/ended/failed/skipped, the failure message and the whole stack trace. Not in the
-- stream: a per-test time (measured here from the arrival of the start and end lines, so a few ms of jitter and fast tests
-- read ~0) and a per-test stdout (the JVM's stdout is another pipe: its lines are attached to the test that was running when
-- they arrived, see tests.lua; lines outside any test are kept as run output).
--
-- Test entry: { key, class, method, display, state = passed|failed|skipped|aborted, error = bool (exception, not an assertion),
--   ms = number|nil, message, lines = { { text, kind = msg|frame|cause|more, file?, lnum?, project? } }, output = { string } }.
-- Model: { root, label, scope, at, ms (runtime the launcher reported, else the sum), tests = { entry }, output = { string } }.
local M = {}

local STATES = { passed = true, failed = true, skipped = true, aborted = true }
M.max_output_lines = 400

--- "at pkg.Class.method(File.java:12)" -> class, method, file name, line. Module/loader prefixes ("java.base/", "app//") dropped.
--- Native / unknown-source frames ("(Native Method)") have a nil line.
function M.parse_frame(l)
  local qual, loc = l:match("^%s*at%s+(.-)%(([^()]*)%)%s*$")
  if not qual then return nil end
  qual = qual:gsub("^.*/", "")
  local cls, method = qual:match("^(.*)%.([^.]+)$")
  if not cls then return nil end
  local file, ln = loc:match("^([^:]*):(%d+)$")
  return cls, method, file or (loc ~= "" and loc or nil), tonumber(ln)
end

--- Trace lines -> { message, lines }. Message = the lines before the first frame (exception class and text). Each line is
--- classified: frame (project = its class resolves to a file through resolve(class) -> path|nil; library otherwise), cause
--- ("Caused by:" / "Suppressed:"), more ("... 5 more"), msg (anything else).
function M.parse_trace(trace, resolve)
  local lines, msg, seen_frame = {}, {}, false
  for _, l in ipairs(trace or {}) do
    local cls, method, file, ln = M.parse_frame(l)
    if cls then
      seen_frame = true
      local path = resolve and resolve(cls) or nil
      lines[#lines + 1] = { text = vim.trim(l), kind = "frame", class = cls, method = method, file = path, lnum = path and ln or nil,
        project = path ~= nil, source = file }
    else
      local t = vim.trim(l)
      local kind = "msg"
      if t:find("^Caused by:") or t:find("^Suppressed:") then kind = "cause"; seen_frame = true
      elseif t:find("^%.%.%. %d+ more") or t:find("^%.%.%. %d+ common frames") then kind = "more" end
      local head = not seen_frame and kind == "msg"
      if head then msg[#msg + 1] = l end
      lines[#lines + 1] = { text = t, kind = kind, head = head or nil }
    end
  end
  local message = vim.trim(table.concat(msg, "\n"))
  return { message = message ~= "" and message or nil, lines = lines }
end

--- First project frame (file and line) of a parsed trace, nil when none.
function M.first_project_frame(lines)
  for _, l in ipairs(lines or {}) do
    if l.kind == "frame" and l.project then return l end
  end
end

local function simple(class)
  return (class or ""):match("([^.$]+)$") or class or ""
end

--- Short label "SimpleClass.method" (display name appended when it differs from the method name).
function M.label(t)
  local base = t.method and (simple(t.class) .. "." .. t.method) or simple(t.class)
  if t.display and t.display ~= "" and t.display ~= t.method and t.display ~= (t.method or "") .. "()" then
    base = base .. "  [" .. t.display .. "]"
  end
  return base
end

--- Stable order: failed first (by run order), then every other test in run order.
function M.order(tests)
  local failed, rest = {}, {}
  for _, t in ipairs(tests) do
    if t.state == "failed" then failed[#failed + 1] = t else rest[#rest + 1] = t end
  end
  return vim.list_extend(failed, rest)
end

function M.counts(model)
  local c = { passed = 0, failed = 0, skipped = 0, aborted = 0, total = 0, ms = 0 }
  for _, t in ipairs(model.tests) do
    if STATES[t.state] then c[t.state] = c[t.state] + 1 end
    c.total = c.total + 1
    c.ms = c.ms + (t.ms or 0)
  end
  return c
end

local function dur(ms)
  if ms == nil then return "" end
  if ms < 1 then return "<1 ms" end
  if ms < 1000 then return ("%d ms"):format(ms + 0.5) end
  return ("%.2f s"):format(ms / 1000)
end
M.duration = dur

--- "2 passed, 1 failed, 1 skipped in 1.23 s" (aborted only when there are some).
function M.summary(model)
  local c = M.counts(model)
  local s = ("%d passed, %d failed, %d skipped"):format(c.passed, c.failed, c.skipped)
  if c.aborted > 0 then s = s .. (", %d aborted"):format(c.aborted) end
  local ms = model.ms or c.ms
  return s .. " in " .. dur(ms):gsub("^<1 ms$", "0 s")
end

--- Merge a partial run (one test, the failed ones, a class) into the stored model of the project: tests of the new run replace
--- the same key; with opts.replace_classes (a class/file run) the old tests of those classes that the new run did not report
--- are dropped; with opts.replace_all the new run is the model.
function M.merge(old, new, opts)
  opts = opts or {}
  if not old or opts.replace_all then return new end
  local fresh, classes = {}, {}
  for _, t in ipairs(new.tests) do
    fresh[t.key] = t
    classes[(t.class or ""):gsub("%$.*$", "")] = true
  end
  local out, placed = {}, {}
  for _, t in ipairs(old.tests) do
    local f = fresh[t.key]
    if f then
      out[#out + 1] = f
      placed[t.key] = true
    elseif not (opts.replace_classes and classes[(t.class or ""):gsub("%$.*$", "")]) then
      out[#out + 1] = t
    end
  end
  for _, t in ipairs(new.tests) do
    if not placed[t.key] then out[#out + 1] = t end
  end
  local m = vim.tbl_extend("force", {}, new)
  m.tests = out
  m.ms = nil -- the sum of the tests (the old run's runtime no longer describes the merged set)
  m.output = new.output
  return m
end

-- ── tree text ───────────────────────────────────────────────────────────────────────────────────

local MARK = { passed = "✓", failed = "✗", skipped = "○", aborted = "◌" }
M.mark = MARK

--- Text of the view. expanded = { [key] = true }. Returns lines, meta, spans:
---   meta[i]  = { kind = "header"|"summary"|"test"|"detail"|"frame"|"output"|"blank", test = entry?, file?, lnum? }
---   spans    = { { line (1-based), col_start, col_end (0-based, -1 = end), group } }
function M.render(model, expanded)
  expanded = expanded or {}
  local lines, meta, spans = {}, {}, {}
  local function add(text, m, group)
    lines[#lines + 1] = text
    meta[#lines] = m or { kind = "detail" }
    if group then spans[#spans + 1] = { #lines, 0, -1, group } end
    return #lines
  end
  local c = M.counts(model)
  local head = "Nv4J tests"
  if model.label and model.label ~= "" then head = head .. "  " .. model.label end
  if model.at then head = head .. "  " .. model.at end
  add(head, { kind = "header" }, "Title")
  local sum = M.summary(model)
  add(sum, { kind = "summary" }, c.failed > 0 and "Nv4JTestFailed" or "Nv4JTestPassed")
  add("<CR> details / jump to frame   r rerun test   R rerun failed   q close", { kind = "header" }, "Nv4JTestDim")
  add("", { kind = "blank" })
  if #model.tests == 0 then add("No tests in the last run.", { kind = "blank" }, "Nv4JTestDim") end
  for _, t in ipairs(M.order(model.tests)) do
    local open = expanded[t.key]
    local row = ("%s %s %s"):format(open and "▾" or "▸", MARK[t.state] or "?", M.label(t))
    if t.ms and t.state ~= "skipped" and t.state ~= "aborted" then row = row .. "   " .. dur(t.ms) end
    if t.state == "skipped" then row = row .. "   skipped" elseif t.state == "aborted" then row = row .. "   aborted (assumption)" end
    local ln = add(row, { kind = "test", test = t })
    local g = t.state == "failed" and "Nv4JTestFailed" or (t.state == "passed" and "Nv4JTestPassed" or "Nv4JTestSkipped")
    spans[#spans + 1] = { ln, 0, #"▸ " + #MARK[t.state] + 1, g }
    if open then
      local function sub(text, m, group) return add("      " .. text, m or { kind = "detail", test = t }, group) end
      if t.message then
        sub("Message:", nil, "Nv4JTestDim")
        for _, ml in ipairs(vim.split(t.message, "\n", { plain = true })) do sub("  " .. ml, nil, "Nv4JTestFailed") end
      end
      if t.lines and #t.lines > 0 then
        sub("Trace:", nil, "Nv4JTestDim")
        for _, l in ipairs(t.lines) do
          if l.head then
            -- the message lines are shown under "Message:"
          elseif l.kind == "frame" then
            sub("  " .. l.text, { kind = "frame", test = t, file = l.file, lnum = l.lnum }, l.project and "Nv4JTestProject" or "Nv4JTestDim")
          elseif l.kind == "cause" then
            sub("  " .. l.text, nil, "Nv4JTestFailed")
          else
            sub("  " .. l.text, nil, "Nv4JTestDim")
          end
        end
      end
      if t.output and #t.output > 0 then
        sub("Output:", nil, "Nv4JTestDim")
        for _, o in ipairs(t.output) do sub("  | " .. o, { kind = "output", test = t }) end
      end
      if not t.message and (not t.lines or #t.lines == 0) and (not t.output or #t.output == 0) then
        sub("(no message, no output)", nil, "Nv4JTestDim")
      end
    end
  end
  if model.output and #model.output > 0 then
    add("", { kind = "blank" })
    add("Run output (not tied to a test)", { kind = "header" }, "Nv4JTestDim")
    for _, o in ipairs(model.output) do add("  | " .. o, { kind = "output" }) end
  end
  return lines, meta, spans
end

-- ── store (per project, in memory only) ───────────────────────────────────────────────────────────

local store = {}
M.last_root = nil

--- Store (and merge) a finished run's model for a project root. opts as M.merge. Returns the stored model.
function M.store(root, model, opts)
  root = root or ""
  model.root = root
  local merged = M.merge(store[root], model, opts)
  merged.root = root
  store[root] = merged
  M.last_root = root
  return merged
end

function M.get(root) return store[root or M.last_root or ""] end
function M.clear() store = {}; M.last_root = nil end

--- The failed tests of a model (for "rerun failed").
function M.failed(model)
  return vim.tbl_filter(function(t) return t.state == "failed" end, model and model.tests or {})
end

return M
