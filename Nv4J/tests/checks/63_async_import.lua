-- P3 async import on completion accept (P1 follow-up). Run via tests/run.sh.
-- Spec: specs/features/async-import.md (decision D24 in specs/001-architecture.md).
-- Budget (P3 plan, not weakened): accepting a completion returns control with the item text inserted
-- <= 100 ms; its import is in the buffer <= 1.5 s after the accept, never lost.
--  accept_first   : the first accept of the session (1 s after ServiceReady, like 31_imports): `List`
--                   from java.util (typed `Lis`). The typed prefix becomes `List` in the buffer <= 100 ms after the
--                   accept (polled every 1 ms: what the user sees; blink's accept callback time is
--                   logged as info, it also waits for jdt.ls's java.completion.onDidSelect command);
--                   `import java.util.List;` present <= 1.5 s after the accept.
--  accept_second  : right after accept_first returns (no pause), `HashMap`: same budgets, and the
--                   first import is still there (never lost).
--  stub_slow      : deterministic twin (003 P2 lesson): every completionItem/resolve answer of the
--                   jdtls client is held back STUB_DELAY_MS (800 ms) before blink sees it, so the case
--                   fails on every run while the accept waits for resolve, however fast jdt.ls is
--                   that day. `ArrayList`: control <= 100 ms, import present <= 1.5 s, exactly once.
--  Review Focus 1 (P3 Task 1), deterministic: every completionItem/resolve answer is held by a gate
--  until the case releases it, so the action always happens between the accept and the late
--  resolve (no timing). `ArrayList` accepted in App.java, then:
--   rf_edit_below    a line typed below the accepted one   -> import applied once, text intact
--   rf_cursor_moved  cursor moved to another line           -> import applied, cursor stays on its text
--   rf_import_typed  the user typed the same import         -> not applied again (count 1)
--   rf_region_changed another import added below `package`  -> import placed in sorted order (jdt.ls's
--                                                              ranges are stale: applied as sent they
--                                                              would delete the new import)
--   rf_removing_edit the late edit would replace an existing import line (rewritten in the gate,
--                    twin of trial t1-l)                    -> import placed, nothing removed
--   rf_stale_insert  a stale pure insertion from jdt.ls (B1)  -> import added by Nv4J, sorted, no split line
--   place_*          importOrder groups, sort, statics, no package + license, comment text, module import
--   rf_resolve_error the resolve answers with an error         -> outcome `none` logged, extmark cleared
--   rf_no_answer     no answer within ASYNC_WAIT_MS (500 here) -> `dropped` logged, extmark cleared
--   rf_in_time_lossy resolved before the accept with jdt.ls's lossy edit (replaces `import java.util.List;`)
--                                                           -> blink does not apply it; import added, List kept
--   rf_undo          `u` undoes the accept                  -> import dropped, buffer as before the accept
--   rf_undo_one      an undo boundary (<Esc>), no text change -> import applied; one `u` removes item and import
--   rf_second        a second accept (`HashMap`) before the first resolve answered -> both imports once
--   rf_closed        buffer wiped                           -> dropped, no error (runs last)
--  Frecency vs project ranking (P1 follow-up): blink's frecency database is pointed at a scratch file
--  (/tmp/nv4j/frecency-63/, not the harness' XDG_STATE_HOME) and polluted by accepting `List` 20
--  times through blink's real accept (frecency write not stubbed), then:
--   frecency_polluted  20 accepts done, the scratch database written
--   frecency_at        `@` in CustomerController: RestController in the top 5, and the `List` items
--                      carry a frecency bonus in blink's score (the pollution is live there)
--   frecency_http      `http.` in SecurityConfig: authorizeHttpRequests in the top 3
-- Baseline (P3 Task 0): blink waits for resolve up to resolve_timeout_ms (1500, plugins/blink.lua),
-- so the item text lands only after resolve: about 0.4-0.8 s for `List`/`HashMap`, about 800 ms in stub_slow.
-- Timings: /tmp/nv4j/logs/latency.jsonl (async_import_*).
vim.o.confirm = false
local lsp = require("lsp")
local C = require("completion")
local E = require("edit")
local P = "63_async_import."
local RETURN_BUDGET_MS, IMPORT_BUDGET_MS, STUB_DELAY_MS = 100, 1500, 800
local src = vim.env.NV4J_FIXTURE .. "/src/main/java/demo/"
local NV = require("nv4j.completion")

-- Same accept path as 31_imports: blink's own accept (resolve, then the edits), with only the
-- dot-repeat hack and the frecency write stubbed (headless normal mode / user state).
local real_access -- blink's frecency write, kept for the frecency cases
local function accept(buf, lnum, col, pick, word, keep_access, preresolve)
  local fuzzy = C.blink()
  if not fuzzy then return nil, "blink not loaded" end
  require("blink.cmp.lib.text_edits").write_to_dot_repeat = function() end
  real_access = real_access or fuzzy.access
  fuzzy.access = keep_access and real_access or function() end
  local m, why = C.menu(buf, lnum, col)
  if not m then return nil, why end
  local item
  for _, it in ipairs(m.items) do
    if pick(it) then item = it break end
  end
  if not item then return nil, "item not in menu: " .. C.labels(m.items, 8) end
  local ctx = require("blink.cmp.completion.trigger.context").new({
    id = math.random(1, 1e9), providers = { "lsp" }, initial_trigger_kind = "keyword", trigger_kind = "keyword",
  })
  vim.api.nvim_win_set_cursor(0, { lnum + 1, col })
  if preresolve then
    -- resolved before the accept (what blink's doc popup does): blink's accept then uses it at once
    local task = require("blink.cmp.sources.lib").resolve(ctx, item)
    vim.wait(10000, function() return task.status ~= 1 end, 5)
  end
  local done, cb_ms, ins_ms = false, nil, nil
  local typed = vim.api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1]
  -- the import lands above the typed line in the same apply: follow the line with an extmark
  local ns = vim.api.nvim_create_namespace("nv4j_63")
  local mark = vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, {})
  local t0 = E.now()
  require("blink.cmp.completion.accept")(ctx, item, function()
    cb_ms = E.now() - t0
    done = true
  end)
  -- polled every 1 ms: the moment the typed prefix became the item text is what the user sees
  vim.wait(10000, function()
    if not ins_ms then
      local row = vim.api.nvim_buf_get_extmark_by_id(buf, ns, mark, {})[1] or lnum
      local l = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
      if l ~= typed and l:find(word, 1, true) then ins_ms = E.now() - t0 end
    end
    return done and ins_ms ~= nil
  end, 1)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  return { ms = ins_ms, cb_ms = cb_ms, done = done, t0 = t0 }
end

local function from(pkg)
  return function(it)
    local where = ((it.labelDetails and it.labelDetails.description) or "") .. " " .. (it.detail or "")
    return where:find(pkg, 1, true) ~= nil
  end
end
local function label(name, pkg) return function(it) return it.label == name and from(pkg)(it) end end

--- Wait until `import <fq>;` is in the buffer; returns ms since t0 (or nil after the budget + 1 s).
local function wait_import(buf, fq, t0)
  local pat = "\nimport " .. fq .. ";\n"
  local ok = vim.wait(IMPORT_BUDGET_MS + 1000, function() return ("\n" .. E.text(buf) .. "\n"):find(pat, 1, true) ~= nil end, 2)
  return ok and (E.now() - t0) or nil
end

local function count(buf, s)
  local n, i = 0, 1
  local txt = E.text(buf)
  while true do
    local a, b = txt:find(s, i, true)
    if not a then return n end
    n, i = n + 1, b + 1
  end
end

local function fmt_edits(edits)
  local ed = {}
  for _, e in ipairs(edits or {}) do
    ed[#ed + 1] = ("%d:%d-%d:%d %q"):format(e.range.start.line, e.range.start.character, e.range["end"].line,
      e.range["end"].character, e.newText)
  end
  return table.concat(ed, ", ")
end
local function fmt_outcomes(list)
  return table.concat(vim.tbl_map(function(o)
    return o.status .. " (" .. tostring(o.why) .. ")" .. (o.placed and (" added " .. table.concat(o.placed, ", ")) or "")
      .. (o.edits and (" [jdt.ls: " .. fmt_edits(o.edits) .. "]") or "")
  end, list), ", ")
end

--- One case: accept, then report control-return time and import time against the budgets.
local function case(name, buf, lnum, col, pick, word, fq, extra)
  local since = NV.async_count
  local r, why = accept(buf, lnum, col, pick, word)
  if not r then return lsp.report(P .. name, false, why) end
  local imp_ms = wait_import(buf, fq, r.t0)
  E.log("async_import_" .. name .. "_return", r.ms or -1, 1)
  E.log("async_import_" .. name .. "_callback", r.cb_ms or -1, 1)
  E.log("async_import_" .. name .. "_import", imp_ms or -1, 1)
  local ok_extra, why_extra = true, ""
  if extra then ok_extra, why_extra = extra() end
  -- what nv4j.completion did with the late resolve (diagnosis on failure)
  local outs = {}
  for i = math.max(1, #NV.async_log - (NV.async_count - since) + 1), #NV.async_log do
    outs[#outs + 1] = fmt_outcomes({ NV.async_log[i] })
  end
  why_extra = why_extra .. (why_extra ~= "" and "; " or "") .. "late import: " .. (#outs > 0 and table.concat(outs, ", ") or "no outcome")
  lsp.report(P .. name, r.done and r.ms ~= nil and r.ms <= RETURN_BUDGET_MS and imp_ms ~= nil and imp_ms <= IMPORT_BUDGET_MS and ok_extra,
    ("%s inserted after %s ms (budget %d); import %s (budget %d ms); blink accept callback %s ms%s"):format(word,
      r.ms and ("%.0f"):format(r.ms) or "NEVER", RETURN_BUDGET_MS, imp_ms and ("after %.0f ms"):format(imp_ms) or "MISSING",
      IMPORT_BUDGET_MS, r.cb_ms and ("%.0f"):format(r.cb_ms) or "never", why_extra ~= "" and ("; " .. why_extra) or ""))
  return r
end

-- Review Focus 1 ------------------------------------------------------------------------------

--- Hold every completionItem/resolve answer of `client` until release() (deterministic late resolve).
local gate_pass -- answers are transformed but not held (rf_in_time_lossy)
local hold_forever -- rf_no_answer: the held answer is released only after the case
local gate_transform -- optional fn(result) applied to each held resolve answer (rf_removing_edit)
local function gate(client)
  local real = client.request
  local held, answered = {}, 0
  client.request = function(self, method, params, handler, bufnr)
    if method == "completionItem/resolve" and type(handler) == "function" then
      return real(self, method, params, function(...)
        local n, a = select("#", ...), { ... }
        answered = answered + 1
        if gate_pass then
          if gate_transform and a[2] then gate_transform(a[2]) end
          return handler(unpack(a, 1, n))
        end
        if gate_transform and a[2] then
          if gate_transform(a[2]) == "error" then a, n = { { code = -32603, message = "stubbed resolve error" }, nil, a[3] }, 3 end
        end
        held[#held + 1] = function() handler(unpack(a, 1, n)) end
      end, bufnr)
    end
    return real(self, method, params, handler, bufnr)
  end
  local g = {}
  function g.wait(n) return vim.wait(10000, function() return answered >= n end, 5) end
  function g.release()
    local h = held
    held = {}
    for _, f in ipairs(h) do f() end
  end
  function g.restore() g.release() client.request = real end
  return g
end

--- Wait until nv4j.completion logged `n` more late-import outcomes than `since`; returns the new entries.
local function outcomes(since, n)
  vim.wait(3000, function() return NV.async_count >= since + n end, 5)
  local got = {}
  local k = NV.async_count - since
  for i = math.max(1, #NV.async_log - k + 1), #NV.async_log do got[#got + 1] = NV.async_log[i] end
  return got
end

local function nonblank(buf)
  local out = {}
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:find("%S") then out[#out + 1] = l end
  end
  return out
end
--- The buffer's non-blank lines are exactly `want` (no corruption, nothing lost, nothing doubled).
local function same(buf, want)
  local got = nonblank(buf)
  return vim.deep_equal(got, want), ("non-blank lines %s"):format(vim.deep_equal(got, want) and "as expected"
    or ("DIFFER: got [" .. table.concat(got, " | ") .. "] want [" .. table.concat(want, " | ") .. "]"))
end

--- The buffer is exactly `want`, blank lines included (import groups).
local function exact(buf, want)
  local got = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ok = vim.deep_equal(got, want)
  return ok, ok and "lines exactly as expected" or ("lines DIFFER: got [" .. table.concat(got, " | ") .. "] want [" .. table.concat(want, " | ") .. "]")
end

local BASE = { "package demo;", "", "public class App {", "    public static void main(String[] args) {",
  "        ArrayLis", "    }", "}" }
local AL = "import java.util.ArrayList;"
local function body(...)
  local out = { "public class App {", "    public static void main(String[] args) {" }
  for _, l in ipairs({ ... }) do out[#out + 1] = l end
  out[#out + 1] = "    }"
  out[#out + 1] = "}"
  return out
end
local function cat(a, b) local o = vim.list_slice(a) vim.list_extend(o, b) return o end

--- One Review Focus case: accept `ArrayList` with the resolve held, run action(buf) before the
--- late resolve, release it, then verify(buf, outcomes, ctx) -> ok, detail.
local function rf(name, buf, client, action, verify, lines, n_outcomes, row)
  -- jdt.ls must have reconciled this text before the completion: right after a case that ended with
  -- the import in place, its resolve sometimes still saw the import and sent no additionalTextEdits
  -- (trial t1-h). Diagnostics are cleared first so only a publish for this text can satisfy the wait.
  vim.diagnostic.reset(nil, buf)
  E.set(buf, lines or BASE)
  local settled = E.wait_diags(buf, function(d) return E.has(d, nil, "ArrayLis cannot be resolved") ~= nil end, 10000)
  -- An undo boundary before the accept, as a user's own typing makes one (blink skips its undo point
  -- for jdt.ls items: they are snippet-format). Headless API edits are otherwise one undo block.
  vim.o.undolevels = vim.o.undolevels
  local g = gate(client)
  local ok, err = pcall(function()
    local since = NV.async_count
    local r, why = accept(buf, row or 4, 16, label("ArrayList", "java.util"), "ArrayList")
    if not r then return lsp.report(P .. name, false, why) end
    local held = g.wait(1)
    -- new `import java.util.ArrayList;` lines since the case's text was set (place_comment_not_import
    -- has that text inside a comment from the start)
    local early = 0
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if l == AL then early = early + 1 end
    end
    for _, l in ipairs(lines or BASE) do
      if l == AL then early = early - 1 end
    end
    local ctx = { r = r, since = since }
    if action then action(buf, ctx) end
    if not hold_forever then g.release() end
    local outs = outcomes(since, n_outcomes or 1)
    vim.wait(300) -- a second (duplicate) apply would land by now
    local okv, detail = verify(buf, outs, ctx)
    lsp.report(P .. name, settled and held and early == 0 and r.ms ~= nil and r.ms <= RETURN_BUDGET_MS and okv,
      ("jdt.ls settled=%s; resolve held=%s; inserted after %s ms; import before release=%d; outcome: %s; %s"):format(tostring(settled), tostring(held),
        r.ms and ("%.0f"):format(r.ms) or "NEVER", early, fmt_outcomes(outs), detail))
  end)
  g.restore()
  if not ok then lsp.report(P .. name, false, "error: " .. tostring(err)) end
end

local function nonblank_of(lines)
  return vim.tbl_filter(function(l) return l:find("%S") ~= nil end, lines)
end

local function status_is(outs, st) return #outs > 0 and outs[#outs].status == st end

local function rf_cases(buf, client)
  vim.api.nvim_set_current_buf(buf)
  rf("rf_edit_below", buf, client, function(b)
    local l = E.line_of(b, "^        ArrayList$")
    vim.api.nvim_buf_set_lines(b, l + 1, l + 1, false, { "        int x = 1;" })
  end, function(b, outs)
    local ok, d = same(b, cat({ "package demo;", AL }, body("        ArrayList", "        int x = 1;")))
    return ok and status_is(outs, "applied") and count(b, AL) == 1, d .. ("; import count %d"):format(count(b, AL))
  end)

  rf("rf_cursor_moved", buf, client, function(b, ctx)
    local l = E.line_of(b, "^    public static void main")
    vim.api.nvim_win_set_cursor(0, { l + 1, 18 })
    ctx.text = vim.api.nvim_get_current_line()
  end, function(b, outs, ctx)
    local ok, d = same(b, cat({ "package demo;", AL }, body("        ArrayList")))
    local cur = vim.api.nvim_win_get_cursor(0)
    local on = vim.api.nvim_get_current_line()
    return ok and status_is(outs, "applied") and on == ctx.text and cur[2] == 18,
      d .. ("; cursor on %q col %d (want %q col 18)"):format(on, cur[2], ctx.text)
  end)

  rf("rf_import_typed", buf, client, function(b)
    vim.api.nvim_buf_set_lines(b, 1, 1, false, { "", AL })
  end, function(b, outs)
    local ok, d = same(b, cat({ "package demo;", AL }, body("        ArrayList")))
    return ok and status_is(outs, "present") and count(b, AL) == 1, d .. ("; import count %d (want 1)"):format(count(b, AL))
  end)

  -- The new import sits right below `package`, inside the range jdt.ls's edit replaces in the text it
  -- saw ((0,13)-(2,0)): applied as sent it would delete `import java.util.Map;`.
  rf("rf_region_changed", buf, client, function(b)
    vim.api.nvim_buf_set_lines(b, 1, 1, false, { "import java.util.Map;" })
  end, function(b, outs)
    local ok, d = same(b, cat({ "package demo;", AL, "import java.util.Map;" }, body("        ArrayList")))
    return ok and status_is(outs, "applied") and count(b, AL) == 1, d .. ("; import count %d (want 1)"):format(count(b, AL))
  end)

  -- Deterministic twin of trial t1-l (jdt.ls once sent, for `HashMap`, an edit replacing the existing
  -- `import java.util.List;` line): the held answer's edit is rewritten to replace the existing import.
  local LB = { "package demo;", "", "import java.util.List;", "", "public class App {",
    "    public static void main(String[] args) {", "        ArrayLis", "    }", "}" }
  gate_transform = function(res)
    res.additionalTextEdits = { { range = { start = { line = 2, character = 0 }, ["end"] = { line = 3, character = 0 } },
      newText = "import java.util.ArrayList;\n" } }
  end
  local ok_rm, err_rm = pcall(rf, "rf_removing_edit", buf, client, nil, function(b, outs)
    local ok, d = same(b, cat({ "package demo;", AL, "import java.util.List;" }, body("        ArrayList")))
    return ok and status_is(outs, "applied"), d
  end, LB, nil, 6)

  -- B1 (review): a stale pure insertion. jdt.ls inserts after `import java.util.List;` at (2,22) in
  -- the text it saw; the user meanwhile put a longer import on line 2. Applied as sent, the insertion
  -- would split `import java.util.concurrent.Future;`. The import must be added by Nv4J, sorted.
  gate_transform = function(res)
    res.additionalTextEdits = { { range = { start = { line = 2, character = 22 }, ["end"] = { line = 2, character = 22 } },
      newText = "\nimport java.util.ArrayList;" } }
  end
  local ok_st, err_st = pcall(rf, "rf_stale_insert", buf, client, function(b)
    vim.api.nvim_buf_set_lines(b, 2, 2, false, { "import java.util.concurrent.Future;" })
  end, function(b, outs)
    local ok, d = exact(b, cat({ "package demo;", "", AL, "import java.util.concurrent.Future;", "import java.util.List;", "" },
      body("        ArrayList")))
    return ok and status_is(outs, "applied"), d
  end, LB, nil, 6)
  gate_transform = nil
  if not ok_st then lsp.report(P .. "rf_stale_insert", false, "error: " .. tostring(err_st)) end

  -- Placement (M1): java.completion.importOrder groups ("", javax, jakarta, java, static), sorted within a
  -- group, a blank line between groups; the import text comes from the (rewritten) resolve answer.
  local function place_case(name, header, imp, want_header)
    local lines = cat(header, { "public class App {", "    public static void main(String[] args) {", "        ArrayLis", "    }", "}" })
    gate_transform = function(res)
      res.additionalTextEdits = { { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
        newText = imp .. "\n" } }
    end
    local okc, errc = pcall(rf, name, buf, client, nil, function(b, outs)
      local ok, d = exact(b, cat(want_header, body("        ArrayList")))
      return ok and status_is(outs, "applied"), d
    end, lines, nil, #header + 2)
    gate_transform = nil
    if not okc then lsp.report(P .. name, false, "error: " .. tostring(errc)) end
  end
  local PK, LIST, SVC = "package demo;", "import java.util.List;", "import org.springframework.stereotype.Service;"
  local STAT = "import static java.util.Objects.requireNonNull;"
  place_case("place_other_first", { PK, "", LIST, "" }, SVC, { PK, "", SVC, "", LIST, "" })
  place_case("place_group_between", { PK, "", SVC, "", LIST, "" }, "import jakarta.persistence.Entity;",
    { PK, "", SVC, "", "import jakarta.persistence.Entity;", "", LIST, "" })
  place_case("place_sorted_in_group", { PK, "", LIST, "import java.util.Map;", "" }, "import java.util.HashMap;",
    { PK, "", "import java.util.HashMap;", LIST, "import java.util.Map;", "" })
  place_case("place_before_static", { PK, "", STAT, "" }, AL, { PK, "", AL, "", STAT, "" })
  place_case("place_static_last", { PK, "", LIST, "" }, STAT, { PK, "", LIST, "", STAT, "" })
  place_case("place_no_package_license", { "/*", " * License text", " */", "" }, AL,
    { "/*", " * License text", " */", "", AL, "" })
  place_case("place_comment_not_import", { PK, "", "/*", AL, "*/", "// " .. AL, "" }, AL,
    { PK, "", AL, "", "/*", AL, "*/", "// " .. AL, "" })
  place_case("place_module_import_kept", { PK, "", "import module java.base;", "" }, AL,
    { PK, "", "import module java.base;", "", AL, "" })
  gate_transform = nil
  if not ok_rm then lsp.report(P .. "rf_removing_edit", false, "error: " .. tostring(err_rm)) end

  -- The resolve fails (error answer) or never answers (jdt.ls died): outcome logged, extmark cleared,
  -- the accepted text stays, nothing else changes.
  local ANS = vim.api.nvim_create_namespace("nv4j_async_import")
  local function no_marks(b) return #vim.api.nvim_buf_get_extmarks(b, ANS, 0, -1, {}) == 0 end
  gate_transform = function() return "error" end
  local ok_e, err_e = pcall(rf, "rf_resolve_error", buf, client, nil, function(b, outs)
    local ok, d = exact(b, { "package demo;", "", "public class App {", "    public static void main(String[] args) {",
      "        ArrayList", "    }", "}" })
    return ok and status_is(outs, "none") and no_marks(b), d .. "; extmarks left " .. #vim.api.nvim_buf_get_extmarks(b, ANS, 0, -1, {})
  end)
  gate_transform = nil
  if not ok_e then lsp.report(P .. "rf_resolve_error", false, "error: " .. tostring(err_e)) end
  local wait0 = NV.ASYNC_WAIT_MS
  NV.ASYNC_WAIT_MS, hold_forever = 500, true
  local ok_n, err_n = pcall(rf, "rf_no_answer", buf, client, nil, function(b, outs)
    local ok, d = exact(b, { "package demo;", "", "public class App {", "    public static void main(String[] args) {",
      "        ArrayList", "    }", "}" })
    return ok and status_is(outs, "dropped") and outs[#outs].why:find("no resolve answer") ~= nil and no_marks(b),
      d .. "; extmarks left " .. #vim.api.nvim_buf_get_extmarks(b, ANS, 0, -1, {})
  end)
  NV.ASYNC_WAIT_MS, hold_forever = wait0, nil
  if not ok_n then lsp.report(P .. "rf_no_answer", false, "error: " .. tostring(err_n)) end

  -- The resolve answered before the accept (doc popup) with jdt.ls's lossy edit seen in 22 of 50 real
  -- runs (2:0-2:22 replacing the existing import line): blink must not apply it as sent either.
  do
    local LB2 = { "package demo;", "", "import java.util.List;", "", "public class App {",
      "    public static void main(String[] args) {", "        ArrayLis", "    }", "}" }
    vim.diagnostic.reset(nil, buf)
    E.set(buf, LB2)
    E.wait_diags(buf, function(d) return E.has(d, nil, "ArrayLis cannot be resolved") ~= nil end, 10000)
    gate_pass = true
    gate_transform = function(res)
      res.additionalTextEdits = { { range = { start = { line = 2, character = 0 }, ["end"] = { line = 2, character = 22 } },
        newText = AL } }
    end
    local g = gate(client)
    local since = NV.async_count
    local okp, errp = pcall(function()
      local r, why = accept(buf, 6, 16, label("ArrayList", "java.util"), "ArrayList", false, true)
      if not r then return lsp.report(P .. "rf_in_time_lossy", false, why) end
      local outs = outcomes(since, 1)
      local ok, d = exact(buf, cat({ "package demo;", "", AL, "import java.util.List;", "" }, body("        ArrayList")))
      lsp.report(P .. "rf_in_time_lossy", ok and status_is(outs, "applied") and r.ms <= RETURN_BUDGET_MS,
        ("inserted after %.0f ms; outcome: %s; %s"):format(r.ms or -1, fmt_outcomes(outs), d))
    end)
    gate_pass, gate_transform = nil, nil
    g.restore()
    if not okp then lsp.report(P .. "rf_in_time_lossy", false, "error: " .. tostring(errp)) end
  end

  rf("rf_undo", buf, client, function(b)
    vim.api.nvim_buf_call(b, function() vim.cmd("silent undo") end)
  end, function(b, outs)
    local ok, d = same(b, nonblank_of(BASE))
    return ok and status_is(outs, "dropped") and count(b, AL) == 0, d .. ("; import count %d (want 0)"):format(count(b, AL))
  end)

  -- The undo boundary that <Esc> (or any normal-mode command) makes between the accept and the late
  -- resolve, without a text change: the import must still join the accept's undo step.
  rf("rf_undo_one", buf, client, function() vim.o.undolevels = vim.o.undolevels end, function(b, outs)
    local ok1, d1 = same(b, cat({ "package demo;", AL }, body("        ArrayList")))
    vim.api.nvim_buf_call(b, function() vim.cmd("silent undo") end)
    local ok2, d2 = same(b, nonblank_of(BASE))
    return ok1 and ok2 and status_is(outs, "applied"), "before u: " .. d1 .. "; after one u: " .. d2
  end)

  -- Second accept before the first resolve answered (fast typing): both answers held, released together.
  rf("rf_second", buf, client, function(b, ctx)
    local l = E.line_of(b, "^        ArrayList$")
    vim.api.nvim_buf_set_lines(b, l, l + 1, false, { "        ArrayList<String> a = null;", "        HashMa" })
    local r2, why = accept(b, l + 1, 14, label("HashMap", "java.util"), "HashMap")
    ctx.r2 = r2 or why
  end, function(b, outs, ctx)
    local ok, d = same(b, cat({ "package demo;", AL, "import java.util.HashMap;" },
      body("        ArrayList<String> a = null;", "        HashMap")))
    local r2 = type(ctx.r2) == "table" and ctx.r2 or nil
    local n1, n2 = count(b, AL), count(b, "import java.util.HashMap;")
    return ok and r2 ~= nil and r2.ms ~= nil and r2.ms <= RETURN_BUDGET_MS and n1 == 1 and n2 == 1,
      d .. ("; second insert %s ms; import counts %d/%d (want 1/1)"):format(r2 and r2.ms and ("%.0f"):format(r2.ms) or tostring(ctx.r2), n1, n2)
  end, nil, 2)
end

--- Last: the buffer is wiped between the accept and the late resolve.
local function rf_closed(buf, client)
  vim.api.nvim_set_current_buf(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local before = table.concat(vim.fn.readfile(path), "\n")
  rf("rf_closed", buf, client, function(b)
    vim.cmd("bwipeout! " .. b)
  end, function(b, outs)
    local disk = table.concat(vim.fn.readfile(path), "\n")
    return not vim.api.nvim_buf_is_valid(b) and status_is(outs, "dropped") and outs[#outs].why == "buffer closed" and disk == before,
      ("buffer valid=%s; file on disk %s"):format(tostring(vim.api.nvim_buf_is_valid(b)), disk == before and "unchanged" or "CHANGED")
  end)
end

-- Frecency vs project ranking ---------------------------------------------------------------------
local function rank_of(items, pred)
  for i, it in ipairs(items) do if pred(it) then return i end end
end

local function frecency_cases(buf)
  vim.api.nvim_set_current_buf(buf)
  -- Pollute: accept `List` 20 times through blink's accept with the frecency write live.
  local accepted = 0
  for _ = 1, 20 do
    E.set(buf, { "package demo;", "", "import java.util.List;", "", "public class App {",
      "    public static void main(String[] args) {", "        Lis", "    }", "}" })
    local r = accept(buf, 6, 11, label("List", "java.util"), "List", true)
    if r and r.ms then accepted = accepted + 1 end
  end
  vim.wait(1500) -- frecency writes run on a libuv worker thread (about 10 ms each)
  local fuzzy = require("blink.cmp.fuzzy")
  fuzzy.access = function() end
  local cfg = require("blink.cmp.config").fuzzy
  local db = vim.uv.fs_stat(cfg.frecency.path)

  lsp.report(P .. "frecency_polluted", accepted == 20 and db ~= nil and db.size > 0,
    ("%d/20 accepts of List with the frecency write live; db %s (%s bytes)"):format(accepted, cfg.frecency.path, db and db.size or "none"))

  local cases = {
    { name = "frecency_at", file = "CustomerController.java", after = "^@RequestMapping", line = "@", label = "RestController", top = 5 },
    { name = "frecency_http", file = "SecurityConfig.java", after = "public SecurityFilterChain filterChain", line = "        http.", label = "authorizeHttpRequests", top = 3 },
  }
  for _, cs in ipairs(cases) do
    local b = C.open_ready(lsp, src .. cs.file, 120000)
    if not b then
      lsp.report(P .. cs.name, false, "jdtls not ready")
    else
      C.scratch(b, function()
        local at = C.find_line(b, cs.after) + 1
        vim.api.nvim_buf_set_lines(b, at, at, false, { cs.line })
        local mm, why = C.menu(b, at, #cs.line)
        if not mm then return lsp.report(P .. cs.name, false, "menu: " .. tostring(why)) end
        local rk = rank_of(mm.items, function(it) return it.label == cs.label end)
        -- The pollution is live in this list: blink's score carries a frecency bonus (score minus
        -- score_offset, nothing typed) on the `List` items; and blink's plain order (score, sortText)
        -- is reported as what the list would be without Nv4J's Java sort.
        local bonus = 0
        for _, it in ipairs(mm.items) do
          if it.label == "List" then bonus = math.max(bonus, (it.score or 0) - (it.score_offset or 0)) end
        end
        local plain = vim.list_slice(mm.items)
        table.sort(plain, function(x, y)
          if (x.score or 0) ~= (y.score or 0) then return (x.score or 0) > (y.score or 0) end
          return (x.sortText or "") < (y.sortText or "")
        end)
        local need_bonus = cs.line:sub(-1) == "@"
        lsp.report(P .. cs.name, rk ~= nil and rk <= cs.top and (not need_bonus or bonus > 0),
          ("rank(%s)=%s (budget <= %d) with the polluted frecency db; frecency bonus on `List` items %d; blink's plain score order would give rank %s; shown=[%s]")
            :format(cs.label, tostring(rk), cs.top, bonus, tostring(rank_of(plain, function(it) return it.label == cs.label end)), C.labels(mm.items, 6)))
      end)
    end
  end
  vim.api.nvim_set_current_buf(buf)
end

local buf = lsp.open(src .. "App.java")
local client = lsp.wait_ready(buf, 120000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready" or "jdtls not ready")
if not client then return lsp.finish() end
local orig = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

-- blink's frecency database: a scratch file of this run, set before blink's first fuzzy call opens it.
local FRECENCY_DIR = "/tmp/nv4j/frecency-63/" .. vim.fn.getpid()
vim.fn.delete(FRECENCY_DIR, "rf")
vim.fn.mkdir(FRECENCY_DIR, "p")
if C.blink() then require("blink.cmp.config").fuzzy.frecency.path = FRECENCY_DIR .. "/frecency.dat" end

--- NV4J_63_REPEAT=N: accept `List` then `HashMap` N times against the REAL jdt.ls resolve (no gate),
--- printing what jdt.ls sent and the final import block; one PASS/FAIL line with the counts.
function repeat_real(buf, n)
  local good, missing, corrupt, dup, nones = 0, 0, 0, 0, 0
  local want = { "package demo;", "import java.util.HashMap;", "import java.util.List;", "public class App {",
    "    public static void main(String[] args) {", "        List<String> a = null;", "        HashMap", "    }", "}" }
  for i = 1, n do
    vim.diagnostic.reset(nil, buf)
    E.set(buf, { "package demo;", "", "public class App {", "    public static void main(String[] args) {",
      "        Lis", "        HashMa", "    }", "}" })
    E.wait_diags(buf, function(d) return E.has(d, nil, "Lis cannot be resolved") ~= nil end, 10000)
    vim.o.undolevels = vim.o.undolevels
    local since = NV.async_count
    local r1 = accept(buf, 4, 11, label("List", "java.util"), "List")
    if r1 then wait_import(buf, "java.util.List", r1.t0) end
    local l1 = E.line_of(buf, "^        List$")
    if l1 then vim.api.nvim_buf_set_lines(buf, l1, l1 + 1, false, { "        List<String> a = null;" }) end
    local l2 = E.line_of(buf, "^        HashMa$")
    local r2 = l2 and accept(buf, l2, 14, label("HashMap", "java.util"), "HashMap")
    if r2 then wait_import(buf, "java.util.HashMap", r2.t0) end
    vim.wait(3000, function() return NV.async_count >= since + 2 end, 5)
    local outs = {}
    for k = math.max(1, #NV.async_log - (NV.async_count - since) + 1), #NV.async_log do
      outs[#outs + 1] = NV.async_log[k]
      if NV.async_log[k].status == "none" then nones = nones + 1 end
    end
    local nl, nh = count(buf, "import java.util.List;"), count(buf, "import java.util.HashMap;")
    local ok = vim.deep_equal(nonblank(buf), want)
    if ok then good = good + 1 end
    if nl == 0 or nh == 0 then missing = missing + 1 end
    if nl > 1 or nh > 1 then dup = dup + 1 end
    if not ok and nl <= 1 and nh <= 1 and nl + nh == 2 then corrupt = corrupt + 1 end
    local block = {}
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, 4, false)) do block[#block + 1] = l end
    print(("REPEAT %d %s; outcomes: %s; head: %s"):format(i, ok and "ok" or "BAD", fmt_outcomes(outs), table.concat(block, " | ")))
  end
  lsp.report(P .. "repeat_real", good == n,
    ("%d/%d runs with both imports once and every line as expected; import missing %d, duplicated %d, other line wrong %d; resolve without import edit (none) %d")
      :format(good, n, missing, dup, corrupt, nones))
end

local ok_all, err = pcall(function()
  local sr = vim.g.nv4j_service_ready_ms
  if sr then vim.wait(10000, function() return vim.uv.hrtime() / 1e6 >= sr + 1000 end, 5) end
  E.set(buf, { "package demo;", "", "public class App {", "    public static void main(String[] args) {",
    "        Lis", "        HashMa", "    }", "}" })
  case("accept_first", buf, 4, 11, label("List", "java.util"), "List", "java.util.List")
  -- no pause: the second accept starts as soon as the first returned. `List` alone on its line
  -- would parse as `List HashMa` (a declaration: jdt.ls then offers variable names), so the first
  -- statement is finished first, as a user would have typed it.
  local l1 = E.line_of(buf, "^        List$")
  if l1 then vim.api.nvim_buf_set_lines(buf, l1, l1 + 1, false, { "        List<String> a = null;" }) end
  local l2 = E.line_of(buf, "^        HashMa$")
  if not l2 then return lsp.report(P .. "accept_second", false, "HashMa line lost after the first accept: " .. E.text(buf)) end
  case("accept_second", buf, l2, 14, label("HashMap", "java.util"), "HashMap", "java.util.HashMap", function()
    local first = count(buf, "import java.util.List;")
    return first == 1, ("java.util.List import count %d (want 1)"):format(first)
  end)

  -- deterministic twin: resolve answers held back STUB_DELAY_MS
  E.set(buf, { "package demo;", "", "public class App {", "    public static void main(String[] args) {",
    "        ArrayLis", "    }", "}" })
  local real = client.request
  local held = 0
  client.request = function(self, method, params, handler, bufnr)
    if method == "completionItem/resolve" and type(handler) == "function" then
      return real(self, method, params, function(...)
        local args = { ... }
        held = held + 1
        vim.defer_fn(function() handler(unpack(args)) end, STUB_DELAY_MS)
      end, bufnr)
    end
    return real(self, method, params, handler, bufnr)
  end
  local ok_s, err_s = pcall(case, "stub_slow", buf, 4, 16, label("ArrayList", "java.util"), "ArrayList", "java.util.ArrayList", function()
    vim.wait(STUB_DELAY_MS + 200) -- a late duplicate apply would land by now
    local n = count(buf, "import java.util.ArrayList;")
    return n == 1 and held > 0, ("%d resolve answer(s) held %d ms; import count %d (want 1)"):format(held, STUB_DELAY_MS, n)
  end)
  client.request = real
  if not ok_s then lsp.report(P .. "stub_slow", false, "error: " .. tostring(err_s)) end

  local rep_n = tonumber(vim.env.NV4J_63_REPEAT or "")
  if rep_n then return repeat_real(buf, rep_n) end
  rf_cases(buf, client)
  frecency_cases(buf)
  rf_closed(buf, client)
end)
E.restore(buf, orig)
if not ok_all then lsp.report(P .. "error", false, tostring(err)) end
lsp.finish()
