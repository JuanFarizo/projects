-- P3 refactors. Run via tests/run.sh. Spec: specs/features/refactors.md (decision D23 in
-- specs/001-architecture.md). Product: nvim/lua/nv4j/refactor.lua (P3 Task 4).
-- Budget (P3 plan, not weakened): each refactor applied <= 2 s on the fixture, all references and
-- imports right, the build clean afterwards (no jdt.ls error in the touched files <= 3 s after the
-- edit), and one `u` per touched buffer gives its text back.
-- Fixture: demo.billing.{Invoice, PriceCalculator}, demo.shop.Checkout (call sites in another package).
-- API under test (Task 4): require("nv4j.refactor").<fn>(opts) at the cursor, no prompts when opts
-- give the answer: rename_class({ name }), rename_package({ name }) (Task 4a, built), move({ package }),
-- inline(), change_signature({ add = { { type, name, default } } }), safe_delete() (4b-4e). Each case
-- uses its function when it exists, else measures today's path: vim.lsp.buf.rename (<leader>cr) or
-- jdt.ls's code action through Neovim/nvim-jdtls (<leader>ca), with nvim-jdtls's prompts answered.
--  api, keys          : the functions built so far and their keys (<leader>jr rename, <leader>jp rename
--                       package; pending: <leader>jm move, <leader>ji inline, <leader>js change
--                       signature, <leader>jd safe delete, listed); <leader>cr stays Rename.
--  rename_class       : Invoice -> Bill from its declaration: Bill.java on disk, Invoice.java gone,
--                       Checkout imports demo.billing.Bill, no `Invoice` token left, touched files
--                       written, summary names them; build clean.
--  rename_class_undo  : one `u` in each touched buffer gives back its text before the rename.
--  rename_class_unsaved: unsaved user edits in Checkout and in Invoice itself survive; Checkout left
--                       unsaved, Bill written by the rename, the summary says both.
--  rename_class_conflict: Invoice -> PriceCalculator: refused with a message, nothing changed.
--  rename_class_boot  : GreetingController (@RestController) -> HelloController; build clean.
--  rename_class_errors: a syntax error in Checkout (jdt.ls then skips its references): the summary
--                       warning names Checkout.java:3. _twin: refactor.new_errors on a planted error.
--  move_class         : Invoice to package demo.shop: demo/shop/Invoice.java, Checkout's import gone,
--                       PriceCalculator imports demo.shop.Invoice; build clean.
--  rename_package     : demo.shop -> demo.store from Checkout's package line: demo/store/Checkout.java,
--                       package line on disk, buffer re-pointed, summary; build clean.
--  rename_package_imports: demo.billing -> demo.invoicing (src/main and src/test folders), package and
--                       import lines, no same-package imports added, unsaved user edits kept.
--  rename_package_fallback: twin of the retry in _imports: jdt.ls stubbed null for src/test/java.
--  rename_package_conflict: into an existing package / into itself: refused, nothing changed.
--  neotree_rename_package, neotree_rename_file: neo-tree's own rename_node (prompt answered): package
--                       line / class and references follow, LazyVim's after-the-move hook not run.
--  rename_package_first_null: jdt.ls stubbed null for the first root: refused, nothing changed.
--  rename_class_strings: JPQL/class-name strings and a properties value naming Invoice: listed in a
--                       warning, not rewritten.
--  neotree_rename_billing: neo-tree folder rename with a src/test/java namesake: both folders move.
--  neotree_refused    : a refused neo-tree rename: nothing moves, buffers intact, no success toast.
--  jr_package_line, prompt_class: <leader>jr on a `package` line; the prompt when no name is given.
--  rename_package_no_type: package-info.java only, jdt.ls null: moved with the package line by text + NOTE.
--  neotree_placeholder: the refusal placeholder: kept 1 s after the last refusal, VimLeavePre removes it,
--                       an existing destination folder is never written into.
--  Unbuilt functions (move, inline, change_signature, safe_delete): their cases FAIL "pending" (today's
--  path shown after it) and `api` adds a pending_<fn> FAIL line each: the check stays red until 4e.
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
-- Built per function (Task 4 is split: 4a rename class/package, 4b move, 4c inline, 4d change
-- signature, 4e safe delete): each case uses its function when it exists, else today's path; `api` and
-- `keys` check the built ones and list the rest as pending (a pending case still fails on its own).
local FNS = { "rename_class", "rename_package", "move", "inline", "change_signature", "safe_delete" }
local function has(f) return ok_mod and type(refactor) == "table" and type(refactor[f]) == "function" end
-- Unbuilt functions fail visibly (ruling, Task 4a fix round 1): the check stays red until 4e. Their cases
-- still run today's path and show it after the pending reason, but never PASS through plain jdt.ls.
local TASK = { rename_class = "4a", rename_package = "4a", move = "4b", inline = "4c", change_signature = "4d", safe_delete = "4e" }
local KEY = { rename_class = "<leader>jr", rename_package = "<leader>jp", move = "<leader>jm", inline = "<leader>ji",
  change_signature = "<leader>js", safe_delete = "<leader>jd" }
local CASE_FN = { move_class = "move", inline_method = "inline", inline_variable = "inline", change_signature = "change_signature",
  safe_delete_blocked = "safe_delete", safe_delete_free = "safe_delete" }
local function pending_reason(f) return ("pending: nv4j.refactor.%s not built (Task %s)"):format(f, TASK[f]) end
do
  local real_report = lsp.report
  lsp.report = function(name, ok, detail)
    local fn = CASE_FN[name:sub(#P + 1)]
    if fn and not has(fn) then return real_report(name, false, pending_reason(fn) .. "; today's path: " .. tostring(detail)) end
    return real_report(name, ok, detail)
  end
end
do
  local built, pending = {}, {}
  for _, f in ipairs(FNS) do
    if has(f) then built[#built + 1] = f else pending[#pending + 1] = f end
  end
  lsp.report(P .. "api", #built > 0, ok_mod and ("nv4j.refactor built: %s; pending: %s"):format(
    #built > 0 and table.concat(built, ", ") or "none", #pending > 0 and table.concat(pending, ", ") or "none")
    or ("nv4j.refactor does not load: " .. tostring(refactor)))
  for _, f in ipairs(pending) do
    lsp.report(P .. "pending_" .. f, false, pending_reason(f) .. "; key " .. KEY[f] .. " not mapped")
  end
end

do
  vim.api.nvim_set_current_buf(buf0)
  local want = {
    { "<leader>jr", "rename_class", "ename" }, { "<leader>jp", "rename_package", "ackage" },
    { "<leader>jm", "move", "Move" }, { "<leader>ji", "inline", "Inline" }, { "<leader>js", "change_signature", "ignature" },
    { "<leader>jd", "safe_delete", "elete" },
  }
  local bad, okk, pending = {}, {}, {}
  for _, w in ipairs(want) do
    local lhs, fn, word = w[1], w[2], w[3]
    if has(fn) then
      local m = E.keymap(lhs, buf0)
      if m and m.desc and m.desc:find(word) then okk[#okk + 1] = lhs
      else bad[#bad + 1] = lhs .. "=" .. tostring(m and (m.desc or "no desc") or "unmapped") end
    else
      pending[#pending + 1] = lhs .. " (" .. fn .. ")"
    end
  end
  local cr = E.keymap("<leader>cr", buf0) or {}
  local cr_ok = (cr.desc or ""):find("Rename") ~= nil
  lsp.report(P .. "keys", #okk > 0 and #bad == 0 and cr_ok,
    ("mapped: %s%s; pending: %s; <leader>cr=%s"):format(#okk > 0 and table.concat(okk, ", ") or "none",
      #bad > 0 and ("; WRONG: " .. table.concat(bad, ", ")) or "", #pending > 0 and table.concat(pending, ", ") or "none",
      tostring(cr.desc)))
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

--- vim.notify messages from now until stop() (the summary and warnings the user sees).
local function capture()
  local got, orig = {}, vim.notify
  vim.notify = function(msg, level, o)
    got[#got + 1] = { msg = tostring(msg), level = level }
    return orig(msg, level, o)
  end
  return got, function() vim.notify = orig end
end

local function find_msg(got, pat, level)
  for _, m in ipairs(got) do
    if m.msg:find(pat, 1, true) and (level == nil or m.level == level) then return m.msg end
  end
end

--- File content on disk, raw (as the snapshot holds it).
local function disk(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

--- Loaded buffer named `path`, or nil.
local function loaded(path)
  local b = vim.fn.bufnr(path)
  return b ~= -1 and vim.api.nvim_buf_is_loaded(b) and b or nil
end

local function rel_src(p) return (p:gsub("^.*/src/", "src/")) end

local function append_line(buf, line)
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { line })
end

local BILL = main .. "demo/billing/Bill.java"

-- rename_class (+ undo)
case("rename_class", function()
  local inv, chk, calc = lsp.open(INVOICE), lsp.open(CHECKOUT), lsp.open(CALC)
  local before = { [chk] = E.text(chk), [calc] = E.text(calc), [inv] = E.text(inv) }
  vim.api.nvim_set_current_buf(inv)
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local got, stop = capture()
  local t0, how = E.now(), nil
  if has("rename_class") then how = "nv4j.refactor.rename_class"; refactor.rename_class({ name = "Bill" })
  else how = "vim.lsp.buf.rename (<leader>cr)"; vim.lsp.buf.rename("Bill") end
  local applied, ms = until_ms(t0, function()
    local ct = text_of(CHECKOUT)
    return vim.uv.fs_stat(BILL) ~= nil and ct:find("import demo.billing.Bill;", 1, true) ~= nil
  end)
  stop()
  local ct, pt, bt = text_of(CHECKOUT), text_of(CALC), text_of(BILL)
  local ok_clean, why = clean({ CHECKOUT, CALC, BILL }, t0)
  local sum = find_msg(got, "Renamed class Invoice -> Bill") or ""
  report_apply("rename_class", how, applied, ms, {
    { "Invoice.java gone", vim.uv.fs_stat(INVOICE) == nil },
    { "Bill.java declares Bill", bt ~= nil and bt:find("public class Bill", 1, true) ~= nil },
    { "no Invoice token left", word_count(ct, "Invoice") + word_count(pt, "Invoice") + word_count(bt, "Invoice") == 0 },
    { "written to disk", (disk(CHECKOUT) or ""):find("import demo.billing.Bill;", 1, true) ~= nil
      and word_count(disk(CALC), "Invoice") == 0 and (disk(BILL) or ""):find("public class Bill", 1, true) ~= nil },
    { "summary lists Bill, Checkout, PriceCalculator", sum:find("Bill.java (from", 1, true) ~= nil
      and sum:find("Checkout.java", 1, true) ~= nil and sum:find("PriceCalculator.java", 1, true) ~= nil },
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

-- rename_class_unsaved: unsaved user edits in a referencing file and in the renamed file itself survive;
-- the referencing file stays unsaved (its edits are the user's to save), the summary says so.
case("rename_class_unsaved", function()
  if not has("rename_class") then return lsp.report(P .. "rename_class_unsaved", false, "pending: no nv4j.refactor.rename_class") end
  local inv, chk = lsp.open(INVOICE), lsp.open(CHECKOUT)
  lsp.open(CALC)
  append_line(chk, "// user edit in Checkout")
  append_line(inv, "// user edit in Invoice")
  vim.api.nvim_set_current_buf(inv)
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local got, stop = capture()
  local t0 = E.now()
  refactor.rename_class({ name = "Bill" })
  local applied, ms = until_ms(t0, function()
    return vim.uv.fs_stat(BILL) ~= nil and (text_of(CHECKOUT) or ""):find("import demo.billing.Bill;", 1, true) ~= nil
  end)
  stop()
  local ok_clean, why = clean({ CHECKOUT, CALC, BILL }, t0)
  local ct, bt = text_of(CHECKOUT), text_of(BILL)
  local sum = find_msg(got, "Renamed class Invoice -> Bill") or ""
  report_apply("rename_class_unsaved", "nv4j.refactor.rename_class", applied, ms, {
    { "Checkout keeps the user edit", (ct or ""):find("// user edit in Checkout", 1, true) ~= nil },
    { "Checkout left unsaved (disk untouched)", loaded(CHECKOUT) ~= nil and vim.bo[loaded(CHECKOUT)].modified
      and disk(CHECKOUT) == snap.files[CHECKOUT] },
    { "Bill keeps the user edit", (bt or ""):find("// user edit in Invoice", 1, true) ~= nil and bt:find("public class Bill", 1, true) ~= nil },
    { "no buffer left on Invoice.java", loaded(INVOICE) == nil and vim.uv.fs_stat(INVOICE) == nil },
    { "summary: Checkout left unsaved, Bill written", sum:find("Checkout.java [left unsaved", 1, true) ~= nil
      and sum:find("Bill.java (from src/main/java/demo/billing/Invoice.java) [written with your unsaved changes]", 1, true) ~= nil },
    { "Bill.java on disk has the user edit", (disk(BILL) or ""):find("// user edit in Invoice", 1, true) ~= nil },
  }, ok_clean, why)
end)

-- rename_class_conflict: Invoice -> PriceCalculator (exists in the package): refused, nothing changed.
case("rename_class_conflict", function()
  if not has("rename_class") then return lsp.report(P .. "rename_class_conflict", false, "pending: no nv4j.refactor.rename_class") end
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT); lsp.open(CALC)
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local got, stop = capture()
  refactor.rename_class({ name = "PriceCalculator" })
  local msg
  vim.wait(APPLY_MS, function()
    msg = find_msg(got, "already exists", vim.log.levels.ERROR)
    return msg ~= nil
  end, 10)
  vim.wait(500) -- nothing must land after the message either
  stop()
  local d = F.diff(snap)
  local dirty = {}
  for _, p in ipairs({ INVOICE, CHECKOUT, CALC }) do
    local b = loaded(p)
    if not b or vim.bo[b].modified then dirty[#dirty + 1] = vim.fs.basename(p) end
  end
  lsp.report(P .. "rename_class_conflict", msg ~= nil and #d.added + #d.changed + #d.missing == 0 and #dirty == 0,
    ("message: %s; disk %s; buffers %s"):format(tostring(msg), F.fmt(d),
      #dirty == 0 and "unchanged" or ("CHANGED/gone: " .. table.concat(dirty, ", "))))
end)

-- rename_class_boot: a Spring controller (GreetingController -> HelloController): file renamed, the
-- annotation and mapping kept, build clean.
case("rename_class_boot", function()
  if not has("rename_class") then return lsp.report(P .. "rename_class_boot", false, "pending: no nv4j.refactor.rename_class") end
  local GC, HC = main .. "demo/GreetingController.java", main .. "demo/HelloController.java"
  local b = lsp.open(GC)
  local l, c = pos(b, "^public class GreetingController", "GreetingController")
  vim.api.nvim_set_current_buf(b); vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local t0 = E.now()
  refactor.rename_class({ name = "HelloController" })
  local applied, ms = until_ms(t0, function() return (disk(HC) or ""):find("public class HelloController", 1, true) ~= nil end)
  local ok_clean, why = clean({ HC }, t0)
  local ht = disk(HC) or ""
  report_apply("rename_class_boot", "nv4j.refactor.rename_class", applied, ms, {
    { "GreetingController.java gone", vim.uv.fs_stat(GC) == nil and loaded(GC) == nil },
    { "@RestController and @GetMapping kept", ht:find("@RestController\npublic class HelloController", 1, true) ~= nil
      and ht:find('@GetMapping("/hello")', 1, true) ~= nil },
  }, ok_clean, why)
end)

-- rename_class_errors: a syntax error already in a referencing file (Checkout, unsaved): jdt.ls renames
-- but skips that file's references (measured), so the rename must not look clean: the summary is a
-- warning naming Checkout.java:3 (its import still names the old class, found from the text). The
-- follow-up from jdt.ls's errors is shown in the detail, not required (jdt.ls does not always publish).
-- Twin (deterministic): the module's error reader on an error set in a check namespace.
case("rename_class_errors", function()
  if not has("rename_class") then
    lsp.report(P .. "rename_class_errors_twin", false, "pending: no nv4j.refactor.rename_class")
    return lsp.report(P .. "rename_class_errors", false, "pending: no nv4j.refactor.rename_class")
  end
  local inv, chk = lsp.open(INVOICE), lsp.open(CHECKOUT)
  lsp.open(CALC)
  local bl = E.line_of(chk, "^public class Checkout")
  vim.api.nvim_buf_set_lines(chk, bl + 1, bl + 1, false, { "    int broken = ;" })
  -- the syntax error is published before the rename (it is "before", not new)
  local tset = E.now()
  vim.wait(CLEAN_MS, function()
    return (published_at[vim.uri_from_fname(CHECKOUT)] or 0) >= tset and E.count(vim.diagnostic.get(chk), vim.diagnostic.severity.ERROR) > 0
  end, 20)
  local before = refactor.error_counts()
  vim.api.nvim_set_current_buf(inv)
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local got, stop = capture()
  local t0 = E.now()
  refactor.rename_class({ name = "Bill" })
  local applied, ms = until_ms(t0, function() return vim.uv.fs_stat(BILL) ~= nil and loaded(BILL) ~= nil end)
  local sum = find_msg(got, "Renamed class Invoice -> Bill: ", vim.log.levels.WARN) or ""
  -- the follow-up (jdt.ls's own errors, 3 s / 8 s) is reported, not required: in 2 of 11 runs jdt.ls never
  -- published Checkout's new errors at all (log in specs/features/refactors.md)
  local warn
  vim.wait(10000, function()
    warn = find_msg(got, "Renamed class Invoice -> Bill applied, but", vim.log.levels.WARN)
    return warn ~= nil
  end, 20)
  stop()
  local ct = text_of(CHECKOUT) or ""
  lsp.report(P .. "rename_class_errors", applied and ms <= APPLY_MS and sum:find("src/main/java/demo/shop/Checkout.java:3", 1, true) ~= nil
    and not sum:find("Bill.java:", 1, true),
    ("applied %s after %.0f ms; Checkout %s by jdt.ls (%d error(s) before); summary %s; follow-up: %s"):format(applied and "yes" or "NO", ms,
      ct:find("import demo.billing.Bill;", 1, true) and "updated" or "NOT updated", before[CHECKOUT] or 0,
      sum:find("Checkout.java:3", 1, true) and "names Checkout.java:3 (stale import)" or ("MISSES Checkout: " .. sum),
      tostring(warn)))
  -- twin of the follow-up (deterministic): an error on Checkout put in a check namespace (what jdt.ls
  -- publishes when it does), then the module's reader: lists it, nothing for the clean files
  local ns = vim.api.nvim_create_namespace("nv4j_check_62_twin")
  vim.diagnostic.set(ns, chk, { { lnum = 12, col = 0, message = "Invoice cannot be resolved to a type", severity = vim.diagnostic.severity.ERROR } })
  local errs = refactor.new_errors(before, { BILL, CALC })
  vim.diagnostic.reset(ns, chk)
  local in_chk = vim.tbl_filter(function(e) return e:find("^Checkout%.java:") end, errs)
  local other = vim.tbl_filter(function(e) return not e:find("^Checkout%.java:") end, errs)
  lsp.report(P .. "rename_class_errors_twin", vim.iter(in_chk):any(function(e) return e:find("Invoice cannot be resolved", 1, true) ~= nil end)
    and #other == 0,
    ("Checkout: %s; others: %s"):format(table.concat(in_chk, " | "), #other == 0 and "none" or table.concat(other, " | ")))
end)

-- move_class
case("move_class", function()
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT); lsp.open(CALC)
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  local MOVED = main .. "demo/shop/Invoice.java"
  local t0, how, applied, ms = E.now(), nil, false, 0
  if has("move") then
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
  local got, stop = capture()
  if has("rename_package") then
    refactor.rename_package({ name = "demo.store" })
    applied, ms = until_ms(t0, moved)
    local st = (refactor.last or {}).ms or {}
    how = ("nv4j.refactor.rename_package (willRenameFiles %.0f ms, edit+write %.0f ms, move %.0f ms)"):format(st.will or -1,
      st.apply or -1, st.move or -1)
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
  stop()
  local ok_clean, why = clean({ MOVED }, t0)
  local sum = find_msg(got, "Renamed package demo.shop -> demo.store") or ""
  report_apply("rename_package", how, applied, ms, {
    { "shop/Checkout.java gone", vim.uv.fs_stat(CHECKOUT) == nil },
    { "package line", (text_of(MOVED) or ""):find("package demo.store;", 1, true) ~= nil },
    { "on disk", (disk(MOVED) or ""):find("package demo.store;", 1, true) ~= nil },
    { "buffer re-pointed", loaded(MOVED) ~= nil and loaded(CHECKOUT) == nil and vim.api.nvim_get_current_buf() == loaded(MOVED) },
    { "summary", sum:find("Checkout.java", 1, true) ~= nil },
  }, ok_clean, why)
end)

-- rename_package_imports: demo.billing -> demo.invoicing from Invoice: src/main and src/test folders
-- moved, package lines of the 4 files and the imports in Checkout updated, no `demo.billing` left;
-- unsaved user edits in Checkout (outside the folder) and PriceCalculator (inside) survive.
case("rename_package_imports", function()
  if not has("rename_package") then return lsp.report(P .. "rename_package_imports", false, "pending: no nv4j.refactor.rename_package") end
  local test = fixture .. "/src/test/java/"
  local NM, NT = main .. "demo/invoicing/", test .. "demo/invoicing/"
  local inv, chk, calc = lsp.open(INVOICE), lsp.open(CHECKOUT), lsp.open(CALC)
  append_line(chk, "// user edit in Checkout")
  append_line(calc, "// user edit in PriceCalculator")
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local t0 = E.now()
  refactor.rename_package({ name = "demo.invoicing" })
  local applied, ms = until_ms(t0, function()
    return vim.uv.fs_stat(NM .. "Invoice.java") ~= nil and vim.uv.fs_stat(NT .. "PriceCalculatorTest.java") ~= nil
      and (text_of(CHECKOUT) or ""):find("import demo.invoicing.Invoice;", 1, true) ~= nil
  end)
  local ok_clean, why = clean({ CHECKOUT, NM .. "Invoice.java", NM .. "PriceCalculator.java", NT .. "PriceCalculatorTest.java" }, t0)
  local left = {}
  local snap_now = F.snapshot()
  for p in pairs(snap_now.files) do
    if p:match("%.java$") then
      local t = text_of(p) or ""
      if t:find("demo.billing", 1, true) then left[#left + 1] = vim.fs.basename(p) end
    end
  end
  local pkg_ok = true
  for _, p in ipairs({ NM .. "Invoice.java", NM .. "PriceCalculator.java", NT .. "PriceCalculatorTest.java",
    NT .. "PriceCalculatorFailingTest.java" }) do
    pkg_ok = pkg_ok and (disk(p) or ""):find("package demo.invoicing;", 1, true) ~= nil
  end
  local ct = text_of(CHECKOUT) or ""
  local last = refactor.last or {}
  report_apply("rename_package_imports", ("nv4j.refactor.rename_package (willRenameFiles tries: %s%s)"):format(
    table.concat(vim.tbl_map(function(k) return rel_src(k) .. "=" .. last.tries[k] end, vim.tbl_keys(last.tries or {})), ", "),
    #(last.notes or {}) > 0 and ("; NOTE " .. table.concat(last.notes, "; ")) or ""), applied, ms, {
    { "main and test folders moved", vim.uv.fs_stat(main .. "demo/billing") == nil and vim.uv.fs_stat(test .. "demo/billing") == nil },
    { "package lines (4 files, disk)", pkg_ok },
    { "Checkout imports", ct:find("import demo.invoicing.Invoice;", 1, true) ~= nil and ct:find("import demo.invoicing.PriceCalculator;", 1, true) ~= nil },
    { "no demo.billing left" .. (#left > 0 and (" (" .. table.concat(left, ",") .. ")") or ""), #left == 0 },
    { "user edits kept", ct:find("// user edit in Checkout", 1, true) ~= nil
      and (text_of(NM .. "PriceCalculator.java") or ""):find("// user edit in PriceCalculator", 1, true) ~= nil },
    { "no buffer on an old path", loaded(INVOICE) == nil and loaded(CALC) == nil },
    { "tests import nothing from their own package", not (disk(NT .. "PriceCalculatorTest.java") or ""):find("import demo.invoicing.", 1, true)
      and not (disk(NT .. "PriceCalculatorFailingTest.java") or ""):find("import demo.invoicing.", 1, true) },
    { "test file unchanged but the package line", (disk(NT .. "PriceCalculatorTest.java") or ""):find("package demo.invoicing;", 1, true) ~= nil
      and (disk(NT .. "PriceCalculatorTest.java") or ""):gsub("package demo.invoicing;", "package demo.billing;", 1)
      == snap.files[test .. "demo/billing/PriceCalculatorTest.java"] },
  }, ok_clean, why)
end)

-- rename_package_fallback (deterministic twin of rename_package_imports' retry): jdt.ls answers null for
-- the second root (src/test/java) every time (stubbed): the package lines there are still set, and the
-- summary says what was not done.
case("rename_package_fallback", function()
  if not has("rename_package") then return lsp.report(P .. "rename_package_fallback", false, "pending: no nv4j.refactor.rename_package") end
  local test = fixture .. "/src/test/java/"
  local NT = test .. "demo/invoicing/"
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT)
  local real = client.request_sync
  local nulls = 0
  client.request_sync = function(self, m, params, t, b)
    if m == "workspace/willRenameFiles" and params.files[1].oldUri:find("/src/test/java/", 1, true) then
      nulls = nulls + 1
      return { result = nil }
    end
    return real(self, m, params, t, b)
  end
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local got, stop = capture()
  local t0 = E.now()
  local ok, err = pcall(refactor.rename_package, { name = "demo.invoicing" })
  client.request_sync = real
  stop()
  local ms = E.now() - t0
  local note = find_msg(got, "jdt.ls gave no edit for src/test/java/demo/billing: its package lines were set by Nv4J", vim.log.levels.WARN)
  local pt, ft = disk(NT .. "PriceCalculatorTest.java") or "", disk(NT .. "PriceCalculatorFailingTest.java") or ""
  local ok_clean, why = clean({ CHECKOUT, NT .. "PriceCalculatorTest.java" }, t0)
  report_apply("rename_package_fallback", ("nv4j.refactor.rename_package, test root stubbed null %d time(s)%s"):format(nulls,
    ok and "" or (" ERROR " .. tostring(err))), ok and vim.uv.fs_stat(NT) ~= nil, ms, {
    { "test package lines set", pt:find("package demo.invoicing;", 1, true) ~= nil and ft:find("package demo.invoicing;", 1, true) ~= nil },
    { "only the package line changed", pt:gsub("package demo.invoicing;", "package demo.billing;", 1) == snap.files[test .. "demo/billing/PriceCalculatorTest.java"] },
    { "summary NOTE names src/test/java", note ~= nil and note:find("src/test/java/demo/billing", 1, true) ~= nil },
  }, ok_clean, why)
end)

-- rename_package_conflict: demo.shop -> demo.billing (exists) and -> demo.shop.sub (into itself): refused,
-- nothing changed, an error message each.
case("rename_package_conflict", function()
  if not has("rename_package") then return lsp.report(P .. "rename_package_conflict", false, "pending: no nv4j.refactor.rename_package") end
  local chk = lsp.open(CHECKOUT)
  vim.api.nvim_set_current_buf(chk); vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local got, stop = capture()
  refactor.rename_package({ name = "demo.billing" })
  refactor.rename_package({ name = "demo.shop.sub" })
  vim.wait(500)
  stop()
  local m1 = find_msg(got, "already exists", vim.log.levels.ERROR)
  local m2 = find_msg(got, "into itself", vim.log.levels.ERROR)
  local d = F.diff(snap)
  lsp.report(P .. "rename_package_conflict", m1 ~= nil and m2 ~= nil and #d.added + #d.changed + #d.missing + #d.dirs == 0
    and loaded(CHECKOUT) ~= nil and not vim.bo[chk].modified,
    ("existing: %s; into itself: %s; disk %s"):format(tostring(m1), tostring(m2), F.fmt(d)))
end)

-- neo-tree: rename the folder/file in the tree (neo-tree's own rename_node, its name prompt answered).
local function neotree_rename(path, new_name)
  require("lazy").load({ plugins = { "neo-tree.nvim" } })
  -- neo-tree defers its setup (event handlers subscribed) until the tree is first shown; a user renaming
  -- in the tree has it open
  require("neo-tree").ensure_config()
  local inputs = require("neo-tree.ui.inputs")
  local real = inputs.input
  inputs.input = function(_, _, cb) inputs.input = real; cb(new_name) end
  local calls = 0
  local real_snacks = Snacks.rename.on_rename_file
  Snacks.rename.on_rename_file = function(...) calls = calls + 1; return real_snacks(...) end
  require("neo-tree.sources.filesystem.lib.fs_actions").rename_node(path)
  return function()
    Snacks.rename.on_rename_file = real_snacks
    return calls
  end
end

-- neotree_rename_package: shop -> store in the tree: package line updated, buffer re-pointed, LazyVim's
-- after-the-move hook not run.
case("neotree_rename_package", function()
  local chk = lsp.open(CHECKOUT)
  vim.api.nvim_set_current_buf(chk)
  local MOVED = main .. "demo/store/Checkout.java"
  local t0 = E.now()
  local done = neotree_rename(main .. "demo/shop", "store")
  local applied, ms = until_ms(t0, function() return (disk(MOVED) or ""):find("package demo.store;", 1, true) ~= nil and loaded(MOVED) ~= nil end)
  vim.wait(300)
  local calls = done()
  local ok_clean, why = clean({ MOVED }, t0)
  report_apply("neotree_rename_package", "neo-tree rename_node (folder)", applied, ms, {
    { "shop/Checkout.java gone", vim.uv.fs_stat(CHECKOUT) == nil },
    { "package line (buffer)", (text_of(MOVED) or ""):find("package demo.store;", 1, true) ~= nil },
    { "buffer re-pointed", loaded(MOVED) ~= nil and loaded(CHECKOUT) == nil },
    { ("LazyVim after-move hook skipped (%d call)"):format(calls), calls == 0 },
  }, ok_clean, why)
end)

-- neotree_rename_file: Invoice.java -> Bill.java in the tree: the class and its references follow.
case("neotree_rename_file", function()
  lsp.open(CHECKOUT); lsp.open(CALC)
  local inv = lsp.open(INVOICE)
  vim.api.nvim_set_current_buf(inv)
  local t0 = E.now()
  local done = neotree_rename(INVOICE, "Bill.java")
  local applied, ms = until_ms(t0, function()
    return (disk(BILL) or ""):find("public class Bill", 1, true) ~= nil and (text_of(CHECKOUT) or ""):find("import demo.billing.Bill;", 1, true) ~= nil
  end)
  vim.wait(300)
  done()
  local ok_clean, why = clean({ CHECKOUT, CALC, BILL }, t0)
  report_apply("neotree_rename_file", "neo-tree rename_node (file)", applied, ms, {
    { "Invoice.java gone, no buffer on it", vim.uv.fs_stat(INVOICE) == nil and loaded(INVOICE) == nil },
    { "no Invoice token left", word_count(text_of(CHECKOUT), "Invoice") + word_count(text_of(CALC), "Invoice") + word_count(text_of(BILL), "Invoice") == 0 },
  }, ok_clean, why)
end)

--- Stub jdt.ls's willRenameFiles to answer null for old uris containing `part`; returns undo, count.
local function null_will_rename(part)
  local real, n = client.request_sync, { 0 }
  client.request_sync = function(self, m, params, t, b)
    if m == "workspace/willRenameFiles" and params.files[1].oldUri:find(part, 1, true) then
      n[1] = n[1] + 1
      return { result = nil }
    end
    return real(self, m, params, t, b)
  end
  return function() client.request_sync = real end, n
end

--- Answer the next vim.ui.input with `answer`; the returned table gets the prompt and default.
local function answer_input(answer)
  local real, seen = vim.ui.input, {}
  vim.ui.input = function(o, cb)
    vim.ui.input = real
    seen.prompt, seen.default = o and o.prompt, o and o.default
    cb(answer)
  end
  return seen
end

-- rename_package_first_null: jdt.ls answers null for the FIRST (only) root every time (stubbed): refused,
-- nothing moved, nothing changed (before the fix the folder moved with the old `package` line).
case("rename_package_first_null", function()
  if not has("rename_package") then return lsp.report(P .. "rename_package_first_null", false, pending_reason("rename_package")) end
  local chk = lsp.open(CHECKOUT)
  vim.api.nvim_set_current_buf(chk); vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local undo, n = null_will_rename("/src/main/java/demo/shop")
  local got, stop = capture()
  local t0 = E.now()
  local ok = refactor.rename_package({ name = "demo.store" })
  local ms = E.now() - t0
  undo(); stop()
  local msg = find_msg(got, "gave no edit", vim.log.levels.ERROR)
  local d = F.diff(snap)
  lsp.report(P .. "rename_package_first_null", ok == false and msg ~= nil and #d.added + #d.changed + #d.missing + #d.dirs == 0
    and loaded(CHECKOUT) ~= nil and not vim.bo[chk].modified,
    ("returned %s after %.0f ms, %d null answer(s); message: %s; disk %s"):format(tostring(ok), ms, n[1], tostring(msg), F.fmt(d)))
end)

-- rename_class_strings: a JPQL string, a class-name string and an application.properties value name
-- Invoice (planted for the case): the rename does not rewrite them (scope: warn only), the summary is a
-- warning listing each place.
case("rename_class_strings", function()
  if not has("rename_class") then return lsp.report(P .. "rename_class_strings", false, pending_reason("rename_class")) end
  local Q = main .. "demo/shop/InvoiceQueries.java"
  local PROPS = fixture .. "/src/main/resources/application.properties"
  local fq = assert(io.open(Q, "w"))
  fq:write([[package demo.shop;

// planted by 62_refactor rename_class_strings, removed after the case
public class InvoiceQueries {
    static final String ALL = "SELECT i FROM Invoice i WHERE i.quantity > 0";
    static final String TYPE = "demo.billing.Invoice";
}
]])
  fq:close()
  local fp = assert(io.open(PROPS, "a"))
  fp:write("demo.refactor.type=demo.billing.Invoice\n")
  fp:close()
  local props_line = #vim.fn.readfile(PROPS)
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT); lsp.open(CALC)
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local got, stop = capture()
  local t0 = E.now()
  refactor.rename_class({ name = "Bill" })
  local applied, ms = until_ms(t0, function() return find_msg(got, "Renamed class Invoice -> Bill: ") ~= nil end)
  stop()
  local sum = find_msg(got, "Renamed class Invoice -> Bill: ", vim.log.levels.WARN) or ""
  local want = { "src/main/java/demo/shop/InvoiceQueries.java:5", "src/main/java/demo/shop/InvoiceQueries.java:6",
    "src/main/resources/application.properties:" .. props_line }
  local missing = vim.tbl_filter(function(w) return not sum:find(w, 1, true) end, want)
  local qt = disk(Q) or ""
  local ok_clean, why = clean({ CHECKOUT, CALC, BILL }, t0)
  report_apply("rename_class_strings", ("nv4j.refactor.rename_class (scan %.0f ms)"):format((refactor.last or {}).scan_ms or -1),
    applied, ms, {
      { "warning lists the 3 places" .. (#missing > 0 and (" (missing " .. table.concat(missing, ", ") .. ")") or ""), #missing == 0 },
      { "nothing rewritten", qt:find("FROM Invoice i", 1, true) ~= nil and (disk(PROPS) or ""):find("=demo.billing.Invoice", 1, true) ~= nil },
      { "no false hit (Checkout, PriceCalculator)", not sum:find("Checkout.java:", 1, true) and not sum:find("PriceCalculator.java:", 1, true) },
    }, ok_clean, why)
end)

-- neotree_rename_billing: billing -> invoicing in the tree (src/main/java): the namesake folder in
-- src/test/java follows (as with rename_package), test package lines and Checkout's imports updated.
case("neotree_rename_billing", function()
  local test = fixture .. "/src/test/java/"
  local NM, NT = main .. "demo/invoicing/", test .. "demo/invoicing/"
  lsp.open(CHECKOUT); lsp.open(CALC)
  local inv = lsp.open(INVOICE)
  vim.api.nvim_set_current_buf(inv)
  local t0 = E.now()
  local done = neotree_rename(main .. "demo/billing", "invoicing")
  local applied, ms = until_ms(t0, function()
    return (disk(NT .. "PriceCalculatorTest.java") or ""):find("package demo.invoicing;", 1, true) ~= nil
      and (text_of(CHECKOUT) or ""):find("import demo.invoicing.Invoice;", 1, true) ~= nil
  end)
  vim.wait(300)
  local calls = done()
  local ok_clean, why = clean({ CHECKOUT, NM .. "Invoice.java", NT .. "PriceCalculatorTest.java" }, t0)
  report_apply("neotree_rename_billing", "neo-tree rename_node (folder with a src/test/java namesake)", applied, ms, {
    { "main and test folders moved", vim.uv.fs_stat(main .. "demo/billing") == nil and vim.uv.fs_stat(test .. "demo/billing") == nil },
    { "test package lines", (disk(NT .. "PriceCalculatorFailingTest.java") or ""):find("package demo.invoicing;", 1, true) ~= nil },
    { "tests import nothing from their own package", not (disk(NT .. "PriceCalculatorTest.java") or ""):find("import demo.invoicing.", 1, true) },
    { ("LazyVim after-move hook skipped (%d call)"):format(calls), calls == 0 },
  }, ok_clean, why)
end)

-- neotree_refused: a neo-tree folder rename that Nv4J refuses (jdt.ls stubbed null): nothing moves, the
-- buffer stays on its file, our error is shown and neo-tree's "Renamed ... successfully" is not (neo-tree
-- cannot cancel from its before-event: its own rename is made to fail, the placeholder removed after 1 s).
case("neotree_refused", function()
  local chk = lsp.open(CHECKOUT)
  vim.api.nvim_set_current_buf(chk)
  local undo, n = null_will_rename("/src/main/java/demo/shop")
  local got, stop = capture()
  local done = neotree_rename(main .. "demo/shop", "store")
  vim.wait(2500, function() return find_msg(got, "successfully") ~= nil end, 20)
  done(); undo(); stop()
  local b = loaded(CHECKOUT)
  local err, ok_msg = find_msg(got, "gave no edit", vim.log.levels.ERROR), find_msg(got, "successfully")
  local d = F.diff(snap)
  lsp.report(P .. "neotree_refused", err ~= nil and ok_msg == nil and #d.added + #d.changed + #d.missing + #d.dirs == 0
    and b ~= nil and E.text(b) == (snap.files[CHECKOUT]:gsub("\n$", "")) and loaded(main .. "demo/store/Checkout.java") == nil,
    ("%d null answer(s); error: %s; success toast: %s; Checkout buffer %s; disk %s"):format(n[1], tostring(err), tostring(ok_msg),
      b and (E.text(b) == (snap.files[CHECKOUT]:gsub("\n$", "")) and "intact" or "CHANGED") or "GONE", F.fmt(d)))
end)

-- jr_package_line: <leader>jr (the mapping's own function) with the cursor on the `package` line renames
-- the package; the name comes from the prompt (answered "demo.store").
case("jr_package_line", function()
  local chk = lsp.open(CHECKOUT)
  vim.api.nvim_set_current_buf(chk); vim.api.nvim_win_set_cursor(0, { 1, 3 })
  local m = vim.fn.maparg("<leader>jr", "n", false, true)
  if not m.callback then return lsp.report(P .. "jr_package_line", false, "<leader>jr has no Lua callback: " .. vim.inspect(m.rhs)) end
  local MOVED = main .. "demo/store/Checkout.java"
  local seen = answer_input("demo.store")
  local t0 = E.now()
  m.callback()
  local applied, ms = until_ms(t0, function() return (disk(MOVED) or ""):find("package demo.store;", 1, true) ~= nil end)
  report_apply("jr_package_line", ("<leader>jr on `package demo.shop;` (prompt %q, default %q)"):format(tostring(seen.prompt),
    tostring(seen.default)), applied, ms, {
    { "package prompt", (seen.prompt or ""):find("Rename package demo.shop", 1, true) ~= nil and seen.default == "demo.shop" },
    { "buffer re-pointed", loaded(MOVED) ~= nil and loaded(CHECKOUT) == nil },
  }, clean({ MOVED }, t0))
end)

-- prompt_class: rename_class() without a name asks with vim.ui.input (prompt names the class, default
-- is its name) and renames with the answer.
case("prompt_class", function()
  if not has("rename_class") then return lsp.report(P .. "prompt_class", false, pending_reason("rename_class")) end
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT); lsp.open(CALC)
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local seen = answer_input("Bill")
  local t0 = E.now()
  refactor.rename_class()
  local applied, ms = until_ms(t0, function()
    return vim.uv.fs_stat(BILL) ~= nil and (text_of(CHECKOUT) or ""):find("import demo.billing.Bill;", 1, true) ~= nil
  end)
  local ok_clean, why = clean({ CHECKOUT, CALC, BILL }, t0)
  report_apply("prompt_class", ("rename_class() with no name (prompt %q, default %q)"):format(tostring(seen.prompt), tostring(seen.default)),
    applied, ms, {
      { "prompt names Invoice, default Invoice", (seen.prompt or ""):find("Rename class Invoice", 1, true) ~= nil and seen.default == "Invoice" },
    }, ok_clean, why)
end)

-- rename_package_no_type: a package whose only file is package-info.java (no top-level type): jdt.ls's
-- null answer is legitimate there (stubbed null every time): moved with the package line set by text and
-- a NOTE, not refused (the refusal is only for files declaring their own type, rename_package_first_null).
case("rename_package_no_type", function()
  if not has("rename_package") then return lsp.report(P .. "rename_package_no_type", false, pending_reason("rename_package")) end
  local PI = main .. "demo/notes/package-info.java"
  local NEW = main .. "demo/memo/package-info.java"
  vim.fn.mkdir(vim.fs.dirname(PI), "p")
  local f = assert(io.open(PI, "w"))
  f:write("/** Planted by 62_refactor rename_package_no_type, removed after the case. */\npackage demo.notes;\n")
  f:close()
  local b = lsp.open(PI)
  vim.api.nvim_set_current_buf(b); vim.api.nvim_win_set_cursor(0, { 2, 0 })
  local undo, n = null_will_rename("/demo/notes")
  local got, stop = capture()
  local t0 = E.now()
  local ok = refactor.rename_package({ name = "demo.memo" })
  local ms = E.now() - t0
  undo(); stop()
  local note = find_msg(got, "jdt.ls gave no edit for src/main/java/demo/notes", vim.log.levels.WARN)
  lsp.report(P .. "rename_package_no_type", ok == true and (disk(NEW) or ""):find("package demo.memo;", 1, true) ~= nil
    and vim.uv.fs_stat(PI) == nil and loaded(NEW) ~= nil and note ~= nil and ms <= APPLY_MS + 1000,
    ("returned %s after %.0f ms (%d null answers, 1 s of retries), new file %s, note: %s"):format(tostring(ok), ms, n[1],
      (disk(NEW) or "MISSING"):match("package [%w.]+;") or "no package line", tostring(note)))
end)

-- neotree_placeholder: the placeholder that blocks neo-tree's own rename after a refusal (handler called
-- directly, jdt.ls stubbed null): a second refusal within 1 s keeps it 1 s past the second; VimLeavePre
-- removes it at once; an existing destination folder is never used (nothing written into it).
case("neotree_placeholder", function()
  local SHOP, STORE = main .. "demo/shop", main .. "demo/store"
  local undo = null_will_rename("/src/main/java/demo/shop")
  local got, stop = capture()
  local r1 = refactor.neotree_before({ source = SHOP, destination = STORE })
  vim.wait(600)
  local r2 = refactor.neotree_before({ source = SHOP, destination = STORE })
  vim.wait(600) -- 1.2 s after the first, 0.6 s after the second
  local kept = vim.uv.fs_stat(STORE) ~= nil and vim.uv.fs_stat(STORE).type == "file"
  vim.wait(700)
  local gone = vim.uv.fs_stat(STORE) == nil
  -- VimLeavePre (only our group)
  refactor.neotree_before({ source = SHOP, destination = STORE })
  local made = vim.uv.fs_stat(STORE) ~= nil
  vim.api.nvim_exec_autocmds("VimLeavePre", { group = "nv4j_refactor_placeholders" })
  local left_after_leave = vim.uv.fs_stat(STORE) ~= nil
  -- an existing (user) destination folder: refused, nothing written into it, neo-tree told "handled"
  vim.fn.mkdir(STORE, "p")
  local r3 = refactor.neotree_before({ source = SHOP, destination = STORE })
  local entries = vim.fn.readdir(STORE)
  undo(); stop()
  vim.uv.fs_rmdir(STORE)
  lsp.report(P .. "neotree_placeholder", r1 == nil and r2 == nil and kept and gone and made and not left_after_leave
    and #entries == 0 and type(r3) == "table" and r3.handled == true and next(refactor._placeholders) == nil,
    ("not handled %s/%s; kept 0.6 s after the 2nd refusal %s; gone 1.3 s after it %s; VimLeavePre removed %s; user folder entries %d (%s), handled %s"):format(
      tostring(r1 == nil), tostring(r2 == nil), tostring(kept), tostring(gone), tostring(made and not left_after_leave), #entries,
      table.concat(entries, ","), tostring(r3 and r3.handled)))
end)

-- stale_scan_truncated: the strings/config scan counts only scannable files and the warning says when it
-- stopped (cap lowered to 3 for the case; the fixture has more).
case("stale_scan_truncated", function()
  if not has("rename_class") then return lsp.report(P .. "stale_scan_truncated", false, pending_reason("rename_class")) end
  local names = { java = { "%f[%w_$]Invoice%f[^%w_$]" }, config = { "%f[%w_$]Invoice%f[^%w_$]" } }
  local _, full = refactor.stale_refs(fixture, names)
  local keep = refactor.scan_max_files
  refactor.scan_max_files = 3
  local _, cut = refactor.stale_refs(fixture, names)
  local note = refactor._stale_note({}, "Invoice", cut)
  refactor.scan_max_files = keep
  lsp.report(P .. "stale_scan_truncated", full == false and cut == true and note:find("scan stopped after 3 files", 1, true) ~= nil,
    ("default cap truncated=%s; cap 3 truncated=%s; note: %s"):format(tostring(full), tostring(cut), note))
end)

--- Inline at (pat, word) in PriceCalculator; `want` must appear in the file afterwards.
local function inline_case(name, pat, word, title, want, gone)
  case(name, function()
    local calc = lsp.open(CALC)
    lsp.open(CHECKOUT)
    local l, c = pos(calc, pat, word)
    local before = E.text(calc)
    local t0, how = E.now(), nil
    if has("inline") then
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
  if has("change_signature") then
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
    if not has("safe_delete") then
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
