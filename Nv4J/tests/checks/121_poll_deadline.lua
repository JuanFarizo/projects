-- Control for the check 82 hang (specs/features/jpa.md "Check 82 hang"): a vim.wait whose predicate runs a nested vim.wait (what
-- request_sync does) never checks its own deadline in Neovim 0.12; lsp.poll does. Pure, no LSP.
--  nested_wait_ignores_deadline  the plain pattern is still unbounded here (stopped from inside after 1.5 s); when a future
--                                Neovim fixes it this case FAILS and lsp.poll can go back to vim.wait
--  poll_bounded                  lsp.poll with a nested vim.wait in its function returns nil at its deadline (600 ms, not forever)
--  poll_value                    it returns the function's value as soon as it is truthy
local lsp = require("lsp")
local P = "121_poll_deadline."
local function nested() local d = false vim.schedule(function() d = true end) vim.wait(1000, function() return d end, 10) end

local n = 0
local t = vim.uv.hrtime()
vim.wait(300, function() n = n + 1 nested() return (vim.uv.hrtime() - t) / 1e6 > 1500 end, 100)
local ms = (vim.uv.hrtime() - t) / 1e6
lsp.report(P .. "nested_wait_ignores_deadline", ms >= 1500, ("%d calls, still running after %.0f ms in a 300 ms wait (stopped from inside)"):format(n, ms))

n = 0
t = vim.uv.hrtime()
local r = lsp.poll(600, 100, function() n = n + 1 nested() return false end)
ms = (vim.uv.hrtime() - t) / 1e6
lsp.report(P .. "poll_bounded", r == nil and ms >= 500 and ms < 1500 and n < 20, ("nil after %.0f ms, %d calls"):format(ms, n))

n = 0
r = lsp.poll(2000, 50, function() n = n + 1 nested() return n == 3 and "ok" end)
lsp.report(P .. "poll_value", r == "ok" and n == 3, tostring(r) .. " after " .. n .. " calls")
lsp.finish()
