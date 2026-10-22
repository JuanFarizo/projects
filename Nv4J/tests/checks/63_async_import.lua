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
-- Baseline (P3 Task 0): blink waits for resolve up to resolve_timeout_ms (1500, plugins/blink.lua),
-- so the item text lands only after resolve: about 0.4-0.8 s for `List`/`HashMap`, about 800 ms in stub_slow.
-- Timings: /tmp/nv4j/logs/latency.jsonl (async_import_*).
vim.o.confirm = false
local lsp = require("lsp")
local C = require("completion")
local E = require("edit")
local P = "63_async_import."
local RETURN_BUDGET_MS, IMPORT_BUDGET_MS, STUB_DELAY_MS = 100, 1500, 800

-- Same accept path as 31_imports: blink's own accept (resolve, then the edits), with only the
-- dot-repeat hack and the frecency write stubbed (headless normal mode / user state).
local function accept(buf, lnum, col, pick, word)
  local fuzzy = C.blink()
  if not fuzzy then return nil, "blink not loaded" end
  require("blink.cmp.lib.text_edits").write_to_dot_repeat = function() end
  require("blink.cmp.fuzzy").access = function() end
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

--- One case: accept, then report control-return time and import time against the budgets.
local function case(name, buf, lnum, col, pick, word, fq, extra)
  local r, why = accept(buf, lnum, col, pick, word)
  if not r then return lsp.report(P .. name, false, why) end
  local imp_ms = wait_import(buf, fq, r.t0)
  E.log("async_import_" .. name .. "_return", r.ms or -1, 1)
  E.log("async_import_" .. name .. "_callback", r.cb_ms or -1, 1)
  E.log("async_import_" .. name .. "_import", imp_ms or -1, 1)
  local ok_extra, why_extra = true, ""
  if extra then ok_extra, why_extra = extra() end
  lsp.report(P .. name, r.done and r.ms ~= nil and r.ms <= RETURN_BUDGET_MS and imp_ms ~= nil and imp_ms <= IMPORT_BUDGET_MS and ok_extra,
    ("%s inserted after %s ms (budget %d); import %s (budget %d ms); blink accept callback %s ms%s"):format(word,
      r.ms and ("%.0f"):format(r.ms) or "NEVER", RETURN_BUDGET_MS, imp_ms and ("after %.0f ms"):format(imp_ms) or "MISSING",
      IMPORT_BUDGET_MS, r.cb_ms and ("%.0f"):format(r.cb_ms) or "never", why_extra ~= "" and ("; " .. why_extra) or ""))
  return r
end

local src = vim.env.NV4J_FIXTURE .. "/src/main/java/demo/"
local buf = lsp.open(src .. "App.java")
local client = lsp.wait_ready(buf, 120000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready" or "jdtls not ready")
if not client then return lsp.finish() end
local orig = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

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
end)
E.restore(buf, orig)
if not ok_all then lsp.report(P .. "error", false, tostring(err)) end
lsp.finish()
