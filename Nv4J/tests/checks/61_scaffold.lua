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
--  compiles     : jdt.ls reports no error for the new class buffer <= 3 s after creation.
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
local published_at = {}
local orig_pd = vim.lsp.handlers["textDocument/publishDiagnostics"]
vim.lsp.handlers["textDocument/publishDiagnostics"] = function(e, result, ctx, cfg)
  if result and result.uri then published_at[result.uri] = E.now() end
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

local function check_file(name, path, pkg, decl, anno, ok, ms, how)
  local on_disk = vim.uv.fs_stat(path) ~= nil
  local lines, b = lines_of(path)
  local txt = table.concat(lines, "\n")
  local current = vim.api.nvim_buf_get_name(0) == path
  local pkg_ok = lines[1] == "package " .. pkg .. ";"
  local decl_ok = txt:find(decl, 1, true) ~= nil
  -- saved: the file on disk has the package line too (nvim-jdtls writes an EMPTY file for a new
  -- buffer on attach, jdtls/setup.lua, so existence alone proves nothing)
  local disk = on_disk and vim.fn.readfile(path) or {}
  local saved = disk[1] == "package " .. pkg .. ";"
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

  -- the new class compiles (jdt.ls, no error diagnostics within 3 s)
  do
    local path = dir .. "/P3Class.java"
    local b = class_buf or vim.fn.bufnr(path)
    if b == -1 or not vim.api.nvim_buf_is_loaded(b) then
      lsp.report(P .. "compiles", false, "no buffer for " .. path)
    else
      local uri = vim.uri_from_bufnr(b)
      local t0 = E.now()
      local ok = vim.wait(COMPILE_MS, function()
        return (published_at[uri] or 0) > 0 and E.count(vim.diagnostic.get(b), vim.diagnostic.severity.ERROR) == 0
      end, 20)
      local errs = vim.tbl_filter(function(d) return d.severity == vim.diagnostic.severity.ERROR end, vim.diagnostic.get(b))
      lsp.report(P .. "compiles", ok and vim.uv.fs_stat(path) ~= nil,
        ("on disk %s; jdt.ls diagnostics %s; %d error(s) after %.0f ms: %s"):format(vim.uv.fs_stat(path) and "yes" or "NO",
          published_at[uri] and "published" or "NEVER published", #errs, E.now() - t0, E.fmt(errs)))
    end
  end
end)
if not ok_all then lsp.report(P .. "error", false, tostring(err)) end
local d = F.restore(snap, client)
local left = F.diff(snap)
lsp.report(P .. "fixture_restored", #left.added + #left.changed + #left.missing == 0, "undone: " .. F.fmt(d) .. "; left: " .. F.fmt(left))
lsp.finish()
