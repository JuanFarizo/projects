-- P3 refactors. Run via tests/run.sh. Spec: specs/features/refactors.md (decision D23 in
-- specs/001-architecture.md). Product: nvim/lua/nv4j/refactor.lua (P3 Task 4).
-- Budget (P3 plan, not weakened): each refactor applied <= 2 s on the fixture, all references and
-- imports right, the build clean afterwards (no jdt.ls error in the touched files <= 3 s after the
-- edit), and one `u` per touched buffer gives its text back.
-- Fixture: demo.billing.{Invoice, PriceCalculator}, demo.shop.Checkout (call sites in another package).
-- API under test (Task 4): require("nv4j.refactor").<fn>(opts) at the cursor, no prompts when opts
-- give the answer: rename_class({ name }), move({ package }), inline(), change_signature({ add = {
-- { type, name, default } } }), safe_delete(). Until it exists, each case measures today's path:
-- vim.lsp.buf.rename (<leader>cr) or jdt.ls's code action through Neovim/nvim-jdtls (<leader>ca), with
-- the prompts nvim-jdtls opens answered by the check.
--  api, keys          : the module and the proposed keys (<leader>jm move, <leader>ji inline,
--                       <leader>js change signature, <leader>jd safe delete, <leader>jr refactor menu;
--                       <leader>cr stays Rename).
--  rename_class       : Invoice -> Bill from its declaration: Bill.java on disk, Invoice.java gone,
--                       Checkout imports demo.billing.Bill, no `Invoice` token left; build clean.
--  rename_class_undo  : one `u` in each touched buffer gives back its text before the rename.
--  move_class         : Invoice to package demo.shop: demo/shop/Invoice.java, Checkout's import gone,
--                       PriceCalculator imports demo.shop.Invoice; build clean.
--  rename_package     : demo.shop -> demo.store from Checkout's package line: demo/store/Checkout.java.
--  inline_method      : `gross(invoice)` call in total inlined: `invoice.quantity() * invoice.unitPrice()`.
--  inline_variable    : local `gross` in total inlined: `return gross(invoice);`.
--  change_signature   : total gets `int discount` with default 0: the 3 call sites in Checkout pass 0.
--  safe_delete_blocked: on `total` (3 usages): nothing deleted, the usages listed (quickfix).
--  safe_delete_free   : on `legacyTotal` (no usages): the method is gone, build clean.
-- The fixture is snapshot before and restored after every case (tests/lib/fixture.lua), jdt.ls told.
-- Timings: /tmp/nv4j/logs/latency.jsonl (refactor_*).
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local F = require("fixture")
local P = "62_refactor."
local APPLY_MS, CLEAN_MS = 2000, 3000

local fixture = vim.env.NV4J_FIXTURE
local main = fixture .. "/src/main/java/"
local INVOICE = main .. "demo/billing/Invoice.java"
local CALC = main .. "demo/billing/PriceCalculator.java"
local CHECKOUT = main .. "demo/shop/Checkout.java"
local snap = F.snapshot()

local published_at = {}
local orig_pd = vim.lsp.handlers["textDocument/publishDiagnostics"]
vim.lsp.handlers["textDocument/publishDiagnostics"] = function(e, result, ctx, cfg)
  if result and result.uri then published_at[result.uri] = E.now() end
  return orig_pd(e, result, ctx, cfg)
end

local buf0 = lsp.open(CALC)
local client = lsp.wait_ready(buf0, 120000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready" or "jdtls not ready")
if not client then return lsp.finish() end
pcall(require, "config.keymaps")

local ok_mod, refactor = pcall(require, "nv4j.refactor")
local FNS = { "rename_class", "move", "inline", "change_signature", "safe_delete" }
local missing = {}
for _, f in ipairs(FNS) do
  if not (ok_mod and type(refactor) == "table" and type(refactor[f]) == "function") then missing[#missing + 1] = f end
end
local api = #missing == 0
lsp.report(P .. "api", api, api and "nv4j.refactor: all 5" or ("nv4j.refactor missing: " .. table.concat(missing, ", ")))

do
  vim.api.nvim_set_current_buf(buf0)
  local want = { ["<leader>jm"] = "Move", ["<leader>ji"] = "Inline", ["<leader>js"] = "ignature", ["<leader>jd"] = "elete",
    ["<leader>jr"] = "efactor" }
  local bad = {}
  for lhs, word in pairs(want) do
    local m = E.keymap(lhs, buf0)
    if not (m and m.desc and m.desc:find(word)) then bad[#bad + 1] = lhs .. "=" .. tostring(m and (m.desc or "no desc") or "unmapped") end
  end
  local cr = E.keymap("<leader>cr", buf0) or {}
  local cr_ok = (cr.desc or ""):find("Rename") ~= nil
  table.sort(bad)
  lsp.report(P .. "keys", #bad == 0 and cr_ok,
    ("%s; <leader>cr=%s"):format(#bad == 0 and "all mapped" or ("wrong: " .. table.concat(bad, ", ")), tostring(cr.desc)))
end

--- 0-based (line, col) of `word` in the first line matching the Lua pattern `pat`.
local function pos(buf, pat, word)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:find(pat) then
      local c = l:find(word, 1, true)
      if c then return i - 1, c - 1 end
    end
  end
  error(("'%s' not found on a line matching '%s'"):format(word, pat))
end

local function text_of(path)
  local b = vim.fn.bufnr(path)
  if b ~= -1 and vim.api.nvim_buf_is_loaded(b) then return E.text(b), b end
  return vim.uv.fs_stat(path) and table.concat(vim.fn.readfile(path), "\n") or nil, nil
end

--- Answer the next vim.ui.select with the item whose label contains `want` (nvim-jdtls prompts).
local function answer_select(want)
  local real = vim.ui.select
  local seen = {}
  vim.ui.select = function(items, opts, cb)
    vim.ui.select = real
    for _, it in ipairs(items) do
      local label = opts and opts.format_item and opts.format_item(it) or tostring(it)
      seen[#seen + 1] = label
      if label:find(want, 1, true) then return cb(it) end
    end
    cb(nil)
  end
  return seen
end

--- Apply the code action whose title matches `pat` at (l, c) of `buf` the way <leader>ca does.
local function code_action(buf, l, c, pat)
  local r = E.code_actions(client, buf, l, c, l, c)
  local a = r.actions and E.find(r.actions, pat)
  if not a then return false, "no code action matching '" .. pat .. "': " .. E.titles(r.actions or {}) end
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local taken = false
  vim.lsp.buf.code_action({ apply = true, filter = function(x)
    if taken or not x.title:find(pat) then return false end
    taken = true
    return true
  end })
  return true, a.title
end

--- Waits for `cond`; returns ok, ms since t0.
local function until_ms(t0, cond, ms)
  local ok = vim.wait(ms or (APPLY_MS + 3000), function()
    local ok2, v = pcall(cond)
    return ok2 and v
  end, 5)
  return ok, E.now() - t0
end

--- Build clean: every path has a jdt.ls publish after t_edit and no ERROR, within CLEAN_MS.
local function clean(paths, t_edit)
  local detail = {}
  local ok = vim.wait(CLEAN_MS, function()
    for _, p in ipairs(paths) do
      local b = vim.fn.bufnr(p)
      if b == -1 then return false end
      local uri = vim.uri_from_fname(p)
      if (published_at[uri] or 0) < t_edit then return false end
      if E.count(vim.diagnostic.get(b), vim.diagnostic.severity.ERROR) > 0 then return false end
    end
    return true
  end, 20)
  if not ok then
    for _, p in ipairs(paths) do
      local b = vim.fn.bufnr(p)
      local errs = b ~= -1 and vim.tbl_filter(function(d) return d.severity == vim.diagnostic.severity.ERROR end, vim.diagnostic.get(b)) or {}
      detail[#detail + 1] = vim.fs.basename(p) .. ": " .. (b == -1 and "no buffer" or
        ((published_at[vim.uri_from_fname(p)] or 0) < t_edit and "no publish after the edit" or (#errs .. " error(s) " .. E.fmt(errs))))
    end
  end
  return ok, table.concat(detail, "; ")
end

local function word_count(txt, w)
  local n = 0
  for _ in (txt or ""):gmatch("%f[%w_]" .. w .. "%f[^%w_]") do n = n + 1 end
  return n
end

local function report_apply(name, how, applied, ms, checks, clean_ok, clean_detail)
  E.log("refactor_" .. name, applied and ms or -1, 1)
  local all = applied and ms <= APPLY_MS and clean_ok
  local parts = {}
  for _, c in ipairs(checks) do
    all = all and c[2]
    parts[#parts + 1] = c[1] .. " " .. (c[2] and "ok" or "WRONG")
  end
  lsp.report(P .. name, all, ("%s: %s after %.0f ms (budget %d); %s; build %s"):format(how, applied and "applied" or "NOT applied",
    ms, APPLY_MS, table.concat(parts, ", "), clean_ok and "clean" or ("NOT clean: " .. (clean_detail or "?"))))
end

local function case(name, fn)
  local ok, err = pcall(fn)
  if not ok then lsp.report(P .. name, false, "error: " .. tostring(err)) end
  vim.cmd.stopinsert()
  F.restore(snap, client)
end

-- rename_class (+ undo)
case("rename_class", function()
  local inv, chk, calc = lsp.open(INVOICE), lsp.open(CHECKOUT), lsp.open(CALC)
  local before = { [chk] = E.text(chk), [calc] = E.text(calc), [inv] = E.text(inv) }
  vim.api.nvim_set_current_buf(inv)
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local BILL = main .. "demo/billing/Bill.java"
  local t0, how = E.now(), nil
  if api then how = "nv4j.refactor.rename_class"; refactor.rename_class({ name = "Bill" })
  else how = "vim.lsp.buf.rename (<leader>cr)"; vim.lsp.buf.rename("Bill") end
  local applied, ms = until_ms(t0, function()
    local ct = text_of(CHECKOUT)
    return vim.uv.fs_stat(BILL) ~= nil and ct:find("import demo.billing.Bill;", 1, true) ~= nil
  end)
  local ct, pt, bt = text_of(CHECKOUT), text_of(CALC), text_of(BILL)
  local ok_clean, why = clean({ CHECKOUT, CALC, BILL }, t0)
  report_apply("rename_class", how, applied, ms, {
    { "Invoice.java gone", vim.uv.fs_stat(INVOICE) == nil },
    { "Bill.java declares Bill", bt ~= nil and bt:find("public class Bill", 1, true) ~= nil },
    { "no Invoice token left", word_count(ct, "Invoice") + word_count(pt, "Invoice") + word_count(bt, "Invoice") == 0 },
  }, ok_clean, why)
  -- undo: one `u` per touched buffer
  local bad = {}
  for b, txt in pairs(before) do
    local bb = vim.api.nvim_buf_is_valid(b) and b or vim.fn.bufnr(BILL)
    if bb ~= -1 and vim.api.nvim_buf_is_valid(bb) then
      vim.api.nvim_buf_call(bb, function() vim.cmd("silent! undo") end)
      if E.text(bb) ~= txt then bad[#bad + 1] = vim.fs.basename(vim.api.nvim_buf_get_name(bb)) end
    else
      bad[#bad + 1] = "buffer gone"
    end
  end
  lsp.report(P .. "rename_class_undo", applied and #bad == 0,
    applied and (#bad == 0 and "one u restored every touched buffer" or ("not restored by one u: " .. table.concat(bad, ", ")))
      or "rename not applied, nothing to undo")
end)

-- move_class
case("move_class", function()
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT); lsp.open(CALC)
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  local MOVED = main .. "demo/shop/Invoice.java"
  local t0, how, applied, ms = E.now(), nil, false, 0
  if api then
    vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { l + 1, c })
    how = "nv4j.refactor.move"; refactor.move({ package = "demo.shop" })
  else
    local seen = answer_select("demo.shop")
    local ok, title = code_action(inv, l, c, "^Move")
    if not ok then return report_apply("move_class", title, false, 0, {}, false, "") end
    applied = vim.wait(5000, function() return #seen > 0 end, 5)
    how = ("code action %s (nvim-jdtls destination prompt %s)"):format(title,
      applied and ("answered 'demo.shop' among: " .. table.concat(seen, " | ")) or "NEVER shown")
  end
  applied, ms = until_ms(t0, function() return vim.uv.fs_stat(MOVED) ~= nil and (text_of(CALC) or ""):find("import demo.shop.Invoice;", 1, true) ~= nil end)
  local ct = text_of(CHECKOUT)
  local ok_clean, why = clean({ CHECKOUT, CALC, MOVED }, t0)
  report_apply("move_class", how, applied, ms, {
    { "billing/Invoice.java gone", vim.uv.fs_stat(INVOICE) == nil },
    { "Checkout import dropped", ct ~= nil and not ct:find("import demo.billing.Invoice;", 1, true) },
    { "package line", (text_of(MOVED) or ""):find("package demo.shop;", 1, true) ~= nil },
  }, ok_clean, why)
end)

-- rename_package
case("rename_package", function()
  local chk = lsp.open(CHECKOUT)
  lsp.open(CALC)
  local l, c = pos(chk, "^package demo%.shop;", "shop")
  vim.api.nvim_set_current_buf(chk); vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local MOVED = main .. "demo/store/Checkout.java"
  local t0, how = E.now(), "vim.lsp.buf.rename (<leader>cr) on the package name"
  local function moved() return vim.uv.fs_stat(MOVED) ~= nil and (text_of(MOVED) or ""):find("package demo.store;", 1, true) ~= nil end
  local applied, ms
  if api and refactor.rename_package then
    how = "nv4j.refactor.rename_package"; refactor.rename_package({ name = "demo.store" })
    applied, ms = until_ms(t0, moved)
  else
    vim.lsp.buf.rename("demo.store")
    applied, ms = until_ms(t0, moved, APPLY_MS + 1000)
    if not applied then
      -- today's other path: rename the folder in neo-tree. LazyVim's neo-tree extra then calls
      -- Snacks.rename.on_rename_file(old, new) AFTER the folder moved (FILE_RENAMED event):
      -- willRenameFiles (1 s request_sync), apply its edit, didRenameFiles.
      local old_dir, new_dir = main .. "demo/shop", main .. "demo/store"
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(b):find(old_dir, 1, true) then pcall(vim.api.nvim_buf_delete, b, { force = true }) end
      end
      t0 = E.now()
      assert(vim.uv.fs_rename(old_dir, new_dir))
      Snacks.rename.on_rename_file(old_dir, new_dir)
      applied, ms = until_ms(t0, moved)
      how = how .. " (prepareRename refused) then the neo-tree folder rename path (Snacks.rename.on_rename_file after the move)"
    end
  end
  local ok_clean, why = clean({ MOVED }, t0)
  report_apply("rename_package", how, applied, ms, {
    { "shop/Checkout.java gone", vim.uv.fs_stat(CHECKOUT) == nil },
    { "package line", (text_of(MOVED) or ""):find("package demo.store;", 1, true) ~= nil },
  }, ok_clean, why)
end)

--- Inline at (pat, word) in PriceCalculator; `want` must appear in the file afterwards.
local function inline_case(name, pat, word, title, want, gone)
  case(name, function()
    local calc = lsp.open(CALC)
    lsp.open(CHECKOUT)
    local l, c = pos(calc, pat, word)
    local before = E.text(calc)
    local t0, how = E.now(), nil
    if api then
      vim.api.nvim_set_current_buf(calc); vim.api.nvim_win_set_cursor(0, { l + 1, c })
      how = "nv4j.refactor.inline"; refactor.inline()
    else
      local ok, t = code_action(calc, l, c, title)
      how = "code action " .. tostring(t)
      if not ok then return report_apply(name, how, false, 0, {}, false, "") end
    end
    local applied, ms = until_ms(t0, function() return E.text(calc) ~= before and E.text(calc):find(want, 1, true) ~= nil end)
    local ok_clean, why = clean({ CALC }, t0)
    report_apply(name, how, applied, ms, { { "`" .. gone .. "` gone", not E.text(calc):find(gone, 1, true) } }, ok_clean, why)
  end)
end
inline_case("inline_method", "int gross = gross%(invoice%);", "gross(", "^Inline [Mm]ethod",
  "int gross = invoice.quantity() * invoice.unitPrice();", "= gross(invoice)")
inline_case("inline_variable", "^%s+return gross;", "gross", "^Inline local variable", "return gross(invoice);", "int gross =")

-- change_signature
case("change_signature", function()
  local calc = lsp.open(CALC)
  lsp.open(CHECKOUT)
  local l, c = pos(calc, "public int total%(Invoice invoice%)", "total")
  local t0, how = E.now(), nil
  if api then
    vim.api.nvim_set_current_buf(calc); vim.api.nvim_win_set_cursor(0, { l + 1, c })
    how = "nv4j.refactor.change_signature"; refactor.change_signature({ add = { { type = "int", name = "discount", default = "0" } } })
  else
    local ok, t = code_action(calc, l, c, "^Change signature")
    how = "code action " .. tostring(t)
    if not ok then return report_apply("change_signature", how, false, 0, {}, false, "") end
    -- nvim-jdtls opens an editable float (Parameters list); fill it as a user would and close it
    local opened = vim.wait(5000, function() return vim.api.nvim_get_current_buf() ~= calc end, 5)
    local pb = vim.api.nvim_get_current_buf()
    local pl = opened and E.line_of(pb, "^%- 0: Invoice invoice")
    if not pl then return report_apply("change_signature", how .. " (no prompt buffer with the parameter list)", false, E.now() - t0, {}, false, "") end
    how = how .. " (nvim-jdtls float prompt filled: '- int discount 0', then closed)"
    vim.api.nvim_buf_set_lines(pb, pl + 1, pl + 1, false, { "- int discount 0" })
    vim.cmd("close")
  end
  local applied, ms = until_ms(t0, function() return (text_of(CHECKOUT) or ""):find("calculator.total(invoice, 0)", 1, true) ~= nil end)
  local ct, pt = text_of(CHECKOUT), text_of(CALC)
  local n0 = select(2, (ct or ""):gsub(", 0%)", ""))
  local ok_clean, why = clean({ CHECKOUT, CALC }, t0)
  report_apply("change_signature", how, applied, ms, {
    { "declaration", (pt or ""):find("total(Invoice invoice, int discount)", 1, true) ~= nil },
    { ("3 call sites pass 0 (%d)"):format(n0), n0 == 3 },
  }, ok_clean, why)
end)

-- safe delete
local function safe_delete_case(name, pat, word, blocked)
  case(name, function()
    local calc = lsp.open(CALC)
    lsp.open(CHECKOUT)
    local l, c = pos(calc, pat, word)
    local before = E.text(calc)
    if not api then
      local r = E.code_actions(client, calc, l, c, l, c)
      local a = E.find(r.actions or {}, "[Dd]elete")
      return lsp.report(P .. name, false, ("no nv4j.refactor.safe_delete; jdt.ls code actions at `%s`: %s%s"):format(word,
        E.titles(r.actions or {}), a and "" or " (no delete action)"))
    end
    vim.fn.setqflist({}, "r", { title = "", items = {} })
    vim.api.nvim_set_current_buf(calc); vim.api.nvim_win_set_cursor(0, { l + 1, c })
    local t0 = E.now()
    refactor.safe_delete()
    if blocked then
      local listed, ms = until_ms(t0, function() return #vim.fn.getqflist() >= 3 end)
      local same = E.text(calc) == before
      local qf = vim.fn.getqflist()
      lsp.report(P .. name, listed and same and ms <= APPLY_MS, ("%.0f ms; text %s; quickfix %d usage(s): %s"):format(ms,
        same and "unchanged" or "CHANGED", #qf, table.concat(vim.tbl_map(function(q) return vim.fs.basename(vim.api.nvim_buf_get_name(q.bufnr)) .. ":" .. q.lnum end, qf), ",")))
    else
      local applied, ms = until_ms(t0, function() return not E.text(calc):find(word, 1, true) end)
      local ok_clean, why = clean({ CALC }, t0)
      report_apply(name, "nv4j.refactor.safe_delete", applied, ms, {}, ok_clean, why)
    end
  end)
end
safe_delete_case("safe_delete_blocked", "public int total%(Invoice invoice%)", "total", true)
safe_delete_case("safe_delete_free", "public int legacyTotal%(", "legacyTotal", false)

local left = F.diff(snap)
lsp.report(P .. "fixture_restored", #left.added + #left.changed + #left.missing == 0, "left: " .. F.fmt(left))
lsp.finish()
