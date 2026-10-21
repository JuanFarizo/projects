-- P2 Spring Boot language server. Run via tests/run.sh. Spec: specs/features/spring-language-server.md.
--  attached    : an LSP client named `spring-boot` is attached to the fixture's application.properties
--                and initialized <= 10 s after jdt.ls is ready (budget in specs/001-architecture.md).
--  props_first : the first completion on `server.po`, sent 1.0 s after the client is initialized (same
--                pin as P1's cold_first, D13: a request in the same millisecond finds the server's
--                property index still empty), lists `server.port`, round trip <= 400 ms.
--  props_warm  : warm completion p95 over 100 samples <= 150 ms, `server.port` in every list.
--  props_hover : hover on `server.port` returns text naming the key, <= 500 ms.
--  rss         : resident memory of the Spring LS process (a child of this nvim) <= 1.5 GB hard
--                limit; above the 1 GB budget it is printed in the detail.
-- Timings: /tmp/nv4j/logs/latency.jsonl (spring_ready, spring_props_first, spring_props_warm_p95,
-- spring_hover). The fixture file is only edited in memory and restored.
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local P = "50_spring_ls."
local READY_BUDGET_MS, FIRST_BUDGET_MS, WARM_BUDGET_MS, HOVER_BUDGET_MS = 10000, 400, 150, 500
local RSS_BUDGET_KB, RSS_HARD_KB = 1024 * 1024, 1536 * 1024
local NAME = "spring-boot"

local fixture = vim.env.NV4J_FIXTURE
local jbuf = lsp.open(fixture .. "/src/main/java/demo/DemoApplication.java")
local jdtls = lsp.wait_ready(jbuf, 120000)
local t_ready = E.now()
if not jdtls then
  lsp.report(P .. "attached", false, "jdtls not ready (prerequisite)")
  return lsp.finish()
end

-- The user opens application.properties: filetype comes from Neovim's own detection.
vim.cmd("edit " .. vim.fn.fnameescape(fixture .. "/src/main/resources/application.properties"))
local pbuf = vim.api.nvim_get_current_buf()
local orig = vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)
local function spring_client()
  local c = vim.lsp.get_clients({ bufnr = pbuf, name = NAME })[1]
  return c and c.initialized and not c:is_stopped() and c or nil
end
vim.wait(READY_BUDGET_MS + 20000, function() return spring_client() ~= nil end, 20)
local client = spring_client()
local ready_ms = E.now() - t_ready
E.log("spring_ready", client and ready_ms or -1, 1)
local names = table.concat(vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({ bufnr = pbuf })), ",")
lsp.report(P .. "attached", client ~= nil and ready_ms <= READY_BUDGET_MS,
  client and ("ready %.0f ms after jdt.ls (budget %d), filetype %s"):format(ready_ms, READY_BUDGET_MS, vim.bo[pbuf].filetype)
    or ("no '%s' client on application.properties after %.0f ms (filetype %s, clients: %s)"):format(
      NAME, ready_ms, vim.bo[pbuf].filetype, names ~= "" and names or "none"))
if not client then
  for _, c in ipairs({ "props_first", "props_warm", "props_hover", "rss" }) do
    lsp.report(P .. c, false, "no '" .. NAME .. "' client (see attached)")
  end
  return lsp.finish()
end

local function complete()
  local t0 = E.now()
  local r = client:request_sync("textDocument/completion",
    { textDocument = { uri = vim.uri_from_bufnr(pbuf) }, position = { line = 0, character = 9 } }, 10000, pbuf)
  local ms = E.now() - t0
  if not r then return { items = {}, ms = ms, err = "timeout" } end
  if r.err then return { items = {}, ms = ms, err = vim.inspect(r.err) } end
  local res = r.result or {}
  return { items = res.items or res, ms = ms }
end
local function has_port(items)
  for i, it in ipairs(items) do
    if it.label == "server.port" then return i end
  end
end
local function labels(items, n)
  local t = {}
  for i = 1, math.min(n, #items) do t[#t + 1] = items[i].label end
  return table.concat(t, ", ")
end

local t_client = E.now()
local ok_all, err = pcall(function()
  E.set(pbuf, { "server.po" })
  vim.wait(10000, function() return E.now() >= t_client + 1000 end, 5)
  local first = complete()
  local rank = has_port(first.items)
  E.log("spring_props_first", first.ms, 1)
  lsp.report(P .. "props_first", not first.err and rank ~= nil and first.ms <= FIRST_BUDGET_MS,
    first.err and ("error: " .. first.err)
      or ("%.0f ms (budget %d), server.port rank %s of %d: %s"):format(first.ms, FIRST_BUDGET_MS, tostring(rank), #first.items, labels(first.items, 5)))

  local samples, missing, errs = {}, 0, 0
  for _ = 1, 100 do
    local r = complete()
    samples[#samples + 1] = r.ms
    if r.err then errs = errs + 1 elseif not has_port(r.items) then missing = missing + 1 end
  end
  table.sort(samples)
  local p95 = samples[95]
  E.log("spring_props_warm_p95", p95, 100)
  lsp.report(P .. "props_warm", errs == 0 and missing == 0 and p95 <= WARM_BUDGET_MS,
    ("p95 %.1f ms (budget %d) over 100, server.port missing in %d, errors %d"):format(p95, WARM_BUDGET_MS, missing, errs))

  E.restore(pbuf, orig)
  local at = E.line_of(pbuf, "^server%.port")
  local t0 = E.now()
  local h = at and client:request_sync("textDocument/hover",
    { textDocument = { uri = vim.uri_from_bufnr(pbuf) }, position = { line = at, character = 3 } }, 10000, pbuf)
  local ms = E.now() - t0
  local c = h and h.result and h.result.contents
  local text = type(c) == "table" and (c.value or table.concat(vim.tbl_map(function(x) return type(x) == "table" and x.value or x end, c), "\n")) or c or ""
  E.log("spring_hover", ms, 1)
  lsp.report(P .. "props_hover", text:find("server.port", 1, true) ~= nil and ms <= HOVER_BUDGET_MS,
    ("%.0f ms (budget %d): %s"):format(ms, HOVER_BUDGET_MS, (text ~= "" and text or vim.inspect(h and (h.err or h.result))):sub(1, 120):gsub("%s+", " ")))

  local pid = vim.trim(vim.fn.system({ "pgrep", "-P", tostring(vim.fn.getpid()), "-f", "spring-boot-language-server|vscode-spring-boot-tools" })):match("^(%d+)")
  local rss = pid and tonumber(vim.trim(vim.fn.system({ "ps", "-o", "rss=", "-p", pid }))) or nil
  lsp.report(P .. "rss", rss ~= nil and rss <= RSS_HARD_KB,
    rss and ("%.0f MB (budget %d MB, hard limit %d MB)%s"):format(rss / 1024, RSS_BUDGET_KB / 1024, RSS_HARD_KB / 1024,
      rss > RSS_BUDGET_KB and " OVER BUDGET" or "") or "Spring LS process (child of this nvim) not found")
end)
E.restore(pbuf, orig)
if not ok_all then lsp.report(P .. "props", false, "error: " .. tostring(err)) end
lsp.finish()
