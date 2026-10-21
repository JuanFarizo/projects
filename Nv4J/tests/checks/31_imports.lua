-- P1 imports. Run via tests/run.sh. Spec: specs/features/diagnostics-imports-actions.md.
--  auto_import_first : the FIRST completion accepted after opening the project (1 s after jdtls is
--                      ready, like a user) adds its import: `List` -> `import java.util.List;`.
--                      Goes through blink.cmp's own accept (completionItem/resolve with blink's
--                      resolve timeout, then the additionalTextEdits). The import edit arrives only in
--                      resolve, so a resolve slower than the timeout silently drops the import.
--  auto_import_group : a Spring type completed in a file with grouped imports lands next to its
--                      package neighbours.
--  organize          : <leader>co (the buffer-local mapping, called as the user would) removes the
--                      unused import and orders the rest IntelliJ-style: all other, javax, jakarta,
--                      java, then static imports.
-- Timings: /tmp/nv4j/logs/latency.jsonl (import_accept_*, organize).
vim.o.confirm = false
local lsp = require("lsp")
local C = require("completion")
local E = require("edit")
local P = "31_imports."
local ACCEPT_BUDGET_MS = 1500 -- the accept waits for completionItem/resolve; see the spec

-- blink writes the accepted text to the `.` register through a temporary insert-mode completion
-- (vim.fn.complete), which headless normal mode cannot run. Only that dot-repeat hack is stubbed.
local function accept(buf, lnum, col, pick)
  local fuzzy = C.blink()
  if not fuzzy then return nil, "blink not loaded" end
  require("blink.cmp.lib.text_edits").write_to_dot_repeat = function() end
  -- Accepting records the label in blink's frecency database, which later boosts every item with
  -- that label (e.g. the nested `List` annotations in an `@` list, breaking check 11). Not recorded.
  require("blink.cmp.fuzzy").access = function() end
  local m, why = C.menu(buf, lnum, col)
  if not m then return nil, why end
  local item, rank
  for i, it in ipairs(m.items) do
    if pick(it) then item, rank = it, i break end
  end
  if not item then return nil, "item not in menu: " .. C.labels(m.items, 8) end
  local ctx = require("blink.cmp.completion.trigger.context").new({
    id = math.random(1, 1e9), providers = { "lsp" }, initial_trigger_kind = "keyword", trigger_kind = "keyword",
  })
  vim.api.nvim_win_set_cursor(0, { lnum + 1, col })
  local done = false
  local t0 = E.now()
  require("blink.cmp.completion.accept")(ctx, item, function() done = true end)
  vim.wait(10000, function() return done end, 1)
  return { ms = E.now() - t0, rank = rank, done = done }
end

local function from(pkg)
  return function(it)
    local where = ((it.labelDetails and it.labelDetails.description) or "") .. " " .. (it.detail or "")
    return where:find(pkg, 1, true) ~= nil
  end
end

local src = vim.env.NV4J_FIXTURE .. "/src/main/java/demo/"
local buf = lsp.open(src .. "App.java")
local client = lsp.wait_ready(buf, 120000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready" or "jdtls not ready")
if not client then return lsp.finish() end
local orig = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

local ok_all, err = pcall(function()
  -- 1 s after ServiceReady, like check 10's cold request: the user's first accept of the session
  local sr = vim.g.nv4j_service_ready_ms
  if sr then vim.wait(10000, function() return vim.uv.hrtime() / 1e6 >= sr + 1000 end, 5) end
  E.set(buf, { "package demo;", "", "public class App {", "    public static void main(String[] args) {",
    "        List", "    }", "}" })
  local r, why = accept(buf, 4, 12, function(it) return it.label == "List" and from("java.util")(it) end)
  local txt = E.text(buf)
  E.log("import_accept_first", r and r.ms or -1, 1)
  lsp.report(P .. "auto_import_first", r ~= nil and r.done and txt:find("\nimport java.util.List;\n", 1, true) ~= nil
    and r.ms <= ACCEPT_BUDGET_MS,
    r and ("accept %.0f ms (budget %d), rank %d, import %s"):format(r.ms, ACCEPT_BUDGET_MS, r.rank,
      txt:find("import java.util.List;", 1, true) and "added" or "MISSING") or why)

  -- a second documented JDK type in the same session (its javadoc is read on resolve again)
  E.set(buf, { "package demo;", "", "import java.util.List;", "", "public class App {",
    "    public static void main(String[] args) {", "        HashMa", "    }", "}" })
  local r2, why2 = accept(buf, 6, 14, function(it) return it.label == "HashMap" and from("java.util")(it) end)
  local txt2 = E.text(buf)
  E.log("import_accept_second", r2 and r2.ms or -1, 1)
  lsp.report(P .. "auto_import_second", r2 ~= nil and txt2:find("import java.util.HashMap;", 1, true) ~= nil and r2.ms <= ACCEPT_BUDGET_MS,
    r2 and ("accept %.0f ms (budget %d), import %s"):format(r2.ms, ACCEPT_BUDGET_MS, txt2:find("import java.util.HashMap;", 1, true) and "added" or "MISSING") or why2)
end)
E.restore(buf, orig)
if not ok_all then lsp.report(P .. "auto_import", false, "error: " .. tostring(err)) end

-- Spring type into a file with grouped imports
local cbuf = lsp.open(src .. "CustomerController.java")
lsp.wait_ready(cbuf, 60000)
local corig = vim.api.nvim_buf_get_lines(cbuf, 0, -1, false)
local ok_g, err_g = pcall(function()
  local at = E.line_of(cbuf, "public Customer create") + 1
  vim.api.nvim_buf_set_lines(cbuf, at, at, false, { "        HttpStat" })
  local r, why = accept(cbuf, at, 16, function(it) return it.label == "HttpStatus" and from("org.springframework.http")(it) end)
  local hs, re = E.line_of(cbuf, "^import org%.springframework%.http%.HttpStatus;"), E.line_of(cbuf, "^import org%.springframework%.http%.ResponseEntity;")
  lsp.report(P .. "auto_import_group", r ~= nil and hs ~= nil and re ~= nil and hs + 1 == re,
    r and ("HttpStatus import at line %s, ResponseEntity at %s (want adjacent)"):format(tostring(hs and hs + 1), tostring(re and re + 1)) or why)
end)
E.restore(cbuf, corig)
if not ok_g then lsp.report(P .. "auto_import_group", false, "error: " .. tostring(err_g)) end

-- organize imports through the user's key
vim.api.nvim_set_current_buf(buf)
local ok_o, err_o = pcall(function()
  local map = vim.fn.maparg("<leader>co", "n", false, true)
  lsp.report(P .. "organize_key", map.buffer == 1 and (map.desc or ""):find("Organize Imports") ~= nil and map.callback ~= nil,
    ("<leader>co in a Java buffer: buffer=%s desc=%s"):format(tostring(map.buffer), tostring(map.desc)))
  -- config/keymaps.lua loads on VeryLazy, after -c commands; load it now (idempotent)
  pcall(require, "config.keymaps")
  local alias = vim.fn.maparg("<leader>cO", "n", false, true)
  lsp.report(P .. "outgoing_calls_key", (alias.desc or ""):find("Outgoing calls") ~= nil,
    "<leader>cO: desc=" .. tostring(alias.desc))
  -- each key means one thing: no global <leader>co (outgoing calls) left for non-Java buffers
  local other = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_set_current_buf(other)
  local g = vim.fn.maparg("<leader>co", "n", false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_delete(other, { force = true })
  lsp.report(P .. "co_only_organize", (g.desc or ""):find("Outgoing calls") == nil,
    "<leader>co outside Java buffers: " .. (g.desc or (next(g) and "unnamed mapping" or "unmapped")))
  if not map.callback then return end
  E.set(buf, E.planted("imports.java.txt"))
  vim.wait(300) -- a user needs at least this long between the edit and the key
  local before = E.text(buf)
  local t0 = E.now()
  map.callback()
  local changed = vim.wait(10000, function() return E.text(buf) ~= before end, 5)
  local ms = E.now() - t0
  E.log("organize", ms, 1)
  local imports = {}
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local st = l:match("^import%s+static%s+([%w%.]+);")
    local name = st or l:match("^import%s+([%w%.]+);")
    if name then imports[#imports + 1] = { static = st ~= nil, name = name } end
  end
  local function group(i)
    if i.static then return 5 end
    if i.name:find("^javax%.") then return 2 end
    if i.name:find("^jakarta%.") then return 3 end
    if i.name:find("^java%.") then return 4 end
    return 1
  end
  local sorted, last, names = true, 0, {}
  for _, i in ipairs(imports) do
    if group(i) < last then sorted = false end
    last = group(i)
    names[#names + 1] = (i.static and "static " or "") .. i.name
  end
  local txt = E.text(buf)
  local kept = true
  for _, n in ipairs({ "java.util.List", "java.util.ArrayList", "org.springframework.http.ResponseEntity", "jakarta.validation.Valid",
    "javax.sql.DataSource", "com.fasterxml.jackson.databind.ObjectMapper", "java.util.Objects.requireNonNull", "org.springframework.http.HttpStatus.OK" }) do
    if not txt:find("import [%w ]-" .. n:gsub("%.", "%%.") .. ";") then kept = false end
  end
  lsp.report(P .. "organize_removes_unused", changed and not txt:find("java.util.Map", 1, true) and kept,
    ("%.0f ms; Map %s; used imports %s"):format(ms, txt:find("java.util.Map", 1, true) and "KEPT" or "removed", kept and "kept" or "LOST"))
  lsp.report(P .. "organize_order", changed and sorted and #imports == 8,
    "order: " .. table.concat(names, ", "))

  -- the file has a compile error: organize imports still removes the unused import (the way to clear
  -- them while jdt.ls itself does not flag them)
  E.set(buf, E.planted("errors_organize.java.txt"))
  vim.wait(300)
  local before2 = E.text(buf)
  map.callback()
  local changed2 = vim.wait(10000, function() return E.text(buf) ~= before2 end, 5)
  local t2 = E.text(buf)
  lsp.report(P .. "organize_with_compile_error", changed2 and not t2:find("java.util.Map", 1, true) and t2:find("import java.util.List;", 1, true) ~= nil,
    ("Map %s, List %s"):format(t2:find("java.util.Map", 1, true) and "KEPT" or "removed", t2:find("import java.util.List;", 1, true) and "kept" or "LOST"))
end)
E.restore(buf, orig)
if not ok_o then lsp.report(P .. "organize", false, "error: " .. tostring(err_o)) end
lsp.finish()
