-- P3 scaffolding. Run via tests/run.sh. Spec: specs/features/scaffolding.md (decision D22 in
-- specs/001-architecture.md). Product: nvim/lua/nv4j/scaffold.lua (P3 Task 3).
-- Budget (P3 plan, not weakened): the file is created on disk, opened, with the right `package`
-- line <= 300 ms after the call.
-- API under test: require("nv4j.scaffold").new({ kind = ..., name = ..., dir = ... }) creates and opens
-- the file (or the package directory) without prompts when name/kind are given.
--  api          : nv4j.scaffold.new exists.
--  key          : <leader>jn is mapped (global, desc names the scaffold) and <leader>j is free of
--                 other meanings (no collision found in Task 0).
--  kind_<k>     : one case per kind in src/main/java/demo/p3scaffold: class, interface, record, enum,
--                 annotation, controller, service, repository, entity. The file exists on disk, is the
--                 current buffer, starts with `package demo.p3scaffold;`, declares the right type, and
--                 stereotypes carry their annotation and import. <= 300 ms.
--  package      : kind "package", name "demo.p3scaffold.sub" creates that directory under src/main/java.
--  nested_name  : name "deep.Thing" in demo/p3scaffold creates demo/p3scaffold/deep/Thing.java with
--                 `package demo.p3scaffold.deep;` (IntelliJ: a dotted name creates the packages).
--  test_for     : kind "test" from demo/shop/Checkout.java creates src/test/java/demo/shop/CheckoutTest.java
--                 (`package demo.shop;`, `class CheckoutTest`, JUnit 5 `@Test` import).
--  compiles     : jdt.ls reports no error for the new class buffer <= 3 s after creation: at creation + 3 s
--                 (snapshot timer) it has been published and shows zero errors, the publish that set its
--                 error count last arrives <= 3 s after creation, and after an explicit build (the
--                 deterministic twin) it has zero errors.
--  compiles_all : the same for every file created (9 kinds, nested, test, default package, test-dir class).
-- Review cases (P3 Task 3):
--  exists       : a second new() of P3Class does not overwrite (disk unchanged), says so, opens it.
--  invalid_name : "1Bad", "class", "a..B", "Foo-Bar", "" are refused with a message, no file.
--  outside_root : a directory outside src/<set>/java (src/main/resources) is refused with a message.
--  default_package: dir = src/main/java creates P3Default.java without a package line.
--  test_dir_class : kind class in src/test/java/demo/shop gets `package demo.shop;`.
--  test_from_test : kind test from a test class is refused with a message (no CheckoutTestTest).
--  prompts      : new({}) (what <leader>jn calls, minus insert) asks the kind (vim.ui.select, answered
--                 "service") and the name (vim.ui.input, "P3Prompted"), in the current file's directory.
--  edit_template: `:e P3Edited.java` (BufNewFile, kind answered "class") leaves the template ON DISK (the
--                 Task 0 baseline left the empty file nvim-jdtls writes).
--  neotree_fill : neo-tree's file_added handler on an empty new file writes the template into it.
-- Baseline (P3 Task 0): only the BufNewFile template exists (util/java_scaffold.lua, `:e Foo.java`
-- or neo-tree `a`, then a vim.ui.select of 8 kinds). Kinds it has are measured through it, with the
-- select answered by the check: it fills an unsaved buffer (on disk only the empty file nvim-jdtls
-- writes for every new Java buffer). No annotation, package,
-- dotted name or test-for-class kinds.
-- The fixture is snapshot before and restored after (tests/lib/fixture.lua), jdt.ls told.
-- Timings: /tmp/nv4j/logs/latency.jsonl (scaffold_*).
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local F = require("fixture")
local P = "61_scaffold."
local BUDGET_MS, COMPILE_MS = 300, 3000

local fixture = vim.env.NV4J_FIXTURE
local main = fixture .. "/src/main/java/"
local dir = main .. "demo/p3scaffold"
local snap = F.snapshot()

-- publishDiagnostics arrival per uri (the `compiles` case waits for jdt.ls's own answer, 003 P2 lesson)
-- published_at: last publish per uri; state_at: last publish whose error count differs from the
-- previous publish (or the first): when the file's diagnostics reached their state. A clean list
-- republished because ANOTHER file was created does not move it.
local published_at, state_at, last_errs = {}, {}, {}
local orig_pd = vim.lsp.handlers["textDocument/publishDiagnostics"]
vim.lsp.handlers["textDocument/publishDiagnostics"] = function(e, result, ctx, cfg)
  if result and result.uri then
    published_at[result.uri] = E.now()
    local n = #vim.tbl_filter(function(x) return x.severity == 1 end, result.diagnostics or {})
    if last_errs[result.uri] ~= n then state_at[result.uri], last_errs[result.uri] = E.now(), n end
  end
  return orig_pd(e, result, ctx, cfg)
end

local buf = lsp.open(main .. "demo/shop/Checkout.java")
local client = lsp.wait_ready(buf, 120000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready" or "jdtls not ready")
if not client then return lsp.finish() end
-- keymaps and autocmds (the BufNewFile template) load on VeryLazy, after -c commands: load them now
-- (require caches them, so LazyVim's own load later is a no-op, no duplicate autocmds)
pcall(require, "config.keymaps")
pcall(require, "config.autocmds")

local ok_mod, scaffold = pcall(require, "nv4j.scaffold")
local api = ok_mod and type(scaffold) == "table" and type(scaffold.new) == "function"
lsp.report(P .. "api", api, api and "nv4j.scaffold.new" or ("nv4j.scaffold missing: " .. tostring(scaffold):gsub("\n.*", "")))

local km = vim.fn.maparg("<leader>jn", "n", false, true)
local kq = E.keymap("<leader>jn", buf)
if kq and kq.queued then km = { desc = kq.desc, rhs = "which-key" } end
local others = {}
for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
  local lhs = m.lhs:gsub(" ", "<leader>")
  if lhs:find("^<leader>j") and lhs ~= "<leader>jn" then others[#others + 1] = lhs .. "=" .. tostring(m.desc) end
end
lsp.report(P .. "key", km.callback ~= nil or (km.rhs or "") ~= "",
  ("<leader>jn: %s; other <leader>j keys: %s"):format(km.desc or (next(km) and "mapped, no desc" or "unmapped"),
    #others > 0 and table.concat(others, ", ") or "none"))

local DECL = {
  class = "public class %s", interface = "public interface %s", record = "public record %s(",
  enum = "public enum %s", annotation = "public @interface %s",
  controller = "public class %s", service = "public class %s", repository = "public class %s", entity = "public class %s",
}
local ANNO = {
  controller = { "@RestController", "import org.springframework.web.bind.annotation.RestController;" },
  service = { "@Service", "import org.springframework.stereotype.Service;" },
  repository = { "@Repository", "import org.springframework.stereotype.Repository;" },
  entity = { "@Entity", "import jakarta.persistence.Entity;" },
}
local TEMPLATE_KINDS = { class = true, interface = true, record = true, enum = true, controller = true, service = true,
  repository = true, entity = true }

--- Baseline path: `:edit` a new file, the BufNewFile template asks the kind (answered here).
local function via_template(kind, path)
  local real = vim.ui.select
  local asked
  vim.ui.select = function(items, opts, cb)
    asked = items
    cb(vim.tbl_contains(items, kind) and kind or nil)
  end
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local t0 = E.now()
  local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(path))
  local ms = E.now() - t0
  vim.ui.select = real
  vim.cmd.stopinsert()
  return ok, ms, ok and (asked and "template" or "no template prompt") or tostring(err)
end

--- Runs one scaffold; returns ms, how, path expected.
local function make(spec, path)
  if api then
    local t0 = E.now()
    local ok, err = pcall(scaffold.new, spec)
    return ok, E.now() - t0, ok and "nv4j.scaffold" or tostring(err)
  end
  if TEMPLATE_KINDS[spec.kind] and not spec.name:find("%.") then return via_template(spec.kind, path) end
  return false, 0, "no way to create kind '" .. spec.kind .. "' (template kinds: class interface record enum controller service repository entity)"
end

local function lines_of(path)
  local b = vim.fn.bufnr(path)
  if b ~= -1 and vim.api.nvim_buf_is_loaded(b) then return vim.api.nvim_buf_get_lines(b, 0, -1, false), b end
  return vim.uv.fs_stat(path) and vim.fn.readfile(path) or {}, nil
end

local created = {} -- { path, t, name } of every file a case created, for compiles_all
-- at3[path]: the file's error diagnostics as the user sees them at creation + 3 s (the budget mark)
local at3 = {}
local function snapshot_at_budget(path, delay)
  vim.defer_fn(function()
    local b = vim.fn.bufnr(path)
    local errs = b ~= -1 and vim.tbl_filter(function(x) return x.severity == vim.diagnostic.severity.ERROR end,
      vim.diagnostic.get(b)) or {}
    at3[path] = { errs = errs, published = published_at[vim.uri_from_fname(path)] ~= nil, buf = b ~= -1 }
  end, math.max(0, delay))
end
local function check_file(name, path, pkg, decl, anno, ok, ms, how)
  if ok then
    created[#created + 1] = { path = path, t = E.now() - ms, name = name }
    snapshot_at_budget(path, COMPILE_MS - ms)
  end
  local on_disk = vim.uv.fs_stat(path) ~= nil
  local lines, b = lines_of(path)
  local txt = table.concat(lines, "\n")
  local current = vim.api.nvim_buf_get_name(0) == path
  -- pkg "" = default package: no package line at all
  local pkg_ok
  if pkg == "" then pkg_ok = #lines > 0 and not txt:find("^%s*package") else pkg_ok = lines[1] == "package " .. pkg .. ";" end
  local decl_ok = txt:find(decl, 1, true) ~= nil
  -- saved: the file on disk has the package line too (nvim-jdtls writes an EMPTY file for a new
  -- buffer on attach, jdtls/setup.lua, so existence alone proves nothing)
  local disk = on_disk and vim.fn.readfile(path) or {}
  local saved
  if pkg == "" then saved = #disk > 0 and not disk[1]:find("^%s*package") else saved = disk[1] == "package " .. pkg .. ";" end
  local anno_ok = not anno or (txt:find(anno[1], 1, true) ~= nil and txt:find(anno[2], 1, true) ~= nil)
  E.log("scaffold_" .. name, ok and ms or -1, 1)
  lsp.report(P .. name, ok and saved and current and pkg_ok and decl_ok and anno_ok and ms <= BUDGET_MS,
    ("%s %.0f ms (budget %d); on disk %s, current buffer %s, package line %s, declaration %s%s"):format(how, ms, BUDGET_MS,
      saved and "yes" or (on_disk and ("WITHOUT the package line (%d lines)"):format(#disk) or "NO"), current and "yes" or "NO", pkg_ok and "ok" or ("WRONG: " .. tostring(lines[1])),
      decl_ok and "ok" or "MISSING", anno and (anno_ok and ", annotation ok" or ", annotation/import MISSING") or ""))
  return b
end

local ok_all, err = pcall(function()
  local class_buf
  for _, kind in ipairs({ "class", "interface", "record", "enum", "annotation", "controller", "service", "repository", "entity" }) do
    local name = "P3" .. kind:sub(1, 1):upper() .. kind:sub(2)
    local path = dir .. "/" .. name .. ".java"
    local ok, ms, how = make({ kind = kind, name = name, dir = dir }, path)
    local b = check_file("kind_" .. kind, path, "demo.p3scaffold", DECL[kind]:format(name), ANNO[kind], ok, ms, how)
    if kind == "class" then class_buf = b end
  end

  -- prompts: kind and name asked, directory = the current file's (P3Entity.java, demo/p3scaffold)
  do
    local path = dir .. "/P3Prompted.java"
    local rs, ri = vim.ui.select, vim.ui.input
    local asked = {}
    vim.ui.select = function(items, opts, cb) asked[#asked + 1] = "select(" .. #items .. ")"; cb("service") end
    vim.ui.input = function(opts, cb) asked[#asked + 1] = "input(" .. tostring(opts.prompt) .. ")"; cb("P3Prompted") end
    local t0 = E.now()
    local ok, err = pcall(scaffold.new, {})
    local ms = E.now() - t0
    vim.ui.select, vim.ui.input = rs, ri
    check_file("prompts", path, "demo.p3scaffold", "public class P3Prompted", ANNO.service, ok, ms,
      ok and ("asked " .. table.concat(asked, ", ")) or tostring(err))
  end

  -- package
  do
    local ok, ms, how = make({ kind = "package", name = "demo.p3scaffold.sub", dir = main }, nil)
    local exists = vim.fn.isdirectory(dir .. "/sub") == 1
    E.log("scaffold_package", ok and ms or -1, 1)
    lsp.report(P .. "package", ok and exists and ms <= BUDGET_MS,
      ("%s %.0f ms; directory demo/p3scaffold/sub %s"):format(how, ms, exists and "created" or "MISSING"))
  end

  -- dotted name creates the packages
  do
    local path = dir .. "/deep/Thing.java"
    local ok, ms, how = make({ kind = "class", name = "deep.Thing", dir = dir }, path)
    check_file("nested_name", path, "demo.p3scaffold.deep", "public class Thing", nil, ok, ms, how)
  end

  -- test class for the current class
  do
    vim.api.nvim_set_current_buf(buf)
    local path = fixture .. "/src/test/java/demo/shop/CheckoutTest.java"
    local ok, ms, how = make({ kind = "test" }, path)
    check_file("test_for", path, "demo.shop", "class CheckoutTest", { "@Test", "import org.junit.jupiter.api.Test;" }, ok, ms, how)
  end

  -- review cases (refusals return nil + reason and notify)
  local notes = E.capture_notify()
  local function refused(spec)
    local n0 = #notes
    local ok, res, why = pcall(scaffold.new, spec)
    local said = #notes > n0 and notes[#notes].msg or nil
    return ok and res == nil and said ~= nil, said or (ok and ("no message; returned " .. tostring(res)) or tostring(res))
  end
  do
    local path = dir .. "/P3Class.java"
    -- a user edit on disk first (a comment line), so an overwrite with the same template shows
    vim.fn.writefile({ "// p3 user edit" }, path, "a")
    local before = vim.uv.fs_stat(path) and table.concat(vim.fn.readfile(path), "\n")
    local ok, said = refused({ kind = "class", name = "P3Class", dir = dir })
    local after = vim.uv.fs_stat(path) and table.concat(vim.fn.readfile(path), "\n")
    local same = before ~= nil and before == after
    local current = vim.api.nvim_buf_get_name(0) == path
    lsp.report(P .. "exists", ok and same and current and said:find("exists") ~= nil,
      ("message: %s; disk %s; opened %s"):format(said, same and "unchanged" or "CHANGED", current and "yes" or "NO"))
  end
  do
    local bad, det = {}, {}
    for _, name in ipairs({ "1Bad", "class", "a..B", "Foo-Bar", "" }) do
      local ok, said = refused({ kind = "class", name = name, dir = dir })
      local file = vim.fn.glob(dir .. "/" .. (name:gsub("[^%w]", "*")) .. "*.java") ~= "" and name ~= ""
      if not ok or file then bad[#bad + 1] = name end
      det[#det + 1] = ("'%s': %s"):format(name, said)
    end
    lsp.report(P .. "invalid_name", #bad == 0, (#bad > 0 and ("NOT refused: " .. table.concat(bad, ",") .. "; ") or "") .. table.concat(det, "; "))
  end
  do
    local rdir = fixture .. "/src/main/resources"
    local ok, said = refused({ kind = "class", name = "P3Outside", dir = rdir })
    local file = vim.uv.fs_stat(rdir .. "/P3Outside.java") ~= nil
    lsp.report(P .. "outside_root", ok and not file, ("message: %s; file %s"):format(said, file and "CREATED" or "none"))
  end
  do
    local path = main .. "P3Default.java"
    local ok, ms, how = make({ kind = "class", name = "P3Default", dir = main:gsub("/$", "") }, path)
    check_file("default_package", path, "", "public class P3Default", nil, ok, ms, how)
  end
  do
    local tdir = fixture .. "/src/test/java/demo/shop"
    local path = tdir .. "/P3TestHelper.java"
    local ok, ms, how = make({ kind = "class", name = "P3TestHelper", dir = tdir }, path)
    check_file("test_dir_class", path, "demo.shop", "public class P3TestHelper", nil, ok, ms, how)
  end
  do
    -- the current buffer is now P3TestHelper (src/test/java): kind test is refused there
    local ok, said = refused({ kind = "test" })
    local file = vim.uv.fs_stat(fixture .. "/src/test/java/demo/shop/P3TestHelperTest.java") ~= nil
    lsp.report(P .. "test_from_test", ok and not file, ("message: %s; file %s"):format(said, file and "CREATED" or "none"))
  end

  -- `:e` a new file: the BufNewFile template, answered "class", is on disk
  do
    local path = dir .. "/P3Edited.java"
    local ok, ms, how = via_template("class", path)
    vim.wait(100, function() return false end)
    check_file("edit_template", path, "demo.p3scaffold", "public class P3Edited", nil, ok, ms, how)
  end
  -- neo-tree `a`: the file_added handler of plugins/neo-tree.lua on the empty file neo-tree made
  do
    local path = dir .. "/P3Tree.java"
    local spec = require("plugins.neo-tree")
    if type(spec[1]) == "table" then spec = spec[1] end
    local handler
    for _, h in ipairs((spec.opts or {}).event_handlers or {}) do
      if h.event == "file_added" then handler = h.handler end
    end
    vim.fn.writefile({}, path)
    local rs = vim.ui.select
    vim.ui.select = function(items, opts, cb) cb("enum") end
    local t0 = E.now()
    local ok, err = pcall(function() assert(handler, "no file_added handler in plugins/neo-tree.lua"); handler(path) end)
    local ms = E.now() - t0
    vim.ui.select = rs
    local disk = vim.fn.readfile(path)
    local good = ok and disk[1] == "package demo.p3scaffold;" and table.concat(disk, "\n"):find("public enum P3Tree", 1, true) ~= nil
    E.log("scaffold_neotree_fill", ok and ms or -1, 1)
    lsp.report(P .. "neotree_fill", good and ms <= BUDGET_MS, ("%s %.0f ms; on disk: %s"):format(ok and "file_added" or tostring(err), ms,
      #disk > 0 and table.concat(disk, " | ") or "EMPTY"))
  end

  -- compiles / compiles_all. jdt.ls publishes a clean list on open (reconcile) and the build's errors
  -- (e.g. a wrong package) later, so "a clean publish" proves nothing (n61a: P3Class passed with a
  -- package error). Per file: the publish that set its error count last (state_at) arrives <= 3 s
  -- after creation (timing), and after an explicit build (nv4j.debug.refresh_and_build, then 500 ms without a publish: the
  -- deterministic twin) it has zero errors.
  do
    local quiet_ms, last_t = 1000, 0
    for _, c in ipairs(created) do last_t = math.max(last_t, c.t) end
    local function newest()
      local n = 0
      for _, c in ipairs(created) do n = math.max(n, published_at[vim.uri_from_fname(c.path)] or 0) end
      return n
    end
    vim.wait(last_t + COMPILE_MS + quiet_ms - E.now(), function() return E.now() - math.max(newest(), last_t) >= quiet_ms end, 20)
    -- every 3 s snapshot taken (each fires at its file's creation + 3 s)
    vim.wait(last_t + COMPILE_MS + 1000 - E.now(), function()
      for _, c in ipairs(created) do if not at3[c.path] then return false end end
      return true
    end, 20)
    local before = {}
    for _, c in ipairs(created) do before[c.path] = state_at[vim.uri_from_fname(c.path)] end
    local built = false
    require("nv4j.debug").refresh_and_build(fixture, function() built = true end, "61_scaffold compiles")
    vim.wait(60000, function() return built end, 20)
    local tb = E.now()
    vim.wait(5000, function() return E.now() - math.max(newest(), tb) >= 500 end, 20)
    local bad, det, cls = {}, {}, nil
    for _, c in ipairs(created) do
      local at = before[c.path]
      local b = vim.fn.bufnr(c.path)
      local errs = b ~= -1 and vim.tbl_filter(function(x) return x.severity == vim.diagnostic.severity.ERROR end,
        vim.diagnostic.get(b)) or {}
      local s3 = at3[c.path]
      local ok3 = s3 ~= nil and s3.buf and s3.published and #s3.errs == 0
      local ok = ok3 and at ~= nil and at - c.t <= COMPILE_MS and #errs == 0 and b ~= -1 and vim.uv.fs_stat(c.path) ~= nil
      local d = ("%s %s, at 3 s %s, %d error(s) after build%s"):format(c.name:gsub("^kind_", ""),
        at and ("settled %.0f ms"):format(at - c.t) or "NEVER published",
        not s3 and "NO snapshot" or not s3.published and "NOT published" or
          (#s3.errs == 0 and "0 errors" or ("%d error(s): %s"):format(#s3.errs, E.fmt(s3.errs))),
        #errs, #errs > 0 and (": " .. E.fmt(errs)) or "")
      if not ok then bad[#bad + 1] = d end
      det[#det + 1] = d
      if c.name == "kind_class" then cls = { ok = ok, d = d } end
    end
    lsp.report(P .. "compiles", cls ~= nil and cls.ok, cls and cls.d or "P3Class not created")
    lsp.report(P .. "compiles_all", #created > 0 and #bad == 0 and built,
      ("%d files, build %s; %s%s"):format(#created, built and "done" or "NOT done", #bad > 0 and ("FAILED: " .. table.concat(bad, "; ") .. "; ALL: ") or "", table.concat(det, "; ")))
  end
end)
if not ok_all then lsp.report(P .. "error", false, tostring(err)) end
local d = F.restore(snap, client)
local left = F.diff(snap)
lsp.report(P .. "fixture_restored", #left.added + #left.changed + #left.missing == 0, "undone: " .. F.fmt(d) .. "; left: " .. F.fmt(left))
lsp.finish()
