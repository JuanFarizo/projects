-- P3 refactors. Run via tests/run.sh. Spec: specs/features/refactors.md (decision D23 in
-- specs/001-architecture.md). Product: nvim/lua/nv4j/refactor.lua (P3 Task 4).
-- Budget (P3 plan, not weakened): each refactor applied <= 2 s on the fixture, all references and
-- imports right, the build clean afterwards (no jdt.ls error in the touched files <= 3 s after the
-- edit), and one `u` per touched buffer gives its text back.
-- Fixture: demo.billing.{Invoice, PriceCalculator}, demo.shop.Checkout (call sites in another package).
-- API under test (Task 4): require("nv4j.refactor").<fn>(opts) at the cursor, no prompts when opts
-- give the answer: rename_class({ name }), rename_package({ name }) (Task 4a, built), move({ package })
-- (Task 4b, built), inline({ all? }) (Task 4c, built), change_signature({ add = { { type, name, default } },
-- remove, rename, retype, reorder, name, returns, visibility, signature }) (Task 4d, built), safe_delete()
-- (Task 4e, built). Each case
-- uses its function when it exists, else measures today's path: vim.lsp.buf.rename (<leader>cr) or
-- jdt.ls's code action through Neovim/nvim-jdtls (<leader>ca), with nvim-jdtls's prompts answered.
--  api, keys          : the functions built so far and their keys (<leader>jr rename, <leader>jp rename
--                       package, <leader>jm move, <leader>ji inline, <leader>js change signature,
--                       <leader>jd safe delete: all six built); <leader>cr stays Rename.
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
--  follow_up_warning  : the 3 s warning from an error planted on a touched buffer; a newer refactor
--                       cancels the older one's pending warning.
--  rename_package_no_type: package-info.java only, jdt.ls null: moved with the package line by text + NOTE.
--  neotree_placeholder: the refusal placeholder: kept 1 s after the last refusal, VimLeavePre removes it,
--                       an existing destination folder is never written into.
--  move_class (+ _undo): Invoice to package demo.shop: demo/shop/Invoice.java, package line, Checkout's
--                       import gone, PriceCalculator and the billing tests import demo.shop.Invoice,
--                       written, buffer re-pointed, summary; build clean; one `u` per buffer.
--  move_class_unsaved : unsaved user edits in Checkout and Invoice survive; Checkout left unsaved.
--  move_class_new_package: to demo.invoicing (no folder): created, moved, summary says so.
--  move_new_package_refused: twin, jdt.ls stubbed null: refused, the created folder removed.
--  move_invalid, move_same_package, move_conflict (main and test root), move_not_top_level (nested
--                       type, second top-level type): refused with the reason, nothing changed.
--  move_symbols_timeout: several types, documentSymbol stubbed to time out: refused visibly.
--  move_prompt, move_key_new_package: vim.ui.select of the project's packages; <leader>jm with "New
--                       package..." and the name typed.
--  move_class_boot, move_class_boot_scan: GreetingController to demo.web (annotations kept, build clean)
--                       and to web (outside the @SpringBootApplication package: warning).
--  move_class_test_stays: a planted InvoiceTest stays in demo.billing (import added); summary says so.
--  move_class_stale   : the old qualified name in application.properties listed; a "Invoice" string not.
--  move_class_errors  : a syntax error in Checkout: still updated by jdt.ls (or warned); _skipped_twin:
--                       Checkout's edit dropped (stub): the summary warns with Checkout.java:3.
--  Unbuilt functions (none since Task 4e): their cases would FAIL "pending" and `api` would add a
--  pending_<fn> FAIL line each.
--  inline_method (+ _undo): `gross(invoice)` call in total inlined: `invoice.quantity() * invoice.unitPrice()`,
--                       declaration kept, written, summary; one `u` gives the text back.
--  inline_variable (+ _undo): local `gross` in total inlined: `return gross(invoice);`.
--  inline_method_all, inline_method_declaration: opts.all on the call / the cursor on the declaration:
--                       every call, declaration removed, not "Make Static".
--  inline_constant    : <leader>ji on a planted constant's reference in Checkout: that reference only.
--  inline_constant_all (+ _undo), inline_unsaved: opts.all from Checkout: Invoice and Checkout inlined,
--                       declaration removed; with unsaved user edits both are left unsaved, edits kept.
--  inline_refused, inline_recursive, inline_resolve_error (stub): no inline at the cursor (@Value field,
--                       keyword, all on a JDK method), jdt.ls gives no edit (recursion), resolve error:
--                       refused with the reason, nothing changed.
--  inline_two_actions (stub): two inline actions at one place: the user picks; opts.all takes "all".
--  inline_bean_call, inline_bean_declaration: @Bean devBanner inlined at a call / everywhere: Spring warning.
--  inline_value_constant: a constant used as @Value key inlined from its declaration: build clean.
--  inline_errors (+ _twin, stub): a syntax error in Checkout: inlined there by jdt.ls or its reference
--                       named in the warning; twin: Checkout's edit dropped, warning names its line.
--  change_signature (+ _undo): total gets `int discount` with default 0 (nv4j.refactor.change_signature):
--                       the 3 call sites in Checkout and the 5 in src/test/java pass 0, written, summary
--                       lists 4 files; build clean = jdt.ls's publish after the revalidation the refactor
--                       sends (cs_clean); one `u` per touched buffer.
--  change_signature_call_site: from a call in Checkout (definition first): total changes, payTwice not.
--  change_signature_unsaved: unsaved edits in PriceCalculator and Checkout kept, both left unsaved.
--  change_signature_reorder, _remove, _header: rename + reorder + method name; remove by position +
--                       retype; visibility + return type + name (no callers).
--  change_signature_prompt: <leader>js with vim.ui.input answered (`... int discount = 0)`, a typed rename).
--  change_signature_refused: 15 refusals with the reason, nothing changed (not on a method, invalid
--                       type/name, no default, duplicate, removed-but-used, clash, reorder, constructor
--                       name, unknown option, no change, jdt.ls's invalid default, library method/interface).
--  change_signature_no_edit (stub): jdt.ls null + showMessage, empty edit: refused, its message once.
--  change_signature_stale, _busy, _finish_error (stubs): a buffer typed into while jdt.ls works: refused
--                       whole; a second refactor while one is pending: refused; an error after the answer:
--                       reported, on_done(false), busy cleared.
--  change_signature_constructor: Invoice(...) + discount: every `new Invoice(` passes 0 (declaration, call).
--  change_signature_interface_ceiling: the first interface change of the session within the 5 s ceiling (FAILs when over).
--  change_signature_interface: from Rule.apply: Half.apply changed too (noted); from Half.apply refused.
--  change_signature_boot: @Bean parameter / @Bean renamed / @GetMapping parameter: Spring warnings.
--  change_signature_errors (+ _twin, stub): syntax error in Checkout; twin: its edit dropped -> warning.
--  change_signature_stale_twin: a planted stale error publish is cleared by refactor.revalidate.
--  change_signature_parse: typed-form and opts parsing (unit, no jdt.ls).
--  safe_delete_blocked: on `total` (8 usages, main and test sources): nothing deleted, all 8 in the
--                       quickfix (opened), the message names the count.
--  safe_delete_free (+ _undo): on `legacyTotal` (no usages): its lines and one blank line removed, written,
--                       summary, build clean; one `u` gives the text back.
--  safe_delete_unsaved, _unsaved_usage: <leader>jd with an unsaved edit in PriceCalculator (edited in place,
--                       left unsaved); an unsaved call typed into Checkout blocks it.
--  safe_delete_unconfirmed_twin (stub): references empty: an unsaved call / a call in a file with errors
--                       blocks it ("possible usage"); errors elsewhere: deleted with a note.
--  safe_delete_errors : a real syntax error in Checkout not naming it: deleted, the note names Checkout.
--  safe_delete_self_ref: a recursive method nobody calls: deleted.
--  safe_delete_hierarchy: @Override method refused; an interface method with an implementation blocked.
--  safe_delete_boot   : @Bean, @GetMapping handler, @Value field: deleted with Spring warnings, a properties
--                       line naming the bean listed, unused imports reported.
--  safe_delete_class  : Invoice blocked; the only type of a file: file deleted, buffer wiped, jdt.ls told;
--                       a second top-level type: its declaration only.
--  safe_delete_trash  : a deleted file is copied to the trash first (stdpath cache), :Nv4jRestoreDeleted puts it
--                       back byte for byte; a failing removal keeps the buffer and the file.
--  safe_delete_supertypes (+ _twin, stub): a method overriding/implementing without @Override refused
--                       naming the supertype's method; no answer from jdt.ls: refused.
--  safe_delete_refused: local, parameter, constructor, record component, keyword, library method, two
--                       declarators, enum constant: refused with the reason, nothing changed.
--  safe_delete_no_answer (stub), safe_delete_busy (stub): references timeout/error refused; a pending change
--                       signature refuses it.
--  Fix wave after the P3 final review (see specs/features/refactors.md "Fix wave"):
--  safe_delete_throw (stub), safe_delete_unreadable (stub + a real mode 000 file): an error after the delete leaves
--                       busy clear; an unreadable file is skipped and named in the warning.
--  rename_class_busy, _stale, _finish_error (stubs): the rename's own busy / stale-buffer refusal / error exit.
--  rename_class_case_only: Invoice -> INVOICE really renames the file (case-insensitive FS only; SKIP printed otherwise).
--  multi_module_roots: module_root / rename_package moves / move conflict, test-stays note and Spring warning on a /tmp/nv4j layout.
--  safe_delete_trash_order, _restore_failed; rename_package_part_way_message; inline_errors now requires ret == true.
-- The fixture is snapshot before and restored after every case (tests/lib/fixture.lua), jdt.ls told.
-- Development: NV4J_CASE=<Lua pattern> runs only the matching cases. jdt.ls answers a very first rename with
-- the declaration only (no references) when nothing warmed it: run a group (e.g. '^rename_class_[uc]'), not a single case.
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
    { "<leader>jm", "move", "ove" }, { "<leader>ji", "inline", "nline" }, { "<leader>js", "change_signature", "ignature" },
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
  -- development only: NV4J_CASE=<Lua pattern> runs just the matching cases (a full run is the real result)
  if vim.env.NV4J_CASE and not name:find(vim.env.NV4J_CASE) then return end
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

-- follow_up_warning (deterministic): the warning after a refactor ("applied, but N error(s)") from an
-- error planted in a check namespace on a touched buffer right after the edit; and a newer refactor
-- cancels the older one's pending warning. A: GreetingController -> HelloController, error planted in
-- HelloController; B (started before A's 3 s look): Invoice -> Bill, error planted in Checkout. Only B's
-- warning may appear, naming Checkout and the planted message.
case("follow_up_warning", function()
  if not has("rename_class") then return lsp.report(P .. "follow_up_warning", false, pending_reason("rename_class")) end
  local GC, HC = main .. "demo/GreetingController.java", main .. "demo/HelloController.java"
  local ns = vim.api.nvim_create_namespace("nv4j_check_62_follow_up")
  local function plant(b, msg)
    vim.diagnostic.set(ns, b, { { lnum = 0, col = 0, message = msg, severity = vim.diagnostic.severity.ERROR } })
  end
  lsp.open(CHECKOUT); lsp.open(CALC)
  local inv, gc = lsp.open(INVOICE), lsp.open(GC)
  local got, stop = capture()
  -- A
  local l, c = pos(gc, "^public class GreetingController", "GreetingController")
  vim.api.nvim_set_current_buf(gc); vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local tA = E.now()
  refactor.rename_class({ name = "HelloController" })
  local a_ok = until_ms(tA, function() return loaded(HC) ~= nil and find_msg(got, "Renamed class GreetingController -> HelloController: ") ~= nil end)
  if a_ok then plant(loaded(HC), "planted A error") end
  -- B, well before A's 3 s look
  l, c = pos(inv, "^public class Invoice", "Invoice")
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local tB = E.now()
  refactor.rename_class({ name = "Bill" })
  local b_ok = until_ms(tB, function() return find_msg(got, "Renamed class Invoice -> Bill: ") ~= nil end)
  local gap = tB - tA
  if b_ok then plant(loaded(CHECKOUT), "planted B error") end
  local warn_b
  vim.wait(6000, function()
    warn_b = find_msg(got, "Renamed class Invoice -> Bill applied, but", vim.log.levels.WARN)
    return warn_b ~= nil
  end, 20)
  local t_warn = E.now() - tB
  -- past A's own 3 s look (A's follow-up started when A was applied, before B started)
  vim.wait(math.max(0, tB + 3600 - E.now()), function() return false end, 50)
  local warn_a = find_msg(got, "Renamed class GreetingController -> HelloController applied, but")
  stop()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do pcall(vim.diagnostic.reset, ns, b) end
  -- B's warning comes from B's own 3 s look (an earlier one would be a stale follow-up not cancelled)
  lsp.report(P .. "follow_up_warning", a_ok and b_ok and gap < 3000 and warn_b ~= nil and t_warn >= 2900
    and warn_b:find("Checkout.java:1 planted B error", 1, true) ~= nil and warn_a == nil,
    ("B started %.0f ms after A; B's warning after %.0f ms: %s; A's (cancelled) warning: %s"):format(gap, t_warn,
      tostring(warn_b), tostring(warn_a)))
end)

-- move_class (+ undo): Invoice to package demo.shop through nv4j.refactor.move: demo/shop/Invoice.java,
-- package line, Checkout's import dropped, PriceCalculator and the billing tests import demo.shop.Invoice,
-- touched files written, buffer re-pointed, summary; one `u` per touched buffer gives its text back.
local SHOP_INV = main .. "demo/shop/Invoice.java"
local TEST = fixture .. "/src/test/java/"
local PCT = TEST .. "demo/billing/PriceCalculatorTest.java"
case("move_class", function()
  local inv, chk, calc = lsp.open(INVOICE), lsp.open(CHECKOUT), lsp.open(CALC)
  local before = { [chk] = E.text(chk), [calc] = E.text(calc), [inv] = E.text(inv) }
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  local got, stop = capture()
  local t0, how, applied, ms = E.now(), nil, false, 0
  local req0 = has("move") and refactor.symbol_requests or 0
  if has("move") then
    vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { l + 1, c })
    how = "nv4j.refactor.move"; refactor.move({ package = "demo.shop" })
  else
    local seen = answer_select("demo.shop")
    local ok, title = code_action(inv, l, c, "^Move")
    if not ok then stop(); return report_apply("move_class", title, false, 0, {}, false, "") end
    applied = vim.wait(5000, function() return #seen > 0 end, 5)
    how = ("code action %s (nvim-jdtls destination prompt %s)"):format(title,
      applied and ("answered 'demo.shop' among: " .. table.concat(seen, " | ")) or "NEVER shown")
  end
  applied, ms = until_ms(t0, function() return vim.uv.fs_stat(SHOP_INV) ~= nil and (text_of(CALC) or ""):find("import demo.shop.Invoice;", 1, true) ~= nil end)
  stop()
  local ct = text_of(CHECKOUT)
  local ok_clean, why = clean({ CHECKOUT, CALC, SHOP_INV }, t0)
  local sum = find_msg(got, "Moved class Invoice to package demo.shop") or ""
  local st = refactor.last or {}
  if st.ms then how = how .. (" (willRenameFiles %.0f ms, edit+write %.0f ms, move %.0f ms)"):format(st.ms.will, st.ms.apply, st.ms.move) end
  report_apply("move_class", how, applied, ms, {
    { "billing/Invoice.java gone", vim.uv.fs_stat(INVOICE) == nil },
    { "Checkout import dropped", ct ~= nil and not ct:find("import demo.billing.Invoice;", 1, true) },
    { "package line", (text_of(SHOP_INV) or ""):find("package demo.shop;", 1, true) ~= nil },
    { "written to disk", (disk(SHOP_INV) or ""):find("package demo.shop;", 1, true) ~= nil
      and (disk(CALC) or ""):find("import demo.shop.Invoice;", 1, true) ~= nil
      and not (disk(CHECKOUT) or ""):find("import demo.billing.Invoice;", 1, true) },
    { "billing tests import demo.shop.Invoice", (disk(PCT) or ""):find("import demo.shop.Invoice;", 1, true) ~= nil },
    { "buffer re-pointed", loaded(SHOP_INV) ~= nil and loaded(INVOICE) == nil },
    { "summary lists Invoice (from billing), Checkout, PriceCalculator", sum:find("Invoice.java (from src/main/java/demo/billing/Invoice.java)", 1, true) ~= nil
      and sum:find("Checkout.java", 1, true) ~= nil and sum:find("PriceCalculator.java", 1, true) ~= nil },
    { ("class found from the text, no documentSymbol request (%d)"):format((refactor.symbol_requests or 0) - req0),
      has("move") and refactor.symbol_requests == req0 },
  }, ok_clean, why)
  if not has("move") then return end
  local bad = {}
  for b, txt in pairs(before) do
    local bb = vim.api.nvim_buf_is_valid(b) and b or vim.fn.bufnr(SHOP_INV)
    if bb ~= -1 and vim.api.nvim_buf_is_valid(bb) then
      vim.api.nvim_buf_call(bb, function() vim.cmd("silent! undo") end)
      if E.text(bb) ~= txt then bad[#bad + 1] = vim.fs.basename(vim.api.nvim_buf_get_name(bb)) end
    else
      bad[#bad + 1] = "buffer gone"
    end
  end
  lsp.report(P .. "move_class_undo", applied and #bad == 0,
    applied and (#bad == 0 and "one u restored every touched buffer (Checkout, PriceCalculator, the moved Invoice)"
      or ("not restored by one u: " .. table.concat(bad, ", "))) or "move not applied, nothing to undo")
end)

-- move_class_unsaved: unsaved user edits in Checkout and in Invoice itself survive the move; Checkout is
-- edited in place and left unsaved, the moved Invoice is written by the move with the user's edit.
case("move_class_unsaved", function()
  if not has("move") then return lsp.report(P .. "move_class_unsaved", false, pending_reason("move")) end
  local inv, chk = lsp.open(INVOICE), lsp.open(CHECKOUT)
  lsp.open(CALC)
  append_line(chk, "// user edit in Checkout")
  append_line(inv, "// user edit in Invoice")
  vim.api.nvim_set_current_buf(inv)
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local got, stop = capture()
  local t0 = E.now()
  refactor.move({ package = "demo.shop" })
  local applied, ms = until_ms(t0, function() return vim.uv.fs_stat(SHOP_INV) ~= nil and loaded(SHOP_INV) ~= nil end)
  stop()
  local ok_clean, why = clean({ CHECKOUT, CALC, SHOP_INV }, t0)
  local ct = text_of(CHECKOUT) or ""
  local sum = find_msg(got, "Moved class Invoice to package demo.shop") or ""
  report_apply("move_class_unsaved", "nv4j.refactor.move", applied, ms, {
    { "Checkout keeps the user edit, import dropped", ct:find("// user edit in Checkout", 1, true) ~= nil
      and not ct:find("import demo.billing.Invoice;", 1, true) },
    { "Checkout left unsaved (disk untouched)", loaded(CHECKOUT) ~= nil and vim.bo[loaded(CHECKOUT)].modified
      and disk(CHECKOUT) == snap.files[CHECKOUT] },
    { "moved Invoice on disk has the user edit", (disk(SHOP_INV) or ""):find("// user edit in Invoice", 1, true) ~= nil
      and (disk(SHOP_INV) or ""):find("package demo.shop;", 1, true) ~= nil },
    { "summary: Checkout left unsaved, Invoice written", sum:find("Checkout.java [left unsaved", 1, true) ~= nil
      and sum:find("Invoice.java (from src/main/java/demo/billing/Invoice.java) [written with your unsaved changes]", 1, true) ~= nil },
  }, ok_clean, why)
end)

-- move_class_new_package: to demo.invoicing (no such folder): the folder is created, jdt.ls told, the
-- class moved there with its references; the summary says the folder was created.
local NEWPKG_INV = main .. "demo/invoicing/Invoice.java"
case("move_class_new_package", function()
  if not has("move") then return lsp.report(P .. "move_class_new_package", false, pending_reason("move")) end
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT); lsp.open(CALC)
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { 5, 14 })
  local got, stop = capture()
  local t0 = E.now()
  refactor.move({ package = "demo.invoicing" })
  local applied, ms = until_ms(t0, function()
    return vim.uv.fs_stat(NEWPKG_INV) ~= nil and (text_of(CHECKOUT) or ""):find("import demo.invoicing.Invoice;", 1, true) ~= nil
  end)
  stop()
  local ok_clean, why = clean({ CHECKOUT, CALC, NEWPKG_INV }, t0)
  local sum = find_msg(got, "Moved class Invoice to package demo.invoicing") or ""
  local st = refactor.last or {}
  report_apply("move_class_new_package", ("nv4j.refactor.move (symbols %.0f ms, willRenameFiles %.0f ms, %s tries, edit+write %.0f ms, move %.0f ms)"):format(
    st.symbols_ms or -1, st.ms and st.ms.will or -1, tostring(st.tries and st.tries[INVOICE]), st.ms and st.ms.apply or -1,
    st.ms and st.ms.move or -1), applied, ms, {
    { "package line", (disk(NEWPKG_INV) or ""):find("package demo.invoicing;", 1, true) ~= nil },
    { "PriceCalculator imports it", (text_of(CALC) or ""):find("import demo.invoicing.Invoice;", 1, true) ~= nil },
    { "summary says the folder was created", sum:find("created package folder src/main/java/demo/invoicing", 1, true) ~= nil },
  }, ok_clean, why)
end)

-- move_new_package_refused (deterministic twin of the folder registration race): jdt.ls stubbed null
-- for the move: refused, the folder made for it removed, nothing changed.
case("move_new_package_refused", function()
  if not has("move") then return lsp.report(P .. "move_new_package_refused", false, pending_reason("move")) end
  local inv = lsp.open(INVOICE)
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { 5, 14 })
  local undo, n = null_will_rename("/demo/billing/Invoice.java")
  local got, stop = capture()
  local t0 = E.now()
  local ok = refactor.move({ package = "demo.invoicing" })
  local ms = E.now() - t0
  undo(); stop()
  local msg = find_msg(got, "gave no edit", vim.log.levels.ERROR)
  local d = F.diff(snap)
  lsp.report(P .. "move_new_package_refused", ok == false and msg ~= nil and #d.added + #d.changed + #d.missing + #d.dirs == 0
    and vim.uv.fs_stat(main .. "demo/invoicing") == nil and loaded(INVOICE) ~= nil and not vim.bo[inv].modified,
    ("returned %s after %.0f ms, %d null answer(s); message: %s; demo/invoicing %s; disk %s, new dirs %d"):format(tostring(ok), ms, n[1],
      tostring(msg), vim.uv.fs_stat(main .. "demo/invoicing") and "LEFT BEHIND" or "removed", F.fmt(d), #d.dirs))
end)

--- Runs move({ package = target }) on Invoice and returns ok, the messages, the diff against the snapshot.
local function move_refused(target)
  local inv = lsp.open(INVOICE)
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { 5, 14 })
  local got, stop = capture()
  local ok = refactor.move({ package = target })
  vim.wait(300)
  stop()
  return ok, got, inv
end

local function unchanged(planted)
  local d = F.diff(snap)
  local added = vim.tbl_filter(function(p) return not planted[p] end, d.added)
  return #added + #d.changed + #d.missing == 0 and #d.dirs == (planted.dirs or 0), F.fmt(d)
end

-- move_invalid: an invalid package name ("demo.1x", "demo.class"): refused, nothing changed.
case("move_invalid", function()
  if not has("move") then return lsp.report(P .. "move_invalid", false, pending_reason("move")) end
  local r = {}
  for _, t in ipairs({ "demo.1x", "demo.class" }) do
    local ok, got, inv = move_refused(t)
    local msg = find_msg(got, "not a valid package name", vim.log.levels.ERROR)
    local same, d = unchanged({})
    r[#r + 1] = { ok = ok == false and msg ~= nil and same and not vim.bo[inv].modified, d = ("%s: %s, disk %s"):format(t, tostring(msg), d) }
  end
  lsp.report(P .. "move_invalid", r[1].ok and r[2].ok, r[1].d .. "; " .. r[2].d)
end)

-- move_same_package: to its own package: a message, nothing changed.
case("move_same_package", function()
  if not has("move") then return lsp.report(P .. "move_same_package", false, pending_reason("move")) end
  local ok, got, inv = move_refused("demo.billing")
  local msg = find_msg(got, "is already in package demo.billing; nothing to do", vim.log.levels.INFO)
  local same, d = unchanged({})
  lsp.report(P .. "move_same_package", ok == false and msg ~= nil and same and not vim.bo[inv].modified,
    ("message: %s; disk %s"):format(tostring(msg), d))
end)

-- move_conflict: demo.shop.Invoice already exists (planted in src/main/java, then in src/test/java):
-- refused both times, the planted file not overwritten, nothing else changed.
case("move_conflict", function()
  if not has("move") then return lsp.report(P .. "move_conflict", false, pending_reason("move")) end
  local r = {}
  for _, rootdir in ipairs({ main, TEST }) do
    local planted = rootdir .. "demo/shop/Invoice.java"
    vim.fn.mkdir(vim.fs.dirname(planted), "p")
    local new_dir = rootdir == TEST and 1 or 0
    local body = "package demo.shop;\n\n// planted by 62_refactor move_conflict\npublic class Invoice {\n}\n"
    local f = assert(io.open(planted, "w")); f:write(body); f:close()
    local ok, got, inv = move_refused("demo.shop")
    local msg = find_msg(got, "demo.shop.Invoice already exists", vim.log.levels.ERROR)
    local same, d = unchanged({ [planted] = true, dirs = new_dir })
    r[#r + 1] = { ok = ok == false and msg ~= nil and same and disk(planted) == body and vim.uv.fs_stat(INVOICE) ~= nil and not vim.bo[inv].modified,
      d = ("%s: %s; disk %s"):format(rel_src(planted), tostring(msg), d) }
    os.remove(planted)
    if rootdir == TEST then vim.uv.fs_rmdir(vim.fs.dirname(planted)) end
  end
  lsp.report(P .. "move_conflict", r[1].ok and r[2].ok, r[1].d .. " | " .. r[2].d)
end)

-- move_not_top_level: a planted Order.java with a nested type Line and a second top-level type Extra:
-- cursor in Line or in Extra: refused with the reason, nothing changed.
local ORDER = main .. "demo/billing/Order.java"
local function plant_order()
  local f = assert(io.open(ORDER, "w"))
  f:write([[package demo.billing;

// planted by 62_refactor move_not_top_level / move_symbols_timeout, removed after the case
public class Order {
    public static class Line {
        int qty;
    }
}

class Extra {
    int n;
}
]])
  f:close()
end
case("move_not_top_level", function()
  if not has("move") then return lsp.report(P .. "move_not_top_level", false, pending_reason("move")) end
  plant_order()
  local req0 = refactor.symbol_requests
  local b = lsp.open(ORDER)
  vim.wait(1500, function() return (published_at[vim.uri_from_fname(ORDER)] or 0) > 0 end, 20)
  local r = {}
  for _, w in ipairs({ { "int qty", "nested type Line" }, { "int n;", "second top-level type" } }) do
    local l = E.line_of(b, w[1])
    vim.api.nvim_set_current_buf(b); vim.api.nvim_win_set_cursor(0, { l + 1, 8 })
    local got, stop = capture()
    local ok = refactor.move({ package = "demo.shop" })
    vim.wait(200)
    stop()
    local msg = find_msg(got, w[2], vim.log.levels.WARN)
    r[#r + 1] = { ok = ok == false and msg ~= nil, d = ("%s: %s"):format(w[1], tostring(msg)) }
  end
  local same, d = unchanged({ [ORDER] = true })
  local reqs = refactor.symbol_requests - req0
  lsp.report(P .. "move_not_top_level", r[1].ok and r[2].ok and same and vim.uv.fs_stat(ORDER) ~= nil and reqs == 2,
    ("%s; %s; documentSymbol asked %d time(s) (file with several types); disk %s"):format(r[1].d, r[2].d, reqs, d))
end)

-- move_symbols_timeout: a file with several types (Order: nested Line, second type Extra), jdt.ls's
-- documentSymbol stubbed to time out, cursor in Line: refused visibly ("did not tell which one"),
-- nothing moved (before the fix: the whole file moved).
case("move_symbols_timeout", function()
  if not has("move") then return lsp.report(P .. "move_symbols_timeout", false, pending_reason("move")) end
  plant_order()
  local b = lsp.open(ORDER)
  local real = client.request_sync
  local n = 0
  client.request_sync = function(self, m, params, t, bb)
    if m == "textDocument/documentSymbol" then n = n + 1; return nil, "timeout" end
    return real(self, m, params, t, bb)
  end
  local l = E.line_of(b, "int qty")
  vim.api.nvim_set_current_buf(b); vim.api.nvim_win_set_cursor(0, { l + 1, 8 })
  local got, stop = capture()
  local ok = refactor.move({ package = "demo.shop" })
  vim.wait(200)
  client.request_sync = real
  stop()
  local msg = find_msg(got, "did not tell which one the cursor is in", vim.log.levels.WARN)
  local same, d = unchanged({ [ORDER] = true })
  lsp.report(P .. "move_symbols_timeout", ok == false and msg ~= nil and n == 1 and same and vim.uv.fs_stat(ORDER) ~= nil,
    ("returned %s; %d stubbed documentSymbol request(s); message: %s; disk %s"):format(tostring(ok), n, tostring(msg), d))
end)

--- Answer the next vim.ui.select with the item equal to `want`; returns the table that gets items/prompt.
local function answer_select_exact(want)
  local real, seen = vim.ui.select, {}
  vim.ui.select = function(items, o, cb)
    vim.ui.select = real
    seen.items, seen.prompt = items, o and o.prompt
    for _, it in ipairs(items) do
      if it == want then return cb(it) end
    end
    cb(nil)
  end
  return seen
end

-- move_prompt: move() with no package from the `package` line (outside any type: the file's class
-- moves) picks the target with vim.ui.select (the project's packages without the current one, plus "New
-- package..."); answered demo.shop.
case("move_prompt", function()
  if not has("move") then return lsp.report(P .. "move_prompt", false, pending_reason("move")) end
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT); lsp.open(CALC)
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local seen = answer_select_exact("demo.shop")
  local t0 = E.now()
  refactor.move()
  local applied, ms = until_ms(t0, function() return vim.uv.fs_stat(SHOP_INV) ~= nil and (text_of(CALC) or ""):find("import demo.shop.Invoice;", 1, true) ~= nil end)
  local items = seen.items or {}
  local ok_clean, why = clean({ CHECKOUT, CALC, SHOP_INV }, t0)
  report_apply("move_prompt", ("move() from the package line (select %q: %s)"):format(tostring(seen.prompt), table.concat(items, " | ")),
    applied, ms, {
      { "items: demo.shop and New package..., not demo.billing", vim.tbl_contains(items, "demo.shop") and vim.tbl_contains(items, "New package...")
        and not vim.tbl_contains(items, "demo.billing") },
    }, ok_clean, why)
end)

-- move_key_new_package: <leader>jm (the mapping's own function): "New package..." then the name typed
-- (demo.invoicing): created and moved.
case("move_key_new_package", function()
  if not has("move") then return lsp.report(P .. "move_key_new_package", false, pending_reason("move")) end
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT); lsp.open(CALC)
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { 5, 14 })
  local m = vim.fn.maparg("<leader>jm", "n", false, true)
  if not m.callback then return lsp.report(P .. "move_key_new_package", false, "<leader>jm has no Lua callback: " .. vim.inspect(m.rhs)) end
  answer_select_exact("New package...")
  local seen = answer_input("demo.invoicing")
  local t0 = E.now()
  m.callback()
  local applied, ms = until_ms(t0, function() return (disk(NEWPKG_INV) or ""):find("package demo.invoicing;", 1, true) ~= nil end)
  report_apply("move_key_new_package", ("<leader>jm, New package..., input %q (default %q)"):format(tostring(seen.prompt), tostring(seen.default)),
    applied, ms, {
      { "input prompt names Invoice", (seen.prompt or ""):find("Move class Invoice", 1, true) ~= nil },
      { "buffer re-pointed", loaded(NEWPKG_INV) ~= nil and loaded(INVOICE) == nil },
    }, clean({ NEWPKG_INV, CHECKOUT, CALC }, t0))
end)

-- move_class_boot: the Spring controller GreetingController to demo.web (new, under the
-- @SpringBootApplication package demo): @RestController/@GetMapping kept, build clean, no scan warning.
-- move_class_boot_scan: to `web` (outside demo): moved, and the summary warns that component scanning
-- will not find it.
local GC = main .. "demo/GreetingController.java"
for _, w in ipairs({ { "move_class_boot", "demo.web", "demo/web" }, { "move_class_boot_scan", "web", "web" } }) do
  case(w[1], function()
    if not has("move") then return lsp.report(P .. w[1], false, pending_reason("move")) end
    local MOVED = main .. w[3] .. "/GreetingController.java"
    local b = lsp.open(GC)
    local l, c = pos(b, "^public class GreetingController", "GreetingController")
    vim.api.nvim_set_current_buf(b); vim.api.nvim_win_set_cursor(0, { l + 1, c })
    local got, stop = capture()
    local t0 = E.now()
    refactor.move({ package = w[2] })
    local applied, ms = until_ms(t0, function() return (disk(MOVED) or ""):find("package " .. w[2] .. ";", 1, true) ~= nil end)
    stop()
    local ok_clean, why = clean({ MOVED }, t0)
    local ht = disk(MOVED) or ""
    local scan = find_msg(got, "component scanning will not find it", vim.log.levels.WARN)
    report_apply(w[1], "nv4j.refactor.move", applied, ms, {
      { "GreetingController.java gone", vim.uv.fs_stat(GC) == nil and loaded(GC) == nil },
      { "@RestController and @GetMapping kept", ht:find("@RestController\npublic class GreetingController", 1, true) ~= nil
        and ht:find('@GetMapping("/hello")', 1, true) ~= nil },
      w[2] == "web" and { "scan warning: " .. tostring(scan), scan ~= nil and scan:find("outside demo", 1, true) ~= nil }
        or { "no scan warning", scan == nil },
    }, ok_clean, why)
  end)
end

-- move_class_test_stays: a test of the moved class (InvoiceTest, planted in src/test/java/demo/billing)
-- stays in its package (jdt.ls moves only Invoice and adds the import there); the summary says so.
case("move_class_test_stays", function()
  if not has("move") then return lsp.report(P .. "move_class_test_stays", false, pending_reason("move")) end
  local IT = TEST .. "demo/billing/InvoiceTest.java"
  local f = assert(io.open(IT, "w"))
  f:write([[package demo.billing;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

// planted by 62_refactor move_class_test_stays, removed after the case
class InvoiceTest {
    @Test
    void quantity() {
        assertEquals(2, new Invoice(2, 3).quantity());
    }
}
]])
  f:close()
  local inv = lsp.open(INVOICE)
  local itb = lsp.open(IT)
  lsp.open(CHECKOUT); lsp.open(CALC)
  vim.wait(1500, function() return (published_at[vim.uri_from_fname(IT)] or 0) > 0 end, 20)
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { 5, 14 })
  local got, stop = capture()
  local t0 = E.now()
  refactor.move({ package = "demo.shop" })
  local applied, ms = until_ms(t0, function() return vim.uv.fs_stat(SHOP_INV) ~= nil and (disk(IT) or ""):find("import demo.shop.Invoice;", 1, true) ~= nil end)
  stop()
  local sum = find_msg(got, "Moved class Invoice to package demo.shop") or ""
  local ok_clean, why = clean({ IT, SHOP_INV, CALC }, t0)
  report_apply("move_class_test_stays", "nv4j.refactor.move", applied, ms, {
    { "InvoiceTest stays in demo.billing", vim.uv.fs_stat(IT) ~= nil and (disk(IT) or ""):find("package demo.billing;", 1, true) ~= nil
      and loaded(IT) == itb },
    { "summary says it stays", sum:find("src/test/java/demo/billing/InvoiceTest.java stays in package demo.billing", 1, true) ~= nil },
  }, ok_clean, why)
end)

-- move_class_stale: a properties value with the old qualified name demo.billing.Invoice and a Java string
-- "Invoice" (planted): the warning lists the properties line, not the simple-name string (still right).
case("move_class_stale", function()
  if not has("move") then return lsp.report(P .. "move_class_stale", false, pending_reason("move")) end
  local Q = main .. "demo/shop/InvoiceLabels.java"
  local PROPS = fixture .. "/src/main/resources/application.properties"
  local fq = assert(io.open(Q, "w"))
  fq:write('package demo.shop;\n\n// planted by 62_refactor move_class_stale\npublic class InvoiceLabels {\n    static final String TITLE = "Invoice";\n}\n')
  fq:close()
  local fp = assert(io.open(PROPS, "a")); fp:write("demo.refactor.type=demo.billing.Invoice\n"); fp:close()
  local props_line = #vim.fn.readfile(PROPS)
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT); lsp.open(CALC)
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { 5, 14 })
  local got, stop = capture()
  local t0 = E.now()
  refactor.move({ package = "demo.shop" })
  local applied, ms = until_ms(t0, function() return find_msg(got, "Moved class Invoice to package demo.shop") ~= nil end)
  stop()
  local sum = find_msg(got, "Moved class Invoice to package demo.shop", vim.log.levels.WARN) or ""
  report_apply("move_class_stale", "nv4j.refactor.move", applied, ms, {
    { "warning lists application.properties:" .. props_line, sum:find("src/main/resources/application.properties:" .. props_line, 1, true) ~= nil },
    { "no hit on the simple name (InvoiceLabels.java)", not sum:find("InvoiceLabels.java:", 1, true) },
    { "nothing rewritten", (disk(PROPS) or ""):find("=demo.billing.Invoice", 1, true) ~= nil },
  }, clean({ CHECKOUT, CALC, SHOP_INV }, t0))
end)

-- move_class_errors: a syntax error in Checkout (unsaved) before the move. Measured: jdt.ls still updates
-- Checkout's import on a move (unlike a class rename, which skips that file); either way the result is
-- honest: the import updated, or the summary warns with Checkout.java:3. The 3 s follow-up (jdt.ls's own
-- errors) is shown in the detail, not required.
case("move_class_errors", function()
  if not has("move") then return lsp.report(P .. "move_class_errors", false, pending_reason("move")) end
  local inv, chk = lsp.open(INVOICE), lsp.open(CHECKOUT)
  lsp.open(CALC)
  local bl = E.line_of(chk, "^public class Checkout")
  vim.api.nvim_buf_set_lines(chk, bl + 1, bl + 1, false, { "    int broken = ;" })
  local tset = E.now()
  vim.wait(CLEAN_MS, function()
    return (published_at[vim.uri_from_fname(CHECKOUT)] or 0) >= tset and E.count(vim.diagnostic.get(chk), vim.diagnostic.severity.ERROR) > 0
  end, 20)
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { 5, 14 })
  local got, stop = capture()
  local t0 = E.now()
  refactor.move({ package = "demo.shop" })
  local applied, ms = until_ms(t0, function() return vim.uv.fs_stat(SHOP_INV) ~= nil and loaded(SHOP_INV) ~= nil end)
  local sum = find_msg(got, "Moved class Invoice to package demo.shop") or ""
  local warn
  vim.wait(4000, function()
    warn = find_msg(got, "Moved class Invoice to package demo.shop applied, but", vim.log.levels.WARN)
    return warn ~= nil
  end, 20)
  stop()
  local ct = text_of(CHECKOUT) or ""
  local updated = not ct:find("import demo.billing.Invoice;", 1, true)
  local named = sum:find("src/main/java/demo/shop/Checkout.java:3", 1, true) ~= nil
  lsp.report(P .. "move_class_errors", applied and ms <= APPLY_MS and (updated or named) and ct:find("int broken = ;", 1, true) ~= nil,
    ("applied %s after %.0f ms; Checkout's import %s by jdt.ls; summary %s; Checkout's syntax error kept; follow-up: %s"):format(
      applied and "yes" or "NO", ms, updated and "updated" or "NOT updated", named and "names Checkout.java:3" or "does not name Checkout",
      tostring(warn)))
end)

-- move_class_skipped_twin (deterministic): jdt.ls's move edit with Checkout's change dropped (what jdt.ls
-- does to a file it cannot parse on a class rename): the summary warns with Checkout.java:3 (its import
-- of demo.billing.Invoice, found from the text).
case("move_class_skipped_twin", function()
  if not has("move") then return lsp.report(P .. "move_class_skipped_twin", false, pending_reason("move")) end
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT); lsp.open(CALC)
  local real = client.request_sync
  client.request_sync = function(self, m, params, t, b)
    local res, err = real(self, m, params, t, b)
    if m == "workspace/willRenameFiles" and res and res.result and res.result.documentChanges then
      res.result.documentChanges = vim.tbl_filter(function(ch)
        return not (ch.textDocument and ch.textDocument.uri:find("/demo/shop/Checkout.java", 1, true))
      end, res.result.documentChanges)
    end
    return res, err
  end
  vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { 5, 14 })
  local got, stop = capture()
  local t0 = E.now()
  local ok = refactor.move({ package = "demo.shop" })
  local ms = E.now() - t0
  client.request_sync = real
  stop()
  local sum = find_msg(got, "Moved class Invoice to package demo.shop", vim.log.levels.WARN) or ""
  lsp.report(P .. "move_class_skipped_twin", ok == true and sum:find("src/main/java/demo/shop/Checkout.java:3", 1, true) ~= nil
    and (text_of(CHECKOUT) or ""):find("import demo.billing.Invoice;", 1, true) ~= nil,
    ("returned %s after %.0f ms; warning: %s"):format(tostring(ok), ms, sum ~= "" and sum or "NONE"))
end)

-- ── inline (Task 4c): nv4j.refactor.inline over jdt.ls's inline code actions ────────────────────────

--- Inline at (pat, word) in PriceCalculator; `want` must appear in the file afterwards, `gone` not; the
--- summary must start with `label` (and name PriceCalculator.java only); written to disk; then one `u`
--- gives the text back (<name>_undo). `opts` for refactor.inline; `checks(text)` extra checks.
local function inline_case(name, pat, word, title, want, gone, label, opts, checks)
  case(name, function()
    local calc = lsp.open(CALC)
    lsp.open(CHECKOUT)
    local l, c = pos(calc, pat, word)
    local before = E.text(calc)
    local t0, how = E.now(), nil
    local got, stop = capture()
    if has("inline") then
      vim.api.nvim_set_current_buf(calc); vim.api.nvim_win_set_cursor(0, { l + 1, c })
      how = "nv4j.refactor.inline(" .. (opts and vim.inspect(opts, { newline = "", indent = "" }) or "") .. ")"; refactor.inline(opts)
    else
      local ok, t = code_action(calc, l, c, title)
      how = "code action " .. tostring(t)
      if not ok then stop(); return report_apply(name, how, false, 0, {}, false, "") end
    end
    local applied, ms = until_ms(t0, function() return E.text(calc) ~= before and E.text(calc):find(want, 1, true) ~= nil end)
    stop()
    local ok_clean, why = clean({ CALC }, t0)
    local txt = E.text(calc)
    local sum = find_msg(got, label) or ""
    local list = {
      { "`" .. gone .. "` gone", not txt:find(gone, 1, true) },
      { "written to disk", (disk(CALC) or ""):find(want, 1, true) ~= nil and not vim.bo[calc].modified },
      { "summary: " .. label .. ", 1 file PriceCalculator.java", sum:find(label .. ": 1 file(s): src/main/java/demo/billing/PriceCalculator.java", 1, true) == 1 },
    }
    for _, x in ipairs(checks and checks(txt) or {}) do list[#list + 1] = x end
    report_apply(name, how, applied, ms, list, ok_clean, why)
    vim.api.nvim_buf_call(calc, function() vim.cmd("silent! undo") end)
    lsp.report(P .. name .. "_undo", applied and E.text(calc) == before,
      applied and (E.text(calc) == before and "one u restored PriceCalculator" or "NOT restored by one u") or "inline not applied, nothing to undo")
  end)
end
inline_case("inline_method", "int gross = gross%(invoice%);", "gross(", "^Inline [Mm]ethod",
  "int gross = invoice.quantity() * invoice.unitPrice();", "= gross(invoice)", "Inlined method gross (this call only; declaration kept)", nil,
  function(txt) return { { "declaration kept (jdt.ls: a call inlines that call)", txt:find("private int gross(Invoice invoice)", 1, true) ~= nil } } end)
inline_case("inline_variable", "^%s+return gross;", "gross", "^Inline local variable", "return gross(invoice);", "int gross =",
  "Inlined local variable gross (every use; declaration removed)")

-- inline_method_all: opts.all on the call: jdt.ls asked at the declaration (every call, declaration removed).
-- inline_method_declaration: the cursor on the declaration without opts: the same (jdt.ls's own choice);
-- "Make Static" (also kind refactor.inline, offered first there) is not taken.
local function gross_removed(txt)
  return {
    { "declaration removed", not txt:find("gross(Invoice", 1, true) },
    { "not made static", not txt:find("static", 1, true) },
  }
end
inline_case("inline_method_all", "int gross = gross%(invoice%);", "gross(", "^Inline [Mm]ethod",
  "int gross = invoice.quantity() * invoice.unitPrice();", "private int gross(", "Inlined method gross (every call; declaration removed)",
  { all = true }, gross_removed)
inline_case("inline_method_declaration", "private int gross%(", "gross", "^Inline [Mm]ethod",
  "int gross = invoice.quantity() * invoice.unitPrice();", "private int gross(", "Inlined method gross (every call; declaration removed)",
  nil, gross_removed)

local GCTRL = main .. "demo/GreetingController.java"
local GCFG = main .. "demo/GreetingConfig.java"

--- Writes `path` as its snapshot content with each { from, to } replaced once (plain text).
local function plant(path, subs)
  local s = assert(snap.files[path], "not in the snapshot: " .. path)
  for _, sub in ipairs(subs) do
    local i, j = s:find(sub[1], 1, true)
    assert(i, ("plant: '%s' not in %s"):format(sub[1], path))
    s = s:sub(1, i - 1) .. sub[2] .. s:sub(j + 1)
  end
  local f = assert(io.open(path, "wb")); f:write(s); f:close()
end

--- Opens `paths` and waits for jdt.ls to publish each (it has their planted content).
local function open_fresh(paths)
  local t, bufs = E.now(), {}
  for _, p in ipairs(paths) do bufs[#bufs + 1] = lsp.open(p) end
  vim.wait(CLEAN_MS + 2000, function()
    for _, p in ipairs(paths) do
      if (published_at[vim.uri_from_fname(p)] or 0) < t then return false end
    end
    return true
  end, 20)
  return unpack(bufs)
end

--- refactor.inline(opts) (or `fn`) with the cursor on `word` in the first line of `buf` matching `pat`.
--- Returns { ret, ms, got } (inline is synchronous unless it prompts).
local function inline_at(buf, pat, word, opts, fn)
  local l, c = pos(buf, pat, word)
  vim.api.nvim_set_current_buf(buf); vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local got, stop = capture()
  local t0 = E.now()
  local ret = (fn or refactor.inline)(opts)
  local ms = E.now() - t0
  stop()
  return { ret = ret, ms = ms, got = got }
end

-- A public constant in Invoice used in Invoice and in Checkout (another package, two files).
local function plant_constant()
  plant(INVOICE, { { "public class Invoice {\n", "public class Invoice {\n    public static final int MAX_QUANTITY = 99;\n\n" },
    { "    public int quantity() {", "    public boolean tooMany() {\n        return quantity > MAX_QUANTITY;\n    }\n\n    public int quantity() {" } })
  plant(CHECKOUT, { { "    public int payTwice(", "    public int cap() {\n        return Invoice.MAX_QUANTITY - 1;\n    }\n\n    public int payTwice(" } })
  return open_fresh({ INVOICE, CHECKOUT })
end

-- inline_constant: <leader>ji (the mapping's own function) on Checkout's reference: that reference only.
case("inline_constant", function()
  if not has("inline") then return lsp.report(P .. "inline_constant", false, pending_reason("inline")) end
  local inv, chk = plant_constant()
  local m = vim.fn.maparg("<leader>ji", "n", false, true)
  if not m.callback then return lsp.report(P .. "inline_constant", false, "<leader>ji has no Lua callback: " .. vim.inspect(m.rhs)) end
  local planted_inv = E.text(inv)
  local r = inline_at(chk, "return Invoice%.MAX_QUANTITY", "MAX_QUANTITY", nil, function() return m.callback() end)
  local label = "Inlined constant MAX_QUANTITY (this reference only; declaration kept)"
  local sum = find_msg(r.got, label) or ""
  report_apply("inline_constant", "<leader>ji", (text_of(CHECKOUT) or ""):find("return 99 - 1;", 1, true) ~= nil, r.ms, {
    { "Invoice unchanged (declaration and its use kept)", E.text(inv) == planted_inv },
    { "Checkout written", (disk(CHECKOUT) or ""):find("return 99 - 1;", 1, true) ~= nil },
    { "summary: 1 file Checkout.java", sum:find(label .. ": 1 file(s): src/main/java/demo/shop/Checkout.java", 1, true) == 1 },
  }, clean({ CHECKOUT, INVOICE }, E.now() - r.ms))
end)

-- inline_constant_all: opts.all on Checkout's reference: every reference in both files, declaration removed.
case("inline_constant_all", function()
  if not has("inline") then return lsp.report(P .. "inline_constant_all", false, pending_reason("inline")) end
  local inv, chk = plant_constant()
  local before = { [inv] = E.text(inv), [chk] = E.text(chk) }
  local r = inline_at(chk, "return Invoice%.MAX_QUANTITY", "MAX_QUANTITY", { all = true })
  local label = "Inlined constant MAX_QUANTITY (every reference; declaration removed)"
  local sum = find_msg(r.got, label) or ""
  local it, ct = E.text(inv), E.text(chk)
  report_apply("inline_constant_all", "nv4j.refactor.inline({ all = true })", r.ret == true and ct:find("return 99 - 1;", 1, true) ~= nil, r.ms, {
    { "Invoice's use inlined", it:find("return quantity > 99;", 1, true) ~= nil },
    { "declaration removed", not it:find("MAX_QUANTITY", 1, true) },
    { "both written", (disk(INVOICE) or ""):find("quantity > 99", 1, true) ~= nil and (disk(CHECKOUT) or ""):find("return 99 - 1;", 1, true) ~= nil },
    { "summary lists both files", sum:find(label .. ": 2 file(s)", 1, true) == 1 and sum:find("demo/billing/Invoice.java", 1, true) ~= nil
      and sum:find("demo/shop/Checkout.java", 1, true) ~= nil },
  }, clean({ CHECKOUT, INVOICE }, E.now() - r.ms))
  local bad = {}
  for b, txt in pairs(before) do
    vim.api.nvim_buf_call(b, function() vim.cmd("silent! undo") end)
    if E.text(b) ~= txt then bad[#bad + 1] = vim.fs.basename(vim.api.nvim_buf_get_name(b)) end
  end
  lsp.report(P .. "inline_constant_all_undo", r.ret == true and #bad == 0, r.ret == true and (#bad == 0 and "one u restored Invoice and Checkout"
    or ("not restored by one u: " .. table.concat(bad, ", "))) or "inline not applied, nothing to undo")
end)

-- inline_unsaved: the same with unsaved user edits in Invoice and Checkout: both edited in place, the user
-- edits kept, both left unsaved (disk = planted content), the summary says so.
case("inline_unsaved", function()
  if not has("inline") then return lsp.report(P .. "inline_unsaved", false, pending_reason("inline")) end
  local inv, chk = plant_constant()
  local d_inv, d_chk = disk(INVOICE), disk(CHECKOUT)
  append_line(inv, "// user edit in Invoice")
  append_line(chk, "// user edit in Checkout")
  local r = inline_at(chk, "return Invoice%.MAX_QUANTITY", "MAX_QUANTITY", { all = true })
  local label = "Inlined constant MAX_QUANTITY (every reference; declaration removed)"
  local sum = find_msg(r.got, label) or ""
  local it, ct = E.text(inv), E.text(chk)
  report_apply("inline_unsaved", "nv4j.refactor.inline({ all = true })", r.ret == true and ct:find("return 99 - 1;", 1, true) ~= nil, r.ms, {
    { "user edits kept", it:find("// user edit in Invoice", 1, true) ~= nil and ct:find("// user edit in Checkout", 1, true) ~= nil },
    { "Invoice inlined in the buffer", it:find("return quantity > 99;", 1, true) ~= nil and not it:find("MAX_QUANTITY", 1, true) },
    { "both left unsaved (disk untouched)", vim.bo[inv].modified and vim.bo[chk].modified and disk(INVOICE) == d_inv and disk(CHECKOUT) == d_chk },
    { "summary: both [left unsaved", select(2, sum:gsub("%[left unsaved", "")) == 2 },
  }, clean({ CHECKOUT, INVOICE }, E.now() - r.ms))
end)

--- Nothing changed: every listed buffer's text as before and not modified, disk as planted.
local function untouched(bufs)
  for b, txt in pairs(bufs) do
    if E.text(b) ~= txt or vim.bo[b].modified then return false end
  end
  return true
end

-- inline_refused: nothing to inline at the cursor (the @Value field `text` in GreetingController, the
-- `return` keyword), and opts.all on a JDK method (its declaration is not in the project): refused with
-- the reason, nothing changed.
case("inline_refused", function()
  if not has("inline") then return lsp.report(P .. "inline_refused", false, pending_reason("inline")) end
  plant(CALC, { { "    public int legacyTotal(", "    public int atLeastOne(int a) {\n        return Math.max(a, 1);\n    }\n\n    public int legacyTotal(" } })
  local gc, calc = open_fresh({ GCTRL, CALC })
  local before = { [gc] = E.text(gc), [calc] = E.text(calc) }
  local a = inline_at(gc, "return text;", "text")
  local b = inline_at(calc, "^%s+return gross;", "return")
  local c = inline_at(calc, "Math%.max", "max", { all = true })
  local ma = find_msg(a.got, "Inline: nothing to inline at `text`", vim.log.levels.WARN)
  local mb = find_msg(b.got, "Inline: nothing to inline at `return`", vim.log.levels.WARN)
  local mc = find_msg(c.got, "its declaration is not in this project", vim.log.levels.WARN)
  lsp.report(P .. "inline_refused", a.ret == false and b.ret == false and c.ret == false and ma and mb and mc and untouched(before) or false,
    ("@Value field: %s (%.0f ms); keyword: %s; all on Math.max: %s; files %s"):format(tostring(ma), a.ms, tostring(mb), tostring(mc),
      untouched(before) and "unchanged" or "CHANGED"))
end)

-- inline_recursive: a recursive method: jdt.ls offers Inline Method at the recursive call but gives no edit:
-- refused, nothing changed.
case("inline_recursive", function()
  if not has("inline") then return lsp.report(P .. "inline_recursive", false, pending_reason("inline")) end
  plant(CALC, { { "    public int legacyTotal(", "    int fact(int n) {\n        return n <= 1 ? 1 : n * fact(n - 1);\n    }\n\n    public int legacyTotal(" } })
  local calc = open_fresh({ CALC })
  local before = { [calc] = E.text(calc) }
  local r = inline_at(calc, "n %* fact%(", "fact")
  local msg = find_msg(r.got, "Inline: jdt.ls offered Inline Method at `fact` but gave no edit", vim.log.levels.WARN)
  lsp.report(P .. "inline_recursive", r.ret == false and msg ~= nil and untouched(before),
    ("returned %s after %.0f ms; message: %s; file %s"):format(tostring(r.ret), r.ms, tostring(msg), untouched(before) and "unchanged" or "CHANGED"))
end)

-- inline_resolve_error (twin, stubbed): jdt.ls answers codeAction/resolve with an error: shown, nothing changed.
case("inline_resolve_error", function()
  if not has("inline") then return lsp.report(P .. "inline_resolve_error", false, pending_reason("inline")) end
  local calc = lsp.open(CALC)
  local before = { [calc] = E.text(calc) }
  local real = client.request_sync
  client.request_sync = function(self, m, params, t, b)
    if m == "codeAction/resolve" then return { err = { code = -32603, message = "stubbed resolve failure" } } end
    return real(self, m, params, t, b)
  end
  local ok, r = pcall(inline_at, calc, "int gross = gross%(invoice%);", "gross(")
  client.request_sync = real
  if not ok then error(r) end
  local msg = find_msg(r.got, "stubbed resolve failure", vim.log.levels.ERROR)
  lsp.report(P .. "inline_resolve_error", r.ret == false and msg ~= nil and untouched(before),
    ("returned %s; message: %s; file %s"):format(tostring(r.ret), tostring(msg), untouched(before) and "unchanged" or "CHANGED"))
end)

-- inline_two_actions (twin, stubbed): jdt.ls offering two inline actions at one place ("... (this
-- invocation)" and "... (all invocations)", same edit): without opts the user picks (vim.ui.select with both
-- titles); with opts.all the "all" one is taken without a prompt.
case("inline_two_actions", function()
  if not has("inline") then return lsp.report(P .. "inline_two_actions", false, pending_reason("inline")) end
  local real = client.request_sync
  client.request_sync = function(self, m, params, t, b)
    local res, err = real(self, m, params, t, b)
    if m == "textDocument/codeAction" and res and type(res.result) == "table" then
      local out = {}
      for _, a in ipairs(res.result) do
        if a.title == "Inline Method" then
          out[#out + 1] = vim.tbl_extend("force", a, { title = "Inline Method (this invocation)" })
          out[#out + 1] = vim.tbl_extend("force", a, { title = "Inline Method (all invocations)" })
        else
          out[#out + 1] = a
        end
      end
      res.result = out
    end
    return res, err
  end
  local orig_sel = vim.ui.select
  local ok, err = pcall(function()
    local calc = lsp.open(CALC)
    local items
    vim.ui.select = function(its, o, cb)
      vim.ui.select = orig_sel
      items = vim.tbl_map(function(x) return o.format_item(x) end, its)
      for _, it in ipairs(its) do
        if o.format_item(it):find("(this invocation)", 1, true) then return cb(it) end
      end
      cb(nil)
    end
    inline_at(calc, "int gross = gross%(invoice%);", "gross(")
    vim.ui.select = orig_sel
    local first = refactor.last and refactor.last.title
    local applied_a = E.text(calc):find("int gross = invoice.quantity() * invoice.unitPrice();", 1, true) ~= nil
    F.restore(snap, client)
    calc = lsp.open(CALC)
    local prompted = false
    vim.ui.select = function(_, _, cb) prompted = true; vim.ui.select = orig_sel; cb(nil) end
    local b = inline_at(calc, "int gross = gross%(invoice%);", "gross(", { all = true })
    vim.ui.select = orig_sel
    local second = refactor.last and refactor.last.title
    lsp.report(P .. "inline_two_actions", applied_a and first == "Inline Method (this invocation)" and b.ret == true
      and second == "Inline Method (all invocations)" and not prompted and items ~= nil and #items >= 2,
      ("no opts: prompt items %s, picked %s, applied %s; all=true: prompted %s, took %s, returned %s"):format(
        items and table.concat(items, " | ") or "NONE", tostring(first), tostring(applied_a), tostring(prompted), tostring(second), tostring(b.ret)))
  end)
  vim.ui.select = orig_sel
  client.request_sync = real
  if not ok then error(err) end
end)

-- inline_bean_call: GreetingConfig with a @Bean greeter calling the @Bean devBanner (planted): the call
-- inlined, devBanner kept, and a warning (the call returned the container's bean, the inlined code
-- builds a new one). inline_bean_declaration: on devBanner's declaration: inlined, devBanner gone, warning
-- (the bean is no longer defined).
local function plant_beans()
  plant(GCFG, { { "        return \"dev: \" + properties.text();\n    }\n", "        return \"dev: \" + properties.text();\n    }\n\n    @Bean\n    public String greeter(GreetingProperties properties) {\n        return devBanner(properties) + \"!\";\n    }\n" } })
  return open_fresh({ GCFG })
end
case("inline_bean_call", function()
  if not has("inline") then return lsp.report(P .. "inline_bean_call", false, pending_reason("inline")) end
  local cfg = plant_beans()
  local r = inline_at(cfg, "return devBanner%(properties%)", "devBanner")
  local t = E.text(cfg)
  local warn = find_msg(r.got, "Spring: devBanner is a @Bean method: the inlined call returned the container's bean", vim.log.levels.WARN)
  report_apply("inline_bean_call", "nv4j.refactor.inline()", r.ret == true, r.ms, {
    { "call inlined", t:find('return "dev: " + properties.text() + "!";', 1, true) ~= nil },
    { "devBanner kept", t:find("public String devBanner(", 1, true) ~= nil },
    { "Spring warning", warn ~= nil },
  }, clean({ GCFG }, E.now() - r.ms))
end)
case("inline_bean_declaration", function()
  if not has("inline") then return lsp.report(P .. "inline_bean_declaration", false, pending_reason("inline")) end
  local cfg = plant_beans()
  local r = inline_at(cfg, "public String devBanner%(", "devBanner")
  local t = E.text(cfg)
  local warn = find_msg(r.got, "the bean `devBanner` is no longer defined", vim.log.levels.WARN)
  report_apply("inline_bean_declaration", "nv4j.refactor.inline()", r.ret == true, r.ms, {
    { "call inlined", t:find('return "dev: " + properties.text() + "!";', 1, true) ~= nil },
    { "devBanner gone", not t:find("devBanner", 1, true) },
    { "summary says declaration removed", find_msg(r.got, "Inlined method devBanner (every call; declaration removed)") ~= nil },
    { "Spring warning", warn ~= nil },
  }, clean({ GCFG }, E.now() - r.ms))
end)

-- inline_value_constant: a constant used as the @Value key in GreetingController (planted), inlined from its
-- declaration: `@Value("${demo.greeting.text:Hello}")` again, constant gone, no Spring warning, build clean.
case("inline_value_constant", function()
  if not has("inline") then return lsp.report(P .. "inline_value_constant", false, pending_reason("inline")) end
  plant(GCTRL, { { '    @Value("${demo.greeting.text:Hello}")', '    static final String TEXT_KEY = "${demo.greeting.text:Hello}";\n\n    @Value(TEXT_KEY)' } })
  local gc = open_fresh({ GCTRL })
  local r = inline_at(gc, "static final String TEXT_KEY", "TEXT_KEY")
  local t = E.text(gc)
  report_apply("inline_value_constant", "nv4j.refactor.inline()", r.ret == true, r.ms, {
    { "@Value literal back", t:find('@Value("${demo.greeting.text:Hello}")', 1, true) ~= nil },
    { "constant gone", not t:find("TEXT_KEY", 1, true) },
    { "no warning", find_msg(r.got, "Inlined constant TEXT_KEY (every reference; declaration removed)", vim.log.levels.INFO) ~= nil },
  }, clean({ GCTRL }, E.now() - r.ms))
end)

-- inline_errors: a syntax error in Checkout (unsaved), then the constant inlined everywhere from Invoice's
-- declaration: either jdt.ls also inlines Checkout's reference, or the summary names Checkout's line
-- (jdt.ls's own references); Checkout keeps its syntax error. _twin (deterministic): Checkout's edit
-- dropped from jdt.ls's answer (stub): the warning names Checkout.java's reference line.
case("inline_errors", function()
  if not has("inline") then return lsp.report(P .. "inline_errors", false, pending_reason("inline")) end
  local inv, chk = plant_constant()
  local bl = E.line_of(chk, "^public class Checkout")
  vim.api.nvim_buf_set_lines(chk, bl + 1, bl + 1, false, { "    int broken = ;" })
  local tset = E.now()
  vim.wait(CLEAN_MS, function()
    return (published_at[vim.uri_from_fname(CHECKOUT)] or 0) >= tset and E.count(vim.diagnostic.get(chk), vim.diagnostic.severity.ERROR) > 0
  end, 20)
  local ref_line = E.line_of(chk, "return Invoice%.MAX_QUANTITY") + 1
  local r = inline_at(inv, "public static final int MAX_QUANTITY", "MAX_QUANTITY")
  local ct = E.text(chk)
  local updated = ct:find("return 99 - 1;", 1, true) ~= nil
  local named = find_msg(r.got, "src/main/java/demo/shop/Checkout.java:" .. ref_line, vim.log.levels.WARN) ~= nil
  lsp.report(P .. "inline_errors", r.ms <= APPLY_MS and r.ret == true and (updated or named) and ct:find("int broken = ;", 1, true) ~= nil,
    ("returned %s after %.0f ms; Checkout's reference %s by jdt.ls; warning %s; Checkout's syntax error kept; messages: %s"):format(tostring(r.ret), r.ms,
      updated and "inlined" or "NOT inlined", named and ("names Checkout.java:" .. ref_line) or "does not name Checkout",
      table.concat(vim.tbl_map(function(m) return m.msg end, r.got), " || ")))
end)
case("inline_errors_twin", function()
  if not has("inline") then return lsp.report(P .. "inline_errors_twin", false, pending_reason("inline")) end
  local inv, chk = plant_constant()
  local ref_line = E.line_of(chk, "return Invoice%.MAX_QUANTITY") + 1
  local real = client.request_sync
  client.request_sync = function(self, m, params, t, b)
    local res, err = real(self, m, params, t, b)
    if m == "codeAction/resolve" and res and res.result and res.result.edit and res.result.edit.documentChanges then
      res.result.edit.documentChanges = vim.tbl_filter(function(ch)
        return not (ch.textDocument and ch.textDocument.uri:find("/demo/shop/Checkout.java", 1, true))
      end, res.result.edit.documentChanges)
    end
    return res, err
  end
  local ok, r = pcall(inline_at, inv, "public static final int MAX_QUANTITY", "MAX_QUANTITY")
  client.request_sync = real
  if not ok then error(r) end
  local warn = find_msg(r.got, "NOT inlined by jdt.ls", vim.log.levels.WARN) or ""
  lsp.report(P .. "inline_errors_twin", r.ret == true and warn:find("src/main/java/demo/shop/Checkout.java:" .. ref_line, 1, true) ~= nil
    and warn:find("whose declaration is gone", 1, true) ~= nil and E.text(chk):find("Invoice.MAX_QUANTITY", 1, true) ~= nil,
    ("returned %s after %.0f ms; warning: %s"):format(tostring(r.ret), r.ms, warn ~= "" and warn or "NONE"))
end)
-- ── change signature (Task 4d): nv4j.refactor.change_signature over jdt.ls's getChangeSignatureInfo /
-- getRefactorEdit ("changeSignature"), with arguments, no float ───────────────────────────────────────
local PCFT = TEST .. "demo/billing/PriceCalculatorFailingTest.java"
local ADD_DISCOUNT = { add = { { type = "int", name = "discount", default = "0" } } }

--- refactor.change_signature(opts) (or `fn`) with the cursor on `word` in the first line of `buf` matching
--- `pat`. Returns { ret, ms, got } (change_signature is synchronous unless it prompts).
local function cs_at(buf, pat, word, opts, fn)
  local l, c = pos(buf, pat, word)
  vim.api.nvim_set_current_buf(buf); vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local got, stop = capture()
  local t0 = E.now()
  local ok, ret = pcall(fn or refactor.change_signature, opts)
  local ms = E.now() - t0
  stop()
  if not ok then error(ret) end
  return { ret = ret, ms = ms, got = got }
end

--- Build clean after a change signature. What it waits on (deterministic, no sleep): jdt.ls's publish
--- for every path AFTER the `java/validateDocument` that change_signature sends for the touched open
--- files once its edit is applied (refactor.last.validated_at), with no ERROR. jdt.ls handles didChange
--- in order and validates on a debounce, so that publish reflects every file of the edit; an earlier
--- publish (e.g. Checkout checked against the old PriceCalculator, then never checked again: the cause
--- of the "build NOT clean" flake in a full run) no longer decides the result. Falls back to t0 when the
--- refactor did not run.
local function cs_clean(paths, t0)
  local last = has("change_signature") and refactor.last
  return clean(paths, (last and last.ok and last.validated_at) or t0)
end

--- Calls of `name` in `txt`: all, and those whose last argument is `last` (a Lua pattern, e.g. "0").
local function calls(txt, name, last)
  local all, hit = 0, 0
  for args in (txt or ""):gmatch("%f[%w_]" .. name .. "%s*(%b())") do
    all = all + 1
    if args:match(",%s*" .. last .. "%)$") then hit = hit + 1 end
  end
  return all, hit
end

--- Where change_signature's time went (refactor.last.ms: info, definition, edit; references and implementations
--- run in parallel with edit; wait = for them after the edit; apply).
local function cs_ms()
  local m = has("change_signature") and refactor.last and refactor.last.ms
  if not m then return "" end
  local parts = {}
  for _, k in ipairs({ "info", "definition", "edit", "references", "implementations", "wait", "apply" }) do
    if m[k] then parts[#parts + 1] = ("%s %.0f"):format(k, m[k]) end
  end
  return " [ms: " .. table.concat(parts, ", ") .. "]"
end

--- The snapshot text of `path` as a buffer shows it (no trailing newline).
local function snap_text(path) return (snap.files[path]:gsub("\n$", "")) end

-- change_signature (+ _undo): total gets `int discount` with default 0 from its declaration: the 3 call
-- sites in Checkout and the 5 in src/test/java (not open) pass 0, every touched file written, summary
-- lists the 4 files; build clean (cs_clean); one `u` per touched buffer gives its text back.
case("change_signature", function()
  local calc = lsp.open(CALC)
  lsp.open(CHECKOUT)
  local l, c = pos(calc, "public int total%(Invoice invoice%)", "total")
  local t0, how = E.now(), nil
  local got, stop = capture()
  if has("change_signature") then
    vim.api.nvim_set_current_buf(calc); vim.api.nvim_win_set_cursor(0, { l + 1, c })
    how = "nv4j.refactor.change_signature({ add = { { type = int, name = discount, default = 0 } } })"; refactor.change_signature(ADD_DISCOUNT)
  else
    local ok, t = code_action(calc, l, c, "^Change signature")
    how = "code action " .. tostring(t)
    if not ok then stop(); return report_apply("change_signature", how, false, 0, {}, false, "") end
    -- nvim-jdtls opens an editable float (Parameters list); fill it as a user would and close it
    local opened = vim.wait(5000, function() return vim.api.nvim_get_current_buf() ~= calc end, 5)
    local pb = vim.api.nvim_get_current_buf()
    local pl = opened and E.line_of(pb, "^%- 0: Invoice invoice")
    if not pl then stop(); return report_apply("change_signature", how .. " (no prompt buffer with the parameter list)", false, E.now() - t0, {}, false, "") end
    how = how .. " (nvim-jdtls float prompt filled: '- int discount 0', then closed)"
    vim.api.nvim_buf_set_lines(pb, pl + 1, pl + 1, false, { "- int discount 0" })
    vim.cmd("close")
  end
  local applied, ms = until_ms(t0, function() return (text_of(CHECKOUT) or ""):find("calculator.total(invoice, 0)", 1, true) ~= nil end)
  stop()
  local ct, pt = text_of(CHECKOUT), text_of(CALC)
  local a1, z1 = calls(ct, "total", "0")
  local a2, z2 = calls(text_of(PCT), "total", "0")
  local a3, z3 = calls(text_of(PCFT), "total", "0")
  local ok_clean, why = cs_clean({ CHECKOUT, CALC, PCT, PCFT }, t0)
  local label = "Changed signature total(Invoice invoice) -> total(Invoice invoice, int discount = 0)"
  local sum = find_msg(got, label) or ""
  local written = true
  for _, p in ipairs({ CALC, CHECKOUT, PCT, PCFT }) do
    local b = loaded(p)
    if not b or vim.bo[b].modified or disk(p) ~= E.text(b) .. "\n" then written = false end
  end
  report_apply("change_signature", how .. cs_ms(), applied, ms, {
    { "declaration", (pt or ""):find("total(Invoice invoice, int discount)", 1, true) ~= nil },
    { ("3 call sites in Checkout pass 0 (%d/%d)"):format(z1, a1), a1 == 3 and z1 == 3 },
    { ("src/test call sites pass 0 (PriceCalculatorTest %d/%d, FailingTest %d/%d)"):format(z2, a2, z3, a3), a2 == 3 and z2 == 3 and a3 == 2 and z3 == 2 },
    { "written to disk", written },
    { "summary: 4 files", sum:find(label .. ": 4 file(s)", 1, true) == 1 and sum:find("src/main/java/demo/shop/Checkout.java", 1, true) ~= nil
      and sum:find("src/test/java/demo/billing/PriceCalculatorTest.java", 1, true) ~= nil and sum:find("PriceCalculatorFailingTest.java", 1, true) ~= nil },
  }, ok_clean, why)
  if not has("change_signature") then return end
  local bad = {}
  for _, p in ipairs({ CALC, CHECKOUT, PCT, PCFT }) do
    local b = loaded(p)
    if b then
      vim.api.nvim_buf_call(b, function() vim.cmd("silent! undo") end)
      if E.text(b) ~= snap_text(p) then bad[#bad + 1] = vim.fs.basename(p) end
    else
      bad[#bad + 1] = vim.fs.basename(p) .. " (no buffer)"
    end
  end
  lsp.report(P .. "change_signature_undo", applied and #bad == 0, applied and (#bad == 0 and "one u restored each of the 4 touched buffers"
    or ("not restored by one u: " .. table.concat(bad, ", "))) or "not applied, nothing to undo")
end)

-- change_signature_call_site: the cursor on a call of total in Checkout's payTwice: total changes (found
-- with textDocument/definition: jdt.ls answers only on a declaration), payTwice does not.
case("change_signature_call_site", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_call_site", false, pending_reason("change_signature")) end
  local chk = lsp.open(CHECKOUT)
  local r = cs_at(chk, "return calculator%.total%(invoice%)", "total", ADD_DISCOUNT)
  local ct, pt = text_of(CHECKOUT), text_of(CALC)
  local a, z = calls(ct, "total", "0")
  report_apply("change_signature_call_site", "nv4j.refactor.change_signature on a call" .. cs_ms(), r.ret == true, r.ms, {
    { "total's declaration changed", (pt or ""):find("public int total(Invoice invoice, int discount)", 1, true) ~= nil },
    { "payTwice unchanged", ct:find("public int payTwice(Invoice invoice) {", 1, true) ~= nil },
    { ("Checkout's calls pass 0 (%d/%d)"):format(z, a), a == 3 and z == 3 },
  }, cs_clean({ CHECKOUT, CALC }, E.now() - r.ms))
end)

-- change_signature_unsaved: unsaved user edits in PriceCalculator (the declaration) and Checkout survive,
-- both left unsaved (disk untouched), the tests (not open) written; the summary says which.
case("change_signature_unsaved", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_unsaved", false, pending_reason("change_signature")) end
  local calc, chk = lsp.open(CALC), lsp.open(CHECKOUT)
  append_line(calc, "// user edit in PriceCalculator")
  append_line(chk, "// user edit in Checkout")
  local r = cs_at(calc, "public int total%(Invoice invoice%)", "total", ADD_DISCOUNT)
  local ct, pt = E.text(chk), E.text(calc)
  local sum = find_msg(r.got, "Changed signature total(") or ""
  local _, z = calls(ct, "total", "0")
  report_apply("change_signature_unsaved", "nv4j.refactor.change_signature (unsaved buffers)" .. cs_ms(), r.ret == true, r.ms, {
    { "user edits kept", pt:find("// user edit in PriceCalculator", 1, true) ~= nil and ct:find("// user edit in Checkout", 1, true) ~= nil },
    { "edited in the buffers", pt:find("total(Invoice invoice, int discount)", 1, true) ~= nil and z == 3 },
    { "both left unsaved (disk untouched)", vim.bo[calc].modified and vim.bo[chk].modified and disk(CALC) == snap.files[CALC] and disk(CHECKOUT) == snap.files[CHECKOUT] },
    { "tests written", (disk(PCT) or ""):find("new Invoice(2, 3), 0)", 1, true) ~= nil },
    { "summary: 2 [left unsaved", select(2, sum:gsub("%[left unsaved", "")) == 2 },
  }, cs_clean({ CHECKOUT, CALC }, E.now() - r.ms))
end)

-- A static method with three parameters in PriceCalculator, called from Checkout.
local function plant_scale()
  plant(CALC, { { "    public int legacyTotal(", "    public static int scale(int value, int factor, int unused) {\n        return value * factor;\n    }\n\n    public int legacyTotal(" } })
  plant(CHECKOUT, { { "    public int payTwice(", "    public int scaled(int q) {\n        return PriceCalculator.scale(q, 2, 7);\n    }\n\n    public int payTwice(" } })
  return open_fresh({ CALC, CHECKOUT })
end

-- change_signature_reorder: scale renamed to times, `factor` renamed to `by` and moved first: the
-- declaration, the body (`value * by`) and the call (`times(2, q, 7)`).
case("change_signature_reorder", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_reorder", false, pending_reason("change_signature")) end
  local calc = plant_scale()
  local r = cs_at(calc, "public static int scale%(", "scale", { name = "times", rename = { factor = "by" }, reorder = { "by", "value", "unused" } })
  local pt, ct = text_of(CALC), text_of(CHECKOUT)
  local label = "Changed signature scale(int value, int factor, int unused) -> times(int by, int value, int unused)"
  report_apply("change_signature_reorder", "nv4j.refactor.change_signature({ name, rename, reorder })" .. cs_ms(), r.ret == true, r.ms, {
    { "declaration", pt:find("public static int times(int by, int value, int unused) {", 1, true) ~= nil },
    { "body uses the new name", pt:find("return value * by;", 1, true) ~= nil },
    { "call reordered", ct:find("return PriceCalculator.times(2, q, 7);", 1, true) ~= nil },
    { "summary", find_msg(r.got, label .. ": 2 file(s)") ~= nil },
  }, cs_clean({ CHECKOUT, CALC }, E.now() - r.ms))
end)

-- change_signature_remove: the unused third parameter removed by position and `value` retyped to Integer:
-- `scale(Integer value, int factor)`, the call `scale(q, 2)`.
case("change_signature_remove", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_remove", false, pending_reason("change_signature")) end
  local calc = plant_scale()
  local r = cs_at(calc, "public static int scale%(", "scale", { remove = { 3 }, retype = { value = "Integer" } })
  local pt, ct = text_of(CALC), text_of(CHECKOUT)
  report_apply("change_signature_remove", "nv4j.refactor.change_signature({ remove = { 3 }, retype })" .. cs_ms(), r.ret == true, r.ms, {
    { "declaration", pt:find("public static int scale(Integer value, int factor) {", 1, true) ~= nil },
    { "call without the argument", ct:find("return PriceCalculator.scale(q, 2);", 1, true) ~= nil },
  }, cs_clean({ CHECKOUT, CALC }, E.now() - r.ms))
end)

-- change_signature_header: legacyTotal (no callers) made protected, returning long, named oldTotal.
case("change_signature_header", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_header", false, pending_reason("change_signature")) end
  local calc = lsp.open(CALC)
  local r = cs_at(calc, "public int legacyTotal%(", "legacyTotal", { visibility = "protected", returns = "long", name = "oldTotal" })
  local pt = text_of(CALC)
  report_apply("change_signature_header", "nv4j.refactor.change_signature({ visibility, returns, name })" .. cs_ms(), r.ret == true, r.ms, {
    { "declaration", pt:find("protected long oldTotal(Invoice invoice) {", 1, true) ~= nil },
    { "summary: 1 file", find_msg(r.got, "Changed signature legacyTotal(Invoice invoice) -> oldTotal(Invoice invoice): 1 file(s)") ~= nil },
  }, cs_clean({ CALC }, E.now() - r.ms))
end)

-- change_signature_prompt: <leader>js (the mapping's own function) without arguments: vim.ui.input shows
-- the signature as text; the answer adds `int discount = 0` (call sites pass 0). Then a typed rename
-- by position: `Invoice inv` in place of `Invoice invoice` renames the parameter (body too).
case("change_signature_prompt", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_prompt", false, pending_reason("change_signature")) end
  local m = vim.fn.maparg("<leader>js", "n", false, true)
  if not m.callback then return lsp.report(P .. "change_signature_prompt", false, "<leader>js has no Lua callback: " .. vim.inspect(m.rhs)) end
  local calc = lsp.open(CALC)
  lsp.open(CHECKOUT)
  -- the prompt path is asynchronous: the mapping returns at once with a progress message; the outcome follows
  local function prompted(buf, answer, fn)
    local seen = answer_input(answer)
    refactor.last = nil
    local l, c = pos(buf, "public int total%(Invoice invoice%)", "total")
    vim.api.nvim_set_current_buf(buf); vim.api.nvim_win_set_cursor(0, { l + 1, c })
    local got, stop = capture()
    local t0 = E.now()
    local ret = fn()
    local returned = E.now() - t0
    local ok = vim.wait(refactor.signature_ms + 1000, function() return refactor.last ~= nil end, 5)
    local ms = E.now() - t0
    stop()
    return { seen = seen, ret = ret, returned = returned, ms = ms, ok = ok and refactor.last.ok,
      progress = find_msg(got, "Changing signature of total...") ~= nil }
  end
  local r = prompted(calc, "public int total(Invoice invoice, int discount = 0)", function() return m.callback() end)
  local seen = r.seen
  local a, z = calls(text_of(CHECKOUT), "total", "0")
  local first = r.ok and a == 3 and z == 3 and r.progress and r.ret == nil
  F.restore(snap, client)
  calc = lsp.open(CALC)
  local r2 = prompted(calc, "public int total(Invoice inv)", function() return refactor.change_signature() end)
  local seen2 = r2.seen
  local pt = text_of(CALC)
  local second = r2.ok and pt:find("public int total(Invoice inv) {", 1, true) ~= nil and pt:find("int gross = gross(inv);", 1, true) ~= nil
  lsp.report(P .. "change_signature_prompt", first and second and seen.default == "public int total(Invoice invoice)"
    and (seen.prompt or ""):find("Type name = default", 1, true) ~= nil and r.ms <= APPLY_MS and r2.ms <= APPLY_MS,
    ("prompt %q default %q; <leader>js: returned %s after %.0f ms with progress message %s, applied %s (%d/%d calls pass 0, done after %.0f ms); typed rename: %s (%.0f ms, prompt default %q)"):format(
      tostring(seen.prompt), tostring(seen.default), tostring(r.ret), r.returned, tostring(r.progress), tostring(first), z, a, r.ms, tostring(second), r2.ms, tostring(seen2.default)))
end)

-- change_signature_refused: each refused with its reason, nothing changed (buffers and disk): not on a
-- method (class line, field), invalid type/name, no default, duplicate name, a removed parameter still
-- used, a new name clashing with a local, bad reorder, constructor renamed, unknown option, nothing to
-- change, an invalid default (jdt.ls's own message, shown once), a library method from a call,
-- an implementation of a library interface method (jdt.ls's refusal).
case("change_signature_refused", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_refused", false, pending_reason("change_signature")) end
  local SR = main .. "demo/StartupRunner.java"
  local T = "public int total%(Invoice invoice%)"
  local runs = {
    { "class line", CALC, "^public class PriceCalculator", "PriceCalculator", ADD_DISCOUNT, "the cursor is not on a method" },
    { "field", CHECKOUT, "private final PriceCalculator calculator", "calculator", ADD_DISCOUNT, "the cursor is not on a method" },
    { "invalid type", CALC, T, "total", { add = { { "in t", "discount", "0" } } }, "`in t` is not a valid parameter type" },
    { "invalid name", CALC, T, "total", { add = { { "int", "class", "0" } } }, "`class` is not a valid parameter name" },
    { "no default", CALC, T, "total", { add = { { type = "int", name = "discount" } } }, "needs a default value" },
    { "duplicate", CALC, T, "total", { add = { { "int", "invoice", "0" } } }, "duplicate parameter name `invoice`" },
    { "removed but used", CALC, T, "total", { remove = { "invoice" } }, "parameter `invoice` is still used in the body of total" },
    { "clash with a local", CALC, T, "total", { add = { { "int", "gross", "0" } } }, "`gross` is already used in the body of total" },
    { "bad reorder", CALC, T, "total", { reorder = { "nope" } }, "reorder: `nope` is not a parameter" },
    { "constructor renamed", INVOICE, "public Invoice%(", "Invoice", { name = "Bill" }, "a constructor keeps its class's name" },
    { "unknown option", CALC, T, "total", { adds = {} }, "unknown option `adds`" },
    { "nothing to change", CALC, T, "total", { name = "total" }, "is unchanged; nothing to do" },
    { "invalid default (jdt.ls)", CALC, T, "total", { add = { { "int", "discount", "1 +" } } }, "'1 +' is not a valid expression" },
    { "library method", SR, "System%.out%.println", "println", ADD_DISCOUNT, "is declared outside this project" },
    { "library interface", SR, "public void run%(", "run", ADD_DISCOUNT, "implementation of method 'void run(ApplicationArguments args)'" },
  }
  local bad, parts, changed = {}, {}, {}
  for _, x in ipairs(runs) do
    local b = lsp.open(x[2])
    local before = { [b] = E.text(b) }
    local r = cs_at(b, x[3], x[4], x[5])
    local msg = find_msg(r.got, x[6])
    local shown = 0
    for _, g in ipairs(r.got) do
      if g.msg:find(x[6], 1, true) then shown = shown + 1 end
    end
    local d = F.diff(snap)
    local same = untouched(before) and #d.added + #d.changed + #d.missing == 0
    local good = r.ret == false and msg ~= nil and shown == 1 and msg:find("nothing", 1, true) ~= nil and same
    if not good then bad[#bad + 1] = x[1] .. " (returned " .. tostring(r.ret) .. ", shown " .. shown .. "x, " .. (same and "unchanged" or "CHANGED") .. ": "
      .. table.concat(vim.tbl_map(function(g) return g.msg end, r.got), " || ") .. ")" end
    if not same then
      changed[#changed + 1] = x[1]
      F.restore(snap, client) -- the next refusal starts from the fixture again
    end
    parts[#parts + 1] = ("%s %.0f ms"):format(x[1], r.ms)
  end
  local same = #changed == 0
  lsp.report(P .. "change_signature_refused", #bad == 0 and same, ("%d/%d refused with the reason (%s)%s; buffers and disk %s"):format(#runs - #bad, #runs,
    table.concat(parts, ", "), #bad > 0 and ("; WRONG: " .. table.concat(bad, "; ")) or "", same and "unchanged" or ("CHANGED by: " .. table.concat(changed, ", "))))
end)

-- change_signature_no_edit (stub): jdt.ls answers getRefactorEdit with null after a window/showMessage
-- error (how it refuses), then with an empty edit: refused, its message in ours (shown once), nothing changed.
case("change_signature_no_edit", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_no_edit", false, pending_reason("change_signature")) end
  local calc = lsp.open(CALC)
  local before = { [calc] = E.text(calc) }
  local real = client.request
  local mode = "null"
  -- getRefactorEdit is asynchronous (client:request): the stub answers on the next tick, like jdt.ls
  client.request = function(self, m, params, handler, b)
    if m == "java/getRefactorEdit" then
      if mode == "null" then
        local h = self.handlers["window/showMessage"] or vim.lsp.handlers["window/showMessage"]
        h(nil, { type = 1, message = "stubbed jdt.ls refusal" }, { method = "window/showMessage", client_id = self.id })
      end
      local result = mode == "null" and vim.NIL or { edit = { documentChanges = {} } }
      vim.schedule(function() handler(nil, result, { method = m, client_id = self.id, bufnr = b }) end)
      return true, 0
    end
    return real(self, m, params, handler, b)
  end
  local ok, r1, r2 = pcall(function()
    local a = cs_at(calc, "public int total%(Invoice invoice%)", "total", ADD_DISCOUNT)
    mode = "empty"
    return a, cs_at(calc, "public int total%(Invoice invoice%)", "total", ADD_DISCOUNT)
  end)
  client.request = real
  if not ok then error(r1) end
  local m1 = find_msg(r1.got, "Change signature: jdt.ls gave no edit and said: stubbed jdt.ls refusal; nothing changed", vim.log.levels.ERROR)
  local n1 = #vim.tbl_filter(function(g) return g.msg:find("stubbed jdt.ls refusal", 1, true) ~= nil end, r1.got)
  local m2 = find_msg(r2.got, "Change signature: jdt.ls gave no edit; nothing changed", vim.log.levels.ERROR)
  lsp.report(P .. "change_signature_no_edit", r1.ret == false and m1 ~= nil and n1 == 1 and r2.ret == false and m2 ~= nil and untouched(before),
    ("null + showMessage: returned %s, message %s (shown %dx); empty edit: returned %s, message %s; file %s"):format(tostring(r1.ret), tostring(m1), n1,
      tostring(r2.ret), tostring(m2), untouched(before) and "unchanged" or "CHANGED"))
end)

--- Delays jdt.ls's getRefactorEdit answer by `ms` (the real answer, handed over later): the window in which
--- an asynchronous change signature is pending. Returns the undo.
local function delay_edit(ms)
  local real = client.request
  client.request = function(self, m, params, handler, b)
    if m ~= "java/getRefactorEdit" then return real(self, m, params, handler, b) end
    return real(self, m, params, function(err, result, ctx) vim.defer_fn(function() handler(err, result, ctx) end, ms) end, b)
  end
  return function() client.request = real end
end

--- refactor.change_signature with opts.async at (pat, word) of `buf`; returns { ret, returned, got, outcome = function }.
local function cs_async(buf, pat, word, opts)
  local res = {}
  opts = vim.tbl_extend("force", opts, { async = true, on_done = function(ok) res.done = ok end })
  local r = cs_at(buf, pat, word, opts)
  res.ret, res.returned, res.got = r.ret, r.ms, r.got
  return res
end

-- change_signature_stale (deterministic: the answer delayed 400 ms by a stub): Checkout is typed into while
-- jdt.ls computes the edit: refused whole ("changed while jdt.ls computed the edit"), nothing applied
-- (PriceCalculator untouched too), the user's line kept, disk unchanged.
case("change_signature_stale", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_stale", false, pending_reason("change_signature")) end
  local calc, chk = lsp.open(CALC), lsp.open(CHECKOUT)
  local before_calc = E.text(calc)
  local undo = delay_edit(400)
  local ok, err = pcall(function()
    local got, stop = capture()
    local a = cs_async(calc, "public int total%(Invoice invoice%)", "total", ADD_DISCOUNT)
    append_line(chk, "// typed while jdt.ls works")
    local typed = E.text(chk)
    vim.wait(refactor.signature_ms + 1000, function() return a.done ~= nil end, 5)
    stop()
    local msg = find_msg(got, "src/main/java/demo/shop/Checkout.java changed while jdt.ls computed the edit; nothing changed", vim.log.levels.WARN)
    local d = F.diff(snap)
    local good = a.ret == nil and a.done == false and msg ~= nil and E.text(calc) == before_calc and E.text(chk) == typed
      and #d.added + #d.changed + #d.missing == 0 and refactor._busy() == nil
    lsp.report(P .. "change_signature_stale", good, ("returned %s, on_done %s; message %s; PriceCalculator %s, Checkout %s; disk %s; busy %s"):format(
      tostring(a.ret), tostring(a.done), tostring(msg), E.text(calc) == before_calc and "untouched" or "CHANGED",
      E.text(chk) == typed and "only the typed line" or "EDITED", #d.changed == 0 and "unchanged" or F.fmt(d), vim.inspect(refactor._busy())))
  end)
  undo()
  if not ok then error(err) end
end)

-- change_signature_busy (deterministic: answer delayed 600 ms): while a change signature is pending, a second
-- one, an inline and a rename are refused ("a refactor is in progress"); the first one then completes;
-- `busy` is cleared and jdt.ls's showMessage handler is the client's own again.
case("change_signature_busy", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_busy", false, pending_reason("change_signature")) end
  local calc, inv = lsp.open(CALC), lsp.open(INVOICE)
  lsp.open(CHECKOUT)
  local own = rawget(client.handlers, "window/showMessage")
  local undo = delay_edit(600)
  local ok, err = pcall(function()
    local a = cs_async(calc, "public int total%(Invoice invoice%)", "total", ADD_DISCOUNT)
    local b = cs_at(calc, "public int legacyTotal%(", "legacyTotal", { name = "oldTotal" })
    local c = inline_at(calc, "int gross = gross%(invoice%);", "gross(")
    vim.api.nvim_set_current_buf(inv); vim.api.nvim_win_set_cursor(0, { E.line_of(inv, "^public class Invoice") + 1, 14 })
    local got, stop = capture()
    local d = refactor.rename_class({ name = "Bill" })
    stop()
    local want = "a refactor is in progress (change signature of total)"
    local refused = b.ret == false and find_msg(b.got, want) ~= nil and c.ret == false and find_msg(c.got, want) ~= nil
      and d == false and find_msg(got, want) ~= nil and vim.uv.fs_stat(INVOICE) ~= nil
    vim.wait(refactor.signature_ms + 1000, function() return a.done ~= nil end, 5)
    local after = a.done == true and select(2, calls(text_of(CHECKOUT), "total", "0")) == 3 and refactor._busy() == nil
      and rawget(client.handlers, "window/showMessage") == own
    lsp.report(P .. "change_signature_busy", refused and after, ("while pending: change signature %s, inline %s, rename %s; first one: on_done %s, busy after %s, showMessage handler %s"):format(
      tostring(b.ret), tostring(c.ret), tostring(d), tostring(a.done), vim.inspect(refactor._busy()),
      rawget(client.handlers, "window/showMessage") == own and "restored" or "LEFT WRAPPED"))
  end)
  undo()
  if not ok then error(err) end
end)

-- change_signature_finish_error: an error after jdt.ls answered (injected in refactor.revalidate): synchronous
-- call returns false at once with an ERROR naming it, asynchronous call reports on_done(false); busy cleared.
case("change_signature_finish_error", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_finish_error", false, pending_reason("change_signature")) end
  local calc = lsp.open(CALC)
  lsp.open(CHECKOUT)
  local real = refactor.revalidate
  refactor.revalidate = function() error("injected finish error") end
  local ok, err = pcall(function()
    local done1
    local r = cs_at(calc, "public int total%(Invoice invoice%)", "total", vim.tbl_extend("force", ADD_DISCOUNT, { on_done = function(x) done1 = x end }))
    local m1 = find_msg(r.got, "injected finish error", vim.log.levels.ERROR)
    local busy1 = refactor._busy()
    F.restore(snap, client)
    calc = lsp.open(CALC)
    local got, stop = capture()
    local a = cs_async(calc, "public int total%(Invoice invoice%)", "total", ADD_DISCOUNT)
    vim.wait(refactor.signature_ms + 1000, function() return a.done ~= nil end, 5)
    stop()
    local m2 = find_msg(got, "injected finish error", vim.log.levels.ERROR)
    lsp.report(P .. "change_signature_finish_error", r.ret == false and done1 == false and m1 ~= nil and r.ms <= APPLY_MS and busy1 == nil
      and a.done == false and m2 ~= nil and refactor._busy() == nil,
      ("sync: returned %s after %.0f ms, on_done %s, message %s; async: on_done %s, message %s; busy %s"):format(tostring(r.ret), r.ms, tostring(done1),
        m1 and "yes" or "NONE", tostring(a.done), m2 and "yes" or "NONE", vim.inspect(refactor._busy())))
  end)
  refactor.revalidate = real
  if not ok then error(err) end
end)

-- change_signature_constructor: Invoice's constructor gets `int discount = 0`: every `new Invoice(...)` in
-- main and test sources passes 0; from the declaration, and from a `new Invoice(` call in Checkout.
case("change_signature_constructor", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_constructor", false, pending_reason("change_signature")) end
  local inv = lsp.open(INVOICE)
  local r = cs_at(inv, "public Invoice%(", "Invoice", ADD_DISCOUNT)
  local a1, z1 = calls(text_of(CHECKOUT), "Invoice", "0")
  local a2, z2 = calls(text_of(PCT), "Invoice", "0")
  local label = "Changed signature Invoice(int quantity, int unitPrice) -> Invoice(int quantity, int unitPrice, int discount = 0)"
  local first = { r.ret == true, a1 == 1 and z1 == 1 and a2 == 3 and z2 == 3, find_msg(r.got, label) ~= nil,
    text_of(INVOICE):find("public Invoice(int quantity, int unitPrice, int discount) {", 1, true) ~= nil }
  local ok_clean, why = cs_clean({ INVOICE, CHECKOUT, PCT }, E.now() - r.ms)
  F.restore(snap, client)
  local chk = lsp.open(CHECKOUT)
  local r2 = cs_at(chk, "new Invoice%(quantity", "Invoice", ADD_DISCOUNT)
  local a3, z3 = calls(text_of(CHECKOUT), "Invoice", "0")
  report_apply("change_signature_constructor", "nv4j.refactor.change_signature on the constructor", first[1], math.max(r.ms, r2.ms), {
    { "declaration", first[4] },
    { ("new Invoice(...) pass 0 (Checkout %d/%d, PriceCalculatorTest %d/%d)"):format(z1, a1, z2, a2), first[2] },
    { "summary label", first[3] },
    { ("from a `new Invoice(` call: returned %s, Checkout %d/%d"):format(tostring(r2.ret), z3, a3), r2.ret == true and a3 == 1 and z3 == 1 },
  }, ok_clean, why)
end)

-- An interface method implemented by a nested class, called through the interface (planted in PriceCalculator).
local function plant_rule()
  plant(CALC, { { "    public int legacyTotal(", [[    interface Rule {
        int apply(int amount);
    }

    static class Half implements Rule {
        @Override
        public int apply(int amount) {
            return amount / 2;
        }
    }

    public int halve(int amount) {
        Rule r = new Half();
        return r.apply(amount);
    }

    public int legacyTotal(]] } })
  return open_fresh({ CALC })
end

-- change_signature_interface_ceiling: change signature of a method WITH implementations or overrides
-- (Rule.apply gets `int extra = 1`), measured on the first such change of the session. This is a CEILING of
-- 5 s, not the 2 s APPLY_MS budget: ruling recorded in the SDD ledger (the user delegated it, reversible;
-- specs/features/refactors.md "Ruling: ceiling 5 s"). jdt.ls's own getRefactorEdit search takes 3.7 to 3.9 s
-- cold and about 2.6 s warm; nothing is left to overlap on our side. Still FAILs when over the ceiling.
-- Every other refactor, and the plain `total(Invoice)` change_signature, keep APPLY_MS.
local CEILING_IMPL_MS = 5000
case("change_signature_interface_ceiling", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_interface_ceiling", false, pending_reason("change_signature")) end
  local calc = plant_rule()
  local r = cs_at(calc, "int apply%(int amount%);", "apply", { add = { { "int", "extra", "1" } } })
  local applied = r.ret == true and text_of(CALC):find("public int apply(int amount, int extra) {", 1, true) ~= nil
  E.log("refactor_change_signature_interface", r.ms, 1)
  local within = applied and r.ms <= CEILING_IMPL_MS
  lsp.report(P .. "change_signature_interface_ceiling", within, ("%s after %.0f ms; ceiling %d ms for methods with implementations (budget %d ms elsewhere)%s%s"):format(
    applied and "applied" or "NOT applied", r.ms, CEILING_IMPL_MS, APPLY_MS, cs_ms(), (applied and not within) and "; OVER the ceiling" or ""))
end)

-- change_signature_interface: from the interface method Rule.apply: jdt.ls changes the implementation
-- Half.apply too (the summary names it), the call passes the default, build clean; from Half.apply:
-- refused with jdt.ls's reason and where to do it. Correctness only, with the request's hard timeout
-- (refactor.signature_ms); the time is change_signature_interface_ceiling's.
case("change_signature_interface", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_interface", false, pending_reason("change_signature")) end
  local calc = plant_rule()
  local before = E.text(calc)
  local r0 = cs_at(calc, "public int apply%(int amount%)", "apply", { add = { { "int", "extra", "1" } } })
  local refused = r0.ret == false and find_msg(r0.got, "change it at the declaration it implements") ~= nil and E.text(calc) == before
  -- asynchronous (opts.async): returns at once with a progress message, the editor is not blocked for jdt.ls's
  -- 2.6-3.9 s; on_done reports the outcome
  local outcome
  local r = cs_at(calc, "int apply%(int amount%);", "apply", { add = { { "int", "extra", "1" } }, async = true, on_done = function(ok) outcome = ok end })
  local t_ret, got = r.ms, r.got
  local got2, stop = capture()
  local t0 = E.now() - r.ms
  vim.wait(refactor.signature_ms + 1000, function() return outcome ~= nil end, 5)
  stop()
  r = { ret = outcome, ms = E.now() - t0, got = vim.list_extend(got, got2) }
  local nonblocking = t_ret < 300 and find_msg(got, "Changing signature of apply...") ~= nil
  local pt = text_of(CALC)
  local changed = pt:find("int apply(int amount, int extra);", 1, true) ~= nil and pt:find("public int apply(int amount, int extra) {", 1, true) ~= nil
    and pt:find("return r.apply(amount, 1);", 1, true) ~= nil
  local note = find_msg(r.got, "jdt.ls also changed the 1 method(s) that implement or override it: src/main/java/demo/billing/PriceCalculator.java:")
  local ok_clean, why = cs_clean({ CALC }, E.now() - r.ms)
  local good = r.ret == true and refused and note ~= nil and ok_clean and changed and r.ms <= refactor.signature_ms and nonblocking
  lsp.report(P .. "change_signature_interface", good, ("from Half.apply: %s; from Rule.apply (async): returned after %.0f ms with a progress message %s, on_done %s (%.0f ms, second change of the session%s); interface + implementation + call changed: %s; note: %s; build %s"):format(
    refused and "refused with jdt.ls's reason" or "NOT refused", t_ret, tostring(nonblocking), tostring(r.ret), r.ms, cs_ms(), tostring(changed),
    note and "yes" or "MISSING", ok_clean and "clean" or ("NOT clean: " .. why)))
end)

-- change_signature_boot: a parameter added to the @Bean devBanner (Spring injects it, the default is not
-- used: warning), devBanner renamed (the bean name changes: warning), a parameter added to the
-- @GetMapping handler hello (bound from the request: warning). Each applied, build clean.
case("change_signature_boot", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_boot", false, pending_reason("change_signature")) end
  local res = {}
  local function one(path, pat, word, opts, want, check_text)
    local b = lsp.open(path)
    local r = cs_at(b, pat, word, opts)
    local w = find_msg(r.got, want, vim.log.levels.WARN)
    local ok_clean, why = cs_clean({ path }, E.now() - r.ms)
    res[#res + 1] = { ok = r.ret == true and w ~= nil and ok_clean and r.ms <= APPLY_MS and text_of(path):find(check_text, 1, true) ~= nil,
      txt = ("%s: returned %s %.0f ms, warning %s, build %s"):format(word, tostring(r.ret), r.ms, w and "yes" or "MISSING", ok_clean and "clean" or ("NOT clean: " .. why)) }
    F.restore(snap, client)
  end
  one(GCFG, "public String devBanner", "devBanner", { add = { { "int", "n", "0" } } }, "Spring: devBanner is a @Bean method: Spring calls it and injects its parameters",
    "devBanner(GreetingProperties properties, int n)")
  one(GCFG, "public String devBanner", "devBanner", { name = "banner" }, "Spring: the bean's name changes from `devBanner` to `banner`", "public String banner(")
  one(GCTRL, "public String hello", "hello", { add = { { "int", "times", "1" } } }, "Spring: hello is a request handler (@GetMapping)", "public String hello(int times)")
  lsp.report(P .. "change_signature_boot", vim.iter(res):all(function(x) return x.ok end), table.concat(vim.tbl_map(function(x) return x.txt end, res), "; "))
end)

-- change_signature_errors: a syntax error in Checkout (unsaved): jdt.ls updates its calls anyway, or the
-- warning names them (jdt.ls's references); Checkout keeps its syntax error. _twin (deterministic):
-- Checkout's edit dropped from jdt.ls's answer (stub): the warning names Checkout's two call lines.
case("change_signature_errors", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_errors", false, pending_reason("change_signature")) end
  local calc, chk = lsp.open(CALC), lsp.open(CHECKOUT)
  local bl = E.line_of(chk, "^public class Checkout")
  vim.api.nvim_buf_set_lines(chk, bl + 1, bl + 1, false, { "    int broken = ;" })
  local tset = E.now()
  vim.wait(CLEAN_MS, function()
    return (published_at[vim.uri_from_fname(CHECKOUT)] or 0) >= tset and E.count(vim.diagnostic.get(chk), vim.diagnostic.severity.ERROR) > 0
  end, 20)
  local r = cs_at(calc, "public int total%(Invoice invoice%)", "total", ADD_DISCOUNT)
  local ct = E.text(chk)
  local a, z = calls(ct, "total", "0")
  local named = find_msg(r.got, "NOT updated by jdt.ls", vim.log.levels.WARN)
  lsp.report(P .. "change_signature_errors", r.ms <= APPLY_MS and r.ret == true and ((a == 3 and z == 3) or (named and named:find("Checkout.java", 1, true) ~= nil) or false)
    and ct:find("int broken = ;", 1, true) ~= nil,
    ("returned %s after %.0f ms; Checkout's calls %d/%d updated by jdt.ls; warning %s; Checkout's syntax error kept"):format(tostring(r.ret), r.ms, z, a,
      named and "names Checkout" or "none"))
end)
case("change_signature_errors_twin", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_errors_twin", false, pending_reason("change_signature")) end
  local calc, chk = lsp.open(CALC), lsp.open(CHECKOUT)
  local l1, l2 = E.line_of(chk, "calculator%.total%(new Invoice") + 1, E.line_of(chk, "calculator%.total%(invoice%)") + 1
  local real = client.request
  client.request = function(self, m, params, handler, b)
    if m ~= "java/getRefactorEdit" then return real(self, m, params, handler, b) end
    return real(self, m, params, function(err, result, ctx)
      if type(result) == "table" and result.edit and result.edit.documentChanges then
        result.edit.documentChanges = vim.tbl_filter(function(ch)
          return not (ch.textDocument and ch.textDocument.uri:find("/demo/shop/Checkout.java", 1, true))
        end, result.edit.documentChanges)
      end
      return handler(err, result, ctx)
    end, b)
  end
  local ok, r = pcall(cs_at, calc, "public int total%(Invoice invoice%)", "total", ADD_DISCOUNT)
  client.request = real
  if not ok then error(r) end
  local warn = find_msg(r.got, "NOT updated by jdt.ls", vim.log.levels.WARN) or ""
  lsp.report(P .. "change_signature_errors_twin", r.ret == true and warn:find("src/main/java/demo/shop/Checkout.java:" .. l1, 1, true) ~= nil
    and warn:find("src/main/java/demo/shop/Checkout.java:" .. l2, 1, true) ~= nil and E.text(chk):find("calculator.total(invoice)", 1, true) ~= nil,
    ("returned %s after %.0f ms; warning: %s"):format(tostring(r.ret), r.ms, warn ~= "" and warn or "NONE"))
end)

-- change_signature_stale_twin (deterministic twin of the build-clean race): after a clean change, a stale
-- ERROR publish for Checkout is planted (what jdt.ls leaves when it checked Checkout against the old
-- declaration and never again); refactor.revalidate (what change_signature sends after its edit) makes
-- jdt.ls publish Checkout again from the current state: the stale error is gone.
case("change_signature_stale_twin", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_stale_twin", false, pending_reason("change_signature")) end
  local calc = lsp.open(CALC)
  lsp.open(CHECKOUT)
  local r = cs_at(calc, "public int total%(Invoice invoice%)", "total", ADD_DISCOUNT)
  local ok1 = cs_clean({ CHECKOUT, CALC }, E.now() - r.ms)
  local chk = loaded(CHECKOUT)
  local h = vim.lsp.handlers["textDocument/publishDiagnostics"]
  h(nil, { uri = vim.uri_from_fname(CHECKOUT), diagnostics = { { range = { start = { line = 11, character = 8 }, ["end"] = { line = 11, character = 20 } },
    severity = 1, source = "Java", message = "planted stale error: total(Invoice) is not applicable" } } }, { method = "textDocument/publishDiagnostics", client_id = client.id })
  local planted = E.count(vim.diagnostic.get(chk), vim.diagnostic.severity.ERROR)
  local t = refactor.revalidate(client, { CHECKOUT })
  local ok2, why = clean({ CHECKOUT }, t)
  lsp.report(P .. "change_signature_stale_twin", r.ret == true and ok1 and planted > 0 and ok2,
    ("change applied %s, clean %s; planted stale errors %d; after revalidate: %s"):format(tostring(r.ret), tostring(ok1), planted, ok2 and "fresh clean publish" or ("still NOT clean: " .. why)))
end)

-- change_signature_parse (unit, no jdt.ls): the typed form and opts turned into the new parameter list.
case("change_signature_parse", function()
  if not has("change_signature") then return lsp.report(P .. "change_signature_parse", false, pending_reason("change_signature")) end
  local info = { methodName = "total", modifier = "public", returnType = "int", parameters = { { type = "Invoice", name = "invoice", originalIndex = 0 } } }
  local v = { methodName = "scale", modifier = "", returnType = "int", parameters = { { type = "int", name = "value", originalIndex = 0 },
    { type = "String...", name = "tags", originalIndex = 1 } } }
  local function sig(spec) return spec and (spec.visibility .. " " .. spec.returns .. " " .. spec.name .. "(" .. table.concat(vim.tbl_map(function(p)
    return p.type .. " " .. p.name .. (p.orig and ("#" .. p.orig) or "") .. (p.default and (" = " .. p.default) or "") end, spec.params), ", ") .. ")") or "nil" end
  local cases = {
    { refactor._spec_from_form(info, 'public int total(Map<String, Integer> m = Map.of("a", 1), Invoice invoice)'),
      'public int total(Map<String, Integer> m = Map.of("a", 1), Invoice invoice#0)' },
    { refactor._spec_from_form(info, "long total(Invoice inv, int d = a < b ? 1 : 2)"), "package long total(Invoice inv#0, int d = a < b ? 1 : 2)" },
    { select(2, refactor._spec_from_form(info, "public int total(Invoice invoice, int x)")), "new parameter `x` needs a default value for the call sites: `int x = value`" },
    { select(2, refactor._spec_from_form({ methodName = "f", modifier = "public", returnType = "int", parameters = { { type = "Invoice", name = "invoice", originalIndex = 0 },
      { type = "int", name = "n", originalIndex = 1 } } }, "public int f(int m)")),
      "`int m` takes the place of `Invoice invoice` with another type: say what you mean: a new parameter needs `= default` (`int m = value`), a rename/retype or removal needs the explicit options (rename = { invoice = \"m\" }, retype, remove)" },
    { refactor._spec_from_form(info, "public int total(Invoice inv)"), "public int total(Invoice inv#0)" },
    { select(2, refactor._spec_from_form(info, "public static int total(Invoice invoice)")), "`static` cannot be changed here (only visibility, return type, name and parameters); leave it out" },
    { refactor._spec_from_opts(v, { add = { { "int", "z", "0" } } }), "package int scale(int value#0, int z = 0, String... tags#1)" },
    { refactor._spec_from_opts(v, { add = { { "int", "z", "0", 1 } }, rename = { value = "x" } }), "package int scale(int z = 0, int x#0, String... tags#1)" },
  }
  local bad = {}
  for i, x in ipairs(cases) do
    local got = type(x[1]) == "table" and sig(x[1]) or tostring(x[1])
    if got ~= x[2] then bad[#bad + 1] = ("#%d got %q want %q"):format(i, got, x[2]) end
  end
  local types = { ["Map<String, List<Integer>>"] = true, ["List<? extends Number>"] = true, ["int[]"] = true, ["java.util.List<String>"] = true,
    ["in t"] = false, ["List<"] = false, ["class"] = false, ["@A int"] = false, ["a..b"] = false }
  for t, want in pairs(types) do
    if refactor._valid_type(t, false, false) ~= want then bad[#bad + 1] = ("type %q: %s"):format(t, tostring(not want)) end
  end
  lsp.report(P .. "change_signature_parse", #bad == 0, #bad == 0 and ("%d forms/opts and %d types as expected"):format(#cases, vim.tbl_count(types))
    or table.concat(bad, "; "))
end)

-- ── safe delete (Task 4e): nv4j.refactor.safe_delete, own code on jdt.ls's symbols/references ─────
local MODERN = main .. "demo/Modern.java"
local PROPS = fixture .. "/src/main/resources/application.properties"
local LEGACY = "\n\n    public int legacyTotal(Invoice invoice) {\n        return invoice.quantity();\n    }"

--- refactor.safe_delete(opts) (or `fn`) with the cursor on `word` in the first line of `buf` matching `pat`.
--- Returns { ret, ms, got } (safe delete is synchronous).
local function sd_at(buf, pat, word, opts, fn)
  local l, c = pos(buf, pat, word)
  vim.api.nvim_set_current_buf(buf); vim.api.nvim_win_set_cursor(0, { l + 1, c })
  vim.fn.setqflist({}, "r", { title = "", items = {} })
  local got, stop = capture()
  local t0 = E.now()
  local ok, ret = pcall(fn or refactor.safe_delete, opts)
  local ms = E.now() - t0
  stop()
  if not ok then error(ret) end
  return { ret = ret, ms = ms, got = got }
end

--- Quickfix entries as "File.java:line" (+ their text), and whether its window is open; closes it.
local function qf_close()
  local qf = vim.fn.getqflist()
  local open = vim.fn.getqflist({ winid = 0 }).winid ~= 0
  local list = vim.tbl_map(function(q) return vim.fs.basename(vim.api.nvim_buf_get_name(q.bufnr)) .. ":" .. q.lnum end, qf)
  local texts = table.concat(vim.tbl_map(function(q) return q.text end, qf), " || ")
  vim.cmd("cclose")
  return list, open, texts
end

local function count_of(list, base)
  return #vim.tbl_filter(function(x) return x:find(base .. ":", 1, true) == 1 end, list)
end

--- Disk and the listed buffers as before (nothing deleted).
local function nothing_changed(bufs)
  local d = F.diff(snap)
  return untouched(bufs) and #d.added + #d.changed + #d.missing == 0
end

-- safe_delete_blocked: on `total` (8 usages: 3 in Checkout, 3 in PriceCalculatorTest, 2 in
-- PriceCalculatorFailingTest, test sources included): nothing deleted (buffer and disk), every usage in
-- the quickfix list (opened, the cursor stays in the source window), the message names the count.
case("safe_delete_blocked", function()
  local calc = lsp.open(CALC)
  lsp.open(CHECKOUT)
  local before = { [calc] = E.text(calc) }
  local r = sd_at(calc, "public int total%(Invoice invoice%)", "total")
  local win_ok = vim.api.nvim_get_current_buf() == calc
  local list, open = qf_close()
  local msg = find_msg(r.got, "Safe delete: method total(Invoice) NOT deleted: 8 usage(s) in 3 file(s), listed in the quickfix", vim.log.levels.WARN)
  local good = r.ret == false and nothing_changed(before) and #list == 8 and count_of(list, "Checkout.java") == 3
    and count_of(list, "PriceCalculatorTest.java") == 3 and count_of(list, "PriceCalculatorFailingTest.java") == 2 and open and win_ok
    and msg ~= nil and msg:find("nothing changed", 1, true) ~= nil and r.ms <= APPLY_MS
  E.log("refactor_safe_delete_blocked", r.ms, 1)
  lsp.report(P .. "safe_delete_blocked", good, ("returned %s after %.0f ms; %s; quickfix %d (%s), window %s, cursor %s; message %s"):format(
    tostring(r.ret), r.ms, nothing_changed(before) and "nothing changed" or "CHANGED", #list, table.concat(list, ","), open and "open" or "NOT open",
    win_ok and "kept in PriceCalculator" or "MOVED", msg and "names 8 usages" or ("WRONG: " .. table.concat(vim.tbl_map(function(g) return g.msg end, r.got), " || "))))
end)

-- safe_delete_free (+ _undo): on `legacyTotal` (no usages): its lines and the blank line before it removed
-- (the text is exactly the snapshot without them), written, summary, busy cleared, build clean; one `u`.
case("safe_delete_free", function()
  local calc = lsp.open(CALC)
  local r = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
  local want = snap_text(CALC):gsub(vim.pesc(LEGACY), "", 1)
  local label = "Deleted method legacyTotal(Invoice): 1 file(s): src/main/java/demo/billing/PriceCalculator.java"
  report_apply("safe_delete_free", "nv4j.refactor.safe_delete" .. (refactor.last and refactor.last.ms and (" [ms: " .. table.concat(vim.tbl_map(function(k)
    return ("%s %.0f"):format(k, refactor.last.ms[k]) end, vim.tbl_keys(refactor.last.ms)), ", ") .. "]") or ""), r.ret == true, r.ms, {
    { "declaration and one blank line removed (exact text)", E.text(calc) == want },
    { "written to disk", not vim.bo[calc].modified and disk(CALC) == want .. "\n" },
    { "summary", find_msg(r.got, label) ~= nil },
    { "busy cleared", refactor._busy() == nil },
  }, clean({ CALC }, E.now() - r.ms))
  vim.api.nvim_buf_call(calc, function() vim.cmd("silent! undo") end)
  lsp.report(P .. "safe_delete_free_undo", r.ret == true and E.text(calc) == snap_text(CALC), r.ret == true and (E.text(calc) == snap_text(CALC)
    and "one u restored PriceCalculator" or "NOT restored by one u") or "not deleted, nothing to undo")
end)

-- safe_delete_unsaved: <leader>jd (the mapping's own function) on legacyTotal with an unsaved user edit in
-- PriceCalculator: deleted in the buffer, the user edit kept, left unsaved (disk = snapshot), summary says so.
case("safe_delete_unsaved", function()
  local m = vim.fn.maparg("<leader>jd", "n", false, true)
  if not m.callback then return lsp.report(P .. "safe_delete_unsaved", false, "<leader>jd has no Lua callback: " .. vim.inspect(m.rhs)) end
  local calc = lsp.open(CALC)
  append_line(calc, "// user edit in PriceCalculator")
  local r = sd_at(calc, "public int legacyTotal%(", "legacyTotal", nil, function() return m.callback() end)
  local pt = E.text(calc)
  report_apply("safe_delete_unsaved", "<leader>jd (unsaved buffer)", not pt:find("public int legacyTotal(", 1, true), r.ms, {
    { "user edit kept", pt:find("// user edit in PriceCalculator", 1, true) ~= nil },
    { "left unsaved (disk untouched)", vim.bo[calc].modified and disk(CALC) == snap.files[CALC] },
    { "summary: [left unsaved", find_msg(r.got, "PriceCalculator.java [left unsaved: it had your unsaved changes]") ~= nil },
  }, clean({ CALC }, E.now() - r.ms))
end)

-- safe_delete_unsaved_usage: an unsaved call of legacyTotal typed into Checkout: blocked (jdt.ls's working
-- copy, or the text of the unsaved buffer), Checkout listed, nothing deleted, the typed line kept.
case("safe_delete_unsaved_usage", function()
  local calc, chk = lsp.open(CALC), lsp.open(CHECKOUT)
  local bl = E.line_of(chk, "public int payTwice")
  vim.api.nvim_buf_set_lines(chk, bl, bl, false, { "    public int lt(Invoice i) { return calculator.legacyTotal(i); }" })
  local typed = E.text(chk)
  local before = { [calc] = E.text(calc) }
  local r = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
  local list = qf_close()
  local good = r.ret == false and untouched(before) and E.text(chk) == typed and count_of(list, "Checkout.java") == 1 and disk(CALC) == snap.files[CALC]
  lsp.report(P .. "safe_delete_unsaved_usage", good, ("returned %s after %.0f ms; quickfix %s; PriceCalculator %s; how: %s"):format(tostring(r.ret), r.ms,
    table.concat(list, ","), untouched(before) and "unchanged" or "CHANGED", refactor.last and refactor.last.possible and refactor.last.possible > 0
      and "possible usage from the unsaved text" or "jdt.ls's references"))
end)

--- Stubs textDocument/references (any request_sync) with `fn(params)`; returns the undo.
local function stub_references(fn)
  local real = client.request_sync
  client.request_sync = function(self, m, params, ms, b)
    if m == "textDocument/references" then return fn(params) end
    return real(self, m, params, ms, b)
  end
  return function() client.request_sync = real end
end

-- safe_delete_unconfirmed_twin (deterministic: jdt.ls's references stubbed empty, as when it has not taken a
-- change in or skipped a broken file): (a) an unsaved call in Checkout: blocked, listed as a possible usage;
-- (b) Checkout saved with a call and an ERROR planted on it (check namespace): blocked, "has errors";
-- (c) an ERROR planted on Invoice (does not name legacyTotal): deleted, the note says it.
case("safe_delete_unconfirmed_twin", function()
  local undo = stub_references(function() return { result = {} } end)
  local ns = vim.api.nvim_create_namespace("nv4j_check_62_sd_twin")
  local ok, err = pcall(function()
    local calc, chk = lsp.open(CALC), lsp.open(CHECKOUT)
    local bl = E.line_of(chk, "public int payTwice")
    vim.api.nvim_buf_set_lines(chk, bl, bl, false, { "    public int lt(Invoice i) { return calculator.legacyTotal(i); }" })
    local a = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
    local la, _, ta = qf_close()
    local ra = a.ret == false and count_of(la, "Checkout.java") == 1 and ta:find("possible usage: unsaved changes", 1, true) ~= nil
      and E.text(calc) == snap_text(CALC)
    F.restore(snap, client)
    plant(CHECKOUT, { { "    public int payTwice(", "    public int lt(Invoice i) {\n        return calculator.legacyTotal(i);\n    }\n\n    public int payTwice(" } })
    calc, chk = open_fresh({ CALC, CHECKOUT })
    vim.diagnostic.set(ns, chk, { { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "planted error", source = "check" } })
    local b = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
    local lb, _, tb = qf_close()
    local rb = b.ret == false and count_of(lb, "Checkout.java") == 1 and tb:find("this file has errors", 1, true) ~= nil and E.text(calc) == snap_text(CALC)
    vim.diagnostic.reset(ns, chk)
    F.restore(snap, client)
    calc = lsp.open(CALC)
    local inv = lsp.open(INVOICE)
    vim.diagnostic.set(ns, inv, { { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "planted error", source = "check" } })
    local cc = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
    vim.diagnostic.reset(ns, inv)
    local note = find_msg(cc.got, "jdt.ls reports errors in 1 file(s) (src/main/java/demo/billing/Invoice.java): none of them names `legacyTotal`")
    local rc = cc.ret == true and note ~= nil and not E.text(calc):find("public int legacyTotal(", 1, true)
    lsp.report(P .. "safe_delete_unconfirmed_twin", ra and rb and rc, ("(a) unsaved call: returned %s, quickfix %s %s; (b) saved call + planted error: returned %s, quickfix %s %s; (c) error elsewhere: returned %s, note %s"):format(
      tostring(a.ret), table.concat(la, ","), ra and "ok" or ("WRONG: " .. ta), tostring(b.ret), table.concat(lb, ","), rb and "ok" or ("WRONG: " .. tb),
      tostring(cc.ret), note and "yes" or "MISSING"))
  end)
  undo()
  if not ok then error(err) end
end)

-- safe_delete_errors: a real syntax error in Checkout (unsaved) that does not name legacyTotal: deleted,
-- the note names the file with errors; Checkout keeps its error; PriceCalculator's build clean.
case("safe_delete_errors", function()
  local calc, chk = lsp.open(CALC), lsp.open(CHECKOUT)
  local bl = E.line_of(chk, "^public class Checkout")
  vim.api.nvim_buf_set_lines(chk, bl + 1, bl + 1, false, { "    int broken = ;" })
  local tset = E.now()
  local seen = vim.wait(CLEAN_MS + 2000, function()
    return (published_at[vim.uri_from_fname(CHECKOUT)] or 0) >= tset and E.count(vim.diagnostic.get(chk), vim.diagnostic.severity.ERROR) > 0
  end, 20)
  local r = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
  local note = find_msg(r.got, "none of them names `legacyTotal`")
  report_apply("safe_delete_errors", "nv4j.refactor.safe_delete (syntax error in Checkout" .. (seen and ", published" or ", NOT published in time") .. ")",
    r.ret == true and not E.text(calc):find("public int legacyTotal(", 1, true), r.ms, {
    { "note names Checkout", note ~= nil and note:find("Checkout.java", 1, true) ~= nil },
    { "Checkout keeps its error", E.text(chk):find("int broken = ;", 1, true) ~= nil },
  }, clean({ CALC }, E.now() - r.ms))
end)

-- safe_delete_self_ref: a recursive method nobody else calls, with a javadoc and an annotation: its own call
-- does not block it (the note says so); javadoc, annotation, method and one blank line go (snapshot text).
case("safe_delete_self_ref", function()
  plant(CALC, { { "    public int legacyTotal(", "    /**\n     * Factorial.\n     */\n    @Deprecated\n    int fact(int n) {\n        return n <= 1 ? 1 : n * fact(n - 1);\n    }\n\n    public int legacyTotal(" } })
  local calc = open_fresh({ CALC })
  local r = sd_at(calc, "int fact%(int n%)", "fact")
  report_apply("safe_delete_self_ref", "nv4j.refactor.safe_delete (recursive, javadoc, annotation)", r.ret == true and E.text(calc) == snap_text(CALC), r.ms, {
    { "note: 1 reference inside itself", find_msg(r.got, "1 reference(s) inside fact itself went with it") ~= nil },
  }, clean({ CALC }, E.now() - r.ms))
end)

-- An interface method implemented by a nested class, nobody calls it (planted in PriceCalculator).
local function plant_rule_uncalled()
  plant(CALC, { { "    public int legacyTotal(", [[    interface Rule {
        int apply(int amount);
    }

    static class Half implements Rule {
        @Override
        public int apply(int amount) {
            return amount / 2;
        }
    }

    public int legacyTotal(]] } })
  return open_fresh({ CALC })
end

-- safe_delete_hierarchy: Half.apply (@Override): refused, says why; Rule.apply (no call, implemented by
-- Half.apply): blocked, the implementation listed in the quickfix. Nothing changed.
case("safe_delete_hierarchy", function()
  local calc = plant_rule_uncalled()
  local before = { [calc] = E.text(calc) }
  local a = sd_at(calc, "public int apply%(int amount%)", "apply")
  local ma = find_msg(a.got, "overrides or implements a method of a supertype (@Override)")
  local b = sd_at(calc, "int apply%(int amount%);", "apply")
  local list, _, texts = qf_close()
  local mb = find_msg(b.got, "0 usage(s), 1 method(s) that implement or override it")
  local good = a.ret == false and ma ~= nil and b.ret == false and mb ~= nil and #list == 1 and texts:find("[implements or overrides it]", 1, true) ~= nil
    and untouched(before)
  lsp.report(P .. "safe_delete_hierarchy", good, ("Half.apply: returned %s, %s; Rule.apply: returned %s, %s, quickfix %s; %s"):format(tostring(a.ret),
    ma and "refused (@Override)" or "NOT refused", tostring(b.ret), mb and "blocked by its implementation" or "NOT blocked", table.concat(list, ","),
    untouched(before) and "nothing changed" or "CHANGED"))
end)

-- safe_delete_boot: the @Bean devBanner (no code usage; a properties line names it): deleted with the
-- Spring warning, the properties line listed, the now unused imports (Bean, Profile) reported; the
-- @GetMapping handler hello: deleted with the endpoint warning; an unused @Value field: deleted with the
-- property warning. Each build clean.
case("safe_delete_boot", function()
  local res = {}
  local function one(path, pat, w, wants, prep)
    if prep then prep() end
    local b = open_fresh({ path })
    local r = sd_at(b, pat, w)
    local miss = {}
    for _, x in ipairs(wants) do
      if not find_msg(r.got, x) then miss[#miss + 1] = x end
    end
    local ok_clean, why = clean({ path }, E.now() - r.ms)
    res[#res + 1] = { ok = r.ret == true and #miss == 0 and ok_clean and r.ms <= APPLY_MS and not E.text(b):find(pat),
      txt = ("%s: returned %s %.0f ms, %s, build %s"):format(w, tostring(r.ret), r.ms, #miss == 0 and "warnings ok" or ("MISSING: " .. table.concat(miss, " | ")),
        ok_clean and "clean" or ("NOT clean: " .. why)) }
    F.restore(snap, client)
  end
  one(GCFG, "public String devBanner", "devBanner", { "Spring/framework: devBanner carries @Bean", "the bean `devBanner` is no longer defined",
    "src/main/resources/application.properties:7", "left unused import(s) in GreetingConfig.java", "org.springframework.context.annotation.Bean",
    "org.springframework.context.annotation.Profile" }, function()
    plant(PROPS, { { "zz.sample.flag=true\n", "zz.sample.flag=true\ndemo.banner.bean=devBanner\n" } })
  end)
  one(GCTRL, "public String hello", "hello", { "Spring/framework: hello carries @GetMapping", "its HTTP endpoint is gone" })
  one(GCTRL, "private String other;", "other", { "Spring/framework: other carries @Value", "the property `${demo.greeting.other:x}` is no longer read" }, function()
    plant(GCTRL, { { "    private String text;\n", "    private String text;\n\n    @Value(\"${demo.greeting.other:x}\")\n    private String other;\n" } })
  end)
  lsp.report(P .. "safe_delete_boot", vim.iter(res):all(function(x) return x.ok end), table.concat(vim.tbl_map(function(x) return x.txt end, res), "; "))
end)

-- safe_delete_class: Invoice (used): blocked; a planted @Service class Unused, the only type of its file,
-- unused: the file deleted, its buffer wiped, jdt.ls told (didChangeWatchedFiles, deleted), Spring warning,
-- no new errors; a second top-level type Helper planted at the end of PriceCalculator.java: only its
-- declaration removed (the file is the snapshot again).
local UNUSED = main .. "demo/billing/Unused.java"
case("safe_delete_class", function()
  local inv = lsp.open(INVOICE)
  local a = sd_at(inv, "^public class Invoice", "Invoice")
  local la = qf_close()
  local ra = a.ret == false and #la >= 8 and vim.uv.fs_stat(INVOICE) ~= nil
  F.restore(snap, client)
  local f = assert(io.open(UNUSED, "wb"))
  f:write("package demo.billing;\n\nimport org.springframework.stereotype.Service;\n\n@Service\npublic class Unused {\n    public int one() {\n        return 1;\n    }\n}\n")
  f:close()
  client:notify("workspace/didChangeWatchedFiles", { changes = { { uri = vim.uri_from_fname(UNUSED), type = 1 } } })
  local ub = open_fresh({ UNUSED })
  local told = false
  local real_notify = client.notify
  client.notify = function(self, m, params)
    if m == "workspace/didChangeWatchedFiles" then
      for _, ch in ipairs(params.changes or {}) do
        if ch.uri == vim.uri_from_fname(UNUSED) and ch.type == 3 then told = true end
      end
    end
    return real_notify(self, m, params)
  end
  refactor.trash_dir = "/tmp/nv4j/trash-check-class" -- the user's trash (stdpath cache) stays out of the checks
  local okb, b = pcall(sd_at, ub, "^public class Unused", "Unused")
  refactor.trash_dir = nil
  vim.fn.delete("/tmp/nv4j/trash-check-class", "rf")
  client.notify = real_notify
  if not okb then error(b) end
  local gone = vim.uv.fs_stat(UNUSED) == nil and vim.fn.bufnr(UNUSED) == -1
  local sum = find_msg(b.got, "Deleted class Unused: 1 file(s): src/main/java/demo/billing/Unused.java [file deleted]") or ""
  local rb = b.ret == true and gone and told and sum:find("Spring/framework: Unused carries @Service", 1, true) ~= nil and b.ms <= APPLY_MS
  local t_del = E.now()
  vim.wait(CLEAN_MS, function() return false end, 50) -- the 3 s look of the follow-up: no new error anywhere
  local errs = refactor.new_errors({}, {})
  errs = vim.tbl_filter(function(e) return not e:find("^Unused") end, errs)
  F.restore(snap, client)
  plant(CALC, { { "    }\n}\n", "    }\n}\n\nclass Helper {\n    int x;\n}\n" } })
  local calc = open_fresh({ CALC })
  local c = sd_at(calc, "^class Helper", "Helper")
  local rc = c.ret == true and E.text(calc) == snap_text(CALC) and disk(CALC) == snap.files[CALC] and vim.uv.fs_stat(CALC) ~= nil
  local ok_clean, why = clean({ CALC }, E.now() - c.ms)
  E.log("refactor_safe_delete_class", b.ms, 1)
  lsp.report(P .. "safe_delete_class", ra and rb and #errs == 0 and rc and ok_clean,
    ("Invoice: returned %s, %d usages listed; Unused: returned %s after %.0f ms, file and buffer %s, jdt.ls told %s, summary %s, errors after %.0f ms: %s; Helper: returned %s after %.0f ms, %s, build %s"):format(
      tostring(a.ret), #la, tostring(b.ret), b.ms, gone and "gone" or "STILL THERE", tostring(told), sum ~= "" and "ok" or "MISSING", E.now() - t_del,
      #errs == 0 and "none" or table.concat(errs, "; "), tostring(c.ret), c.ms, rc and "only its declaration removed (snapshot text)" or ("WRONG: " .. E.text(calc)),
      ok_clean and "clean" or ("NOT clean: " .. why)))
end)

--- Writes the planted @Service class Unused (the only type of its file), tells jdt.ls, opens it.
local UNUSED_TEXT = "package demo.billing;\n\nimport org.springframework.stereotype.Service;\n\n@Service\npublic class Unused {\n    public int one() {\n        return 1;\n    }\n}\n"
local function plant_unused()
  local f = assert(io.open(UNUSED, "wb"))
  f:write(UNUSED_TEXT)
  f:close()
  client:notify("workspace/didChangeWatchedFiles", { changes = { { uri = vim.uri_from_fname(UNUSED), type = 1 } } })
  return open_fresh({ UNUSED })
end

-- safe_delete_trash: the default trash is under stdpath("cache") (not the repo, not /tmp); with the trash
-- pointed at /tmp/nv4j/trash-check: deleting Unused.java copies it byte for byte to the trash first, the
-- notification names the copy and :Nv4jRestoreDeleted (not `u`); :Nv4jRestoreDeleted puts it back byte for
-- byte, opens it, tells jdt.ls, empties the entry. Then os.remove made to fail (stub): refused, the buffer
-- still open, the file still there, no trash entry left.
case("safe_delete_trash", function()
  local def = refactor.trash_root()
  local cache = vim.fn.stdpath("cache")
  local def_ok = def:sub(1, #cache + 1) == cache .. "/" and not def:find(vim.fn.getcwd(), 1, true) and not def:find("^/tmp") and not def:find("^/private/tmp")
  local tdir = "/tmp/nv4j/trash-check"
  vim.fn.delete(tdir, "rf")
  refactor.trash_dir = tdir
  local real_remove = os.remove
  local ok, err = pcall(function()
    local ub = plant_unused()
    local told = {}
    local real_notify = client.notify
    client.notify = function(self, m, params)
      if m == "workspace/didChangeWatchedFiles" then
        for _, ch in ipairs(params.changes or {}) do
          if ch.uri == vim.uri_from_fname(UNUSED) then told[#told + 1] = ch.type end
        end
      end
      return real_notify(self, m, params)
    end
    local okd, r = pcall(sd_at, ub, "^public class Unused", "Unused")
    local entries = vim.fn.glob(tdir .. "/*", false, true)
    local copy = entries[1] and (entries[1] .. "/src/main/java/demo/billing/Unused.java")
    local copied = #entries == 1 and copy and disk(copy) == UNUSED_TEXT and vim.uv.fs_stat(UNUSED) == nil
    local msg = okd and (find_msg(r.got, "Deleted class Unused") or "") or ""
    local named = copy and msg:find(copy, 1, true) ~= nil and msg:find(":Nv4jRestoreDeleted", 1, true) ~= nil
      and msg:find("deleted anyway; `:Nv4jRestoreDeleted` brings the file back", 1, true) ~= nil and not msg:find("`u` gives it back", 1, true)
    local got, stop = capture()
    local okr, rerr = pcall(vim.cmd, "Nv4jRestoreDeleted")
    stop()
    local restored = okr and disk(UNUSED) == UNUSED_TEXT and vim.api.nvim_buf_get_name(0) == UNUSED and #vim.fn.glob(tdir .. "/*", false, true) == 0
      and find_msg(got, "restored from the trash") ~= nil
    client.notify = real_notify
    if not okd then error(r) end
    -- removal fails: nothing deleted, buffer kept, no entry left
    local ub2 = open_fresh({ UNUSED })
    os.remove = function(p) if p == UNUSED then return nil, "stubbed EPERM" end return real_remove(p) end
    local r2 = sd_at(ub2, "^public class Unused", "Unused")
    os.remove = real_remove
    local m2 = find_msg(r2.got, "could not delete src/main/java/demo/billing/Unused.java (stubbed EPERM); its buffer is still open, nothing deleted", vim.log.levels.ERROR)
    local kept = r2.ret == false and m2 ~= nil and vim.api.nvim_buf_is_loaded(ub2) and vim.api.nvim_buf_get_name(ub2) == UNUSED
      and disk(UNUSED) == UNUSED_TEXT and #vim.fn.glob(tdir .. "/*", false, true) == 0
    os.remove(UNUSED) -- the planted file goes before the restore (not in the snapshot)
    lsp.report(P .. "safe_delete_trash", def_ok and copied and named and restored and kept and vim.tbl_contains(told, 3) and vim.tbl_contains(told, 1),
      ("default trash %s (%s); delete: copy %s, message %s, jdt.ls told %s; :Nv4jRestoreDeleted: %s%s; removal failing: %s"):format(def,
        def_ok and "under stdpath cache" or "WRONG place", copied and "byte for byte" or ("WRONG: " .. vim.inspect(entries)), named and "names the copy and the command"
        or ("WRONG: " .. msg), table.concat(vim.tbl_map(tostring, told), ","), restored and "file back byte for byte, opened, entry gone" or "FAILED",
        okr and "" or (" " .. tostring(rerr)), kept and "refused, buffer and file kept, no trash entry" or ("WRONG: returned " .. tostring(r2.ret) .. " " .. tostring(m2))))
  end)
  os.remove = real_remove
  refactor.trash_dir = nil
  vim.fn.delete(tdir, "rf")
  if not ok then error(err) end
end)

-- An interface method and a toString() overridden WITHOUT @Override, and an unused own method.
local function plant_no_override()
  plant(CALC, { { "    public int legacyTotal(", [[    interface Rule {
        int apply(int amount);
    }

    static class Half implements Rule {
        public int apply(int amount) {
            return amount / 2;
        }

        public String toString() {
            return "half";
        }

        int own() {
            return 1;
        }
    }

    public int legacyTotal(]] } })
  return open_fresh({ CALC })
end

-- safe_delete_supertypes: no @Override: Half.apply (implements Rule.apply) and toString (overrides
-- Object.toString) refused, the supertype named (jdt.ls's super implementation); the unused own() deleted.
case("safe_delete_supertypes", function()
  local calc = plant_no_override()
  local before = E.text(calc)
  local a = sd_at(calc, "public int apply%(int amount%)", "apply")
  local b = sd_at(calc, "public String toString", "toString")
  local ma = find_msg(a.got, "`apply` overrides or implements demo.billing.PriceCalculator$Rule.apply (no @Override on it)")
  local mb = find_msg(b.got, "`toString` overrides or implements java.lang.Object.toString (no @Override on it)")
  local same = E.text(calc) == before
  local c = sd_at(calc, "int own%(%)", "own")
  local gone = c.ret == true and not E.text(calc):find("int own()", 1, true)
  lsp.report(P .. "safe_delete_supertypes", a.ret == false and ma ~= nil and b.ret == false and mb ~= nil and same and gone,
    ("Half.apply: %s; toString: %s; text %s; own(): returned %s after %.0f ms"):format(ma and "refused, Rule.apply named" or "NOT refused",
      mb and "refused, Object.toString named" or "NOT refused", same and "unchanged" or "CHANGED", tostring(c.ret), c.ms))
end)

-- safe_delete_supertypes_twin (deterministic: java/findLinks stubbed): a super implementation answered for
-- legacyTotal: refused naming it; no answer: refused "could not check the supertypes" (never deleted).
case("safe_delete_supertypes_twin", function()
  local mode = "found"
  local real = client.request_sync
  client.request_sync = function(self, m, params, ms, b)
    if m == "java/findLinks" then
      if mode == "found" then return { result = { { displayName = "stub.Base.legacyTotal", kind = "method", uri = "file:///stub/Base.java",
        range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } } } } } end
      return nil, "timeout"
    end
    return real(self, m, params, ms, b)
  end
  local ok, err = pcall(function()
    local calc = lsp.open(CALC)
    local before = { [calc] = E.text(calc) }
    local a = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
    mode = "none"
    local b = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
    local ma = find_msg(a.got, "`legacyTotal` overrides or implements stub.Base.legacyTotal")
    local mb = find_msg(b.got, "could not check the supertypes of `legacyTotal`", vim.log.levels.ERROR)
    lsp.report(P .. "safe_delete_supertypes_twin", a.ret == false and ma ~= nil and b.ret == false and mb ~= nil and nothing_changed(before),
      ("found: returned %s, %s; no answer: returned %s, %s; %s"):format(tostring(a.ret), ma and "refused naming it" or "NOT refused", tostring(b.ret),
        mb and "refused (could not check)" or "NOT refused", nothing_changed(before) and "nothing changed" or "CHANGED"))
  end)
  client.request_sync = real
  if not ok then error(err) end
end)

-- safe_delete_refused: each refused with its reason, nothing changed: a local variable, a parameter, a
-- constructor, a record component, the `return` keyword, a library method, then (planted) a field declared
-- together with another and an enum constant.
case("safe_delete_refused", function()
  local SR = main .. "demo/StartupRunner.java"
  local runs = {
    { "local", CALC, "int gross = gross%(invoice%);", "gross", "is a local variable or a parameter" },
    { "parameter", CALC, "public int legacyTotal%(", "invoice", "is a local variable or a parameter" },
    { "constructor", INVOICE, "public Invoice%(", "Invoice", "is a constructor" },
    { "record component", MODERN, "^record Circle", "radius", "is a record component" },
    { "keyword", CALC, "^%s+return gross;", "return", "the cursor is not on a declaration or a reference" },
    { "library method", SR, "System%.out%.println", "println", "is declared outside this project" },
    { "two declarators", CALC, "private int a = 1, b = 2;", "b", "is declared together with `a`", true },
    { "enum constant", CALC, "enum Level", "HIGH", "is an enum constant", true },
  }
  local bad, parts = {}, {}
  local planted = false
  for _, x in ipairs(runs) do
    if x[6] and not planted then
      planted = true
      F.restore(snap, client)
      plant(CALC, { { "public class PriceCalculator {\n", "public class PriceCalculator {\n    private int a = 1, b = 2;\n\n    enum Level { LOW, HIGH }\n" } })
      open_fresh({ CALC })
    end
    local b = lsp.open(x[2])
    local before = { [b] = E.text(b) }
    local r = sd_at(b, x[3], x[4])
    local msg = find_msg(r.got, x[5])
    local d = F.diff(snap)
    local same = untouched(before) and #d.added + #d.missing == 0 and #d.changed == (x[6] and 1 or 0)
    if not (r.ret == false and msg and msg:find("nothing deleted", 1, true) and same) then
      bad[#bad + 1] = x[1] .. " (returned " .. tostring(r.ret) .. ", " .. (same and "unchanged" or "CHANGED") .. ": "
        .. table.concat(vim.tbl_map(function(g) return g.msg end, r.got), " || ") .. ")"
    end
    parts[#parts + 1] = ("%s %.0f ms"):format(x[1], r.ms)
    qf_close()
  end
  lsp.report(P .. "safe_delete_refused", #bad == 0, ("%d/%d refused with the reason (%s)%s"):format(#runs - #bad, #runs, table.concat(parts, ", "),
    #bad > 0 and ("; WRONG: " .. table.concat(bad, "; ")) or ""))
end)

-- safe_delete_no_answer (stub): jdt.ls's references time out, then answer an error: refused ("usages
-- unknown"), nothing deleted (never taken as "no usages").
case("safe_delete_no_answer", function()
  local mode = "timeout"
  local undo = stub_references(function()
    if mode == "timeout" then return nil, "timeout" end
    return { err = { code = -32603, message = "stubbed internal error" } }
  end)
  local ok, err = pcall(function()
    local calc = lsp.open(CALC)
    local before = { [calc] = E.text(calc) }
    local a = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
    mode = "error"
    local b = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
    local ma = find_msg(a.got, "did not answer the references request", vim.log.levels.ERROR)
    local mb = find_msg(b.got, "refused the references request (stubbed internal error)", vim.log.levels.ERROR)
    lsp.report(P .. "safe_delete_no_answer", a.ret == false and b.ret == false and ma ~= nil and mb ~= nil and nothing_changed(before)
      and (ma or ""):find("usages unknown; nothing deleted", 1, true) ~= nil,
      ("timeout: returned %s, %s; error: returned %s, %s; %s"):format(tostring(a.ret), ma or "NO MESSAGE", tostring(b.ret), mb or "NO MESSAGE",
        nothing_changed(before) and "nothing changed" or "CHANGED"))
  end)
  undo()
  if not ok then error(err) end
end)

-- safe_delete_busy (deterministic: change signature's answer delayed 600 ms): safe delete refused while it
-- is pending ("a refactor is in progress"), legacyTotal kept; the change signature completes.
case("safe_delete_busy", function()
  local calc = lsp.open(CALC)
  lsp.open(CHECKOUT)
  local undo = delay_edit(600)
  local ok, err = pcall(function()
    local a = cs_async(calc, "public int total%(Invoice invoice%)", "total", ADD_DISCOUNT)
    local b = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
    local msg = find_msg(b.got, "a refactor is in progress (change signature of total)")
    local kept = E.text(calc):find("public int legacyTotal(", 1, true) ~= nil
    vim.wait(refactor.signature_ms + 1000, function() return a.done ~= nil end, 5)
    lsp.report(P .. "safe_delete_busy", b.ret == false and msg ~= nil and kept and a.done == true and refactor._busy() == nil,
      ("while pending: safe delete returned %s, message %s, legacyTotal %s; change signature on_done %s; busy after %s"):format(tostring(b.ret),
        msg and "yes" or "NONE", kept and "kept" or "DELETED", tostring(a.done), vim.inspect(refactor._busy())))
  end)
  undo()
  if not ok then error(err) end
end)

-- safe_delete_throw (stub, fix wave R-I4): an error thrown after the declaration was deleted (refactor.stale_refs
-- made to throw): safe delete returns false, on_done(false) once, an ERROR names it, and `busy` is clear, so
-- a refactor started right after is not refused.
case("safe_delete_throw", function()
  local calc = lsp.open(CALC)
  local real = refactor.stale_refs
  refactor.stale_refs = function() error("injected stale_refs error") end
  local ok, err = pcall(function()
    local calls_done, last = 0, nil
    local r = sd_at(calc, "public int legacyTotal%(", "legacyTotal", { on_done = function(x) calls_done, last = calls_done + 1, x end })
    local m = find_msg(r.got, "injected stale_refs error", vim.log.levels.ERROR)
    local busy1 = refactor._busy()
    refactor.stale_refs = real
    F.restore(snap, client)
    calc = lsp.open(CALC)
    local r2 = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
    local refused = find_msg(r2.got, "a refactor is in progress")
    lsp.report(P .. "safe_delete_throw", r.ret == false and calls_done == 1 and last == false and m ~= nil and busy1 == nil
      and r2.ret == true and refused == nil and refactor._busy() == nil,
      ("thrown: returned %s, on_done x%d (%s), ERROR %s, busy after %s; next safe delete returned %s%s"):format(tostring(r.ret), calls_done,
        tostring(last), m and "yes" or "NONE", vim.inspect(busy1), tostring(r2.ret), refused and (" REFUSED: " .. refused) or ""))
  end)
  refactor.stale_refs = real
  if not ok then error(err) end
end)

-- safe_delete_unreadable (stub + real file): (a) stub: reading application-dev.yml throws; safe delete of
-- legacyTotal still deletes and the result warns "could not read 1 file(s)"; (b) real: stale_refs on a
-- /tmp/nv4j directory holding a mode 000 file returns it as unread and still finds the hit in the readable one.
case("safe_delete_unreadable", function()
  local calc = lsp.open(CALC)
  local real = refactor._readfile
  refactor._readfile = function(p, ...)
    if p:find("application-dev.yml", 1, true) then error("Vim:E484: Can't open file " .. p) end
    return real(p, ...)
  end
  local ok, err = pcall(function()
    local r = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
    local m = find_msg(r.got, "could not read 1 file(s), so they were not checked for `legacyTotal`: src/main/resources/application-dev.yml", vim.log.levels.WARN)
    refactor._readfile = real
    local dir = "/tmp/nv4j/unreadable62"
    vim.fn.delete(dir, "rf")
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "key: legacyTotal" }, dir .. "/seen.yml")
    vim.fn.writefile({ "key: legacyTotal" }, dir .. "/hidden.yml")
    vim.uv.fs_chmod(dir .. "/hidden.yml", 0)
    local sok, stale, _, unread = pcall(function() local a, b, c = refactor.stale_refs(dir, { java = { "legacyTotal" }, config = { "legacyTotal" } }); return a, b, c end)
    vim.uv.fs_chmod(dir .. "/hidden.yml", 420)
    vim.fn.delete(dir, "rf")
    local real_unread = sok and type(unread) == "table" and #unread == 1 and unread[1] == "hidden.yml"
    -- running as root, a mode 000 file is still readable: the real half then proves nothing; say so
    local as_root = vim.uv.getuid and vim.uv.getuid() == 0
    lsp.report(P .. "safe_delete_unreadable", r.ret == true and m ~= nil and refactor._busy() == nil
      and sok and #stale == 1 and (real_unread or as_root),
      ("stub: returned %s, warning %s, busy %s; real mode 000 file: stale_refs %s, hits %s, unread %s%s"):format(tostring(r.ret), m and "yes" or "NONE",
        vim.inspect(refactor._busy()), sok and "returned" or ("THREW " .. tostring(stale)), sok and #stale or "?", vim.inspect(unread),
        as_root and " (root: not a real test of the chmod half)" or ""))
  end)
  refactor._readfile = real
  if not ok then error(err) end
end)

--- Delays jdt.ls's answer to `method` by `ms` (a deterministic window for a request in flight); returns the restore function.
local function delay_request(method, ms)
  local real = client.request
  client.request = function(self, m, params, handler, b)
    if m ~= method then return real(self, m, params, handler, b) end
    return real(self, m, params, function(err, result, ctx) vim.defer_fn(function() handler(err, result, ctx) end, ms) end, b)
  end
  return function() client.request = real end
end

--- rename_class from Invoice's declaration, asynchronous: { ret, done = ok once on_done ran, got }.
local function rc_async(inv, name)
  vim.api.nvim_set_current_buf(inv)
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local res = {}
  res.got, res.stop = capture()
  res.ret = refactor.rename_class({ name = name, on_done = function(ok) res.done = ok end })
  return res
end

-- rename_class_busy (deterministic: jdt.ls's rename answer delayed 600 ms): while a class rename is pending,
-- a second rename, a change signature, an inline and a safe delete are refused ("a refactor is in
-- progress (rename class Invoice)"); the first one then completes (Bill.java) and `busy` is cleared.
case("rename_class_busy", function()
  local inv, calc = lsp.open(INVOICE), lsp.open(CALC)
  lsp.open(CHECKOUT)
  local undo = delay_request("textDocument/rename", 600)
  local ok, err = pcall(function()
    local a = rc_async(inv, "Bill")
    local busy_during = refactor._busy()
    local want = "a refactor is in progress (rename class Invoice)"
    local b = cs_at(calc, "public int legacyTotal%(", "legacyTotal", { name = "oldTotal" })
    local c = inline_at(calc, "int gross = gross%(invoice%);", "gross(")
    local d = sd_at(calc, "public int legacyTotal%(", "legacyTotal")
    vim.api.nvim_set_current_buf(inv)
    local got2, stop2 = capture()
    local e = refactor.rename_class({ name = "Bill2" })
    stop2()
    local refused = b.ret == false and find_msg(b.got, want) ~= nil and c.ret == false and find_msg(c.got, want) ~= nil
      and d.ret == false and find_msg(d.got, want) ~= nil and e == false and find_msg(got2, want) ~= nil
    vim.wait(3000, function() return a.done ~= nil end, 5)
    a.stop()
    local after = a.done == true and vim.uv.fs_stat(BILL) ~= nil and vim.uv.fs_stat(INVOICE) == nil and refactor._busy() == nil
      and vim.uv.fs_stat(main .. "demo/billing/Bill2.java") == nil
    lsp.report(P .. "rename_class_busy", busy_during ~= nil and refused and after,
      ("while pending: busy %s; change signature %s, inline %s, safe delete %s, second rename %s; first one: on_done %s, Bill.java %s, busy after %s"):format(
        vim.inspect(busy_during), tostring(b.ret), tostring(c.ret), tostring(d.ret), tostring(e), tostring(a.done),
        vim.uv.fs_stat(BILL) and "there" or "MISSING", vim.inspect(refactor._busy())))
  end)
  undo()
  if not ok then error(err) end
end)

-- rename_class_stale (deterministic: the answer delayed 400 ms): Checkout (which the rename touches) is typed into
-- while jdt.ls computes the edit: refused whole ("changed while jdt.ls computed the edit"), nothing applied
-- (Invoice.java still there, no Bill.java, PriceCalculator untouched), the typed line kept, disk unchanged, busy clear.
case("rename_class_stale", function()
  local inv, chk, calc = lsp.open(INVOICE), lsp.open(CHECKOUT), lsp.open(CALC)
  local before_calc = E.text(calc)
  local undo = delay_request("textDocument/rename", 400)
  local ok, err = pcall(function()
    local a = rc_async(inv, "Bill")
    append_line(chk, "// typed while jdt.ls works")
    local typed = E.text(chk)
    vim.wait(3000, function() return a.done ~= nil end, 5)
    a.stop()
    local msg = find_msg(a.got, "src/main/java/demo/shop/Checkout.java changed while jdt.ls computed the edit; nothing changed", vim.log.levels.WARN)
    local d = F.diff(snap)
    local good = a.done == false and msg ~= nil and vim.uv.fs_stat(INVOICE) ~= nil and vim.uv.fs_stat(BILL) == nil
      and E.text(calc) == before_calc and E.text(chk) == typed and #d.added + #d.changed + #d.missing == 0 and refactor._busy() == nil
    lsp.report(P .. "rename_class_stale", good, ("on_done %s; message %s; Invoice.java %s, Bill.java %s; PriceCalculator %s, Checkout %s; disk %s; busy %s"):format(
      tostring(a.done), tostring(msg), vim.uv.fs_stat(INVOICE) and "kept" or "GONE", vim.uv.fs_stat(BILL) and "CREATED" or "absent",
      E.text(calc) == before_calc and "untouched" or "CHANGED", E.text(chk) == typed and "only the typed line" or "EDITED",
      #d.changed == 0 and "unchanged" or F.fmt(d), vim.inspect(refactor._busy())))
  end)
  undo()
  if not ok then error(err) end
end)

-- rename_class_finish_error (stub): an error after jdt.ls answered (refactor.stale_refs throws): on_done(false), an ERROR
-- names it, `busy` cleared, the next refactor is not refused.
case("rename_class_finish_error", function()
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT)
  local real = refactor.stale_refs
  refactor.stale_refs = function() error("injected rename error") end
  local ok, err = pcall(function()
    local a = rc_async(inv, "Bill")
    vim.wait(5000, function() return a.done ~= nil end, 5)
    a.stop()
    local m = find_msg(a.got, "injected rename error", vim.log.levels.ERROR)
    lsp.report(P .. "rename_class_finish_error", a.done == false and m ~= nil and refactor._busy() == nil,
      ("on_done %s; ERROR %s; busy %s"):format(tostring(a.done), m and "yes" or "NONE", vim.inspect(refactor._busy())))
  end)
  refactor.stale_refs = real
  if not ok then error(err) end
end)

--- True when the file system treats names that differ only by case as one (macOS default).
local function case_insensitive_fs()
  local probe = "/tmp/nv4j/CaseProbe62.tmp"
  os.remove(probe)
  local f = io.open(probe, "w")
  if not f then return nil end
  f:close()
  local same = vim.uv.fs_stat("/tmp/nv4j/caseprobe62.tmp") ~= nil
  os.remove(probe)
  return same
end

--- File names in `dir` (as listed on disk, case as stored).
local function names_in(dir)
  local out = {}
  for name in vim.fs.dir(dir) do out[name] = true end
  return out
end

-- rename_class_case_only (fix wave R-I1): Invoice -> INVOICE. On a case-insensitive file system (macOS default)
-- jdt.ls answers with one text edit on the declaration (no reference updated) and a RenameFile that Neovim skips
-- ("already exists"): INVOICE.java never existed, Invoice.java held `class INVOICE`, Checkout kept
-- `import demo.billing.Invoice`, and the summary still said renamed (reproduced, log in refactors.md). Expected: done in
-- two real renames through a temporary name: the directory lists INVOICE.java only (no temporary file left), it
-- declares INVOICE, Checkout and PriceCalculator use INVOICE, the summary is true (INVOICE.java (from Invoice.java)),
-- the build is clean. SKIPPED (printed, not a PASS) on a case-sensitive file system, where the problem cannot exist.
case("rename_class_case_only", function()
  local ci = case_insensitive_fs()
  if ci ~= true then
    return print("SKIP " .. P .. "rename_class_case_only " .. (ci == false and "this file system is case-sensitive: the case-only rename problem cannot occur here"
      or "cannot create a probe file in /tmp/nv4j"))
  end
  local inv, chk = lsp.open(INVOICE), lsp.open(CHECKOUT)
  lsp.open(CALC)
  local billing = main .. "demo/billing"
  local NEW = billing .. "/INVOICE.java"
  vim.api.nvim_set_current_buf(inv)
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local got, stop = capture()
  local t0, res = E.now(), {}
  refactor.rename_class({ name = "INVOICE", on_done = function(ok) res.done = ok end })
  local applied, ms = until_ms(t0, function() return res.done ~= nil end)
  stop()
  local names = names_in(billing)
  local sum = find_msg(got, "Renamed class Invoice -> INVOICE") or ""
  local on_disk = disk(NEW) or ""
  local ct, pt = disk(CHECKOUT) or "", disk(CALC) or ""
  local ok_clean, why = clean({ NEW, CHECKOUT }, t0)
  local tmp_left = false
  for n in pairs(names) do if n:find("Nv4jTmp", 1, true) then tmp_left = true end end
  report_apply("rename_class_case_only", "nv4j.refactor.rename_class Invoice -> INVOICE", applied and res.done == true, ms, {
    { "directory lists INVOICE.java and not Invoice.java, no temporary file", names["INVOICE.java"] == true and names["Invoice.java"] == nil and not tmp_left },
    { "INVOICE.java declares INVOICE on disk", on_disk:find("public class INVOICE", 1, true) ~= nil and on_disk:find("class Invoice", 1, true) == nil },
    { ("Checkout imports demo.billing.INVOICE, no Invoice token left (Checkout %d, PriceCalculator %d; INVOICE tokens in PriceCalculator %d)"):format(
      word_count(ct, "Invoice"), word_count(pt, "Invoice"), word_count(pt, "INVOICE")), ct:find("import demo.billing.INVOICE;", 1, true) ~= nil
      and word_count(ct, "Invoice") == 0 and word_count(pt, "Invoice") == 0 and word_count(pt, "INVOICE") > 0 },
    { "summary says INVOICE.java (from Invoice.java)", sum:find("INVOICE.java (from src/main/java/demo/billing/Invoice.java", 1, true) ~= nil
      or sum:find("INVOICE.java (from Invoice.java", 1, true) ~= nil },
    { "no ERROR or 'already exists' notification", find_msg(got, "FAILED", vim.log.levels.ERROR) == nil and find_msg(got, "already exists") == nil },
  }, ok_clean, why)
end)

-- multi_module_roots (fix wave R-I3; no jdt.ls round trip, a throwaway layout under /tmp/nv4j/mm62, the fixture is
-- not touched). Layout: repo/.git + repo/pom.xml (so root.project is the REPO), repo/mod (pom, main and test roots:
-- demo.billing in both, demo.invoicing/A.java in test, an @SpringBootApplication in demo), repo/mod2 (a namesake
-- demo.billing of ANOTHER module), repo/g (build.gradle.kts, main and test demo.billing). Checks:
--  (a) module_root = the module, not the repo (and root.project IS the repo: the old base); gradle module too;
--  (b) rename_package from mod's A.java (rename_paths stubbed, its moves captured): the main folder then the TEST
--      namesake of the same module, nothing of mod2 or g;
--  (c) move A to demo.invoicing: refused, the class exists in mod's TEST root;
--  (d) move A to demo.other: the note says ATest stays in demo.billing (mod's test root);
--  (e) move Ctl (@RestController) to package web: the Spring scan warning is there (mod's @SpringBootApplication found).
-- A full jdt.ls multi-module project is not built here (the Maven import alone is minutes); jdt.ls's side is the same
-- willRenameFiles call per root as on the fixture (rename_package_imports).
case("multi_module_roots", function()
  vim.fn.delete("/tmp/nv4j/mm62", "rf")
  vim.fn.mkdir("/tmp/nv4j/mm62", "p")
  local R = vim.uv.fs_realpath("/tmp/nv4j/mm62") -- buffers carry the real path (/tmp is a symlink on macOS)
  local function put(rel_path, text)
    local abs = R .. "/" .. rel_path
    vim.fn.mkdir(vim.fs.dirname(abs), "p")
    local f = assert(io.open(abs, "w")); f:write(text); f:close()
    return abs
  end
  vim.fn.mkdir(R .. "/.git", "p")
  put("pom.xml", "<project/>\n"); put("mod/pom.xml", "<project/>\n"); put("mod2/pom.xml", "<project/>\n")
  put("g/build.gradle.kts", "\n")
  -- nearest build file wins whatever the marker (no src root: the fallback path): repo/k2/pom.xml above repo/k2/sub/build.gradle.kts
  put("k2/pom.xml", "<project/>\n"); put("k2/sub/build.gradle.kts", "\n")
  local K2 = put("k2/sub/Bar.java", "class Bar {}\n")
  local A = put("mod/src/main/java/demo/billing/A.java", "package demo.billing;\n\npublic class A {}\n")
  local CTL = put("mod/src/main/java/demo/billing/Ctl.java", "package demo.billing;\n\n@RestController\npublic class Ctl {}\n")
  put("mod/src/main/java/demo/App.java", "package demo;\n\n@SpringBootApplication\npublic class App {}\n")
  put("mod/src/test/java/demo/billing/ATest.java", "package demo.billing;\n\nclass ATest {}\n")
  put("mod/src/test/java/demo/invoicing/A.java", "package demo.invoicing;\n\nclass A {}\n")
  put("mod2/src/main/java/demo/billing/B.java", "package demo.billing;\n\npublic class B {}\n")
  local G = put("g/src/main/java/demo/billing/G.java", "package demo.billing;\n\npublic class G {}\n")
  put("g/src/test/java/demo/billing/GTest.java", "package demo.billing;\n\nclass GTest {}\n")
  local real_paths, real_clients, real_last = refactor.rename_paths, vim.lsp.get_clients, refactor.last
  local ok, err = pcall(function()
    -- (a)
    local project = require("nv4j.root").project(A)
    local m_mod, m_g = refactor._module_root(A), refactor._module_root(G)
    local m_k2 = refactor._module_root(K2)
    local a_ok = project == R and m_mod == R .. "/mod" and m_g == R .. "/g" and m_k2 == R .. "/k2/sub"
    -- (b)
    local captured
    refactor.rename_paths = function(moves, label, c, o) captured = { moves = moves, label = label, opts = o }; return true end
    vim.cmd.edit(vim.fn.fnameescape(A))
    local rp = refactor.rename_package({ name = "demo.invoicing2" })
    local mv = captured and captured.moves or {}
    local b_ok = rp == true and #mv == 2 and mv[1][1] == R .. "/mod/src/main/java/demo/billing" and mv[1][2] == R .. "/mod/src/main/java/demo/invoicing2"
      and mv[2][1] == R .. "/mod/src/test/java/demo/billing" and mv[2][2] == R .. "/mod/src/test/java/demo/invoicing2"
    -- move: a fake jdtls client rooted at the repo (no round trip: single-type files; rename_paths stubbed)
    local fake = { name = "jdtls", id = 99, config = { root_dir = R }, root_dir = R, notify = function() end,
      request_sync = function() return nil, "not asked" end, offset_encoding = "utf-16" }
    vim.lsp.get_clients = function(f)
      local out = real_clients(f)
      if f and f.name == "jdtls" then out[#out + 1] = fake end
      return out
    end
    local function move_to(file, pkg)
      vim.cmd.edit(vim.fn.fnameescape(file))
      captured = nil
      local got, stop = capture()
      local r = refactor.move({ package = pkg })
      stop()
      return r, got, captured
    end
    -- (c)
    local rc, gotc = move_to(A, "demo.invoicing")
    local c_ok = rc == false and find_msg(gotc, "demo.invoicing.A already exists") ~= nil
    -- (d)
    local rd, gotd, capd = move_to(A, "demo.other")
    local d_ok = rd == true and capd ~= nil and table.concat(capd.opts.info or {}, " | "):find("ATest.java stays in package demo.billing", 1, true) ~= nil
    -- (e)
    local re, gote, cape = move_to(CTL, "web")
    local e_ok = re == true and cape ~= nil and table.concat(cape.opts.warn or {}, " | "):find("Spring: Ctl (@RestController) is now in web", 1, true) ~= nil
    lsp.report(P .. "multi_module_roots", a_ok and b_ok and c_ok and d_ok and e_ok,
      ("(a) module_root %s (root.project %s), gradle %s, nearest build file (no src root) %s; (b) rename_package moves %s; (c) move into demo.invoicing: %s; (d) test-stays note: %s; (e) Spring warning: %s"):format(
        vim.fs.basename(m_mod), vim.fs.basename(project), vim.fs.basename(m_g), m_k2:sub(#R + 2), vim.inspect(vim.tbl_map(function(m) return m[1]:sub(#R + 2) end, mv)),
        c_ok and "refused" or ("NOT refused (" .. tostring(rc) .. "): " .. table.concat(vim.tbl_map(function(g) return g.msg end, gotc), " || ")),
        d_ok and "yes" or ("NO: " .. vim.inspect(capd and capd.opts.info)), e_ok and "yes" or ("NO: " .. vim.inspect(cape and cape.opts.warn))))
  end)
  refactor.rename_paths, vim.lsp.get_clients, refactor.last = real_paths, real_clients, real_last
  pcall(vim.cmd, "silent! %bwipeout!")
  vim.fn.delete(R, "rf")
  if not ok then error(err) end
end)

-- safe_delete_trash_order (fix wave R-m4; deterministic: vim.uv.hrtime stubbed so its microseconds WRAP between the
-- 2nd and 3rd entry, the wall clock stubbed increasing, trash dir under /tmp/nv4j): six entries made in a row sort in
-- creation order (their .origin lines are F1..F6), and restore_deleted puts back the NEWEST (F6) only. The old name
-- (date + hrtime microseconds mod 1e6) sorted the entries after the wrap before the earlier ones.
case("safe_delete_trash_order", function()
  local dir = "/tmp/nv4j/trash62-order"
  vim.fn.delete(dir, "rf")
  vim.fn.mkdir(dir .. "/src", "p")
  local real_root, real_hr, real_gt = refactor.trash_dir, vim.uv.hrtime, vim.uv.gettimeofday
  refactor.trash_dir = dir .. "/trash"
  local ok, err = pcall(function()
    local files = {}
    for i = 1, 6 do
      files[i] = ("%s/src/F%d.txt"):format(dir, i)
      vim.fn.writefile({ "content " .. i }, files[i])
    end
    local hr_us, k, g = { 999900, 999950, 100, 150, 200, 250 }, 0, 0
    vim.uv.hrtime = function() k = k + 1; return (hr_us[k] or 300) * 1000 end
    vim.uv.gettimeofday = function() g = g + 1; return 1800000000, 1000 * g end
    for i = 1, 6 do assert(refactor._to_trash(files[i], dir)) end
    vim.uv.hrtime, vim.uv.gettimeofday = real_hr, real_gt
    local order = {}
    for _, name in ipairs(refactor._trash_entries()) do
      order[#order + 1] = vim.fs.basename(vim.fn.readfile(refactor.trash_root() .. "/" .. name .. "/.origin")[1])
    end
    for i = 1, 6 do os.remove(files[i]) end
    local rok, rmsg = refactor.restore_deleted()
    local back6 = vim.uv.fs_stat(files[6]) ~= nil and table.concat(vim.fn.readfile(files[6]), "") == "content 6"
    local only6 = true
    for i = 1, 5 do if vim.uv.fs_stat(files[i]) then only6 = false end end
    vim.cmd("silent! %bwipeout!")
    lsp.report(P .. "safe_delete_trash_order", table.concat(order, ",") == "F1.txt,F2.txt,F3.txt,F4.txt,F5.txt,F6.txt" and rok == true and back6 and only6
      and #refactor._trash_entries() == 5,
      ("entries in order %s; restore_deleted %s: F6 back %s, nothing else %s; %d entries left"):format(table.concat(order, ","), tostring(rok),
        back6 and "yes" or "NO", only6 and "yes" or "NO (an older one was restored)", #refactor._trash_entries()))
  end)
  vim.uv.hrtime, vim.uv.gettimeofday, refactor.trash_dir = real_hr, real_gt, real_root
  vim.fn.delete(dir, "rf")
  if not ok then error(err) end
end)

-- safe_delete_restore_failed (fix wave R-m5; deterministic: io.open stubbed so the write to the destination fails with
-- "No space left on device"): restore_deleted says so, returns false, leaves no partial file, and KEEPS the trash entry
-- (the only copy). The old code deleted the entry after a failed write.
case("safe_delete_restore_failed", function()
  local dir = "/tmp/nv4j/trash62-restore"
  vim.fn.delete(dir, "rf")
  vim.fn.mkdir(dir .. "/src", "p")
  local real_root, real_open = refactor.trash_dir, io.open
  refactor.trash_dir = dir .. "/trash"
  local ok, err = pcall(function()
    local f = dir .. "/src/Keep.txt"
    vim.fn.writefile({ "precious" }, f)
    assert(refactor._to_trash(f, dir))
    os.remove(f)
    local got, stop = capture()
    io.open = function(p, mode)
      if p == f and mode == "wb" then
        return { write = function() return nil, "No space left on device (stub)" end, close = function() return true end }
      end
      return real_open(p, mode)
    end
    local rok, rmsg = refactor.restore_deleted()
    io.open = real_open
    stop()
    local entries = refactor._trash_entries()
    local copy_kept = #entries == 1 and table.concat(vim.fn.readfile(refactor.trash_root() .. "/" .. entries[1] .. "/src/Keep.txt"), "") == "precious"
    local says = (rmsg or ""):find("No space left on device (stub)", 1, true) ~= nil and find_msg(got, "the copy stays in", vim.log.levels.ERROR) ~= nil
    lsp.report(P .. "safe_delete_restore_failed", rok == false and says and copy_kept and vim.uv.fs_stat(f) == nil,
      ("restore_deleted returned %s, message %s; trash entry %s; destination %s"):format(tostring(rok), tostring(rmsg):sub(1, 110),
        copy_kept and "kept" or "LOST", vim.uv.fs_stat(f) and "PARTIAL FILE LEFT" or "absent"))
  end)
  io.open, refactor.trash_dir = real_open, real_root
  vim.fn.delete(dir, "rf")
  if not ok then error(err) end
end)

-- rename_package_part_way_message (fix wave R-m1; deterministic: willRenameFiles refused for the second root): demo.billing ->
-- demo.invoicing moves src/main/java first, then fails on src/test/java. The ERROR names the folder that ALREADY moved and
-- says `u` does not move it back (it used to promise `u` undoes the files listed, which leaves main and test in different packages).
case("rename_package_part_way_message", function()
  local calc = lsp.open(CALC)
  lsp.open(INVOICE)
  vim.api.nvim_set_current_buf(calc); vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local real = client.request_sync
  client.request_sync = function(self, m, params, t, b)
    if m == "workspace/willRenameFiles" and params.files[1].oldUri:find("/src/test/java/", 1, true) then
      return { err = { code = -32603, message = "stubbed refusal for the test root" } }
    end
    return real(self, m, params, t, b)
  end
  local ok, err = pcall(function()
    local got, stop = capture()
    local r = refactor.rename_package({ name = "demo.invoicing" })
    stop()
    local msg = find_msg(got, "FAILED part-way", vim.log.levels.ERROR) or ""
    lsp.report(P .. "rename_package_part_way_message", r == false and msg:find("stubbed refusal for the test root", 1, true) ~= nil
      and msg:find("Already moved, and `u` does NOT move them back: src/main/java/demo/billing -> src/main/java/demo/invoicing", 1, true) ~= nil
      and not msg:find("Undo with `u` in each file listed.", 1, true),
      ("returned %s; message: %s"):format(tostring(r), msg ~= "" and msg:sub(1, 400) or "NONE"))
  end)
  client.request_sync = real
  if not ok then error(err) end
end)

-- rename_class_no_answer / _not_sent (re-review N1; deterministic stubs on client.request): a class rename whose request never
-- gets an answer (refactor.rename_ms 400 ms) ends with a visible ERROR, on_done(false) once and `busy` cleared; an answer
-- arriving later is ignored (nothing applied); a request that returns false (jdt.ls stopped) or throws ends at once the same way.
case("rename_class_no_answer", function()
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT)
  local real, real_ms = client.request, refactor.rename_ms
  local late
  client.request = function(self, m, params, handler, b)
    if m ~= "textDocument/rename" then return real(self, m, params, handler, b) end
    late = handler
    return true, 1
  end
  refactor.rename_ms = 400
  local ok, err = pcall(function()
    local calls_done, last = 0, nil
    vim.api.nvim_set_current_buf(inv)
    local l, c = pos(inv, "^public class Invoice", "Invoice")
    vim.api.nvim_win_set_cursor(0, { l + 1, c })
    local got, stop = capture()
    refactor.rename_class({ name = "Bill", on_done = function(x) calls_done, last = calls_done + 1, x end })
    local busy_during = refactor._busy()
    vim.wait(3000, function() return calls_done > 0 end, 10)
    local busy_after = refactor._busy()
    -- the answer that comes too late: a text edit that must NOT be applied
    if late then late(nil, { changes = { [vim.uri_from_fname(INVOICE)] = { { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } }, newText = "// LATE\n" } } } }) end
    stop()
    local msg = find_msg(got, "jdt.ls did not answer in 400 ms", vim.log.levels.ERROR)
    local d = F.diff(snap)
    lsp.report(P .. "rename_class_no_answer", busy_during ~= nil and calls_done == 1 and last == false and msg ~= nil and busy_after == nil
      and not E.text(inv):find("// LATE", 1, true) and #d.added + #d.changed + #d.missing == 0,
      ("busy while pending %s; on_done x%d (%s); ERROR %s; busy after %s; late answer %s; disk %s"):format(vim.inspect(busy_during), calls_done, tostring(last),
        msg and "yes" or "NONE", vim.inspect(busy_after), E.text(inv):find("// LATE", 1, true) and "APPLIED" or "ignored", F.fmt(d)))
  end)
  client.request, refactor.rename_ms = real, real_ms
  if not ok then error(err) end
end)

case("rename_class_not_sent", function()
  local inv = lsp.open(INVOICE)
  local real = client.request
  local ok, err = pcall(function()
    local results = {}
    for _, how in ipairs({ "false", "throws" }) do
      client.request = function(self, m, params, handler, b)
        if m ~= "textDocument/rename" then return real(self, m, params, handler, b) end
        if how == "throws" then error("stub: client is gone") end
        return false
      end
      local n, last = 0, nil
      vim.api.nvim_set_current_buf(inv)
      local l, c = pos(inv, "^public class Invoice", "Invoice")
      vim.api.nvim_win_set_cursor(0, { l + 1, c })
      local got, stop = capture()
      refactor.rename_class({ name = "Bill", on_done = function(x) n, last = n + 1, x end })
      stop()
      results[#results + 1] = { how = how, n = n, last = last, busy = refactor._busy(), msg = find_msg(got, "the request could not be sent to jdt.ls", vim.log.levels.ERROR) }
    end
    client.request = real
    local good = true
    for _, r in ipairs(results) do good = good and r.n == 1 and r.last == false and r.busy == nil and r.msg ~= nil end
    lsp.report(P .. "rename_class_not_sent", good, table.concat(vim.tbl_map(function(r)
      return ("request %s: on_done x%d (%s), busy %s, message %s"):format(r.how, r.n, tostring(r.last), vim.inspect(r.busy), r.msg and "yes" or "NONE") end, results), "; "))
  end)
  client.request = real
  if not ok then error(err) end
end)

-- rename_class_on_done_throws (re-review N4): a caller's on_done that throws after a successful rename is not called a second time.
case("rename_class_on_done_throws", function()
  local inv = lsp.open(INVOICE)
  lsp.open(CHECKOUT)
  vim.api.nvim_set_current_buf(inv)
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local n, args = 0, {}
  local got, stop = capture()
  refactor.rename_class({ name = "Bill", on_done = function(x) n = n + 1; args[#args + 1] = tostring(x); error("on_done boom") end })
  vim.wait(4000, function() return n > 0 end, 10)
  vim.wait(500)
  stop()
  lsp.report(P .. "rename_class_on_done_throws", n == 1 and args[1] == "true" and refactor._busy() == nil,
    ("on_done called %d time(s) (%s); busy %s"):format(n, table.concat(args, ","), vim.inspect(refactor._busy())))
end)

-- rename_class_case_only_undo (re-review Q1): the two renames of a case-only rename (via the temporary name) form ONE undo step in each
-- touched buffer: one `u` gives back the text from before (the file keeps its new name, as with any rename). SKIP on a case-sensitive FS.
case("rename_class_case_only_undo", function()
  if case_insensitive_fs() ~= true then return print("SKIP " .. P .. "rename_class_case_only_undo case-sensitive file system") end
  local inv, chk, calc = lsp.open(INVOICE), lsp.open(CHECKOUT), lsp.open(CALC)
  local before = { Checkout = E.text(chk), PriceCalculator = E.text(calc), Invoice = E.text(inv) }
  vim.api.nvim_set_current_buf(inv)
  local l, c = pos(inv, "^public class Invoice", "Invoice")
  vim.api.nvim_win_set_cursor(0, { l + 1, c })
  local res = {}
  refactor.rename_class({ name = "INVOICE", on_done = function(ok) res.done = ok end })
  vim.wait(8000, function() return res.done ~= nil end, 10)
  local bad = {}
  for name, path in pairs({ Checkout = CHECKOUT, PriceCalculator = CALC, Invoice = main .. "demo/billing/INVOICE.java" }) do
    local b = vim.fn.bufnr(path)
    if b == -1 or not vim.api.nvim_buf_is_loaded(b) then bad[#bad + 1] = name .. " (no buffer)"
    else
      vim.api.nvim_buf_call(b, function() vim.cmd("silent! undo") end)
      if E.text(b) ~= before[name] then bad[#bad + 1] = name end
    end
  end
  lsp.report(P .. "rename_class_case_only_undo", res.done == true and #bad == 0,
    res.done == true and (#bad == 0 and "one u restored every touched buffer" or ("not restored by one u: " .. table.concat(bad, ", "))) or "rename not done")
end)

local left = F.diff(snap)
lsp.report(P .. "fixture_restored", #left.added + #left.changed + #left.missing == 0, "left: " .. F.fmt(left))
lsp.finish()
