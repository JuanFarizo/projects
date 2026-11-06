-- JPQL completion + derived-query diagnostic with the REAL jdt.ls on the Boot 4 fixture (tests/fixtures/jpa4, copied to
-- /tmp so the fixture stays clean; edits are in memory only). HEAVY: starts jdt.ls (+ the Spring LS); run when the machine
-- is free. Twin of 79_jpql_buf (stub jdt.ls) and 76/77 (derived names).
--   wired          blink.cmp opts have provider "jpql" and per_filetype.java starts with it
--   member_root    `FROM Booking b WHERE b.|` offers id, reference, total, status, deletedAt, customer
--   member_join    `JOIN b.customer c WHERE c.|` offers Customer's email, fullName, bookings (type read through the real jdt.ls)
--   member_other   `FROM Booking b, Customer x WHERE x.|` (Customer found by the real workspace/symbol)
--   entity         `FROM |` lists Booking and Customer
--   source         nv4j.jpqlsource.get_completions answers like the module
--   derived_diag   `findByReferenc` in BookingRepository gets the ERROR "No property 'referenc' found for type 'Booking'"
local lsp = require("lsp")
local D = require("nv4j.dataquery")
local C = require("nv4j.jpqlcomplete")
local P = "80_jpql_live."

local SRC = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures/jpa4"
local TMP = "/tmp/nv4j/jpql-live-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
vim.fn.system({ "cp", "-R", SRC .. "/.", TMP })
vim.fn.delete(TMP .. "/target", "rf")
TMP = vim.uv.fs_realpath(TMP)
local FILE = TMP .. "/src/main/java/jpa4/BookingRepository.java"

-- blink wiring (the lazy.nvim spec merge)
do
  local ok, cfg = pcall(function() return require("lazy.core.config").plugins["blink.cmp"] end)
  local opts = ok and cfg and cfg.opts
  if type(opts) == "function" then opts = nil end
  local pf = opts and opts.sources and opts.sources.per_filetype and opts.sources.per_filetype.java
  local prov = opts and opts.sources and opts.sources.providers and opts.sources.providers.jpql
  lsp.report(P .. "wired", prov ~= nil and pf ~= nil and pf[1] == "jpql" or false,
    ("provider=%s per_filetype.java=%s"):format(vim.inspect(prov), vim.inspect(pf)))
end

local buf = lsp.open(FILE)
local client, why = lsp.wait_ready(buf, 300000)
if not client then
  lsp.report(P .. "ready", false, why)
  lsp.finish()
  return
end

local base = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
--- Replace the last "}" by a method with `query` (marker § = cursor), complete there. Returns items.
local function at(query)
  local lines = vim.deepcopy(base)
  while lines[#lines] == "" or lines[#lines]:match("^%s*$") do table.remove(lines) end
  assert(lines[#lines] == "}")
  lines[#lines] = nil
  local row = #lines + 1
  local before, after = query:match("^(.-)§(.*)$")
  lines[#lines + 1] = ('    @org.springframework.data.jpa.repository.Query("%s%s")'):format(before, after)
  lines[#lines + 1] = "    java.util.List<Booking> probe();"
  lines[#lines + 1] = "}"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local col = #('    @org.springframework.data.jpa.repository.Query("' .. before)
  local got, done
  C.complete(buf, row, col, function(items) got, done = items, true end)
  vim.wait(20000, function() return done end, 50)
  return got
end
local function has(items, ...)
  local t = {}
  for _, it in ipairs(items or {}) do t[it.label] = true end
  for _, l in ipairs({ ... }) do if not t[l] then return false end end
  return true
end
local function show(items) return items and table.concat(vim.tbl_map(function(i) return i.label end, items), ",") or "nil" end

-- give the Spring/jdt.ls project a moment to settle on the new text, then ask
local r = at("SELECT b FROM Booking b WHERE b.§")
lsp.report(P .. "member_root", has(r, "id", "reference", "total", "status", "deletedAt", "customer"), show(r))
r = at("SELECT b FROM Booking b JOIN b.customer c WHERE c.§")
lsp.report(P .. "member_join", has(r, "email", "fullName", "bookings"), show(r))
r = at("SELECT b FROM Booking b, Customer x WHERE x.§")
lsp.report(P .. "member_other", has(r, "email", "fullName"), show(r))
r = at("SELECT b FROM §")
lsp.report(P .. "entity", has(r, "Booking", "Customer"), show(r))

-- the blink source module
do
  local src = require("nv4j.jpqlsource").new()
  local lines = vim.deepcopy(base)
  while lines[#lines]:match("^%s*$") do table.remove(lines) end
  lines[#lines] = nil
  lines[#lines + 1] = '    @org.springframework.data.jpa.repository.Query("SELECT b FROM Booking b WHERE b.")'
  lines[#lines + 1] = "    java.util.List<Booking> probe();"
  lines[#lines + 1] = "}"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local row = #lines - 2
  local col = #lines[row + 1] - 2
  local got
  src:get_completions({ bufnr = buf, cursor = { row + 1, col } }, function(res) got = res end)
  vim.wait(20000, function() return got ~= nil end, 50)
  lsp.report(P .. "source", got and has(got.items, "reference", "customer") or false, show(got and got.items))
end

-- derived name diagnostic with the real jdt.ls
do
  local lines = vim.deepcopy(base)
  while lines[#lines]:match("^%s*$") do table.remove(lines) end
  lines[#lines] = nil
  lines[#lines + 1] = "    java.util.List<Booking> findByReferenc(String r);"
  lines[#lines + 1] = "}"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local found
  vim.wait(30000, function()
    D.run(buf)
    for _, d in ipairs(vim.diagnostic.get(buf, { namespace = D.ns })) do found = d.message end
    return found ~= nil
  end, 1000)
  lsp.report(P .. "derived_diag", found == "No property 'referenc' found for type 'Booking'", tostring(found))
end

vim.api.nvim_buf_set_lines(buf, 0, -1, false, base)
vim.bo[buf].modified = false
vim.fn.delete(TMP, "rf")
lsp.finish()
