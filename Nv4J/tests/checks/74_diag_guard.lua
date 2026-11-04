-- Underline diagnostic past the end of a shortened file (nv4j/diagfix.lua, Neovim 0.12.4 sharp edge: diagnostic.lua:1845
-- nvim_buf_get_lines strict, run on BufRead for a buffer that was unloaded when the diagnostic was set). The user saw
-- "E5108 neo-tree/utils/init.lua:920: BufReadPost Autocommands for <buffer=73>: ... Index out of bounds" opening a file.
-- Real Neovim, real files in /tmp/nv4j/d74-<pid>, opened with :edit (the call neo-tree makes). No jdt.ls, no timing.
--  api             : nv4j.diagfix loads (setup, fit); init.lua wires setup; the underline handler is the guarded one.
--  upstream        : informational: the unguarded Neovim handler really throws on this file (detail says yes/no).
--  set_unloaded    : vim.diagnostic.set (the path of tests.lua) on an unloaded buffer, file shortened on disk, :edit -> no error;
--                    a BufReadPost autocmd registered after the diagnostic still runs (the chain is not aborted).
--  lsp_publish     : a stubbed textDocument/publishDiagnostics for a closed file, file shortened, :edit -> no error.
--  keeps_valid     : in the same buffer a diagnostic inside the new file keeps its underline, the one past the end has none.
--  boundary        : lnum == line count is dropped, lnum == line count - 1 is kept (off by one).
--  loaded_buffer   : the guarded handler called directly with an out-of-range diagnostic on a LOADED buffer: no error.
--  reset_cancels   : a valid diagnostic set on an unloaded buffer then reset (hide) before the load: nothing is drawn after :edit.
--  reshow          : set twice on the unloaded buffer (both lists valid, 2 then 1 entries): only the second list is drawn (the first deferred show is cancelled).
--  fit_file        : diagfix.fit on an unloaded buffer uses the file on disk; on a loaded one the buffer; no file -> unchanged.
--  our_paths       : tests.lua and unused_imports.lua call diagfix.fit before vim.diagnostic.set.
--  idempotent      : setup() a second time changes nothing (returns false, same handler).
local lsp = require("lsp")
local P = "74_diag_guard."
local TMP = "/tmp/nv4j/d74-" .. vim.fn.getpid()
local api = vim.api
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
local seq = 0

local ok_mod, D = pcall(require, "nv4j.diagfix")
local cases = { "upstream", "set_unloaded", "lsp_publish", "keeps_valid", "boundary", "loaded_buffer",
  "reset_cancels", "reshow", "fit_file", "our_paths", "idempotent" }
local h = vim.diagnostic.handlers.underline
lsp.report(P .. "api", ok_mod and type(D.setup) == "function" and type(D.fit) == "function" and h._nv4j_guard == true,
  ok_mod and ("guard flag on handler: " .. tostring(h._nv4j_guard)) or tostring(D):gsub("\n.*", ""))
if not ok_mod then
  for _, c in ipairs(cases) do lsp.report(P .. c, false, "nv4j.diagfix not loadable") end
  return lsp.finish()
end

local function case(name, fn)
  local ok, err = pcall(fn)
  if not ok then lsp.report(P .. name, false, "error: " .. tostring(err):gsub("\n.*", "")) end
end
local function lines(n) local t = {} for i = 1, n do t[i] = "line" .. i end return t end
--- A closed file of `n` lines, its unloaded buffer and a fresh diagnostic namespace.
local function mk(n)
  seq = seq + 1
  local f = ("%s/f%d.txt"):format(TMP, seq)
  vim.fn.writefile(lines(n), f)
  local b = vim.fn.bufadd(f)
  return f, b, api.nvim_create_namespace("d74." .. seq)
end
local function dg(l, el) return { lnum = l, col = 0, end_lnum = el or l, end_col = 3, severity = vim.diagnostic.severity.ERROR, message = "d74 @" .. l } end
local function marks(b, ns)
  local u = vim.diagnostic.get_namespace(ns).user_data.underline_ns
  if not u or not api.nvim_buf_is_valid(b) then return 0 end
  return #api.nvim_buf_get_extmarks(b, u, 0, -1, {})
end
local function edit(f)
  local ran = false
  local au = api.nvim_create_autocmd("BufReadPost", { once = true, callback = function() ran = true end })
  local ok, err = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(f))
  pcall(api.nvim_del_autocmd, au)
  return ok, tostring(err):gsub("\n.*", ""), ran
end

case("upstream", function()
  local f, b, ns = mk(60)
  local u = D._upstream
  u.show(ns, b, { dg(50) }, {})
  vim.fn.writefile(lines(2), f)
  local ok = edit(f)
  u.hide(ns, b)
  lsp.report(P .. "upstream", true, "unguarded Neovim handler throws on :edit: " .. tostring(not ok))
end)

case("set_unloaded", function()
  local f, b, ns = mk(60)
  vim.diagnostic.set(ns, b, { dg(50) })
  vim.fn.writefile(lines(2), f)
  local ok, err, ran = edit(f)
  lsp.report(P .. "set_unloaded", ok and ran and marks(b, ns) == 0, ("edit ok=%s chain_ran=%s marks=%d %s"):format(tostring(ok), tostring(ran), marks(b, ns), err))
end)

case("lsp_publish", function()
  local f = ("%s/lsp.txt"):format(TMP)
  vim.fn.writefile(lines(60), f)
  local cid = vim.lsp.start({ name = "d74fake", cmd = { "cat" } }, { attach = false })
  local ok, err, ran, n
  if cid then
    vim.lsp.diagnostic.on_publish_diagnostics(nil, { uri = vim.uri_from_fname(f), diagnostics = {
      { range = { start = { line = 50, character = 0 }, ["end"] = { line = 50, character = 3 } }, severity = 1, message = "d74 lsp" } } },
      { client_id = cid, method = "textDocument/publishDiagnostics" })
    local b = vim.uri_to_bufnr(vim.uri_from_fname(f))
    n = #vim.diagnostic.get(b)
    vim.fn.writefile(lines(2), f)
    ok, err, ran = edit(f)
    pcall(function() vim.lsp.get_client_by_id(cid):stop(true) end)
  end
  lsp.report(P .. "lsp_publish", cid ~= nil and n == 1 and ok and ran, ("client=%s stored=%s edit ok=%s chain_ran=%s %s"):format(tostring(cid), tostring(n), tostring(ok), tostring(ran), tostring(err)))
end)

case("keeps_valid", function()
  local f, b, ns = mk(60)
  vim.diagnostic.set(ns, b, { dg(1), dg(50), dg(0) })
  vim.fn.writefile(lines(3), f)
  local ok = edit(f)
  lsp.report(P .. "keeps_valid", ok and marks(b, ns) == 2, ("edit ok=%s underline marks=%d (want 2: lines 0 and 1)"):format(tostring(ok), marks(b, ns)))
end)

case("boundary", function()
  local f, b, ns = mk(60)
  vim.diagnostic.set(ns, b, { dg(4) })
  vim.fn.writefile(lines(4), f) -- lnum 4 == line count: past the end
  local ok1 = edit(f)
  local m1 = marks(b, ns)
  local f2, b2, ns2 = mk(60)
  vim.diagnostic.set(ns2, b2, { dg(3) })
  vim.fn.writefile(lines(4), f2) -- lnum 3 is the last line
  local ok2 = edit(f2)
  local m2 = marks(b2, ns2)
  lsp.report(P .. "boundary", ok1 and ok2 and m1 == 0 and m2 == 1, ("lnum==count: ok=%s marks=%d; lnum==count-1: ok=%s marks=%d"):format(tostring(ok1), m1, tostring(ok2), m2))
end)

case("loaded_buffer", function()
  local f, b, ns = mk(3)
  vim.cmd("edit " .. vim.fn.fnameescape(f))
  local cur = api.nvim_get_current_buf()
  local ds = { dg(1), dg(30), dg(2, 30) }
  for _, d in ipairs(ds) do d.bufnr = cur end -- vim.diagnostic.set adds it; the handler reads it
  local ok, err = pcall(vim.diagnostic.handlers.underline.show, ns, cur, ds, {})
  local m = marks(cur, ns)
  lsp.report(P .. "loaded_buffer", ok and m >= 2, ("show ok=%s %s marks=%d (lines 1 and 2 drawn, 30 dropped)"):format(tostring(ok), tostring(err), m))
end)

case("reset_cancels", function()
  local f, b, ns = mk(60)
  vim.diagnostic.set(ns, b, { dg(0) })
  vim.diagnostic.reset(ns, b)
  vim.fn.writefile(lines(2), f)
  local ok = edit(f)
  lsp.report(P .. "reset_cancels", ok and marks(b, ns) == 0, ("edit ok=%s marks=%d"):format(tostring(ok), marks(b, ns)))
end)

case("reshow", function()
  local f, b, ns = mk(60)
  vim.diagnostic.set(ns, b, { dg(0), dg(1) })
  vim.diagnostic.set(ns, b, { dg(0) })
  vim.fn.writefile(lines(2), f)
  local ok = edit(f)
  lsp.report(P .. "reshow", ok and marks(b, ns) == 1, ("edit ok=%s marks=%d (want 1)"):format(tostring(ok), marks(b, ns)))
end)

case("fit_file", function()
  local f, b = mk(60)
  vim.fn.writefile(lines(5), f)
  local on_disk = #D.fit(b, { dg(2), dg(4), dg(5), dg(40), dg(-1) }) -- unloaded: file has 5 lines -> 2 and 4 stay
  vim.cmd("edit " .. vim.fn.fnameescape(f))
  api.nvim_buf_set_lines(b, 2, -1, false, {}) -- buffer has 2 lines now, the file still 5
  local in_buf = #D.fit(b, { dg(0), dg(1), dg(2), dg(4) })
  local nofile = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(nofile, TMP .. "/never-written.txt")
  vim.cmd("bunload! " .. nofile)
  local unchanged = #D.fit(nofile, { dg(2), dg(900) })
  lsp.report(P .. "fit_file", on_disk == 2 and in_buf == 2 and unchanged == 2, ("unloaded->file %d (want 2), loaded->buffer %d (want 2), no file %d (want 2)"):format(on_disk, in_buf, unchanged))
end)

case("our_paths", function()
  local root = vim.fn.fnamemodify(vim.env.NV4J_FIXTURE or ".", ":p"):gsub("/tests/fixtures/demo/?$", "")
  local function src(p) local fh = io.open(root .. "/nvim/lua/nv4j/" .. p) local s = fh and fh:read("*a") or "" if fh then fh:close() end return s end
  local t, u, i = src("tests.lua"), src("unused_imports.lua"), io.open(root .. "/nvim/init.lua")
  local init = i and i:read("*a") or ""
  if i then i:close() end
  local ok_t = t:find('diagfix").fit(b, ds)', 1, true) ~= nil
  local ok_u = u:find('diagfix").fit(buf, diags)', 1, true) ~= nil
  local ok_i = init:find('require("nv4j.diagfix").setup()', 1, true) ~= nil
  lsp.report(P .. "our_paths", ok_t and ok_u and ok_i, ("tests.lua %s, unused_imports.lua %s, init.lua %s"):format(tostring(ok_t), tostring(ok_u), tostring(ok_i)))
end)

case("idempotent", function()
  local before = vim.diagnostic.handlers.underline
  local r = D.setup()
  lsp.report(P .. "idempotent", r == false and vim.diagnostic.handlers.underline == before, "second setup returned " .. tostring(r))
end)

vim.fn.delete(TMP, "rf")
lsp.finish()
