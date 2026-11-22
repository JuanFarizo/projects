-- Documentation window and resolve requests (specs/features/completion-ranking.md, experiment 6). Run via tests/run.sh.
-- jdt.ls renders javadoc on completionItem/resolve (0.4 to 0.8 s per item), and blink asks for it when the documentation
-- window opens. Case `delay_scroll`: the cursor passes 10 menu items, one every 300 ms (a held arrow key), then rests.
-- blink's own timer (docs.auto_show_item, started with completion.documentation.auto_show_delay_ms) decides how many
-- resolves are sent: with 200 ms every item gets one (10), with 450 ms only the item the cursor rests on (1).
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

lsp.finish()
