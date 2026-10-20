-- Project usage index (nvim/lua/nv4j/usage.lua) used by Java completion ranking. No jdtls needed.
-- Counts on a temp project, then: a failing rg and a timed-out rg keep the previous counts,
-- writes are debounced into one run, and without rg nothing breaks (no counts, ranking falls back).
vim.o.confirm = false
local lsp = require("lsp")
local usage = require("nv4j.usage")

local base = "/tmp/nv4j/usage-check"
vim.fn.delete(base, "rf")
local root = base .. "/proj"
vim.fn.mkdir(root .. "/src", "p")
vim.fn.writefile({
  "package demo;",
  "import org.example.save;",
  "@Service",
  "class A { void f() { repo.save(x); repo.save(y); repo.findById(1); } }",
}, root .. "/src/A.java")
local real_path = vim.env.PATH
local real_rg = vim.fn.exepath("rg")

local function wait_run(prev, ms) return vim.wait(ms or 15000, function() return usage.runs > prev end, 20) end

-- 1. counts
local n = usage.runs
usage.build(root)
local ok = wait_run(n)
local c = usage.get(root)
lsp.report("12_usage_index.counts", ok and c and c.member.save == 2 and c.member.findById == 1 and c.anno.Service == 1,
  c and ("save=%s findById=%s @Service=%s (import line not counted: want save=2)"):format(
    tostring(c.member.save), tostring(c.member.findById), tostring(c.anno.Service)) or "no counts")

-- 2. rg fails (exit 2): previous counts stay
local bin = base .. "/fakebin"
vim.fn.mkdir(bin, "p")
vim.fn.writefile({ "#!/bin/sh", "echo 'rg: boom' >&2", "exit 2" }, bin .. "/rg")
vim.fn.setfperm(bin .. "/rg", "rwxr-xr-x")
vim.env.PATH = bin .. ":" .. real_path
n = usage.runs
usage.build(root)
ok = wait_run(n)
c = usage.get(root)
lsp.report("12_usage_index.rg_fails_keeps_counts", ok and c and c.member.save == 2,
  ("run finished=%s save=%s"):format(tostring(ok), c and tostring(c.member.save) or "nil"))

-- 2b. only the second rg (token extraction) fails: previous counts stay, not replaced by empty ones
vim.fn.writefile({
  "#!/bin/sh",
  'if [ "$1" = "--only-matching" ]; then echo "rg: boom" >&2; exit 2; fi',
  'exec "' .. real_rg .. '" "$@"',
}, bin .. "/rg")
n = usage.runs
usage.build(root)
ok = wait_run(n)
c = usage.get(root)
lsp.report("12_usage_index.second_rg_fails_keeps_counts", ok and c and c.member.save == 2 and c.anno.Service == 1,
  ("run finished=%s save=%s @Service=%s"):format(tostring(ok), c and tostring(c.member.save) or "nil",
    c and tostring(c.anno.Service) or "nil"))

-- 3. rg hangs past the timeout: killed, previous counts stay
vim.fn.writefile({ "#!/bin/sh", "sleep 5" }, bin .. "/rg")
local timeout = usage.TIMEOUT_MS
usage.TIMEOUT_MS = 500
n = usage.runs
local t0 = vim.uv.hrtime()
usage.build(root)
ok = wait_run(n, 4000)
local took = (vim.uv.hrtime() - t0) / 1e6
c = usage.get(root)
lsp.report("12_usage_index.timeout_keeps_counts", ok and took < 4000 and c and c.member.save == 2,
  ("finished=%s after %.0f ms (timeout 500) save=%s"):format(tostring(ok), took, c and tostring(c.member.save) or "nil"))
usage.TIMEOUT_MS = timeout
vim.env.PATH = real_path

-- 4. debounce: five writes in a burst cost one run
local debounce = usage.DEBOUNCE_MS
usage.DEBOUNCE_MS = 200
n = usage.runs
for _ = 1, 5 do usage.schedule(root) end
vim.wait(1500, function() return false end, 20)
lsp.report("12_usage_index.debounced", usage.runs - n == 1, ("runs after 5 schedules: %d (want 1)"):format(usage.runs - n))
usage.DEBOUNCE_MS = debounce

-- 5. no rg on PATH: build/watch are no-ops, transform still works without counts
vim.env.PATH = "/usr/bin:/bin"
local absent = vim.fn.executable("rg") == 0
local root2 = base .. "/proj2"
vim.fn.mkdir(root2, "p")
local okw = pcall(usage.watch, root2)
usage.build(root2)
vim.cmd("enew")
vim.bo.filetype = "java"
local K = vim.lsp.protocol.CompletionItemKind
local ctx = { bufnr = vim.api.nvim_get_current_buf(), line = "        repository.", bounds = { start_col = 20, length = 0 } }
local items = {
  { label = "save", kind = K.Method, sortText = "999999035", client_id = 99999 },
  { label = "count", kind = K.Method, sortText = "999999035", client_id = 99999 },
}
local okt, out = pcall(require("nv4j.completion").transform_lsp, ctx, items)
lsp.report("12_usage_index.no_rg_fallback", absent and okw and usage.get(root2) == nil and okt and #out == 2 and out[1].nv4j_uses == nil,
  ("rg absent=%s watch ok=%s counts=%s transform ok=%s items=%s"):format(tostring(absent), tostring(okw),
    tostring(usage.get(root2)), tostring(okt), okt and tostring(#out) or tostring(out)))
vim.env.PATH = real_path

lsp.finish()
