-- Documentation window and resolve requests (specs/features/completion-ranking.md, experiment 6). Run via tests/run.sh.
-- jdt.ls renders javadoc on completionItem/resolve (0.4 to 0.8 s per item), and blink asks for it when the documentation
-- window opens. Case `delay_scroll`: the cursor passes 10 menu items, one every 300 ms (a held arrow key), then rests.
-- blink's own timer (docs.auto_show_item, started with completion.documentation.auto_show_delay_ms) decides how many
-- resolves are sent: with 200 ms every item gets one (10), with 450 ms only the item the cursor rests on (1).
-- Cases `resolve_cache_*`: a list requested again inside one blink context (what an isIncomplete list does on every
-- keystroke) must not resolve the same item at jdt.ls again, a new context must, the reused answer must keep the
-- import edit and must not overwrite the new item's own textEdit.
-- The menu is not drawn in a headless run: the window check is stubbed open and sources.resolve is counted, not answered.
vim.o.confirm = false
local lsp = require("lsp")
local C = require("completion")

local fuzzy = C.blink()
local cfg = require("blink.cmp.config").completion.documentation
lsp.report("16_completion_docs.delay_config", cfg.auto_show == true and cfg.auto_show_delay_ms >= 400 and cfg.auto_show_delay_ms <= 500,
  ("auto_show=%s auto_show_delay_ms=%s (want 400 to 500)"):format(tostring(cfg.auto_show), tostring(cfg.auto_show_delay_ms)))

local menu = require("blink.cmp.completion.windows.menu")
local docs = require("blink.cmp.completion.windows.documentation")
local sources = require("blink.cmp.sources.lib")
local real_resolve, real_open = sources.resolve, menu.win.is_open
local calls = {}
local fake_task = {}
function fake_task:map() return self end
function fake_task:catch() return self end
sources.resolve = function(_, item)
  calls[#calls + 1] = item.label
  return fake_task
end
menu.win.is_open = function() return true end

local ctx = { id = 777 }
local STEP_MS, N = 300, 10
for i = 1, N do
  docs.auto_show_item(ctx, { label = "item" .. i })
  vim.wait(STEP_MS, function() return false end, 10)
end
vim.wait(900, function() return false end, 10) -- the cursor rests on the last item
docs.auto_show_timer:stop()

sources.resolve, menu.win.is_open = real_resolve, real_open
lsp.report("16_completion_docs.delay_scroll", #calls <= 2 and calls[#calls] == "item" .. N,
  ("%d resolve request(s) for %d items passed one per %d ms (budget <= 2, last = %s; 200 ms sent %d)"):format(
    #calls, N, STEP_MS, tostring(calls[#calls]), N))

-- 2. resolve cache (live jdt.ls; ArrayList is not imported by App.java)
local src = vim.env.NV4J_FIXTURE .. "/src/main/java/demo/"
local buf = C.open_ready(lsp, src .. "App.java", 120000)
if not buf then
  lsp.report("16_completion_docs.resolve_cache_hit", false, "jdtls not ready within 120 s")
  lsp.finish()
  return
end
local client = vim.lsp.get_clients({ bufnr = buf, name = "jdtls" })[1]
local NC = require("nv4j.completion")
if vim.env.NV4J_RESOLVE_CONTROL == "1" then
  NC.resolve_cached = function(module, item, callback) return module:resolve(item, callback) end -- no cache
end
local server_resolves = 0
local orig_request = client.request
client.request = function(self, method, ...)
  if method == "completionItem/resolve" then server_resolves = server_resolves + 1 end
  return orig_request(self, method, ...)
end

local function fetch(ctx)
  local got
  local function on(ev) if ev.context.id == ctx.id then got = ev end end
  sources.completions_emitter:on(on)
  sources.request_completions(ctx)
  vim.wait(30000, function() return got ~= nil end, 1)
  sources.completions_emitter:off(on)
  return got and got.items.lsp or {}
end
local function find(items)
  for _, it in ipairs(items) do
    local ld = it.labelDetails
    if it.label == "ArrayList" and ld and ld.description == "java.util" then return it end
  end
end
local function resolve(ctx, item)
  local out
  sources.resolve(ctx, item):map(function(r) out = r end)
  vim.wait(10000, function() return out ~= nil end, 5)
  return out
end

C.scratch(buf, function()
  local at = C.find_line(buf, "Repo repo = new Repo") + 1
  local line = "        Arr"
  vim.api.nvim_buf_set_lines(buf, at, at, false, { line })
  vim.wait(300, function() return false end, 10)
  vim.api.nvim_win_set_cursor(0, { at + 1, #line })
  local function new_ctx(id)
    return require("blink.cmp.completion.trigger.context").new({
      id = id, providers = sources.get_enabled_provider_ids("default"),
      initial_trigger_kind = "keyword", trigger_kind = "keyword",
    })
  end
  local cur = 900
  NC.context_id = function() return cur end
  local ctx = new_ctx(900)
  local la = fetch(ctx)
  local a = find(la)
  -- An isIncomplete list asked again in the same context returns new item objects with the same content;
  -- a deep copy is exactly that (blink reuses the objects of a complete list, so it cannot be provoked with `Arr`).
  local b = a and vim.deepcopy(a)
  local lb = la
  if not a or not b or a == b then
    lsp.report("16_completion_docs.resolve_cache_hit", false,
      ("no java.util.ArrayList item: first %d items found=%s, second %d items found=%s, same=%s first=" .. (la[1] and la[1].label or "-") .. "," .. (la[2] and la[2].label or "-")):format(
        #la, tostring(a ~= nil), #lb, tostring(b ~= nil), tostring(a == b)))
    return
  end
  if type(b.textEdit) == "table" and b.textEdit.range then
    b.textEdit.range["end"].character = b.textEdit.range["end"].character + 1 -- the second request's own range
  end
  local own_edit = vim.deepcopy(b.textEdit)
  local base, base_hits = server_resolves, NC.resolve_cache_hits
  local ra = resolve(ctx, a)
  local after_first = server_resolves
  local rb = resolve(ctx, b)
  local doc = function(r) return r and r.documentation and (r.documentation.value or r.documentation) end
  lsp.report("16_completion_docs.resolve_cache_hit",
    after_first - base == 1 and server_resolves == after_first and NC.resolve_cache_hits - base_hits == 1 and doc(ra) ~= nil and doc(ra) == doc(rb),
    ("jdt.ls resolves: first %d, second %d (want 1 and 0); cache hits %d; same documentation %s"):format(
      after_first - base, server_resolves - after_first, NC.resolve_cache_hits - base_hits, tostring(doc(ra) ~= nil and doc(ra) == doc(rb))))
  lsp.report("16_completion_docs.resolve_cache_keeps_edits",
    rb ~= nil and vim.deep_equal(rb.textEdit, own_edit)
      and #(rb.additionalTextEdits or {}) + #(rb.nv4j_imports or {}) == #(ra.additionalTextEdits or {}) + #(ra.nv4j_imports or {}),
    ("textEdit kept %s; import edits first %d second %d"):format(tostring(vim.deep_equal(rb and rb.textEdit, own_edit)),
      #(ra.additionalTextEdits or {}) + #(ra.nv4j_imports or {}), rb and (#(rb.additionalTextEdits or {}) + #(rb.nv4j_imports or {})) or -1))
  -- a new context (a new completion session): the answer is asked for again
  cur = 901
  local ctx2 = new_ctx(901)
  local c = find(fetch(ctx2))
  local before = server_resolves
  resolve(ctx2, c)
  lsp.report("16_completion_docs.resolve_cache_new_context", server_resolves - before == 1,
    ("jdt.ls resolves in a new context: %d (want 1)"):format(server_resolves - before))
end)
client.request = orig_request

lsp.finish()
