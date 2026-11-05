-- Refactors (decision D23, specs/features/refactors.md, check 62_refactor). P3 Task 4a: rename class and
-- rename package; Task 4b: move a class to another package; Task 4c: inline a method call, local variable
-- or constant (jdt.ls's inline code actions, see M.inline); Task 4d: change a method's signature with
-- arguments (java/getChangeSignatureInfo + java/getRefactorEdit, see M.change_signature); Task 4e: safe
-- delete (references first; usages to the quickfix, else the declaration removed, see M.safe_delete).
--
-- move: the class's file moved to the target package's folder through the same path as a package rename
-- (rename_paths): `workspace/willRenameFiles` for the file move (jdt.ls's computeMoveEdit runs the same
-- MoveHandler.move as the "Move 'X'..." code action's java/move: package line, imports and references),
-- applied, written, then the file moved with its buffer re-pointed.
--
-- rename_class: textDocument/rename on the type (jdt.ls returns the reference/import edits plus the
-- file rename), applied here so the touched files can be written and summarised.
-- rename_package (and neo-tree renames/moves of a .java file or a folder with Java files,
-- plugins/neo-tree.lua): jdt.ls has no rename for a package declaration (prepareRename refuses), so
-- the folder rename is announced first with `workspace/willRenameFiles` (on the OLD uris, the folder
-- still in place), its edit applied and the touched buffers written, then the folder moves with
-- vim.lsp.util.rename (buffers re-pointed with :saveas, undo history kept), then
-- `workspace/didRenameFiles`. LazyVim asks willRenameFiles only after neo-tree moved the folder, which
-- left the old `package` line (Task 0 baseline). jdt.ls's package rename also rewrites the namesake
-- package in the other source roots (src/test/java): those folders move too.
--
-- IntelliJ gaps round: rename_class also renames variables declared with the type and inheritors (M._plan_vars,
-- M._plan_subclasses, M._var_step; steps of M.rename_chain, undone in reverse order); move picks packages of the
-- main and test roots (opts.root), lists conflicts before moving (M._move_conflicts, opts.force), moves the class
-- under the cursor when it is another project class; rename_package merges into an existing package
-- (M._merge_moves, rename_paths opts.merge).
--
-- Buffers: a touched buffer without unsaved changes before the refactor is written afterwards; one
-- that had unsaved changes is edited in place and left unsaved (named in the summary). A renamed or
-- moved file's buffer is written by the move (:saveas), its unsaved changes included (also named).
-- One `u` per buffer gives its text back (the file keeps its new name).
-- Honest results: refusals change nothing and say why; a failure part-way lists what changed; 3 s
-- after the edit, errors in the touched files, or new errors anywhere (a reference jdt.ls did not
-- update, e.g. in a file with a syntax error), are shown as a warning.
local M = {}

local TITLE = "Nv4J refactor"
local REQUEST_MS = 3000 -- willRenameFiles answers in about 30 ms; a busy jdt.ls gets 3 s before we give up
local ERRORS_MS = 3000 -- the build-clean budget: errors this long after the edit are reported
local LATE_MS = 8000 -- second look when the first found nothing (dependents still building)
local ERROR = vim.diagnostic.severity.ERROR

--- Last refactor outcome (summary and checks): { label, ok, err?, files = { { path, from?, unsaved?,
--- saved_dirty?, outside?, write_err? } }, errors? (filled by the follow-up) }.
M.last = nil
M.undo_op = nil -- the last rename/move, undone by M.undo_last

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = TITLE })
end

--- A refactor waiting for jdt.ls (change signature's edit request, 2.6-3.9 s for a method with
--- implementations, asynchronous on the prompt path): { label } until it ends; every refactor refuses to
--- start meanwhile (its edit would be computed on a state the pending one is about to change).
local busy = nil
function M._busy() return busy end -- checks

local function busy_msg()
  return ("a refactor is in progress (%s); try again when it finishes"):format(busy.label)
end

local function root_of(client)
  return client.root_dir or (client.config and client.config.root_dir)
end

local function under(path, dir)
  return path == dir or path:sub(1, #dir + 1) == dir .. "/"
end

local function jdtls_for(path)
  for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do
    local root = root_of(c)
    if not root or under(path, root) then return c end
  end
end

local function rel(path, root)
  if root and under(path, root) and path ~= root then return path:sub(#root + 2) end
  return path
end

local function valid_identifier(s)
  return require("nv4j.scaffold").valid_identifier(s)
end

--- Source root and package of a directory inside `src/<set>/java` (nil outside one).
local function src_root_of(dir)
  return require("nv4j.scaffold").source_root(dir)
end

--- The module a path belongs to: the parent of its `src/<set>/java` root (where the module's own main and test
--- roots live), else the nearest folder above it holding a pom.xml / build.gradle(.kts), else the project
--- root. In a multi-module repo this is the module, not `root.project` (the repo: a git root with a build
--- file wins there), so `src/*/java` globs find the module's own roots. Same folder as the nearest build file
--- in every standard layout.
local MODULE_MARKERS = { "pom.xml", "build.gradle", "build.gradle.kts" }
local function module_root(path)
  local start = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
  local sr = src_root_of(start)
  local m = sr and sr:match("^(.*)/src/[^/]+/java$")
  if not m then -- nearest directory first, then any marker within it
    local hit = vim.fs.find(MODULE_MARKERS, { upward = true, path = start, limit = 1 })[1]
    m = hit and vim.fs.dirname(hit)
  end
  return vim.fs.normalize(m or require("nv4j.root").project(path))
end
M._module_root = module_root -- checks

-- ── strings and config that still name the old class/package (warn only, never rewritten) ────────

local SCAN_EXT = { java = true, properties = true, yml = true, yaml = true, xml = true }
local SCAN_SKIP = { [".git"] = true, target = true, build = true, node_modules = true, out = true, bin = true,
  [".gradle"] = true, [".idea"] = true }
M.scan_max_files = 5000 -- scannable files (.java/.properties/.yml/.yaml/.xml) per scan

local function word(name)
  return "%f[%w_$]" .. vim.pesc(name) .. "%f[^%w_$]"
end

--- "file:line" where an old name is still written as text after a rename: an `import` of the old name
--- (a reference jdt.ls did not update), inside a Java string literal
--- (JPQL `FROM Invoice`, `"demo.billing.Invoice"`, a `@Qualifier`/`@Named`/`@Resource` bean name) or
--- anywhere in a .properties/.yml/.xml file of the project. `names.java` / `names.config`: Lua patterns.
--- jdt.ls's rename does not touch these (IntelliJ offers "search in strings"); Nv4J warns, nothing more.
--- Second value: true when the scan stopped at M.scan_max_files scannable files (said in the warning).
function M.stale_refs(root, names)
  local out, n, truncated, unread = {}, 0, false, {}
  local function scan(path, ext)
    local b = vim.fn.bufnr(path)
    local lines
    if b ~= -1 and vim.api.nvim_buf_is_loaded(b) then
      lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
    elseif vim.fn.getfsize(path) < 1048576 then
      -- an unreadable file (mode 000, a root-owned bind mount) must not abort the scan: skipped and said
      local ok, got = pcall(M._readfile, path)
      if ok then lines = got else unread[#unread + 1] = rel(path, root) end
    end
    lines = lines or {}
    for i, l in ipairs(lines) do
      local hit = false
      if ext == "java" then
        -- an import jdt.ls did not update (e.g. it skipped a file with a syntax error): found from the text,
        -- whether or not jdt.ls ever reports the error
        for _, pat in ipairs(names.imports or {}) do
          if l:find(pat) then hit = true end
        end
        for lit in l:gmatch('"(.-)"') do
          for _, pat in ipairs(names.java) do
            if lit:find(pat) then hit = true end
          end
        end
        if not hit and names.bean and l:find("@[QNRD][%a]*%(") and (l:find("@Qualifier", 1, true) or l:find("@Named", 1, true)
            or l:find("@Resource", 1, true) or l:find("@DependsOn", 1, true)) then
          for lit in l:gmatch('"(.-)"') do
            if lit:find(names.bean) then hit = true end
          end
        end
      else
        for _, pat in ipairs(names.config) do
          if l:find(pat) then hit = true end
        end
      end
      if hit then out[#out + 1] = ("%s:%d"):format(rel(path, root), i) end
    end
  end
  local function walk(dir)
    for name, kind in vim.fs.dir(dir) do
      local p = dir .. "/" .. name
      if kind == "directory" and not SCAN_SKIP[name] then
        walk(p)
      elseif kind == "file" then
        local ext = name:match("%.(%w+)$")
        if ext and SCAN_EXT[ext] then
          n = n + 1
          if n <= M.scan_max_files then scan(p, ext) else truncated = true end
        end
      end
    end
  end
  if root then walk(root) end
  return out, truncated, unread
end

M._readfile = vim.fn.readfile -- checks stub it

--- Patterns for a renamed class `old` in package `pkg` (nil = default package).
local function class_names(old, pkg)
  local fqn = pkg and (pkg .. "." .. old) or nil
  local bean = old:sub(1, 1):lower() .. old:sub(2)
  local imports = fqn and { "^%s*import%s+" .. vim.pesc(fqn) .. "%s*;", "^%s*import%s+static%s+" .. vim.pesc(fqn) .. "%." } or nil
  return { java = { word(old) }, config = fqn and { word(fqn), word(old) } or { word(old) }, bean = word(bean), imports = imports }
end

--- Patterns for a renamed package `pkg`.
local function package_names(pkg)
  return { java = { word(pkg) }, config = { word(pkg) },
    imports = { "^%s*import%s+" .. vim.pesc(pkg) .. "%.", "^%s*import%s+static%s+" .. vim.pesc(pkg) .. "%." } }
end

local function stale_note(stale, old, truncated, unread)
  local cut = truncated and (". The strings/config scan stopped after %d files: the rest of the project was not checked")
    :format(M.scan_max_files) or ""
  if unread and #unread > 0 then
    cut = cut .. (". WARNING: could not read %d file(s), so they were not checked for %s: %s"):format(#unread, old or "the old name",
      table.concat(vim.list_slice(unread, 1, 5), ", "))
  end
  if not stale or #stale == 0 then return cut end
  return (". NOT rewritten, still naming %s (strings, config, or imports jdt.ls did not update; check them): %s%s"):format(old,
    table.concat(vim.list_slice(stale, 1, 8), ", "), #stale > 8 and (", +" .. (#stale - 8) .. " more") or "") .. cut
end

M._stale_note = stale_note -- checks

-- ── errors before/after ──────────────────────────────────────────────────────────────────────────

--- ERROR diagnostics per file path, all buffers (jdt.ls publishes for unopened files too).
function M.error_counts()
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(nil, { severity = ERROR })) do
    local p = vim.api.nvim_buf_get_name(d.bufnr)
    out[p] = (out[p] or 0) + 1
  end
  return out
end

--- "File.java:line message" for the errors in `paths` (touched files) and in every file whose error
--- count grew since `before` (M.error_counts() taken before the edit). Files gone from disk are skipped.
function M.new_errors(before, paths)
  local touched, counts, out = {}, M.error_counts(), {}
  for _, p in ipairs(paths or {}) do touched[p] = true end
  for _, d in ipairs(vim.diagnostic.get(nil, { severity = ERROR })) do
    local p = vim.api.nvim_buf_get_name(d.bufnr)
    if vim.uv.fs_stat(p) and (touched[p] or counts[p] > ((before or {})[p] or 0)) then
      out[#out + 1] = ("%s:%d %s"):format(vim.fs.basename(p), d.lnum + 1, (d.message:gsub("\n.*", "")))
    end
  end
  return out
end

local generation = 0 -- a newer refactor cancels the pending follow-up (its errors would be blamed on this one)

--- Checks at ERRORS_MS and, when nothing was found yet, again at LATE_MS: errors in files the edit did
--- not touch come from jdt.ls's build of the dependents, which can take longer than the 3 s budget.
local function follow_up(label, before, paths)
  local rec = M.last
  generation = generation + 1
  local gen = generation
  local function check(last)
    if gen ~= generation then return end
    local errs = M.new_errors(before, paths)
    if rec then rec.errors = errs end
    if #errs > 0 then
      notify(("%s applied, but %d error(s) in the touched files or new since: %s%s"):format(label, #errs,
        table.concat(vim.list_slice(errs, 1, 5), "; "), #errs > 5 and "; ..." or ""), vim.log.levels.WARN)
    elseif not last then
      vim.defer_fn(function() check(true) end, LATE_MS - ERRORS_MS)
    end
  end
  vim.defer_fn(function() check(false) end, ERRORS_MS)
end

-- ── applying a WorkspaceEdit ─────────────────────────────────────────────────────────────────────

--- Files a WorkspaceEdit touches, in order: { path, from? } (from = old path of a file it renames).
local function edit_files(edit)
  local by, list = {}, {}
  local function add(path)
    if not by[path] then
      by[path] = { path = path }
      list[#list + 1] = by[path]
    end
    return by[path]
  end
  for _, ch in ipairs(edit.documentChanges or {}) do
    if ch.kind == "rename" then
      local from, to = vim.uri_to_fname(ch.oldUri), vim.uri_to_fname(ch.newUri)
      local f = by[from] or add(from)
      by[from], f.from, f.path, by[to] = nil, from, to, f
    elseif ch.kind == nil and ch.textDocument then
      add(vim.uri_to_fname(ch.textDocument.uri))
    end
  end
  for uri in pairs(edit.changes or {}) do add(vim.uri_to_fname(uri)) end
  return list
end

--- Loaded buffers with unsaved changes now: { [path] = true }.
local function dirty_buffers()
  local out = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified then out[vim.api.nvim_buf_get_name(b)] = true end
  end
  return out
end

--- changedtick of every loaded buffer now: { [path] = tick }. Taken when an edit is asked of jdt.ls.
local function tick_snapshot()
  local ticks = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then ticks[vim.api.nvim_buf_get_name(b)] = vim.api.nvim_buf_get_changedtick(b) end
  end
  return ticks
end

--- Paths (project-relative) of the loaded buffers `edit` touches that changed since `ticks` (typed into while
--- jdt.ls computed the edit; or loaded and modified since). The edit would land at stale positions there
--- (Neovim version-checks only the first document change): the caller refuses it whole.
local function stale_buffers(edit, ticks, root)
  local moved = {}
  for _, f in ipairs(edit_files(edit)) do
    local p = f.from or f.path
    local b = vim.fn.bufnr(p)
    if b ~= -1 and vim.api.nvim_buf_is_loaded(b) then
      local was = ticks[p]
      if (was and vim.api.nvim_buf_get_changedtick(b) ~= was) or (not was and vim.bo[b].modified) then moved[#moved + 1] = rel(p, root) end
    end
  end
  return moved
end

local function write(path)
  local b = vim.fn.bufnr(path)
  if b == -1 or not vim.api.nvim_buf_is_loaded(b) or not vim.bo[b].modified then return nil end
  local ok, err = pcall(vim.api.nvim_buf_call, b, function() vim.cmd("silent write") end)
  return not ok and tostring(err) or nil
end

--- Applies `edit` and writes the touched buffers that had no unsaved changes (`dirty`, taken before),
--- except those under a folder about to move (`moving(path)`: the move writes them). Returns ok, files.
local function apply(client, edit, dirty, moving)
  local files = edit_files(edit)
  local ok, err = pcall(vim.lsp.util.apply_workspace_edit, edit, client.offset_encoding)
  local root = root_of(client)
  for _, f in ipairs(files) do
    local was_dirty = dirty[f.from or f.path]
    if f.from then
      f.saved_dirty = was_dirty -- renamed by the edit: :saveas wrote it
    elseif was_dirty then
      f.unsaved = true
    elseif not (moving and moving(f.path)) then
      f.write_err = write(f.path)
    end
    f.outside = root and not under(f.path, root) or nil
  end
  return ok, files, not ok and tostring(err) or nil
end

--- "<label>: N file(s): a (from b), c [left unsaved ...], ...".
local function summary(label, files, root)
  local parts = {}
  for _, f in ipairs(files) do
    local s = rel(f.path, root)
    if f.from then s = s .. " (from " .. rel(f.from, root) .. ")" end
    if f.unsaved then s = s .. " [left unsaved: it had your unsaved changes]" end
    if f.saved_dirty then s = s .. " [written with your unsaved changes]" end
    if f.write_err then s = s .. " [NOT written: " .. f.write_err .. "]" end
    if f.outside then s = s .. " [outside the project]" end
    parts[#parts + 1] = s
  end
  return ("%s: %d file(s): %s"):format(label, #files, table.concat(parts, ", "))
end

--- `moved`: { { from, to } } folders/files already moved when it failed (`u` does not move those back).
local function failed_part_way(label, why, files, root, moved)
  local undo = " Undo with `u` in each file listed."
  if moved and #moved > 0 then
    undo = (" Already moved, and `u` does NOT move them back: %s. Put them back by renaming each back (<leader>jp, or neo-tree), then `u` in each file listed undoes the text edits."):format(
      table.concat(vim.tbl_map(function(m) return rel(m[1], root) .. " -> " .. rel(m[2], root) end, moved), ", "))
  end
  local msg = ("%s FAILED part-way (%s). %s."):format(label, why, summary("Changed so far", files, root)) .. undo
  M.last = { label = label, files = files, ok = false, err = msg }
  notify(msg, vim.log.levels.ERROR)
  return false, msg
end

-- ── rename class ─────────────────────────────────────────────────────────────────────────────────

--- 0-based (line, col, name) of the type to rename: the type name under the cursor (a capitalised
--- word with a lower-case letter), else the file's primary type declaration (the file's basename).
local function type_position(buf)
  local cur = vim.api.nvim_win_get_cursor(0)
  local word = vim.fn.expand("<cword>")
  if word:match("^%u[%w_$]*$") and word:match("%l") then
    local line = vim.api.nvim_buf_get_lines(buf, cur[1] - 1, cur[1], false)[1] or ""
    local s = 1
    while true do
      local a, b = line:find(word, s, true)
      if not a then break end
      if cur[2] + 1 >= a and cur[2] + 1 <= b then return cur[1] - 1, a - 1, word end
      s = b + 1
    end
  end
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r")
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    for _, kw in ipairs({ "class", "interface", "enum", "record", "@interface" }) do
      local _, e = l:find("%f[%w@]" .. kw .. "%s+" .. vim.pesc(name) .. "%f[^%w_$]")
      if e then return i - 1, e - #name, name end
    end
  end
  return nil, nil, name
end

--- True when `path`'s file system treats names that differ only by case as one file (macOS default):
--- the same file answers to the name with every letter's case swapped.
local function case_insensitive_at(path)
  local base = vim.fs.basename(path)
  local alt = vim.fs.dirname(path) .. "/" .. base:gsub("%a", function(ch) return ch == ch:lower() and ch:upper() or ch:lower() end)
  local a, b = vim.uv.fs_stat(path), vim.uv.fs_stat(alt)
  return alt ~= path and a ~= nil and b ~= nil and a.ino == b.ino
end
M._case_insensitive_at = case_insensitive_at -- checks

--- A name that differs from `old` only by case, on a case-insensitive file system, for the class in the file
--- named after it: jdt.ls's own answer is then one text edit on the declaration and a RenameFile that Neovim
--- skips ("already exists"; the references are not updated either), so the file stays `Old.java` holding
--- `class NEW` and the summary still says renamed. Done in two real renames through a temporary name instead.
local TMP_SUFFIX = "__Nv4jTmp"

M.rename_ms = 10000 -- textDocument/rename: 0.4-1 s normally (19.7 s once, a jdt.ls stall); no answer by then ends it
local rename_class_impl
M.warn_max = 10 -- file:line entries named in a WARN; the full list stays in M.last.left
local function capped(list)
  local n = #list
  if n <= M.warn_max then return table.concat(list, ", ") end
  return table.concat(list, ", ", 1, M.warn_max) .. (", ... and %d more"):format(n - M.warn_max)
end
local function cold_note(old, left)
  return ("WARNING: jdt.ls did NOT update these references to %s (it skipped the file, even after a second request); they still name the old class and the project may not compile: %s"):format(
    old, capped(left))
end
local UNVERIFIED = "WARNING: could not verify that all usages were renamed (jdt.ls gave no usable answer to textDocument/references, even after a second request); check that the project still compiles"
local references, untouched_refs -- defined with change_signature/inline below; the cold-rename check shares them

--- Test classes of `old` (IntelliJ's "Rename tests", on by default there): in the module's other source roots,
--- `<Old>Test`, `<Old>Tests`, `<Old>IT`, `<Old>ITCase`, `<Old>TestCase`, `Test<Old>` (a JUnit/TestNG import in the
--- file). IntelliJ matches any test class whose name CONTAINS the old name and asks which to rename; with no
--- list to confirm, only these suffixes are taken, so `UserServiceTest` is not caught by renaming `User`.
--- Returns { { path, name } } (each to be renamed to the new name) and the list of those skipped (target exists).
local TEST_SUFFIXES = { "Test", "Tests", "IT", "ITCase", "TestCase" }
function M.related_tests(path, old, new)
  local sr = src_root_of(vim.fs.dirname(path))
  if not sr then return {}, {} end
  local function is_test(p)
    for _, l in ipairs(vim.fn.readfile(p, "", 200)) do
      if l:match("^%s*import%s+static%s+org%.junit") or l:match("^%s*import%s+org%.junit") or l:match("^%s*import%s+org%.testng")
          or l:match("^%s*import%s+junit%.") then
        return true
      end
    end
    return false
  end
  if vim.fn.filereadable(path) == 1 and is_test(path) then return {}, {} end
  local want = { ["Test" .. old] = "Test" .. new }
  for _, sfx in ipairs(TEST_SUFFIXES) do want[old .. sfx] = new .. sfx end
  local out, skipped = {}, {}
  for _, root in ipairs(vim.fn.glob(module_root(path) .. "/src/*/java", false, true)) do
    root = vim.fs.normalize(root)
    if root ~= sr then
      for _, f in ipairs(vim.fs.find(function(n) return n:match("%.java$") ~= nil and want[n:sub(1, -6)] ~= nil end,
          { path = root, type = "file", limit = math.huge })) do
        local nn = want[vim.fs.basename(f):sub(1, -6)]
        if is_test(f) then
          if vim.uv.fs_stat(vim.fs.dirname(f) .. "/" .. nn .. ".java") then
            skipped[#skipped + 1] = ("%s (%s.java exists)"):format(rel(f, require("nv4j.root").project(f)), nn)
          else
            out[#out + 1] = { path = f, name = nn }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.path < b.path end)
  return out, skipped
end

-- ── variables and inheritors (IntelliJ's "Rename variables" / "Rename inheritors", on by default there) ──
--
-- After a class rename Invoice -> Bill, `Bill invoice` becomes `Bill bill` and `List<Bill> invoices` becomes
-- `bills` (a variable, field or parameter DECLARED with exactly the renamed type, its name built from the old
-- one), and `class InvoiceImpl extends Bill` becomes `BillImpl` (a top-level class whose name is the old name
-- plus a capitalised suffix and whose header extends/implements the renamed type). Each is a jdt.ls rename
-- (references follow), so every one is a step of the same chain as the test renames, with its own inverse for
-- `<leader>ju`. A name that is taken (the new name appears anywhere in the declaring file, or the class file
-- exists) is skipped and named in a warning. opts.variables = false / opts.subclasses = false skip them.
local lines_of -- defined with the move helpers below
M.variables_max = 40 -- variable renames per class rename (each is a jdt.ls request, about 100 ms)

local function decap(s)
  if #s == 1 and s:match("%u") then return s:lower() end
  if s:match("^%u%l") then return s:sub(1, 1):lower() .. s:sub(2) end
end

--- The new name of a variable called `n` after class `old` became `new`, or nil when `n` is not built from the
--- old name (invoice, invoices, invoiceList, pendingInvoice, pendingInvoices).
function M._var_new_name(n, old, new)
  local od, nd = decap(old), decap(new)
  if not od or not nd then return nil end
  local out
  if n == od then out = nd
  elseif n == od .. "s" then out = nd .. "s"
  elseif n:sub(1, #od) == od and n:sub(#od + 1, #od + 1):match("%u") then out = nd .. n:sub(#od + 1)
  elseif #n > #old and n:sub(-#old) == old and n:sub(-#old - 1, -#old - 1):match("%l") then out = n:sub(1, -#old - 1) .. new
  elseif #n > #old + 1 and n:sub(-#old - 1) == old .. "s" and n:sub(-#old - 2, -#old - 2):match("%l") then
    out = n:sub(1, -#old - 2) .. new .. "s"
  end
  return out and out ~= n and valid_identifier(out) and out or nil
end

--- Variables declared with type `tname` on one (code) line: { { name, col } } (col 0-based). `Type name`,
--- `Type[] name`, `Type... name`, and one generic argument list holding the type (`List<Type> name`).
local function var_decls(line, tname)
  local out = {}
  local t = vim.trim(line)
  if t:match("^//") or t:match("^%*") or t:match("^/%*") then return out end
  local w = word(tname)
  local s = 1
  while true do
    local a, b = line:find(w, s)
    if not a then break end
    s = b + 1
    local before, rest = line:sub(1, a - 1), line:sub(b + 1)
    if not before:match("%.%s*$") then
      local nm = rest:match("^%s+([%a_$][%w_$]*)%s*[=;,):]") or rest:match("^%s*%[%s*%]%s*([%a_$][%w_$]*)%s*[=;,):]")
        or rest:match("^%.%.%.%s*([%a_$][%w_$]*)%s*[=;,)]")
      if nm then
        local c0 = line:find(nm, b + 1, true)
        if c0 then out[#out + 1] = { name = nm, col = c0 - 1 } end
      else -- List<Type> name: the closing `>` right after the type (or after more `>`)
        local close = rest:match("^%s*(>[>%s]*)")
        if close and before:find("<[^<>;()]*$") then
          local nm2 = rest:sub(#close + 1):match("^([%a_$][%w_$]*)%s*[=;,):]")
          if nm2 then
            local c0 = line:find(nm2, b + #close + 1, true)
            if c0 and #close > 0 then out[#out + 1] = { name = nm2, col = c0 - 1 } end
          end
        end
      end
    end
  end
  return out
end
M._var_decls = var_decls -- checks

local function java_files(root)
  local out, n = {}, 0
  local function walk(dir)
    for name, kind in vim.fs.dir(dir) do
      local p = dir .. "/" .. name
      if kind == "directory" and not SCAN_SKIP[name] then
        walk(p)
      elseif kind == "file" and name:match("%.java$") then
        n = n + 1
        if n <= M.scan_max_files then out[#out + 1] = p end
      end
    end
  end
  if root then walk(root) end
  table.sort(out)
  return out
end

--- Variable renames due after `old` became `new`: steps ({ var = true, path, line, type = new, from, to }) and
--- the skipped ones ("file:line name (why)"). Text of loaded buffers, else the disk.
function M._plan_vars(root, old, new)
  local steps, skipped, seen = {}, {}, {}
  for _, p in ipairs(java_files(root)) do
    local lines = lines_of(p)
    local txt
    for i, l in ipairs(lines) do
      if l:find(new, 1, true) then
        for _, d in ipairs(var_decls(l, new)) do
          local nn = M._var_new_name(d.name, old, new)
          if nn then
            txt = txt or table.concat(lines, "\n")
            local where = ("%s:%d %s -> %s"):format(rel(p, root), i, d.name, nn)
            if txt:find(word(nn)) then
              skipped[#skipped + 1] = where .. " (the name " .. nn .. " is already used in that file)"
            elseif #steps >= M.variables_max then
              skipped[#skipped + 1] = where .. (" (more than %d variables: the rest are left)"):format(M.variables_max)
            else
              steps[#steps + 1] = { var = true, path = p, line = i - 1, type = new, from = d.name, to = nn }
            end
          end
        end
      end
    end
  end
  return steps, skipped
end

--- Top-level classes named `<Old><Suffix>` whose header extends/implements `new`, to be renamed `<New><Suffix>`:
--- steps ({ path, name }) and the skipped ones.
function M._plan_subclasses(root, old, new, exclude)
  local steps, skipped = {}, {}
  for _, p in ipairs(java_files(root)) do
    local base = vim.fs.basename(p):sub(1, -6)
    local suffix = base:match("^" .. vim.pesc(old) .. "(%u[%w_$]*)$")
    if suffix and not exclude[p] then
      local src = table.concat(lines_of(p), "\n")
      src = src:gsub("/%*.-%*/", " "):gsub("//[^\n]*", " ")
      local header
      for _, kw in ipairs({ "class", "interface", "record" }) do
        header = header or src:match("%f[%w_$]" .. kw .. "%s+" .. vim.pesc(base) .. "%f[^%w_$]([^{;]*)")
      end
      local sup = header and (header:match("extends(.*)") or header:match("implements(.*)"))
      if sup and sup:find(word(new)) then
        local nn = new .. suffix
        if vim.uv.fs_stat(vim.fs.dirname(p) .. "/" .. nn .. ".java") then
          skipped[#skipped + 1] = ("%s (%s.java exists)"):format(rel(p, root), nn)
        else
          steps[#steps + 1] = { path = p, name = nn }
        end
      end
    end
  end
  return steps, skipped
end

--- What a variable rename's edit changes, as the inverse: { path, off, len, text, new } per text edit (off = 0-based byte
--- offset in the file's lines joined by "\n" where the NEW text sits after all earlier edits of the file are in, len = #new,
--- text = the old text, possibly several lines: jdt.ls answers a parameter rename with ONE edit from the parameter to its
--- last use). Undo applies this directly: asking jdt.ls to rename back could miss a declaration (it answers from its own
--- view of files it may not have caught up on; intermittent miss seen in a full run). nil when the edit is not plain
--- text edits on ASCII text.
local function inverse_text_edits(edit)
  local per = {}
  local function add(uri, edits)
    local p = vim.uri_to_fname(uri)
    per[p] = per[p] or {}
    for _, e in ipairs(edits) do per[p][#per[p] + 1] = e end
  end
  for _, ch in ipairs(edit.documentChanges or {}) do
    if ch.kind ~= nil then return nil end
    if ch.textDocument then add(ch.textDocument.uri, ch.edits or {}) end
  end
  for uri, edits in pairs(edit.changes or {}) do add(uri, edits) end
  local out = {}
  for p, edits in pairs(per) do
    local lines = lines_of(p)
    local starts, acc = {}, 0 -- byte offset of each line start
    for i, l in ipairs(lines) do
      if l:find("[\128-\255]") then return nil end
      starts[i] = acc
      acc = acc + #l + 1
    end
    local text = table.concat(lines, "\n")
    local function off(pos)
      local base = starts[pos.line + 1]
      if not base then return nil end
      return base + pos.character
    end
    table.sort(edits, function(a, b)
      if a.range.start.line ~= b.range.start.line then return a.range.start.line < b.range.start.line end
      return a.range.start.character < b.range.start.character
    end)
    local delta = 0
    for _, e in ipairs(edits) do
      local o1, o2 = off(e.range.start), off(e.range["end"])
      if not o1 or not o2 or o2 < o1 then return nil end
      out[#out + 1] = { path = p, off = o1 + delta, len = #e.newText, text = text:sub(o1 + 1, o2), new = e.newText }
      delta = delta + #e.newText - (o2 - o1)
    end
  end
  return out
end

--- Applies a variable rename's recorded inverse edits (see inverse_text_edits). cb(ok, text). An edit whose spot no
--- longer holds the new text (edited since) is left and named; the rest are applied.
local function undo_text_edits(step, cb)
  local by = {}
  for _, e in ipairs(step.edits) do
    by[e.path] = by[e.path] or {}
    table.insert(by[e.path], e)
  end
  local done_n, missed = 0, {}
  local dirty = dirty_buffers()
  for p, list in pairs(by) do
    local b = vim.fn.bufnr(p)
    local loaded = b ~= -1 and vim.api.nvim_buf_is_loaded(b)
    if not loaded and not vim.uv.fs_stat(p) then
      -- deleted since: loading it would make an empty file at the old place when written
      missed[#missed + 1] = vim.fs.basename(p) .. " (file gone)"
      goto next_path
    end
    if not loaded then b = vim.fn.bufadd(p); vim.fn.bufload(b) end
    local text = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
    table.sort(list, function(x, y) return x.off > y.off end) -- right to left keeps the offsets valid
    for _, e in ipairs(list) do
      if text:sub(e.off + 1, e.off + e.len) == e.new then
        text = text:sub(1, e.off) .. e.text .. text:sub(e.off + e.len + 1)
        done_n = done_n + 1
      else
        missed[#missed + 1] = ("%s@%d"):format(vim.fs.basename(p), e.off)
      end
    end
    vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.split(text, "\n", { plain = true }))
    if not dirty[p] then write(p) end
    ::next_path::
  end
  cb(#missed == 0, ("%s: %s -> %s (%d edit(s))"):format(vim.fs.basename(step.path), step.from, step.to, done_n)
    .. (#missed > 0 and (", NOT undone (changed since): " .. table.concat(missed, ", ")) or ""))
end

--- One variable rename: jdt.ls `textDocument/rename` on the declaration, applied and written like a class rename.
--- cb(ok, inverse_step, text): ok false = not done (nothing changed), text = what was touched / why not.
function M._var_step(s, cb)
  if s.edits then -- undo of a variable rename: the recorded edits, no jdt.ls
    return undo_text_edits(s, function(ok, text) cb(ok, nil, text) end)
  end
  local client = jdtls_for(s.path)
  local function fail(why) return cb(false, nil, ("%s:%d %s -> %s: %s"):format(vim.fs.basename(s.path), s.line + 1, s.from, s.to, why)) end
  if busy then return fail("another refactor is in progress") end
  if not client then return fail("jdt.ls is not running") end
  local col
  for _, d in ipairs(var_decls(lines_of(s.path)[s.line + 1] or "", s.type)) do
    if d.name == s.from then col = d.col end
  end
  if not col then return fail("the declaration is not there any more") end
  local keep = vim.api.nvim_get_current_buf()
  local b = vim.fn.bufnr(s.path)
  if b == -1 or not vim.api.nvim_buf_is_loaded(b) or #vim.lsp.get_clients({ bufnr = b, name = "jdtls" }) == 0 then
    if not pcall(vim.cmd, "silent keepalt edit " .. vim.fn.fnameescape(s.path)) then return fail("could not open the file") end
    b = vim.api.nvim_get_current_buf()
    vim.wait(3000, function() return #vim.lsp.get_clients({ bufnr = b, name = "jdtls" }) > 0 end, 20)
    if vim.api.nvim_buf_is_valid(keep) then pcall(vim.api.nvim_set_current_buf, keep) end
  end
  busy = { label = ("rename variable %s"):format(s.from) }
  local settled = false
  local function finish(ok, inv, text)
    if settled then return end
    settled = true
    busy = nil
    cb(ok, inv, text)
  end
  local ok, sent = pcall(client.request, client, "textDocument/rename", { textDocument = { uri = vim.uri_from_fname(s.path) },
    position = { line = s.line, character = col }, newName = s.to }, function(err, edit)
    if settled then return end
    if err or not edit then
      busy = nil
      settled = true
      return fail(err and (err.message or "refused") or "no edit")
    end
    local rec = inverse_text_edits(edit)
    local aok, files, why = apply(client, edit, dirty_buffers())
    if not aok then return finish(false, nil, ("%s:%d %s -> %s: %s"):format(vim.fs.basename(s.path), s.line + 1, s.from, s.to, why)) end
    finish(true, { var = true, path = s.path, line = s.line, type = s.type, from = s.to, to = s.from, edits = rec },
      ("%s:%d %s -> %s"):format(vim.fs.basename(s.path), s.line + 1, s.from, s.to))
  end, b)
  if not ok or not sent then busy = nil; settled = true; return fail("the request could not be sent") end
  vim.defer_fn(function()
    if not settled then
      busy = nil
      settled = true
      fail(("jdt.ls did not answer in %d ms"):format(M.rename_ms))
    end
  end, M.rename_ms)
end

--- Class renames one after another: steps = { { path, name } } (the class of each file, renamed to `name`);
--- cb(all_ok, done_steps) with the inverse steps of those that worked ({ path = new file, name = old name }).
--- Each step is a rename_class (own summary, own undo step per buffer).
function M.rename_chain(steps, cb)
  local i, all_ok, did, vars, var_failed = 0, true, {}, {}, {}
  local function nxt()
    i = i + 1
    local s = steps[i]
    if not s then return cb(all_ok, did, { vars = vars, var_failed = var_failed }) end
    if s.var then -- a variable rename: a failure is a warning, never the chain's failure
      return M._var_step(s, function(ok, inv, text)
        if ok then did[#did + 1] = inv; vars[#vars + 1] = text else var_failed[#var_failed + 1] = text end
        vim.schedule(nxt)
      end)
    end
    local ok = pcall(vim.cmd, "silent keepalt edit " .. vim.fn.fnameescape(s.path))
    local b = vim.api.nvim_get_current_buf()
    if ok then
      vim.wait(3000, function() return #vim.lsp.get_clients({ bufnr = b, name = "jdtls" }) > 0 end, 20)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
    end
    local started = ok and rename_class_impl({ name = s.name, _chain = true, on_done = function(rok, step)
      if rok and step then did[#did + 1] = step else all_ok = false end
      vim.schedule(nxt)
    end })
    if not ok then
      notify(("Rename class: could not open %s; nothing changed there"):format(s.path), vim.log.levels.WARN)
      all_ok = false
      vim.schedule(nxt)
    end
    return started
  end
  nxt()
end

--- opts._quiet: step 1 of a case-only rename (no summary, scan or follow-up); opts._shown_old: the name the
--- user sees in step 2's label and string scan; opts._tmp_from = { tmp_path = original_path }.
function rename_class_impl(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  local client = jdtls_for(path)
  local mine = false -- this call set `busy`: only it clears it
  local called = false -- on_done once, even when it throws (the error handler below calls done again)
  local function done(ok, step)
    if mine then busy, mine = nil, false end
    if opts.on_done and not called then
      called = true
      opts.on_done(ok, step)
    end
    return ok
  end
  if busy then
    notify("Rename class: " .. busy_msg() .. "; nothing changed", vim.log.levels.WARN)
    return done(false)
  end
  if not client or #vim.lsp.get_clients({ bufnr = buf, name = "jdtls" }) == 0 then
    notify("Rename class: jdt.ls is not attached to this buffer", vim.log.levels.WARN)
    return done(false)
  end
  local l, c, old = type_position(buf)
  if not l then
    notify(("Rename class: no declaration of '%s' in this file and no class name under the cursor"):format(old),
      vim.log.levels.WARN)
    return done(false)
  end
  local function run(name)
    if not name or name == "" or name == old then return done(false) end
    if not valid_identifier(name) then
      notify(("Rename class: '%s' is not a valid Java class name; nothing changed"):format(name), vim.log.levels.ERROR)
      return done(false)
    end
    if not opts._quiet and not opts._shown_old and name:lower() == old:lower() and vim.fn.fnamemodify(path, ":t:r") == old
        and case_insensitive_at(path) then
      -- 1. Old -> Old__Nv4jTmp (a real rename: file, references, imports), 2. that -> New (the file name is free)
      local dir = vim.fs.dirname(path)
      local tmp = old .. TMP_SUFFIX
      local tmp_path = dir .. "/" .. tmp .. ".java"
      if vim.uv.fs_stat(tmp_path) then
        notify(("Rename class: %s exists; it is the temporary name for a case-only rename (%s -> %s); nothing changed"):format(tmp_path, old, name),
          vim.log.levels.ERROR)
        return done(false)
      end
      local function step2(ok)
        if not ok then
          notify(("Rename class %s -> %s: the first step (via %s) did not complete; see the message above. The class may be named %s now: rename it back with the same key"):format(
            old, name, tmp, tmp), vim.log.levels.ERROR)
          return done(false)
        end
        local nb = vim.fn.bufnr(tmp_path)
        if nb == -1 or not vim.api.nvim_buf_is_loaded(nb) then nb = vim.fn.bufadd(tmp_path); vim.fn.bufload(nb) end
        vim.api.nvim_set_current_buf(nb)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        rename_class_impl({ name = name, on_done = opts.on_done, _shown_old = old, _tmp_from = { [tmp_path] = path } })
      end
      return rename_class_impl({ name = tmp, _quiet = true, on_done = step2 })
    end
    local shown = opts._shown_old or old
    -- an existing class of that name: jdt.ls refuses ("Compilation unit 'X.java' already exists"), shown below
    local label = ("Renamed class %s -> %s"):format(shown, name)
    local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = l, character = c }, newName = name }
    if busy then -- another refactor started while the name was being typed
      notify("Rename class: " .. busy_msg() .. "; nothing changed", vim.log.levels.WARN)
      return done(false)
    end
    local ticks = tick_snapshot()
    busy, mine = { label = ("rename class %s"):format(old) }, true
    local function answered(err, edit, left, unknown)
      if err then
        notify(("Rename class %s -> %s: jdt.ls refused (%s); nothing changed"):format(old, name, err.message or vim.inspect(err)),
          vim.log.levels.ERROR)
        return done(false)
      end
      if not edit then
        notify(("Rename class %s -> %s: jdt.ls returned no change"):format(old, name), vim.log.levels.WARN)
        return done(false)
      end
      -- the edit was computed on the buffers as they were when it was asked for (see change_signature)
      local moved = stale_buffers(edit, ticks, root_of(client))
      if #moved > 0 then
        notify(("Rename class %s -> %s: %s changed while jdt.ls computed the edit; nothing changed (run it again)"):format(old, name,
          table.concat(moved, ", ")), vim.log.levels.WARN)
        return done(false)
      end
      local before = M.error_counts()
      if opts._tmp_from then
        -- step 2 of a case-only rename: its edits join step 1's undo block in each buffer they touch, so one
        -- `u` per buffer gives back the text from before the whole rename
        for _, f in ipairs(edit_files(edit)) do
          local b = vim.fn.bufnr(f.from or f.path)
          if b ~= -1 and vim.api.nvim_buf_is_loaded(b) then
            pcall(vim.api.nvim_buf_call, b, function() vim.cmd("undojoin") end)
          end
        end
      end
      local ok, files, why = apply(client, edit, dirty_buffers())
      if not ok then
        failed_part_way(label, why, files, root_of(client))
        return done(false)
      end
      if opts._quiet then -- step 1 of a case-only rename: step 2's scan reports what still names the old class
        if left and #left > 0 then notify(cold_note(old, left), vim.log.levels.WARN) end
        if unknown then notify(UNVERIFIED, vim.log.levels.WARN) end
      end
      if opts._quiet then return done(true) end -- step 1 of a case-only rename: step 2 reports
      for _, f in ipairs(files) do -- step 2: the file came from the user's name, not from the temporary one
        if f.from and opts._tmp_from and opts._tmp_from[f.from] then f.from = opts._tmp_from[f.from] end
      end
      local t_scan = vim.uv.hrtime()
      local _, pkg = src_root_of(vim.fs.dirname(path))
      local stale, cut, unread = M.stale_refs(require("nv4j.root").project(path), class_names(shown, pkg ~= "" and pkg or nil))
      left = left or {}
      M.last = { label = label, files = files, ok = true, stale = stale, left = left, unverified = unknown or false, scan_ms = (vim.uv.hrtime() - t_scan) / 1e6, truncated = cut, unread = unread }
      notify(summary(label, files, root_of(client)) .. stale_note(stale, shown, cut, unread)
        .. (#left > 0 and (". " .. cold_note(shown, left)) or "") .. (unknown and (". " .. UNVERIFIED) or ""),
        (#stale > 0 or cut or #unread > 0 or #left > 0 or unknown) and vim.log.levels.WARN or nil)
      -- every open Java file of this jdt.ls, not only the touched ones: a dependent jdt.ls skipped (a syntax
      -- error there) otherwise keeps its diagnostics from before the rename and the follow-up sees nothing
      -- (flake B: 1 of 4 runs of `62_refactor` rename_class_errors, follow-up nil)
      M.revalidate(client, vim.tbl_filter(function(p) return p:match("%.java$") end, vim.tbl_map(function(b)
        return vim.api.nvim_buf_get_name(b)
      end, vim.lsp.get_buffers_by_client_id(client.id))))
      follow_up(label, before, vim.tbl_map(function(f) return f.path end, files))
      local new_path = path
      for _, f in ipairs(files) do
        if f.from == path or (opts._tmp_from and f.from and opts._tmp_from[f.from] == path) then new_path = f.path end
      end
      local step = { path = new_path, name = shown }
      if opts._chain then -- a step of a chain (related tests, undo): the chain records the undo
        return done(true, step)
      end
      -- IntelliJ's "Rename tests" (on by default): test classes named <Old>Test/<Old>Tests/<Old>IT/... follow
      local tests, skipped = {}, {}
      if opts.tests ~= false then tests, skipped = M.related_tests(new_path, shown, name) end
      -- "Rename variables" and "Rename inheritors" (on by default in IntelliJ too): `Bill invoice` -> `Bill bill`,
      -- `class InvoiceImpl extends Bill` -> `BillImpl`
      local steps, vskipped, sskipped = {}, {}, {}
      local project = require("nv4j.root").project(path)
      if opts.variables ~= false then steps, vskipped = M._plan_vars(project, shown, name) end
      local subs = {}
      if opts.subclasses ~= false then subs, sskipped = M._plan_subclasses(project, shown, name, { [new_path] = true }) end
      vim.list_extend(steps, subs)
      local in_subs = {}
      for _, x in ipairs(subs) do in_subs[x.path] = true end
      for _, t in ipairs(tests) do
        if not in_subs[t.path] then steps[#steps + 1] = t end
      end
      if #skipped > 0 then
        notify("Related tests NOT renamed: " .. table.concat(skipped, "; "), vim.log.levels.WARN)
      end
      if #sskipped > 0 then
        notify("Inheritors NOT renamed: " .. table.concat(sskipped, "; "), vim.log.levels.WARN)
      end
      if #steps == 0 then
        if #vskipped > 0 then
          notify("Variables NOT renamed: " .. table.concat(vskipped, "; "), vim.log.levels.WARN)
        end
        M.undo_op = { label = label, steps = { step } }
        M.last_extras = { vars = {}, var_failed = {}, var_skipped = vskipped, sub_skipped = sskipped, subclasses = {} }
        return done(true)
      end
      if mine then busy, mine = nil, false end -- the related renames take the lock one by one
      local keep = vim.api.nvim_get_current_buf()
      local nvars = #vim.tbl_filter(function(x) return x.var end, steps)
      M.rename_chain(steps, function(ok, inverses, extra)
        -- undo = the exact reverse of what was done (a variable's inverse needs the file name it had then)
        local undo = { step }
        vim.list_extend(undo, inverses)
        local rev = {}
        for j = #undo, 1, -1 do rev[#rev + 1] = undo[j] end
        M.undo_op = { label = label, steps = rev }
        M.last_extras = { vars = extra.vars, var_failed = extra.var_failed, var_skipped = vskipped, sub_skipped = sskipped, subclasses = subs }
        if nvars > 0 or #vskipped > 0 then
          local warn = #extra.var_failed > 0 or #vskipped > 0
          notify(("Renamed variables after %s -> %s: %d: %s"):format(shown, name, #extra.vars, #extra.vars > 0 and table.concat(extra.vars, ", ") or "none")
            .. (#extra.var_failed > 0 and ("; NOT renamed (jdt.ls): " .. table.concat(extra.var_failed, "; ")) or "")
            .. (#vskipped > 0 and ("; skipped: " .. table.concat(vskipped, "; ")) or ""), warn and vim.log.levels.WARN or nil)
        end
        if vim.api.nvim_buf_is_valid(keep) then pcall(vim.api.nvim_set_current_buf, keep) end
        done(ok)
      end)
    end
    local settled = false
    -- Cold jdt.ls (first rename of a session): it refuses a dependent ("has syntax errors. Content of that file
    -- will not be updated") or answers without the references, and the project stops compiling with a
    -- success toast. So before applying, the files of the edit are compared with the files that reference the
    -- old declaration (async, no UI freeze); missing ones, or no usable answer to the references request
    -- (error, timeout: "unknown"): ask once more (the first request warms jdt.ls), still so: apply what
    -- jdt.ls gave and warn (the list of files, or "could not verify"). Every request has its own M.rename_ms
    -- bound (a slow first answer cannot starve the retry); an answer after its bound is ignored.
    local function ask(method, p, cb)
      local fired = false
      local function fire(err, res, timed)
        if fired or settled then return end
        fired = true
        cb(err, res, timed)
      end
      local pok, sent = pcall(client.request, client, method, p, function(err, res) fire(err, res, false) end, buf)
      if not pok or not sent then return false, pok and "it is not running" or tostring(sent) end
      vim.defer_fn(function() fire(nil, nil, true) end, M.rename_ms)
      return true
    end
    -- cb(left, unknown): files of the old declaration's references the edit did not touch; unknown = no answer
    local function check_refs(edit, cb)
      local sent = ask("textDocument/references", { textDocument = { uri = params.textDocument.uri },
        position = params.position, context = { includeDeclaration = false } }, function(err, res, timed)
        if timed or err or type(res) ~= "table" then return cb({}, true) end
        local refs = {}
        for _, r in ipairs(res) do
          if r.uri and r.uri:match("^file:") then refs[#refs + 1] = { path = vim.uri_to_fname(r.uri), l = r.range.start.line } end
        end
        local files = {}
        for _, f in ipairs(edit_files(edit)) do
          files[#files + 1] = f
          if f.from then files[#files + 1] = { path = f.from } end -- references inside the renamed file itself
        end
        cb(untouched_refs(refs, files, root_of(client)), false)
      end)
      if not sent then cb({}, true) end
    end
    local function finish(err, edit, left, unknown)
      settled = true
      -- whatever goes wrong after the answer, the caller hears of it (on_done) and `busy` is cleared
      local ok, e = pcall(answered, err, edit, left, unknown)
      if not ok then
        M.last = { label = label, files = {}, ok = false, err = tostring(e) }
        notify(("Rename class %s -> %s FAILED after jdt.ls answered (%s); files in an earlier summary line, if any, may be changed: undo with `u` there"):format(
          old, name, tostring(e)), vim.log.levels.ERROR)
        done(false)
      end
    end
    local function send(attempt, prev)
      return ask("textDocument/rename", params, function(err, edit, timed)
        if timed or err or not edit then
          -- the retry failed: the first answer, with the warning
          if prev then return finish(nil, prev.edit, prev.left, prev.unknown) end
          if timed then
            settled = true
            M.last = { label = label, files = {}, ok = false, err = "no answer" }
            notify(("Rename class %s -> %s: jdt.ls did not answer in %d ms; nothing changed (an answer arriving later is ignored)"):format(
              old, name, M.rename_ms), vim.log.levels.ERROR)
            return done(false)
          end
          return finish(err, edit)
        end
        check_refs(edit, function(left, unknown)
          if settled then return end
          if (#left > 0 or unknown) and attempt == 1 then
            if send(2, { edit = edit, left = left, unknown = unknown }) then return end
          end
          finish(nil, edit, left, unknown)
        end)
      end)
    end
    local sent, why = send(1)
    -- the request was not sent (jdt.ls stopped, or the call threw): nothing will ever answer
    if not sent then
      settled = true
      M.last = { label = label, files = {}, ok = false, err = "request not sent" }
      notify(("Rename class %s -> %s: the request could not be sent to jdt.ls (%s); nothing changed"):format(old, name, why),
        vim.log.levels.ERROR)
      return done(false)
    end
  end
  if opts.name then return run(opts.name) end
  vim.ui.input({ prompt = ("Rename class %s to: "):format(old), default = old }, run)
end

--- Renames the class at the cursor (or the file's class) to opts.name (prompted when missing): the file
--- is renamed, references and imports in every file updated. opts.on_done(ok) is called afterwards.
--- A rename that only changes the case of the name is done in two steps on a case-insensitive file system.
function M.rename_class(opts)
  return rename_class_impl(opts)
end

-- ── rename/move files and folders (package rename, neo-tree) ─────────────────────────────────────

local function has_java(dir)
  return #vim.fs.find(function(n) return n:match("%.java$") ~= nil end, { path = dir, limit = 1 }) > 0
end

--- A rename jdt.ls must answer with an edit: a .java file or a folder with Java files, from and to both
--- inside a source root. A null answer there means "not ready", not "nothing to do".
local function needs_edit(from, to)
  local st = vim.uv.fs_stat(from)
  if not st then return false end
  local dir_from = st.type == "directory" and from or vim.fs.dirname(from)
  local dir_to = st.type == "directory" and to or vim.fs.dirname(to)
  if not (src_root_of(dir_from) and src_root_of(dir_to)) then return false end
  if st.type == "directory" then return has_java(from) end
  return from:match("%.java$") ~= nil
end

--- Fallback edit for a package folder: the `package` line of every .java file under `from` (subpackages
--- too) set for its place under `to`. Text from the loaded buffer, else the disk.
lines_of = function(p)
  local b = vim.fn.bufnr(p)
  if b ~= -1 and vim.api.nvim_buf_is_loaded(b) then return vim.api.nvim_buf_get_lines(b, 0, -1, false) end
  if not vim.uv.fs_stat(p) then return {} end
  local ok, got = pcall(M._readfile, p) -- unreadable (mode 000): treated as empty, never thrown
  return ok and got or {}
end

--- True when the .java file declares a top-level type named like the file (the case where jdt.ls's
--- willRenameFiles must answer with an edit: references to that type exist or may exist).
local function declares_own_type(p)
  local name = vim.fn.fnamemodify(p, ":t:r")
  for _, l in ipairs(lines_of(p)) do
    if not l:match("^%s") then -- top level: not indented
      for _, kw in ipairs({ "class", "interface", "enum", "record", "@interface" }) do
        if l:find("%f[%w@]" .. kw .. "%s+" .. vim.pesc(name) .. "%f[^%w_$]") then return true end
      end
    end
  end
  return false
end

--- A file, or any .java file under a folder, declaring its own top-level type.
local function has_own_type(path)
  if vim.fn.isdirectory(path) == 0 then return path:match("%.java$") ~= nil and declares_own_type(path) end
  for name, kind in vim.fs.dir(path, { depth = 32 }) do
    if kind == "file" and name:match("%.java$") and declares_own_type(path .. "/" .. name) then return true end
  end
  return false
end

local function package_lines_edit(from, to)
  local is_file = vim.fn.isdirectory(from) == 0
  local _, old_pkg = src_root_of(is_file and vim.fs.dirname(from) or from)
  local _, new_pkg = src_root_of(is_file and vim.fs.dirname(to) or to)
  if not (old_pkg and new_pkg) or old_pkg == new_pkg or old_pkg == "" then return false end
  local changes = {}
  local entries = is_file and { { vim.fs.basename(from), "file" } } or {}
  if not is_file then
    for name, kind in vim.fs.dir(from, { depth = 32 }) do entries[#entries + 1] = { name, kind } end
  end
  for _, e in ipairs(entries) do
    local name, kind = e[1], e[2]
    if kind == "file" and name:match("%.java$") then
      local p = is_file and from or (from .. "/" .. name)
      local sub = is_file and "." or vim.fs.dirname(name)
      sub = sub ~= "." and ("." .. sub:gsub("/", ".")) or ""
      local lines = lines_of(p)
      local old_name = old_pkg .. sub
      for i, l in ipairs(lines) do
        local pre = l:match("^(%s*package%s+)" .. vim.pesc(old_name) .. "%s*;")
        if pre then
          changes[#changes + 1] = { textDocument = { uri = vim.uri_from_fname(p), version = vim.NIL }, edits = { {
            range = { start = { line = i - 1, character = #pre }, ["end"] = { line = i - 1, character = #pre + #old_name } },
            newText = new_pkg .. sub } } }
          break
        end
      end
    end
  end
  return #changes > 0 and { documentChanges = changes } or false
end

local function will_rename(client, from, to)
  local res, rerr = client:request_sync("workspace/willRenameFiles",
    { files = { { oldUri = vim.uri_from_fname(from), newUri = vim.uri_from_fname(to) } } }, REQUEST_MS, 0)
  if not res then return nil, ("jdt.ls did not answer willRenameFiles in %d ms (%s)"):format(REQUEST_MS, tostring(rerr)) end
  if res.err then return nil, ("jdt.ls refused (%s)"):format(res.err.message or vim.inspect(res.err)) end
  return res.result or false
end

--- Imports of the file's own package (`import demo.billing.X;` in a file of demo.billing) removed: a merge moves a
--- class into the package of the classes it imported, and jdt.ls leaves those imports behind. A blank line left
--- doubled goes too. A buffer with unsaved changes is skipped. Returns the paths changed.
local function drop_same_package_imports(paths, dirty)
  local changed = {}
  for _, p in ipairs(paths) do
    local lines = lines_of(p)
    local pkg
    for _, l in ipairs(lines) do
      pkg = l:match("^%s*package%s+([%w_$.]+)%s*;")
      if pkg then break end
    end
    local b = vim.fn.bufnr(p)
    if pkg and not dirty[p] and not (b ~= -1 and vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified) then
      local out, gone = {}, false
      for i, l in ipairs(lines) do
        local ipkg = l:match("^%s*import%s+([%w_$.]+)%.[%w_$]+%s*;")
        if ipkg == pkg and not l:match("^%s*import%s+static") then
          gone = true
          if (out[#out] or "") == "" and (lines[i + 1] or "") == "" then table.remove(lines, i + 1) end
        else
          out[#out + 1] = l
        end
      end
      if gone then
        if b == -1 or not vim.api.nvim_buf_is_loaded(b) then b = vim.fn.bufadd(p); vim.fn.bufload(b) end
        vim.api.nvim_buf_set_lines(b, 0, -1, false, out)
        write(p)
        changed[#changed + 1] = p
      end
    end
  end
  return changed
end

--- Renames/moves files or folders `moves` ({ {from, to}, ... }, absolute) with jdt.ls told first:
--- willRenameFiles for the first one (and for any other whose files that edit did not touch), edits
--- applied and written, then each move with buffers re-pointed, then didRenameFiles. Synchronous
--- (neo-tree's before-rename hook needs it). Nothing changes when a check or the request fails.
--- Returns ok, message.
function M.rename_paths(moves, label, client, opts)
  opts = opts or {}
  local function fail(msg, level)
    msg = label:gsub("^Renamed", "Rename"):gsub("^Moved", "Move") .. ": " .. msg .. "; nothing changed"
    M.last = { label = label, files = {}, ok = false, err = msg }
    notify(msg, level or vim.log.levels.ERROR)
    return false, msg
  end
  if busy then return fail(busy_msg(), vim.log.levels.WARN) end
  for _, m in ipairs(moves) do
    m[1], m[2] = vim.fs.normalize(m[1]):gsub("/+$", ""), vim.fs.normalize(m[2]):gsub("/+$", "")
    if not vim.uv.fs_stat(m[1]) then return fail(m[1] .. " does not exist") end
    if vim.uv.fs_stat(m[2]) then return fail(m[2] .. " already exists (merging is not supported)") end
    if under(m[2], m[1]) then return fail("cannot move a folder into itself") end
  end
  client = client or jdtls_for(moves[1][1])
  if not client then return fail("jdt.ls is not running for this project", vim.log.levels.WARN) end
  local root = root_of(client)
  local function moving(p)
    for _, m in ipairs(moves) do
      if under(p, m[1]) then return true end
    end
  end
  local dirty, before = dirty_buffers(), M.error_counts()
  -- One move at a time: willRenameFiles, apply, move, didRenameFiles, then the next one (jdt.ls
  -- computes the next edit on the moved state). jdt.ls renames the package of ONE source root and, for
  -- the namesake package in a later root (src/test/java), adds imports of the moved types: those edits
  -- are dropped (that root's own rename follows and puts its files in the same package again).
  -- Callers put src/main/java first (tests depend on main, not the other way round).
  local files, changes, tries_by, notes = {}, { files = {} }, {}, {}
  local step_log, recordable = {}, true -- per move: its folder/file and the inverse of its edit (see undo_recorded)
  local function done_moves() -- the moves completed so far, as { from, to }
    return vim.tbl_map(function(c) return { vim.uri_to_fname(c.oldUri), vim.uri_to_fname(c.newUri) } end, changes.files)
  end
  -- per-step ms (M.last.ms, profiling): will = willRenameFiles, apply = edit + writes, move = folder + :saveas
  local ms, t = { will = 0, apply = 0, move = 0 }, vim.uv.hrtime()
  local function lap(k)
    local n = vim.uv.hrtime()
    ms[k], t = ms[k] + (n - t) / 1e6, n
  end
  for i, m in ipairs(moves) do
    local from, to = m[1], m[2]
    if opts.mkdirs and not vim.uv.fs_stat(vim.fs.dirname(to)) then -- undoing a merge: the folder the file came from is gone
      local made, d = {}, vim.fs.dirname(to)
      while not vim.uv.fs_stat(d) do
        table.insert(made, 1, d)
        d = vim.fs.dirname(d)
      end
      vim.fn.mkdir(vim.fs.dirname(to), "p")
      client:notify("workspace/didChangeWatchedFiles", { changes = vim.tbl_map(function(q)
        return { uri = vim.uri_from_fname(q), type = 1 }
      end, made) })
    end
    local edit, err = will_rename(client, from, to)
    -- a later root right after the previous move: jdt.ls sometimes answers null while it is still taking
    -- that move in (measured in the check run, not alone): ask again for up to 1 s, then fall back to the
    -- package lines only (said in the summary)
    local tries = 1
    local needs = needs_edit(from, to) and not opts.same_package -- same package name, other source root: nothing to rewrite
    -- an undo must not give up on jdt.ls's first answer either: right after the refactor it is undoing, jdt.ls can still be
    -- taking the move in and answer an error ("Internal error.") or null
    while ((edit == false and needs) or (edit == nil and opts.undoing)) and tries < 10 do
      vim.wait(edit == nil and 200 or 100)
      edit, err = will_rename(client, from, to)
      tries = tries + 1
    end
    tries_by[from] = tries
    lap("will")
    -- refused only where an edit was due: the first move holds a top-level type named like its file. An
    -- empty or broken file, package-info.java or a file without its own type gets null legitimately:
    -- moved with the package lines set by text (NOTE), like a later root.
    if edit == false and needs and i == 1 and has_own_type(from) then
      return fail(("jdt.ls gave no edit for this Java rename (asked %d times over 1 s): the code would be left with the old names; try again once jdt.ls is idle"):format(tries))
    end
    if edit == false and needs then
      edit = package_lines_edit(from, to)
      notes[#notes + 1] = ("jdt.ls gave no edit for %s: %s"):format(rel(from, root), edit
        and "its package lines were set by Nv4J; references to its classes from other packages were not updated"
        or "moved as is (no package line to change)")
    end
    if edit == nil then
      if i == 1 then return fail(err) end
      return failed_part_way(label, err .. " for " .. rel(from, root), files, root, done_moves())
    end
    if opts.merge then
      -- a merge moves files one by one: an edit to a file that moves later (a reference to the class just moved)
      -- is needed, there is no second rename that would put it right
    elseif edit and edit.documentChanges then
      edit.documentChanges = vim.tbl_filter(function(ch)
        local p = ch.textDocument and vim.uri_to_fname(ch.textDocument.uri) or (ch.oldUri and vim.uri_to_fname(ch.oldUri))
        for j = i + 1, #moves do
          if p and under(p, moves[j][1]) then return false end
        end
        return true
      end, edit.documentChanges)
    elseif edit and edit.changes then
      for uri in pairs(edit.changes) do
        for j = i + 1, #moves do
          if under(vim.uri_to_fname(uri), moves[j][1]) then edit.changes[uri] = nil end
        end
      end
    end
    local rec = {}
    if edit then
      rec = inverse_text_edits(edit)
      if rec == nil then recordable = false end
      local ok, fs, why = apply(client, edit, dirty, moving)
      for _, f in ipairs(fs) do
        local dup = vim.iter(files):find(function(g) return g.path == f.path end)
        if not dup then files[#files + 1] = f end
      end
      if not ok then return failed_part_way(label, why, files, root, done_moves()) end
    end
    lap("apply")
    -- the edit may have moved it already (a RenameFile in jdt.ls's answer)
    if vim.uv.fs_stat(from) then
      local mok, merr = pcall(vim.lsp.util.rename, from, to, { overwrite = false })
      if not mok or vim.uv.fs_stat(from) or not vim.uv.fs_stat(to) then
        return failed_part_way(label, ("moving %s to %s failed: %s; the edits above are applied"):format(rel(from, root),
          rel(to, root), tostring(merr or "not moved")), files, root, done_moves())
      end
    end
    lap("move")
    step_log[#step_log + 1] = { from = from, to = to, rec = rec }
    local change = { oldUri = vim.uri_from_fname(from), newUri = vim.uri_from_fname(to) }
    changes.files[#changes.files + 1] = change
    client:notify("workspace/didRenameFiles", { files = { change } })
    -- jdt.ls's resource tree learns of a move into a package folder that did not exist (or across source roots) only from
    -- the file events: without them its next willRenameFiles for the moved file (the undo) answered "Internal error."
    -- until something else refreshed it (Java model errors "File not found <old path>" in lsp.log)
    client:notify("workspace/didChangeWatchedFiles", { changes = {
      { uri = change.newUri, type = 1 }, { uri = change.oldUri, type = 3 } } })
    for _, f in ipairs(files) do
      if under(f.path, from) then
        f.from = f.from or f.path
        f.path = to .. f.path:sub(#from + 1)
        if dirty[f.from] then f.unsaved, f.saved_dirty = nil, true end
      end
    end
  end
  -- buffers under a moved folder that the edit did not touch but had unsaved changes: written by the move
  for p in pairs(dirty) do
    for _, m in ipairs(moves) do
      if under(p, m[1]) and not vim.iter(files):any(function(f) return f.from == p end) then
        files[#files + 1] = { path = m[2] .. p:sub(#m[1] + 1), from = p, saved_dirty = true }
      end
    end
  end
  for _, m in ipairs(moves) do -- a file moved with no edit of its own (other source root, same package) is still listed
    if vim.fn.isdirectory(m[2]) == 0 and not vim.iter(files):any(function(f) return f.path == m[2] end) then
      files[#files + 1] = { path = m[2], from = m[1], saved_dirty = dirty[m[1]] or nil, outside = root and not under(m[2], root) or nil }
    end
  end
  if opts.merge then
    local javas = {}
    for _, m in ipairs(moves) do
      if vim.fn.isdirectory(m[2]) == 1 then
        for n, kind in vim.fs.dir(m[2], { depth = 32 }) do
          if kind == "file" and n:match("%.java$") then javas[#javas + 1] = m[2] .. "/" .. n end
        end
      elseif m[2]:match("%.java$") then
        javas[#javas + 1] = m[2]
      end
    end
    local dropped = drop_same_package_imports(javas, dirty)
    if #dropped > 0 then
      notes[#notes + 1] = ("%d same-package import(s) removed in %s"):format(#dropped, table.concat(vim.tbl_map(function(q) return rel(q, root) end, dropped), ", "))
    end
  end
  local moved = table.concat(vim.tbl_map(function(m) return rel(m[1], root) .. " -> " .. rel(m[2], root) end, moves), ", ")
  local stale, cut, unread = {}, false, {}
  if opts.stale then stale, cut, unread = M.stale_refs(root, opts.stale.names) end
  M.last = { label = label, files = files, ok = true, moves = moves, tries = tries_by, notes = notes, ms = ms, stale = stale,
    truncated = cut, unread = unread, info = opts.info }
  -- opts.warn: caller's warnings (WARN level); opts.info: caller's notes (level unchanged)
  vim.list_extend(notes, opts.warn or {})
  local warn = #notes > 0 or #stale > 0 or cut or #unread > 0
  notify(summary(("%s (moved %s)"):format(label, moved), files, root) .. (#notes > 0 and (". NOTE: " .. table.concat(notes, "; ")) or "")
    .. stale_note(stale, opts.stale and opts.stale.old, cut, unread) .. ((opts.info and #opts.info > 0) and (". " .. table.concat(opts.info, "; ")) or ""),
    warn and vim.log.levels.WARN or nil)
  -- every open Java file of this jdt.ls, as after a class rename: a dependent or the moved file keeps stale
  -- diagnostics otherwise and the follow-up sees nothing (audit_move_class: 1 of 4 runs had no warning)
  M.revalidate(client, vim.tbl_filter(function(p) return p:match("%.java$") end, vim.tbl_map(function(b)
    return vim.api.nvim_buf_get_name(b)
  end, vim.lsp.get_buffers_by_client_id(client.id))))
  follow_up(label, before, vim.tbl_map(function(f) return f.path end, files))
  if not opts.undoing then
    M.undo_op = { label = label, moves = vim.tbl_map(function(m) return { m[2], m[1] } end, moves), merge = opts.merge, mkdirs = opts.merge, same_package = opts.same_package, recorded = (recordable and not opts.merge) and step_log or nil } -- a merge also removes imports outside the edits: its undo is the jdt.ls inverse
  end
  return true
end

--- Undo from what the refactor recorded, without asking jdt.ls (which can answer an error or null right after the
--- refactor, seen for the undo of a move into a new test package): in reverse order, each move is put back and then
--- the inverse of the edit that came before it is applied. Returns ok.
local function undo_recorded(op)
  local steps = op.recorded
  local client = jdtls_for(steps[1].from) or jdtls_for(steps[1].to)
  local root = client and root_of(client)
  local files, problems = {}, {}
  for i = #steps, 1, -1 do
    local st = steps[i]
    if not vim.uv.fs_stat(st.to) then
      problems[#problems + 1] = rel(st.to, root) .. " is gone"
    else
      local d, made = vim.fs.dirname(st.from), {}
      while not vim.uv.fs_stat(d) do
        table.insert(made, 1, d)
        d = vim.fs.dirname(d)
      end
      vim.fn.mkdir(vim.fs.dirname(st.from), "p")
      local mok, merr = pcall(vim.lsp.util.rename, st.to, st.from, { overwrite = false })
      if not mok or vim.uv.fs_stat(st.to) or not vim.uv.fs_stat(st.from) then
        problems[#problems + 1] = ("could not move %s back (%s)"):format(rel(st.to, root), tostring(merr or "not moved"))
      elseif client then
        client:notify("workspace/didRenameFiles", { files = { { oldUri = vim.uri_from_fname(st.to), newUri = vim.uri_from_fname(st.from) } } })
        local ch = { { uri = vim.uri_from_fname(st.from), type = 1 }, { uri = vim.uri_from_fname(st.to), type = 3 } }
        for _, m in ipairs(made) do ch[#ch + 1] = { uri = vim.uri_from_fname(m), type = 1 } end
        client:notify("workspace/didChangeWatchedFiles", { changes = ch })
      end
    end
    if #st.rec > 0 then
      undo_text_edits({ edits = st.rec, path = st.from, from = "recorded", to = "inverse" }, function(ok, text)
        if not ok then problems[#problems + 1] = text end
        files[#files + 1] = st.from
      end)
    else
      files[#files + 1] = st.from
    end
  end
  local gone = {}
  for j = #(op.created or {}), 1, -1 do
    if vim.uv.fs_rmdir(op.created[j]) then gone[#gone + 1] = { uri = vim.uri_from_fname(op.created[j]), type = 3 } end
  end
  if client and #gone > 0 then client:notify("workspace/didChangeWatchedFiles", { changes = gone }) end
  if client then
    M.revalidate(client, vim.tbl_filter(function(q) return q:match("%.java$") end, vim.tbl_map(function(b)
      return vim.api.nvim_buf_get_name(b)
    end, vim.lsp.get_buffers_by_client_id(client.id))))
  end
  notify(("Undid: %s: %d step(s) put back from the recorded edits%s"):format(op.label, #steps,
    #problems > 0 and ("; PROBLEMS: " .. table.concat(problems, "; ")) or ""), #problems > 0 and vim.log.levels.WARN or nil)
  M.last = { label = "Undid: " .. op.label, files = vim.tbl_map(function(f) return { path = f } end, files), ok = #problems == 0 }
  return #problems == 0
end

--- Undo the last rename, move or package rename of this session the way IntelliJ's one undo does: the
--- inverse refactor, so file names, folders, `package` lines, imports and references all come back (`u` in
--- a buffer gives back its text only; the files stay where they are). Edits made since stay. Only the last
--- refactor is remembered; undoing it forgets it (no redo). opts.on_done(ok).
function M.undo_last(opts)
  opts = opts or {}
  local function fin(ok)
    if opts.on_done then opts.on_done(ok) end
    return ok
  end
  local op = M.undo_op
  if not op then
    notify("Undo refactor: nothing to undo (only the last rename or move of this session is remembered)", vim.log.levels.WARN)
    return fin(false)
  end
  if busy then
    notify("Undo refactor: " .. busy_msg() .. "; nothing changed", vim.log.levels.WARN)
    return fin(false)
  end
  M.undo_op = nil
  if op.moves and op.recorded then return fin(undo_recorded(op)) end
  if op.moves then
    return fin(M.rename_paths(op.moves, "Undid: " .. op.label, nil, { undoing = true, merge = op.merge, mkdirs = op.mkdirs, same_package = op.same_package }))
  end
  M.rename_chain(op.steps, function(ok)
    notify(("Undid: %s%s"):format(op.label, ok and "" or " (not completely: see the messages above)"),
      ok and vim.log.levels.INFO or vim.log.levels.WARN)
    fin(ok)
  end)
end

--- Moves for renaming package `pkg` to `name`: its folder in `src_root` and the namesake folders in the
--- MODULE's other source roots (`src/*/java`), src/main/java first (see M.rename_paths).
local function namesake_moves(module, src_root, pkg, name)
  local pkg_path, new_path = pkg:gsub("%.", "/"), name:gsub("%.", "/")
  local roots = { src_root }
  for _, r in ipairs(vim.fn.glob(module .. "/src/*/java", false, true)) do
    r = vim.fs.normalize(r)
    if r ~= src_root and vim.fn.isdirectory(r .. "/" .. pkg_path) == 1 then roots[#roots + 1] = r end
  end
  table.sort(roots, function(a, b)
    local ma, mb = a:match("/src/main/java$") ~= nil, b:match("/src/main/java$") ~= nil
    if ma ~= mb then return ma end
    return a < b
  end)
  return vim.tbl_map(function(r) return { r .. "/" .. pkg_path, r .. "/" .. new_path } end, roots)
end

M._namesake_moves = namesake_moves -- checks

--- Package of the current buffer from its `package` line.
local function current_package(buf)
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, math.min(200, vim.api.nvim_buf_line_count(buf)), false)) do
    local p = l:match("^%s*package%s+([%w_$.]+)%s*;")
    if p then return p end
  end
end

--- Moves that merge folder `from` into the existing folder `to`: a file per move; a sub-folder missing in `to`
--- moves whole. Names already in `to` are added to `clashes` ("sub/Name.java"). `label` prefixes nothing.
function M._merge_moves(from, to, clashes, _label, prefix)
  prefix = prefix or ""
  local out, names = {}, {}
  for n, kind in vim.fs.dir(from) do names[#names + 1] = { n, kind } end
  table.sort(names, function(a, b) return a[1] < b[1] end)
  for _, e in ipairs(names) do
    local n, kind = e[1], e[2]
    local f, t = from .. "/" .. n, to .. "/" .. n
    if kind == "directory" then
      if vim.uv.fs_stat(t) then
        vim.list_extend(out, M._merge_moves(f, t, clashes, _label, prefix .. n .. "/"))
      else
        out[#out + 1] = { f, t }
      end
    elseif vim.uv.fs_stat(t) then
      clashes[#clashes + 1] = prefix .. n
    else
      out[#out + 1] = { f, t }
    end
  end
  return out
end

--- Renames the package of the current file to opts.name (prompted when missing): `package`/`import`
--- lines in every file updated, the folder moved (with the same package folder in the project's other
--- source roots, e.g. src/test/java), buffers re-pointed. Returns ok (nil while prompting).
function M.rename_package(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  local pkg = current_package(buf)
  if not pkg then
    notify("Rename package: no `package` line in this file (default package)", vim.log.levels.WARN)
    return false
  end
  local dir = vim.fs.dirname(path)
  local pkg_path = pkg:gsub("%.", "/")
  if dir:sub(-#pkg_path - 1) ~= "/" .. pkg_path then
    notify(("Rename package: this file's folder does not match `package %s;`; fix that first"):format(pkg), vim.log.levels.ERROR)
    return false
  end
  local src_root = dir:sub(1, #dir - #pkg_path - 1)
  local function run(name)
    if not name or name == "" or name == pkg then return false end
    for _, part in ipairs(vim.split(name, ".", { plain = true })) do
      if not valid_identifier(part) then
        notify(("Rename package: '%s' is not a valid package name; nothing changed"):format(name), vim.log.levels.ERROR)
        return false
      end
    end
    local moves = namesake_moves(module_root(path), src_root, pkg, name)
    -- the target package exists (in some source root): merge, like IntelliJ, when no file of the old package has
    -- the name of one in the target; otherwise refuse, naming them. A root where the target is missing keeps
    -- the plain folder move.
    local merged, clashes, final, sources = false, {}, {}, {}
    local project = require("nv4j.root").project(path)
    for _, m in ipairs(moves) do
      if vim.uv.fs_stat(m[2]) and not under(m[2], m[1]) and vim.fn.isdirectory(m[2]) == 1 then
        merged = true
        local mine = M._merge_moves(m[1], m[2], clashes, rel(m[1], src_root_of(m[1]) or project))
        vim.list_extend(final, mine)
        sources[#sources + 1] = m[1]
      else
        final[#final + 1] = m
      end
    end
    if merged and #clashes > 0 then
      local msg = ("Rename package %s -> %s: %s already exists and both hold %s; nothing changed (rename or move those classes first)"):format(
        pkg, name, name, table.concat(clashes, ", "))
      M.last = { label = "Rename package", files = {}, ok = false, err = msg, clashes = clashes }
      notify(msg, vim.log.levels.ERROR)
      if opts.on_done then opts.on_done(false) end
      return false
    end
    local label = ("Renamed package %s -> %s%s"):format(pkg, name, merged and " (merged into the existing package)" or "")
    local ok = M.rename_paths(merged and final or moves, label, nil,
      { stale = { names = package_names(pkg), old = pkg }, merge = merged or nil })
    if ok and merged then -- the emptied source folders go; jdt.ls is told
      local gone = {}
      local function prune(dir)
        for n, kind in vim.fs.dir(dir) do
          if kind == "directory" then prune(dir .. "/" .. n) end
        end
        if vim.uv.fs_rmdir(dir) then gone[#gone + 1] = { uri = vim.uri_from_fname(dir), type = 3 } end
      end
      for _, d in ipairs(sources) do prune(d) end
      local client = jdtls_for(path) or jdtls_for(final[1][2])
      if client and #gone > 0 then client:notify("workspace/didChangeWatchedFiles", { changes = gone }) end
      if M.last then M.last.merged, M.last.pruned = true, #gone end
    end
    if opts.on_done then opts.on_done(ok) end
    return ok
  end
  if opts.name then return run(opts.name) end
  vim.ui.input({ prompt = ("Rename package %s to: "):format(pkg), default = pkg }, run)
end

--- <leader>jr: rename the package on a `package` line, else the class.
function M.rename(opts)
  if vim.api.nvim_get_current_line():match("^%s*package%s") then return M.rename_package(opts) end
  return M.rename_class(opts)
end

-- ── move a class to another package (Task 4b) ────────────────────────────────────────────────────

--- Patterns for a class `old` moved out of package `pkg`: its old fully qualified name only (the simple
--- name is still right after a move).
local function move_names(old, pkg)
  if not pkg or pkg == "" then return { java = {}, config = {} } end
  local fqn = pkg .. "." .. old
  return { java = { word(fqn) }, config = { word(fqn) },
    imports = { "^%s*import%s+" .. vim.pesc(fqn) .. "%s*;", "^%s*import%s+static%s+" .. vim.pesc(fqn) .. "%." } }
end

local TYPE_KINDS = { [5] = true, [10] = true, [11] = true, [23] = true } -- class, enum, interface, struct (LSP SymbolKind)

local function contains(r, l, c)
  local s, e = r.start, r["end"]
  if l < s.line or l > e.line then return false end
  if l == s.line and c < s.character then return false end
  if l == e.line and c > e.character then return false end
  return true
end

--- The class to move: the file's own top-level type (named like the file) when the cursor is in it or
--- outside every type (package/import lines). nil, reason when the cursor is in a nested type, in a second
--- top-level type, or the file declares no type of its name. jdt.ls moves whole files (compilation units).
--- Type declarations in the buffer's text (comments, strings and char literals blanked): the names after
--- `class`/`interface`/`enum`/`record`/`@interface`. Text-only: any extra token makes the file "ambiguous".
local function declared_types(buf)
  local src = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  src = src:gsub("/%*.-%*/", " "):gsub("//[^\n]*", " "):gsub('"""(.-)"""', '""'):gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''")
  local names = {}
  for name in src:gmatch("%f[%w_$@]@?interface%s+([%a_$][%w_$]*)") do names[#names + 1] = name end
  for _, kw in ipairs({ "class", "enum", "record" }) do
    for name in src:gmatch("%f[%w_$]" .. kw .. "%s+([%a_$][%w_$]*)") do names[#names + 1] = name end
  end
  return names
end

M.symbol_requests = 0 -- documentSymbol requests made by move (checks: the common case makes none)
M.symbols_timeout_ms = 2000

local function movable_type(buf, client, path)
  local own = vim.fn.fnamemodify(path, ":t:r")
  -- common case, no jdt.ls round trip (it can take over 1 s when jdt.ls is busy): the text declares one
  -- type, named like the file, so wherever the cursor is, that is the class
  local decl = declared_types(buf)
  if #decl == 1 and decl[1] == own then return own end
  local cur = vim.api.nvim_win_get_cursor(0)
  local l, c = cur[1] - 1, cur[2]
  M.symbol_requests = M.symbol_requests + 1
  local res, rerr = client:request_sync("textDocument/documentSymbol", { textDocument = { uri = vim.uri_from_bufnr(buf) } },
    M.symbols_timeout_ms, buf)
  local syms = res and res.result
  local function plain(n) return (tostring(n):gsub("<.*$", "")) end
  if type(syms) ~= "table" or (syms[1] and not syms[1].range) then
    -- the file has nested or several types and jdt.ls did not say where the cursor is: refused (moving the
    -- whole file could move a type the cursor was not on)
    return nil, ("this file declares several types (%s) and jdt.ls did not tell which one the cursor is in (%s); try again once jdt.ls is idle"):format(
      table.concat(decl, ", "), res == nil and ("no answer in %d ms: %s"):format(M.symbols_timeout_ms, tostring(rerr))
        or (res.err and (res.err.message or "error")) or "no document symbols")
  end
  local top
  for _, s in ipairs(syms) do
    if TYPE_KINDS[s.kind] and contains(s.range, l, c) then top = s end
  end
  if not top then
    for _, s in ipairs(syms) do
      if TYPE_KINDS[s.kind] and plain(s.name) == own then return own end
    end
    return nil, ("the cursor is not in a class and this file declares no top-level type named %s"):format(own)
  end
  if plain(top.name) ~= own then
    return nil, ("the cursor is in %s, a second top-level type of %s.java: Move takes whole files (the file's own type %s); put the cursor on %s to move the file"):format(
      plain(top.name), own, own, own)
  end
  local function nested(s)
    for _, ch in ipairs(s.children or {}) do
      if contains(ch.range, l, c) then
        local deeper = nested(ch)
        if deeper then return deeper end
        if TYPE_KINDS[ch.kind] then return ch end
      end
    end
  end
  local n = nested(top)
  if n then
    return nil, ("the cursor is in the nested type %s (inside %s): only top-level types move; put the cursor outside %s to move %s"):format(
      plain(n.name), own, plain(n.name), own)
  end
  return own
end

--- The module's source roots (`src/*/java`), `first` (the current file's) first.
local function source_roots(module, first)
  local roots = { first }
  for _, r in ipairs(vim.fn.glob(module .. "/src/*/java", false, true)) do
    r = vim.fs.normalize(r)
    if r ~= first then roots[#roots + 1] = r end
  end
  return roots
end

--- Packages with at least one .java file in the project's source roots (sorted, no default package).
local function project_packages(roots)
  local set = {}
  for _, r in ipairs(roots) do
    for name, kind in vim.fs.dir(r, { depth = 32 }) do
      if kind == "file" and name:match("%.java$") then
        local d = vim.fs.dirname(name)
        if d ~= "." then set[(d:gsub("/", "."))] = true end
      end
    end
  end
  local out = vim.tbl_keys(set)
  table.sort(out)
  return out
end

local STEREOTYPES = { "RestController", "Controller", "Service", "Component", "Repository", "Configuration",
  "ControllerAdvice", "RestControllerAdvice" }

--- Spring Boot: a component (stereotype annotation) moved out of every @SpringBootApplication package is
--- no longer found by component scanning. Returns a warning, or nil.
local function spring_scan_warning(path, module, name, target)
  local ann
  for _, l in ipairs(lines_of(path)) do
    for _, a in ipairs(STEREOTYPES) do
      if l:match("^%s*@" .. a .. "%f[^%w_]") then ann = ann or a end
    end
  end
  if not ann then return nil end
  local bases, n = {}, 0
  for _, r in ipairs(vim.fn.glob(module .. "/src/main/java", false, true)) do
    r = vim.fs.normalize(r)
    for rel_path, kind in vim.fs.dir(r, { depth = 32 }) do
      if kind == "file" and rel_path:match("%.java$") then
        n = n + 1
        if n > M.scan_max_files then break end
        local p = r .. "/" .. rel_path
        if p ~= path then
          for _, l in ipairs(lines_of(p)) do
            if l:find("@SpringBootApplication", 1, true) then
              local d = vim.fs.dirname(rel_path)
              bases[#bases + 1] = { pkg = d == "." and "" or (d:gsub("/", ".")), app = vim.fn.fnamemodify(p, ":t:r") }
              break
            end
          end
        end
      end
    end
  end
  if #bases == 0 then return nil end
  for _, b in ipairs(bases) do
    if b.pkg == "" or target == b.pkg or target:sub(1, #b.pkg + 1) == b.pkg .. "." then return nil end
  end
  return ("Spring: %s (@%s) is now in %s, outside %s (scanned from @SpringBootApplication %s): component scanning will not find it unless @ComponentScan/scanBasePackages names %s"):format(
    name, ann, target, bases[1].pkg, bases[1].app, target)
end

-- ── conflicts found BEFORE a move (IntelliJ lists them and asks) ─────────────────────────────────
--
-- Moving a class out of its package breaks what only the package allowed: package-private (and protected,
-- when not inherited) members and types of the old package that the moved class uses, and members or the class
-- itself, when not public, that the old package's other classes use. Text pass (comments and strings blanked)
-- finds the candidates, jdt.ls `textDocument/references` on a member confirms the use (a name that merely appears
-- is not a conflict); a references request that gives no answer makes it "possible". Moving between source roots
-- (main <-> test) adds: a main class that would depend on test code; a test class using test libraries moved to main.
M.conflict_ms = 3000 -- per references request
M.conflict_refs_max = 30 -- references requests per analysis; the rest are reported as "not checked"

local function blank_code(src)
  src = src:gsub("/%*.-%*/", function(m) return (m:gsub("[^\n]", " ")) end)
  src = src:gsub('"""(.-)"""', function(m) return '""' .. (m:gsub("[^\n]", " ")) end)
  src = src:gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''"):gsub("//[^\n]*", "")
  return src
end

--- { name, kind, public, members = { { name, vis, line, col } } } of the file's own top-level type, text only.
--- vis: "public", "private", "protected" or "package". Interface members are public; enum and record bodies are
--- not listed (constants, components).
local function type_facts(path)
  local own = vim.fn.fnamemodify(path, ":t:r")
  local src = blank_code(table.concat(lines_of(path), "\n"))
  local facts = { name = own, public = false, kind = nil, members = {}, extends = {} }
  local depth = 0
  local in_own = false
  local i = 0
  for line in (src .. "\n"):gmatch("(.-)\n") do
    i = i + 1
    local d0 = depth
    if d0 == 0 then
      local mods, kw = line:match("^(.-)%f[%w_$](class)%s+" .. vim.pesc(own) .. "%f[^%w_$]")
      if not kw then mods, kw = line:match("^(.-)%f[%w_$](interface)%s+" .. vim.pesc(own) .. "%f[^%w_$]") end
      if not kw then mods, kw = line:match("^(.-)%f[%w_$](enum)%s+" .. vim.pesc(own) .. "%f[^%w_$]") end
      if not kw then mods, kw = line:match("^(.-)%f[%w_$](record)%s+" .. vim.pesc(own) .. "%f[^%w_$]") end
      if kw then
        in_own, facts.kind = true, kw
        facts.public = (mods .. " "):find("%f[%w_$]public%f[^%w_$]") ~= nil
        local ext = line:match("extends%s+([%w_$.<>, ]+)")
        if ext then facts.extends[#facts.extends + 1] = ext end
      end
    elseif d0 == 1 and in_own and (facts.kind == "class" or facts.kind == "interface") then
      local head = line:gsub("@[%w_.]+%b()", ""):gsub("@[%w_.]+", "")
      head = head:match("^([^{;=]*)") or ""
      local name, vis
      local pm = head:match("([%a_$][%w_$]*)%s*%(")
      if pm and not head:match("^%s*}") then name = pm
      else name = (line:gsub("@[%w_.]+%b()", "")):match("([%a_$][%w_$]*)%s*[=;]") end
      if name and not head:match("%f[%w_$]class%f[^%w_$]") and not head:match("%f[%w_$]interface%f[^%w_$]")
          and not head:match("%f[%w_$]enum%f[^%w_$]") and not head:match("%f[%w_$]record%f[^%w_$]") and not head:match("^%s*return") then
        local h = head .. " "
        if h:find("%f[%w_$]public%f[^%w_$]") or facts.kind == "interface" then vis = "public"
        elseif h:find("%f[%w_$]private%f[^%w_$]") then vis = "private"
        elseif h:find("%f[%w_$]protected%f[^%w_$]") then vis = "protected"
        else vis = "package" end
        local col = line:find(name, 1, true)
        if col and (pm or line:find("[=;]")) then
          facts.members[#facts.members + 1] = { name = name, vis = vis, line = i - 1, col = col - 1 }
        end
      end
    end
    for ch in line:gmatch("[{}]") do depth = depth + (ch == "{" and 1 or -1) end
  end
  return facts
end
M._type_facts = type_facts -- checks

local function has_word(txt, w) return txt:find(word(w)) ~= nil end

--- Files of package directory `rel_dir` (relative to a source root) in the given roots: { path }.
local function package_files(roots, rel_dir)
  local out = {}
  for _, r in ipairs(roots) do
    local d = r .. (rel_dir ~= "" and ("/" .. rel_dir) or "")
    for name, kind in vim.fs.dir(d) do
      if kind == "file" and name:match("%.java$") then out[#out + 1] = d .. "/" .. name end
    end
  end
  table.sort(out)
  return out
end

--- Conflicts of moving the class in `path` (package `pkg`, source root `src_root`) to `target` in `troot`.
--- Returns a list of messages (empty = none) and the number of references requests made.
function M._move_conflicts(client, buf, path, pkg, src_root, target, troot, roots)
  local out, requests = {}, 0
  local name = vim.fn.fnamemodify(path, ":t:r")
  local project = require("nv4j.root").project(path)
  local mtxt = blank_code(table.concat(lines_of(path), "\n"))
  local mfacts = type_facts(path)
  local function add(s) out[#out + 1] = s end
  local function refs(p, l, c)
    if requests >= M.conflict_refs_max then return nil end
    requests = requests + 1
    local res = client:request_sync("textDocument/references", { textDocument = { uri = vim.uri_from_fname(p) },
      position = { line = l, character = c }, context = { includeDeclaration = false } }, M.conflict_ms, buf)
    if not res or res.err or type(res.result) ~= "table" then return nil end
    local files = {}
    for _, r in ipairs(res.result) do
      if r.uri and r.uri:match("^file:") then files[vim.uri_to_fname(r.uri)] = true end
    end
    return files
  end
  if pkg ~= target and pkg ~= "" then
    local pdir = pkg:gsub("%.", "/")
    local use_roots = {}
    for _, r in ipairs(roots) do
      if not (src_root:match("/src/main/java$") and r:match("/src/test/java$")) then use_roots[#use_roots + 1] = r end
    end
    local pkg_label = pkg
    -- what the moved class uses from the old package
    for _, f in ipairs(package_files(use_roots, pdir)) do
      if f ~= path then
        local ff = type_facts(f)
        local ftxt
        if ff.kind and not ff.public and has_word(mtxt, ff.name) then
          add(("%s uses %s, a package-private %s of %s (not visible from %s)"):format(name, ff.name, ff.kind or "type", pkg_label, target))
        elseif ff.public or ff.kind then
          for _, m in ipairs(ff.members) do
            if (m.vis == "package" or m.vis == "protected") and has_word(mtxt, m.name)
                and not (m.vis == "protected" and vim.iter(mfacts.extends):any(function(e) return e:find(word(ff.name)) end)) then
              ftxt = ftxt or true
              local got = refs(f, m.line, m.col)
              if got == nil or got[path] then
                add(("%s uses %s%s of %s, which is %s (not visible from %s)%s"):format(name, m.name, ff.kind == "interface" and "" or "()", ff.name,
                  m.vis == "protected" and "protected" or "package-private", target, got == nil and " [possible: jdt.ls gave no answer]" or ""))
              end
            end
          end
        end
      end
    end
    -- what the old package's other classes use from the moved class
    local others = {}
    for _, f in ipairs(package_files(roots, pdir)) do
      if f ~= path then others[#others + 1] = { path = f, txt = blank_code(table.concat(lines_of(f), "\n")) } end
    end
    if not mfacts.public then
      for _, o in ipairs(others) do
        if has_word(o.txt, name) then
          add(("%s is package-private and %s (%s) uses it (not visible from %s)"):format(name, vim.fs.basename(o.path):sub(1, -6), pkg_label, target))
        end
      end
    end
    for _, m in ipairs(mfacts.members) do
      if m.vis == "package" or m.vis == "protected" then
        local cand = vim.tbl_filter(function(o)
          return has_word(o.txt, m.name) and not (m.vis == "protected" and o.txt:find("extends%s+" .. word(name)))
        end, others)
        if #cand > 0 then
          local got = refs(path, m.line, m.col)
          if got == nil then
            add(("%s() of %s is %s and may be used by %s (not visible from %s) [possible: jdt.ls gave no answer]"):format(m.name, name,
              m.vis == "protected" and "protected" or "package-private", vim.fs.basename(cand[1].path):sub(1, -6), target))
          else
            for _, o in ipairs(cand) do
              if got[o.path] then
                add(("%s%s of %s is %s and %s (%s) uses it (not visible from %s)"):format(m.name, "()", name,
                  m.vis == "protected" and "protected" or "package-private", vim.fs.basename(o.path):sub(1, -6), pkg_label, target))
              end
            end
          end
        end
      end
    end
  end
  -- across source roots
  if troot ~= src_root then
    if troot:match("/src/test/java$") and src_root:match("/src/main/java$") then
      for _, r in ipairs(roots) do
        if r:match("/src/main/java$") then
          for n2, kind in vim.fs.dir(r, { depth = 32 }) do
            if kind == "file" and n2:match("%.java$") and r .. "/" .. n2 ~= path
                and has_word(blank_code(table.concat(lines_of(r .. "/" .. n2), "\n")), name) then
              add(("main code would depend on test code: %s uses %s, which moves to %s"):format(rel(r .. "/" .. n2, project), name, rel(troot, project)))
            end
          end
        end
      end
    elseif troot:match("/src/main/java$") and src_root:match("/src/test/java$") then
      for _, l in ipairs(lines_of(path)) do
        if l:match("^%s*import%s+static%s+org%.junit") or l:match("^%s*import%s+org%.junit") or l:match("^%s*import%s+org%.testng")
            or l:match("^%s*import%s+org%.mockito") or l:match("^%s*import%s+org%.assertj") or l:match("^%s*import%s+org%.hamcrest")
            or l:match("^%s*import%s+org%.springframework%.boot%.test") or l:match("^%s*import%s+org%.springframework%.test") then
          add(("%s uses test libraries (%s) that are not on the main classpath"):format(name, vim.trim(l):gsub("^import%s+static%s+", ""):gsub("^import%s+", ""):gsub(";.*", "")))
          break
        end
      end
    end
  end
  return out, requests
end

--- Moves the class at the cursor (the file's own top-level type) to package opts.package (picked with
--- vim.ui.select / vim.ui.input when missing) of this source root, or of opts.root ("main", "test", another
--- `src/<set>/java` name, or its absolute path): the file moves to that package's folder (created when
--- missing), its `package` line and every import/reference updated by jdt.ls, touched files written (unsaved
--- ones left unsaved), the buffer re-pointed (undo kept), a summary shown. With the cursor on a reference to
--- another class of the project (textDocument/definition resolves it to another file), that class moves, as
--- in IntelliJ; a library class is refused. Before the move, conflicts (package-private members used across
--- the package border, main code depending on test code, see M._move_conflicts) are listed and the user is
--- asked (vim.ui.select); opts.force = true moves without asking (the conflicts stay in the summary).
--- Refused with nothing changed: invalid package, same package and root (a message), a class of that name
--- already in the target package (any source root), cursor in a nested/second type. opts.on_done(ok) afterwards.
--- Returns ok (nil while prompting).
function M.move(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  local function done(ok)
    if opts.on_done then opts.on_done(ok) end
    return ok
  end
  local function refuse(msg, level)
    notify("Move class: " .. msg, level or vim.log.levels.WARN)
    return done(false)
  end
  if busy then return refuse(busy_msg() .. "; nothing changed") end
  local client = jdtls_for(path)
  if not client or #vim.lsp.get_clients({ bufnr = buf, name = "jdtls" }) == 0 then
    return refuse("jdt.ls is not attached to this buffer")
  end
  local src_root, pkg = src_root_of(vim.fs.dirname(path))
  if not (path:match("%.java$") and src_root) then
    return refuse("this file is not a .java file in a source root (src/<set>/java)")
  end
  local project = require("nv4j.root").project(path)
  -- the cursor on a reference to another class: that class moves (IntelliJ F6); a library class is refused
  local name, why
  local cword = vim.fn.expand("<cword>")
  local cur = vim.api.nvim_win_get_cursor(0)
  local at = (vim.api.nvim_get_current_line():sub(cur[2] + 1, cur[2] + 1))
  if cword:match("^%u[%w_$]*$") and cword:match("%l") and at:match("[%w_$]") and cword ~= vim.fn.fnamemodify(path, ":t:r") then
    local res = client:request_sync("textDocument/definition", { textDocument = { uri = vim.uri_from_bufnr(buf) },
      position = { line = cur[1] - 1, character = cur[2] } }, M.symbols_timeout_ms, buf)
    local loc = res and res.result
    if type(loc) == "table" and loc.uri == nil and loc.targetUri == nil then loc = loc[1] end
    local uri = type(loc) == "table" and (loc.uri or loc.targetUri)
    if uri and uri ~= vim.uri_from_bufnr(buf) then
      if uri:sub(1, 5) ~= "file:" then
        return refuse(("%s is a library class (%s); only classes of this project can be moved; nothing changed"):format(cword, uri:match("^(%a+):") or "jar"))
      end
      local rp = vim.fs.normalize(vim.uri_to_fname(uri))
      local rsr = rp:match("%.java$") and src_root_of(vim.fs.dirname(rp))
      if not (rsr and under(rp, project)) then
        return refuse(("%s is declared outside this project's source roots (%s); only classes of this project can be moved; nothing changed"):format(cword, rp))
      end
      if vim.fn.fnamemodify(rp, ":t:r") ~= cword or not declares_own_type(rp) then
        return refuse(("%s is not a top-level class of its own file (%s): only those move; nothing changed"):format(cword, rel(rp, project)))
      end
      path, name = rp, cword
      src_root, pkg = src_root_of(vim.fs.dirname(path))
    end
  end
  local symbols_ms = 0
  if not name then
    local t_sym = vim.uv.hrtime()
    name, why = movable_type(buf, client, path)
    symbols_ms = (vim.uv.hrtime() - t_sym) / 1e6
    if not name then return refuse(why .. "; nothing changed") end
  end
  local modroot = module_root(path)
  local roots = source_roots(modroot, src_root)
  local function root_named(spec)
    if spec == nil then return src_root end
    for _, r in ipairs(roots) do
      if r == spec or r:match("/src/" .. vim.pesc(spec) .. "/java$") then return r end
    end
  end
  local function run(target, troot)
    if target == nil then return done(false) end -- cancelled
    target = vim.trim(target)
    if target == "" then return done(false) end
    troot = troot or root_named(opts.root)
    if not troot then
      return refuse(("'%s' is not a source root of this module (%s); nothing changed"):format(tostring(opts.root),
        table.concat(vim.tbl_map(function(r) return rel(r, modroot) end, roots), ", ")), vim.log.levels.ERROR)
    end
    for _, part in ipairs(vim.split(target, ".", { plain = true })) do
      if not valid_identifier(part) then
        return refuse(("'%s' is not a valid package name; nothing changed"):format(target), vim.log.levels.ERROR)
      end
    end
    if target == pkg and troot == src_root then
      return refuse(("%s is already in package %s; nothing to do"):format(name, target), vim.log.levels.INFO)
    end
    local rel_to = target:gsub("%.", "/") .. "/" .. name .. ".java"
    for _, r in ipairs(roots) do
      if r .. "/" .. rel_to ~= path and vim.uv.fs_stat(r .. "/" .. rel_to) then
        return refuse(("%s.%s already exists (%s); nothing changed, nothing overwritten"):format(target, name,
          rel(r .. "/" .. rel_to, project)), vim.log.levels.ERROR)
      end
    end
    local to = troot .. "/" .. rel_to
    local function proceed(conflicts)
      -- the target package's folder (and parents) when missing; jdt.ls is told so it can compute the move
      local created, d = {}, vim.fs.dirname(to)
      while not vim.uv.fs_stat(d) do
        table.insert(created, 1, d)
        d = vim.fs.dirname(d)
      end
      for _, dir in ipairs(created) do
        if not vim.uv.fs_mkdir(dir, 493) then
          for j = #created, 1, -1 do vim.uv.fs_rmdir(created[j]) end
          return refuse(("could not create %s; nothing changed"):format(rel(dir, project)), vim.log.levels.ERROR)
        end
      end
      if #created > 0 then
        client:notify("workspace/didChangeWatchedFiles", { changes = vim.tbl_map(function(p)
          return { uri = vim.uri_from_fname(p), type = 1 }
        end, created) })
      end
      -- notes: the class's test stays where it is (jdt.ls moves the one file); Spring component scanning
      local info, warn = {}, {}
      if troot ~= src_root then
        info[#info + 1] = ("moved from %s to %s"):format(rel(src_root, modroot), rel(troot, modroot))
      end
      if #created > 0 then
        info[#info + 1] = ("created package folder %s"):format(rel(created[#created], project))
      end
      if #conflicts > 0 then
        warn[#warn + 1] = ("conflicts accepted: %s"):format(table.concat(conflicts, "; "))
      end
      for _, r in ipairs(roots) do
        if r ~= src_root and troot == src_root then
          for _, suffix in ipairs({ "Test", "Tests", "IT" }) do
            local t = r .. "/" .. (pkg or ""):gsub("%.", "/") .. "/" .. name .. suffix .. ".java"
            if vim.uv.fs_stat(t) then
              info[#info + 1] = ("%s stays in package %s (only %s moves; move it too with <leader>jm to keep them together)"):format(
                rel(t, project), pkg ~= "" and pkg or "(default)", name)
            end
          end
        end
      end
      local sw = troot:match("/src/main/java$") and spring_scan_warning(path, modroot, name, target)
      if sw then warn[#warn + 1] = sw end
      local label = ("Moved class %s to package %s"):format(name, target)
      local ok = M.rename_paths({ { path, to } }, label, client,
        { stale = target ~= pkg and { names = move_names(name, pkg), old = (pkg ~= "" and (pkg .. ".") or "") .. name } or nil,
          info = info, warn = warn, same_package = target == pkg or nil })
      if not ok then
        -- nothing moved (or part-way): the folders made for it go when empty
        local gone = {}
        for j = #created, 1, -1 do
          if vim.uv.fs_rmdir(created[j]) then gone[#gone + 1] = { uri = vim.uri_from_fname(created[j]), type = 3 } end
        end
        if #gone > 0 then client:notify("workspace/didChangeWatchedFiles", { changes = gone }) end
      elseif M.last then
        if M.undo_op then M.undo_op.created = created end
        M.last.created, M.last.symbols_ms, M.last.conflicts = created, symbols_ms, conflicts
      end
      return done(ok)
    end
    local t_conf = vim.uv.hrtime()
    local conflicts, requests = M._move_conflicts(client, buf, path, pkg, src_root, target, troot, roots)
    M.last_conflict_check = { ms = (vim.uv.hrtime() - t_conf) / 1e6, requests = requests, conflicts = conflicts }
    if #conflicts == 0 then return proceed(conflicts) end
    local text = ("Move class %s to %s%s: %d conflict(s): %s"):format(name, target,
      troot ~= src_root and (" (" .. rel(troot, modroot) .. ")") or "", #conflicts, table.concat(conflicts, "; "))
    if opts.force then
      notify(text .. ". Moving anyway (force)", vim.log.levels.WARN)
      return proceed(conflicts)
    end
    notify(text, vim.log.levels.WARN)
    vim.ui.select({ "Move anyway", "Cancel" }, { prompt = ("%d conflict(s) moving %s to %s (listed above): move anyway?"):format(#conflicts, name, target) },
      function(choice)
        if choice ~= "Move anyway" then
          M.last = { label = "Move class " .. name, files = {}, ok = false, err = "cancelled", conflicts = conflicts }
          return refuse(("cancelled by you because of %d conflict(s); nothing changed"):format(#conflicts), vim.log.levels.INFO)
        end
        return proceed(conflicts)
      end)
  end
  if opts.package then return run(opts.package) end
  local NEW = "New package..."
  local pick, items = {}, {}
  for _, r in ipairs(roots) do
    local tag = r == src_root and "" or ("  [" .. rel(r, modroot) .. "]")
    for _, p in ipairs(project_packages({ r })) do
      if not (p == pkg and r == src_root) then
        local label = p .. tag
        items[#items + 1] = label
        pick[label] = { p, r }
      end
    end
  end
  items[#items + 1] = NEW
  for _, r in ipairs(roots) do
    if r ~= src_root then
      local label = ("New package in %s..."):format(rel(r, modroot))
      items[#items + 1] = label
      pick[label] = { nil, r }
    end
  end
  vim.ui.select(items, { prompt = ("Move class %s (package %s) to:"):format(name, pkg ~= "" and pkg or "(default)") }, function(choice)
    if choice == nil then return done(false) end
    local pk = pick[choice]
    local function typed(r)
      vim.ui.input({ prompt = ("Move class %s to package: "):format(name), default = pkg }, function(v) run(v, r) end)
    end
    if choice == NEW then typed(src_root)
    elseif pk and pk[1] == nil then typed(pk[2])
    elseif pk then run(pk[1], pk[2])
    else run(choice) end
  end)
end

-- ── inline a method call, local variable or constant (Task 4c) ──────────────────────────────────
--
-- jdt.ls's own code actions (RefactorProcessor.getInlineProposal, kind `refactor.inline`): "Inline
-- Method", "Inline local variable", "Inline Constant". "Make Static" has the same kind (filtered out by
-- title). The edit comes from `codeAction/resolve`; it is applied through apply() like a rename (touched
-- buffers written unless they had unsaved changes, summary, 3 s follow-up). What gets inlined is
-- jdt.ls's choice by cursor position (measured, trial t4c-a): on a call or a constant reference, that
-- occurrence only (the declaration stays); on the method/constant declaration, every occurrence and the
-- declaration removed; a local variable, every use and its declaration (from the declaration or a use).
-- opts.all = true on a call/reference asks jdt.ls at the declaration instead (textDocument/definition):
-- all occurrences, declaration removed. jdt.ls offers one inline action per position; if it ever offers
-- several (e.g. "Inline all"/"Inline this"), opts.all picks by title, else the user picks.

--- "method" / "variable" / "constant" for an inline action's title ("Inline Method", "Inline local
--- variable", "Inline Constant"; any "Inline ..." naming one of them), else nil ("Make Static").
local function inline_kind(title)
  local t = (title or ""):lower()
  if not t:match("^inline%f[^%a]") then return nil end
  if t:find("local variable", 1, true) or t:find("variable", 1, true) then return "variable" end
  if t:find("method", 1, true) then return "method" end
  if t:find("constant", 1, true) then return "constant" end
end
M.inline_ms = REQUEST_MS -- per jdt.ls request (code actions, definition, resolve)

local function cursor_diags(buf, l)
  return vim.lsp.diagnostic.from(vim.tbl_filter(function(d) return d.lnum <= l and d.end_lnum >= l end, vim.diagnostic.get(buf)))
end

--- Inline actions jdt.ls offers at (uri, l, c): list, or nil, reason.
local function inline_actions(client, buf, uri, l, c)
  local res, rerr = client:request_sync("textDocument/codeAction", {
    textDocument = { uri = uri },
    range = { start = { line = l, character = c }, ["end"] = { line = l, character = c } },
    context = { diagnostics = uri == vim.uri_from_bufnr(buf) and cursor_diags(buf, l) or {}, only = { "refactor.inline" }, triggerKind = 1 },
  }, M.inline_ms, buf)
  if not res then return nil, ("jdt.ls did not answer the code action request in %d ms (%s)"):format(M.inline_ms, tostring(rerr)) end
  if res.err then return nil, ("jdt.ls refused the code action request (%s)"):format(res.err.message or vim.inspect(res.err)) end
  local out = {}
  for _, a in ipairs(res.result or {}) do
    -- jdt.ls ignores `only` for some kinds (extract, move...): kind and title both checked
    if a.kind == "refactor.inline" and inline_kind(a.title) then out[#out + 1] = a end
  end
  return out
end

--- The edit of an inline action: edit, or false (jdt.ls gave none), or nil, reason (error/timeout).
local function inline_edit(client, buf, a)
  local edit = a.edit
  if not edit then
    if not a.data then
      return nil, a.command and ("jdt.ls answered with a command (%s), not an edit"):format(tostring(a.command.command))
        or "jdt.ls's action has neither an edit nor data to resolve"
    end
    local res, rerr = client:request_sync("codeAction/resolve", a, M.inline_ms, buf)
    if not res then return nil, ("jdt.ls did not resolve %s in %d ms (%s)"):format(a.title, M.inline_ms, tostring(rerr)) end
    if res.err then return nil, ("jdt.ls refused (%s)"):format(res.err.message or vim.inspect(res.err)) end
    edit = res.result and res.result.edit
  end
  if type(edit) ~= "table" then return false end
  local n = #(edit.documentChanges or {})
  for _, e in pairs(edit.changes or {}) do n = n + #e end
  return n > 0 and edit or false
end

--- Declaration of the symbol at (l, c): { uri, path, l, c, range }, or nil, reason.
local function declaration(client, buf, l, c)
  local res, rerr = client:request_sync("textDocument/definition",
    { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = l, character = c } }, M.inline_ms, buf)
  if not res then return nil, ("jdt.ls did not answer the definition request in %d ms (%s)"):format(M.inline_ms, tostring(rerr)) end
  if res.err then return nil, ("jdt.ls refused the definition request (%s)"):format(res.err.message or vim.inspect(res.err)) end
  local loc = res.result
  if type(loc) == "table" and not loc.uri and not loc.targetUri then loc = loc[1] end
  if type(loc) ~= "table" then return nil, "jdt.ls found no declaration" end
  local uri, range = loc.uri or loc.targetUri, loc.targetSelectionRange or loc.range
  return { uri = uri, path = uri:match("^file:") and vim.uri_to_fname(uri) or nil, l = range.start.line, c = range.start.character,
    range = range }
end

--- The first annotation matching Lua pattern `pat` (e.g. "@Bean%f[^%w_]") on the method declared at 0-based
--- line `l` of `lines` (annotation lines above it, or the same line); nil when there is none.
local function annotated(lines, l, pat)
  local hit = (lines[l + 1] or ""):match(pat)
  if hit then return hit end
  for i = l, math.max(1, l - 8), -1 do
    local s = lines[i] or ""
    hit = s:match(pat)
    if hit then return hit end
    if not (s:match("^%s*@") or s:match("^%s*$") or s:match("^%s*//") or s:match("^%s*%*") or s:match("^%s*/%*")) then return nil end
  end
end

--- `@Bean` on the method declared at 0-based line `l` of `lines`.
local function is_bean(lines, l)
  return annotated(lines, l, "@Bean%f[^%w_]") ~= nil
end

--- jdt.ls's references to the symbol declared at (uri, l, c) in project files: { { path, l } }.
function references(client, buf, uri, l, c)
  local res = client:request_sync("textDocument/references", { textDocument = { uri = uri },
    position = { line = l, character = c }, context = { includeDeclaration = false } }, M.inline_ms, buf)
  local refs = {}
  for _, r in ipairs(res and type(res.result) == "table" and res.result or {}) do
    if r.uri and r.uri:match("^file:") then refs[#refs + 1] = { path = vim.uri_to_fname(r.uri), l = r.range.start.line } end
  end
  return refs
end

--- "file:line" of the references in files the edit did not touch (`files`: apply()'s list): occurrences
--- jdt.ls did not update (it skips a file it cannot parse).
function untouched_refs(refs, files, root)
  local touched, left, seen = {}, {}, {}
  for _, f in ipairs(files) do touched[f.path] = true end
  for _, r in ipairs(refs) do
    local at = ("%s:%d"):format(rel(r.path, root), r.l + 1)
    if not touched[r.path] and not seen[at] then left[#left + 1], seen[at] = at, true end -- one per line
  end
  return left
end

--- A declaration of method/constant `name` is still written in `lines` (after an inline: kept or removed).
local function still_declared(lines, name, kind)
  for _, s in ipairs(lines) do
    local pre = s:match("^(%s*[%w_$<>%[%],.?@%s]-)%f[%w_$]" .. vim.pesc(name) .. "%s*" .. (kind == "method" and "%(" or "="))
    if pre and pre:match("%S") and not pre:match("%f[%w]return%f[^%w]") and not pre:match("%.%s*$")
        and (kind == "method" or pre:match("%f[%w]final%f[^%w]")) then
      return true
    end
  end
  return false
end

--- Inlines the method call, local variable or constant at the cursor through jdt.ls (see above).
--- opts.all = true: every occurrence from a call/reference too. opts.on_done(ok) afterwards. Returns ok
--- (nil while the user picks between several inline actions).
function M.inline(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  local function done(ok)
    if opts.on_done then opts.on_done(ok) end
    return ok
  end
  local function refuse(msg, level)
    M.last = { label = "Inline", files = {}, ok = false, err = msg }
    notify("Inline: " .. msg, level or vim.log.levels.WARN)
    return done(false)
  end
  if busy then return refuse(busy_msg() .. "; nothing changed") end
  local client = jdtls_for(path)
  if not client or #vim.lsp.get_clients({ bufnr = buf, name = "jdtls" }) == 0 then
    return refuse("jdt.ls is not attached to this buffer")
  end
  local root = root_of(client)
  local cur = vim.api.nvim_win_get_cursor(0)
  local l, c = cur[1] - 1, cur[2]
  local name = vim.fn.expand("<cword>")
  local ms, t = {}, vim.uv.hrtime()
  local function lap(k)
    local n = vim.uv.hrtime()
    ms[k], t = (ms[k] or 0) + (n - t) / 1e6, n
  end
  local acts, aerr = inline_actions(client, buf, vim.uri_from_bufnr(buf), l, c)
  lap("actions")
  if not acts then return refuse(aerr .. "; nothing changed", vim.log.levels.ERROR) end
  if #acts == 0 then
    return refuse(("nothing to inline at `%s`: jdt.ls inlines a method (at a call or its declaration), a local variable, or a static final constant; not a parameter, a plain field (e.g. an @Value field), a type or a keyword; nothing changed"):format(name))
  end
  -- explicit: the action's own title says all/this (several inline actions offered): no retargeting
  local function run(a, explicit)
    if not a then return done(false) end -- cancelled
    local kind = inline_kind(a.title)
    local mode, decl, derr = "all", nil, nil
    if kind ~= "variable" then
      decl, derr = declaration(client, buf, l, c)
      lap("definition")
      local here = decl and decl.uri == vim.uri_from_bufnr(buf) and contains(decl.range, l, c)
      mode = here and "all" or (decl and "this" or "?")
      local t = a.title:lower()
      if explicit and (t:find("%f[%a]all%f[^%a]") or t:find("%f[%a]this%f[^%a]")) then
        mode = t:find("%f[%a]all%f[^%a]") and "all" or "this"
      elseif opts.all and not here then
        if not decl then return refuse(("cannot inline every occurrence of `%s`: %s; nothing changed"):format(name, derr), vim.log.levels.ERROR) end
        if not decl.path or not (root and under(decl.path, root)) then
          return refuse(("cannot inline every occurrence of `%s`: its declaration is not in this project (%s); jdt.ls inlines all occurrences only from a declaration it can edit; nothing changed"):format(
            name, decl.path or decl.uri))
        end
        local at, err2 = inline_actions(client, buf, decl.uri, decl.l, decl.c)
        lap("actions")
        if not at then return refuse(err2 .. "; nothing changed", vim.log.levels.ERROR) end
        local same = vim.iter(at):find(function(x) return inline_kind(x.title) == kind end)
        if not same then
          return refuse(("jdt.ls offers no %s at the declaration of `%s` (%s); nothing changed"):format(a.title, name, rel(decl.path, root)))
        end
        a, mode = same, "all"
      end
    end
    local edit, eerr = inline_edit(client, buf, a)
    lap("resolve")
    if edit == nil then return refuse(("%s at `%s`: %s; nothing changed"):format(a.title, name, eerr), vim.log.levels.ERROR) end
    if edit == false then
      return refuse(("jdt.ls offered %s at `%s` but gave no edit: it does that when this inline is not possible (a recursive method, a body using members not visible at the call, a syntax error in the file); nothing changed"):format(
        a.title, name))
    end
    -- every occurrence: jdt.ls's own references, to name any it did not inline (a file it skipped)
    local refs = {}
    if mode == "all" and decl and kind ~= "variable" then
      refs = references(client, buf, decl.uri, decl.l, decl.c)
      lap("references")
    end
    -- Spring: a @Bean method is called through the @Configuration proxy (the container's bean, created once)
    local decl_lines = decl and decl.path and lines_of(decl.path)
    local bean = kind == "method" and decl_lines and is_bean(decl_lines, decl.l)
    local before = M.error_counts()
    local ok, files, why = apply(client, edit, dirty_buffers())
    lap("apply")
    local what = kind == "variable" and "local variable" or kind
    local label = ("Inlined %s %s"):format(what, name)
    if not ok then
      failed_part_way(label, why, files, root)
      return done(false)
    end
    local removed
    if kind == "variable" then
      label = label .. " (every use; declaration removed)"
    elseif mode == "all" then
      removed = not (decl and decl.path and still_declared(lines_of(decl.path), name, kind))
      label = label .. (" (every %s; declaration %s)"):format(kind == "method" and "call" or "reference", removed and "removed" or "kept")
    elseif mode == "this" then
      label = label .. (" (this %s only; declaration kept)"):format(kind == "method" and "call" or "reference")
    end
    local warn = {}
    local left = untouched_refs(refs, files, root)
    if #left > 0 then
      warn[#warn + 1] = ("NOT inlined by jdt.ls (it skips a file it cannot parse), still naming `%s`%s: %s"):format(name,
        removed and ", whose declaration is gone" or "", table.concat(left, ", "))
    end
    if bean then
      if mode == "all" and removed then
        warn[#warn + 1] = ("Spring: %s was a @Bean method and its declaration is gone: the bean `%s` is no longer defined; whatever injects it (by type or by name) fails at startup"):format(name, name)
      else
        warn[#warn + 1] = ("Spring: %s is a @Bean method: the inlined call returned the container's bean (one shared instance through the @Configuration proxy); the inlined code builds a new one each time"):format(name)
      end
    end
    M.last = { label = label, files = files, ok = true, kind = kind, mode = mode, title = a.title, removed = removed, bean = bean,
      left = left, ms = ms, warn = warn }
    notify(summary(label, files, root) .. (#warn > 0 and (". WARNING: " .. table.concat(warn, "; ")) or ""),
      #warn > 0 and vim.log.levels.WARN or nil)
    follow_up(label, before, vim.tbl_map(function(f) return f.path end, files))
    return done(true)
  end
  if #acts == 1 then return run(acts[1]) end
  -- several inline actions at one place (not seen with jdt.ls 1.62): opts.all picks by title, else the user
  if opts.all ~= nil then
    local want = opts.all and "all" or "this"
    local pick = vim.iter(acts):find(function(x) return x.title:lower():find("%f[%a]" .. want .. "%f[^%a]") ~= nil end)
    if pick then return run(pick, true) end
  end
  vim.ui.select(acts, { prompt = ("Inline `%s`:"):format(name), format_item = function(x) return x.title end },
    function(x) run(x, true) end)
end

-- ── change a method's signature (Task 4d) ────────────────────────────────────────────────────────
--
-- jdt.ls's own engine (Eclipse's ChangeSignatureProcessor) without nvim-jdtls's float: the method's
-- signature from `java/getChangeSignatureInfo` (asked at the declaration: jdt.ls answers only on the
-- declaration header, so on a call the declaration is found first with textDocument/definition), the new
-- one built here from opts (or from a typed signature), the edit from `java/getRefactorEdit` command
-- "changeSignature", applied through apply() like every refactor here (touched files written unless they
-- had unsaved changes, summary, follow-up). Supported (all that jdt.ls's request takes, except two):
-- parameters added (with the default value the call sites pass), removed, renamed, retyped, reordered;
-- the method's name, return type and visibility. Not exposed: the exceptions (`throws` is kept as it is)
-- and the "keep the old signature as a deprecated delegate" switch. Refused before jdt.ls is asked (own
-- checks, nothing changed): cursor not on a method declaration or call, invalid name/type, missing
-- default, duplicate parameter name, a removed parameter still used in the body, a new name already used
-- in the body (local, field: it would clash or shadow), varargs not last, a constructor renamed or given
-- a return type. jdt.ls's own refusals (an implementation of an interface/superclass method: change it
-- at the declaration it implements; a method of a library type; an invalid default expression) are shown
-- with its message. A method that others implement/override: jdt.ls changes all of them (named in the
-- summary). After the edit the touched open files are revalidated (`java/validateDocument`): jdt.ls
-- otherwise keeps a dependent file's diagnostics from before the declaration changed.

M.signature_ms = 10000 -- getRefactorEdit: about 0.4 s; a method with implementations takes jdt.ls 2.6-3.9 s (hierarchy search); hard timeout

local PRIMITIVES = { boolean = true, byte = true, char = true, short = true, int = true, long = true, float = true, double = true }
local VISIBILITY = { public = true, protected = true, private = true, package = true }
local VIS_RANK = { private = 0, package = 1, protected = 2, public = 3 }
local OPT_KEYS = { add = true, remove = true, rename = true, retype = true, reorder = true, name = true, returns = true,
  visibility = true, signature = true, on_done = true, async = true }

--- `src` with string/char literal contents and comments replaced by spaces (same length, newlines kept).
local function blank(src)
  local function sp(s) return (s:gsub("[^\n]", " ")) end
  return (src:gsub('"""(.-)"""', function(x) return '"""' .. sp(x) .. '"""' end)
    :gsub('"[^"\n]*"', function(x) return '"' .. sp(x:sub(2, -2)) .. '"' end)
    :gsub("'[^'\n]*'", function(x) return "'" .. sp(x:sub(2, -2)) .. "'" end)
    :gsub("/%*.-%*/", sp):gsub("//[^\n]*", sp))
end

--- A Java type as written in a parameter or return type: dotted names, generics (`? extends`/`? super`),
--- arrays, varargs (`...` when `varargs`), primitives (`void` when `void_ok`). No annotations.
local function valid_type(t, varargs, void_ok)
  t = vim.trim(t or "")
  if t == "" or t:find("@", 1, true) then return false end
  if void_ok and t == "void" then return true end
  if varargs then t = t:gsub("%s*%.%.%.$", "") end
  local s = t:gsub("%?%s+extends%s+", "?+"):gsub("%?%s+super%s+", "?-"):gsub("%s*([<>,%[%]?])%s*", "%1")
  if s:find("%s") or not s:match("^[%a_$]") or not s:match("^[%w_$.<>,%[%]?+%-]+$") then return false end
  if s:find("%.%.") or s:find("%.$") or s:find("%.[^%a_$]") then return false end
  local depth = 0
  for ch in s:gmatch("[<>]") do
    depth = depth + (ch == "<" and 1 or -1)
    if depth < 0 then return false end
  end
  if depth ~= 0 or s:find("%[[^%]]") or s:find("%[$") or s:find("[^%[]%]") or s:find("%]%a") then return false end
  for seg in s:gmatch("[%w_$]+") do
    if not (valid_identifier(seg) or PRIMITIVES[seg]) then return false end
  end
  return true
end

--- Splits `s` at top-level commas (outside () [] {} <> and quotes; `<`/`>` count only before a piece's
--- `=`, so a default like `a < b` does not open a generic).
local function split_params(s)
  local out, cur, depth, angle, q, eq, esc = {}, {}, 0, 0, nil, false, false
  for ch in s:gmatch(".") do
    local cut = false
    if q then
      if esc then esc = false elseif ch == "\\" then esc = true elseif ch == q then q = nil end
    elseif ch == '"' or ch == "'" then q = ch
    elseif ch:match("[%(%[{]") then depth = depth + 1
    elseif ch:match("[%)%]}]") then depth = depth - 1
    elseif ch == "<" and not eq then angle = angle + 1
    elseif ch == ">" and not eq then angle = angle - 1
    elseif ch == "=" and depth == 0 and angle == 0 then eq = true
    elseif ch == "," and depth == 0 and angle == 0 then cut = true
    end
    if cut then
      out[#out + 1] = table.concat(cur)
      cur, eq = {}, false
    else
      cur[#cur + 1] = ch
    end
  end
  out[#out + 1] = table.concat(cur)
  if #out == 1 and vim.trim(out[1]) == "" then return {} end
  return out
end

--- `Type name` or `Type name = default`: { type, name, default? }, or nil, reason.
local function parse_param(piece)
  piece = vim.trim(piece)
  local left, right = piece, nil
  local depth, angle = 0, 0
  for i = 1, #piece do
    local ch = piece:sub(i, i)
    if ch:match("[%(%[{]") then depth = depth + 1
    elseif ch:match("[%)%]}]") then depth = depth - 1
    elseif ch == "<" then angle = angle + 1
    elseif ch == ">" then angle = angle - 1
    elseif ch == "=" and depth == 0 and angle == 0 then
      left, right = vim.trim(piece:sub(1, i - 1)), vim.trim(piece:sub(i + 1))
      break
    end
  end
  if piece == "" then return nil, "an empty parameter (two commas in a row?)" end
  local name = left:match("([%a_$][%w_$]*)$")
  local typ = name and vim.trim(left:sub(1, #left - #name)) or ""
  if not name or typ == "" then return nil, ("`%s` is not `Type name` or `Type name = default`"):format(piece) end
  if right == "" then return nil, ("`%s`: the default value after `=` is empty"):format(piece) end
  return { type = typ, name = name, default = right }
end

local function vis_of(info)
  return (info.modifier == nil or info.modifier == "") and "package" or info.modifier
end

local function param_text(p) return p.type .. " " .. p.name end

--- `name(Type a, Type b)` (with ` = default` for added parameters when `defaults`).
local function sig_text(name, params, defaults)
  return name .. "(" .. table.concat(vim.tbl_map(function(p)
    return param_text(p) .. ((defaults and p.orig == nil and p.default) and (" = " .. p.default) or "")
  end, params), ", ") .. ")"
end

--- The signature as the prompt shows it: `public int total(Invoice invoice)` (no return type for a constructor).
local function sig_form(info, ctor)
  local vis = vis_of(info)
  return (vis ~= "package" and (vis .. " ") or "") .. (ctor and "" or (info.returnType .. " "))
    .. sig_text(info.methodName, vim.tbl_map(function(p) return { type = p.type, name = p.name } end, info.parameters))
end

--- The new signature from a typed form (`[visibility] [return type] name(Type a, Type b = default)`):
--- parameters match the old ones by name (a different type retypes it); a new name with `= default` is
--- added; a new name without a default takes the place of the old parameter at the same position whose
--- name is gone (a rename). Returns spec, or nil, reason.
local function spec_from_form(info, s, ctor)
  s = vim.trim(s or "")
  local open = s:find("(", 1, true)
  local close = s:match(".*()%)")
  if not open or not close or close < open then
    return nil, "write it as `[visibility] [return type] name(Type name, Type name = default)`"
  end
  if vim.trim(s:sub(close + 1)) ~= "" then return nil, ("`%s` after `)`: only the part up to `)` can change (throws is kept)"):format(vim.trim(s:sub(close + 1))) end
  local head = vim.trim(s:sub(1, open - 1))
  local name = head:match("([%a_$][%w_$]*)$")
  if not name then return nil, "no method name before `(`" end
  local rest = vim.trim(head:sub(1, #head - #name))
  local vis = "package"
  local first = rest:match("^(%a+)%f[^%w_$]")
  if first and VISIBILITY[first] then vis, rest = first, vim.trim(rest:sub(#first + 1)) end
  local other = rest:match("^(%a+)%f[^%w_$]")
  if other and (other == "static" or other == "final" or other == "abstract" or other == "synchronized" or other == "default" or other == "native") then
    return nil, ("`%s` cannot be changed here (only visibility, return type, name and parameters); leave it out"):format(other)
  end
  local spec = { name = name, visibility = vis, returns = ctor and info.returnType or rest, params = {} }
  if ctor and rest ~= "" then return nil, ("a constructor has no return type (`%s`)"):format(rest) end
  local by_name, used = {}, {}
  for _, p in ipairs(info.parameters) do by_name[p.name] = p end
  local parsed = {}
  for _, piece in ipairs(split_params(s:sub(open + 1, close - 1))) do
    local p, err = parse_param(piece)
    if not p then return nil, err end
    parsed[#parsed + 1] = p
    if by_name[p.name] and not p.default then used[p.name] = true end
  end
  for i, p in ipairs(parsed) do
    local old = (not p.default) and by_name[p.name]
    if not old and not p.default then
      -- a rename: the old parameter at this position, if its name is gone from the form
      local at = info.parameters[i]
      if at and not used[at.name] and at.type ~= p.type then
        -- ambiguous: a rename + retype, or a new parameter without its default in place of a removed one
        return nil, ("`%s %s` takes the place of `%s %s` with another type: say what you mean: a new parameter needs `= default` (`%s %s = value`), a rename/retype or removal needs the explicit options (rename = { %s = \"%s\" }, retype, remove)"):format(
          p.type, p.name, at.type, at.name, p.type, p.name, at.name, p.name)
      elseif at and not used[at.name] then
        old, used[at.name] = at, true
      else
        return nil, ("new parameter `%s` needs a default value for the call sites: `%s %s = value`"):format(p.name, p.type, p.name)
      end
    end
    spec.params[i] = { type = p.type, name = p.name, default = old and nil or p.default, orig = old and old.originalIndex or nil }
  end
  return spec
end

local function field(x, k, i)
  if type(x) ~= "table" then return nil end
  local v = x[k]
  if v == nil then v = x[i] end
  return v ~= nil and tostring(v) or nil
end

--- The new signature from opts (add/remove/rename/retype/reorder/name/returns/visibility). spec or nil, reason.
local function spec_from_opts(info, opts)
  for k in pairs(opts) do
    if not OPT_KEYS[k] then return nil, ("unknown option `%s` (known: add, remove, rename, retype, reorder, name, returns, visibility, signature)"):format(tostring(k)) end
  end
  local params = {}
  for _, p in ipairs(info.parameters) do params[#params + 1] = { type = p.type, name = p.name, orig = p.originalIndex } end
  local function find(name)
    for i, p in ipairs(params) do
      if p.name == name then return i end
    end
  end
  -- remove: names or 1-based positions in the method's current parameter list
  local drop = {}
  for _, r in ipairs(opts.remove or {}) do
    local i = type(r) == "number" and r or nil
    if i then
      if not info.parameters[i] then return nil, ("remove: there is no parameter %d (the method has %d)"):format(i, #info.parameters) end
      drop[info.parameters[i].name] = true
    elseif type(r) == "string" and find(r) then
      drop[r] = true
    else
      return nil, ("remove: no parameter `%s`"):format(tostring(r))
    end
  end
  params = vim.tbl_filter(function(p) return not drop[p.name] end, params)
  for old, t in pairs(opts.retype or {}) do
    local i = find(old)
    if not i then return nil, ("retype: no parameter `%s`"):format(tostring(old)) end
    params[i].type = tostring(t)
  end
  local renamed = {}
  for old, new in pairs(opts.rename or {}) do
    local i = find(old)
    if not i then return nil, ("rename: no parameter `%s`"):format(tostring(old)) end
    renamed[i] = tostring(new)
  end
  for i, new in pairs(renamed) do params[i].name = new end
  for _, a in ipairs(opts.add or {}) do
    local p = { type = field(a, "type", 1), name = field(a, "name", 2), default = field(a, "default", 3) }
    if not p.type or not p.name then return nil, "add: each new parameter needs a type and a name: { type = \"int\", name = \"discount\", default = \"0\" }" end
    local at = tonumber(field(a, "at", 4))
    if at then
      if at < 1 or at > #params + 1 then return nil, ("add: position %d is outside 1..%d"):format(at, #params + 1) end
      table.insert(params, at, p)
    elseif #params > 0 and params[#params].type:match("%.%.%.$") then
      table.insert(params, #params, p) -- before a trailing varargs parameter (Java allows nothing after it)
    else
      params[#params + 1] = p
    end
  end
  if opts.reorder then
    local order, seen = {}, {}
    for _, n in ipairs(opts.reorder) do
      local i = find(n)
      if not i or seen[n] then
        return nil, ("reorder: `%s` is not a parameter of the new signature (or named twice); list every one: %s"):format(tostring(n),
          table.concat(vim.tbl_map(function(p) return p.name end, params), ", "))
      end
      seen[n] = true
      order[#order + 1] = params[i]
    end
    if #order ~= #params then
      return nil, ("reorder: list every parameter of the new signature once (%s)"):format(table.concat(vim.tbl_map(function(p) return p.name end, params), ", "))
    end
    params = order
  end
  return { name = opts.name or info.methodName, visibility = opts.visibility or vis_of(info), returns = opts.returns or info.returnType, params = params }
end

M._spec_from_form, M._spec_from_opts, M._valid_type, M._split_params = spec_from_form, spec_from_opts, valid_type, split_params -- checks

--- Identifiers used in the body of the method declared at 0-based line `l` (not after a `.`), from the
--- text; {} for a method without a body (abstract, interface).
local function body_identifiers(lines, l, name)
  local src = blank(table.concat(lines, "\n"))
  local off = 1
  for _ = 1, l do off = (src:find("\n", off, true) or #src) + 1 end
  local s = src:find("%f[%w_$]" .. vim.pesc(name) .. "%s*%(", off)
  if not s then return {} end
  local i, depth = src:find("(", s, true), 0
  while i and i <= #src do
    local ch = src:sub(i, i)
    if ch == "(" then depth = depth + 1 elseif ch == ")" then depth = depth - 1 end
    if depth == 0 then break end
    i = i + 1
  end
  if not i then return {} end
  local b = src:find("[{;]", i)
  if not b or src:sub(b, b) == ";" then return {} end
  local e = b
  depth = 0
  while e <= #src do
    local ch = src:sub(e, e)
    if ch == "{" then depth = depth + 1 elseif ch == "}" then depth = depth - 1 end
    if depth == 0 then break end
    e = e + 1
  end
  local out = {}
  local body = src:sub(b, e):gsub("%f[%w_$]%d[%w_$.]*", " ") -- number literals (10L, 1.5f)
  for pre, id in body:gmatch("([^%w_$]?)([%a_$][%w_$]*)") do
    if pre ~= "." then out[id] = true end
  end
  return out
end

--- Checks the new signature: nil when fine, else the reason.
local function check_spec(spec, info, ctor, body)
  if not valid_identifier(spec.name) then return ("`%s` is not a valid method name"):format(spec.name) end
  if ctor and spec.name ~= info.methodName then
    return ("a constructor keeps its class's name (%s); rename the class with <leader>jr"):format(info.methodName)
  end
  if not VISIBILITY[spec.visibility] then return ("visibility `%s`: use public, protected, private or package"):format(tostring(spec.visibility)) end
  if ctor and spec.returns ~= info.returnType then return "a constructor has no return type" end
  if not ctor and not valid_type(spec.returns, false, true) then return ("`%s` is not a valid return type"):format(spec.returns) end
  local seen = {}
  for i, p in ipairs(spec.params) do
    if not valid_identifier(p.name) then return ("`%s` is not a valid parameter name"):format(p.name) end
    if not valid_type(p.type, i == #spec.params, false) then
      return p.type:match("%.%.%.$") and ("`%s %s`: a varargs parameter must be the last one"):format(p.type, p.name)
        or ("`%s` is not a valid parameter type (annotations cannot be added here)"):format(p.type)
    end
    if seen[p.name] then return ("duplicate parameter name `%s`"):format(p.name) end
    seen[p.name] = true
    if p.orig == nil and (p.default == nil or vim.trim(p.default) == "") then
      return ("new parameter `%s %s` needs a default value: the call sites pass it"):format(p.type, p.name)
    end
  end
  local kept = {}
  for _, p in ipairs(spec.params) do
    if p.orig then kept[p.orig] = p end
  end
  for _, old in ipairs(info.parameters) do
    local now = kept[old.originalIndex]
    if not now and body[old.name] then
      return ("parameter `%s` is still used in the body of %s: removing it would not compile; remove its uses first"):format(old.name, info.methodName)
    end
  end
  for _, p in ipairs(spec.params) do
    local old = p.orig and info.parameters[p.orig + 1]
    if (not old or old.name ~= p.name) and body[p.name] then
      return ("`%s` is already used in the body of %s (a local variable or a field): the parameter would clash with it or hide it; pick another name"):format(
        p.name, info.methodName)
    end
  end
end

--- Changes nothing? (same name, visibility, return type, parameters in order with the same type/name).
local function unchanged(spec, info)
  if spec.name ~= info.methodName or spec.visibility ~= vis_of(info) or spec.returns ~= info.returnType then return false end
  if #spec.params ~= #info.parameters then return false end
  for i, p in ipairs(spec.params) do
    local o = info.parameters[i]
    if p.orig ~= o.originalIndex or p.type ~= o.type or p.name ~= o.name then return false end
  end
  return true
end

--- window/showMessage capture, shared per client: one wrapper is installed while at least one request
--- captures (each gets its own message list); the client's own handler is put back when the last ends.
local captures = {} -- client id -> { own, lists = { [list] = true }, n }

local function capture_start(client)
  local key = "window/showMessage"
  local c = captures[client.id]
  if not c then
    c = { own = rawget(client.handlers, key), lists = {}, n = 0 }
    captures[client.id] = c
    client.handlers[key] = function(err, result, ctx, cfg)
      if c.n > 0 and result and (result.type == 1 or result.type == 2) then
        for list in pairs(c.lists) do list[#list + 1] = result.message end
        return vim.NIL
      end
      local h = c.own or vim.lsp.handlers[key]
      return h and h(err, result, ctx, cfg)
    end
  end
  local msgs = {}
  c.lists[msgs], c.n = true, c.n + 1
  return msgs, function()
    if c.lists[msgs] then c.lists[msgs], c.n = nil, c.n - 1 end
    if c.n == 0 and captures[client.id] == c then
      client.handlers[key], captures[client.id] = c.own, nil
    end
  end
end

--- Asynchronous jdt.ls request with its window/showMessage errors/warnings captured until the answer
--- (jdt.ls reports a refused change signature that way and answers null): cb(res, rerr, messages) once,
--- res = { err?, result? }, or res = nil and rerr on a timeout after `ms`. Other messages go to the usual
--- handler.
local function request_capturing(client, method, params, ms, buf, cb)
  local msgs, stop = capture_start(client)
  local finished = false
  local function finish(res, rerr)
    if finished then return end
    finished = true
    stop()
    cb(res, rerr, msgs)
  end
  local ok, sent, id = pcall(client.request, client, method, params, function(err, result)
    finish({ err = err, result = result })
  end, buf)
  if not ok or not sent then return finish(nil, ok and "the request could not be sent" or tostring(sent)) end
  vim.defer_fn(function()
    if not finished then
      pcall(client.cancel_request, client, id)
      finish(nil, "timeout")
    end
  end, ms)
end

--- Fires a jdt.ls request now and returns a slot filled when it answers ({ done, result, ms }); wait(slot)
--- waits for it (at most M.inline_ms).
local function fire(client, method, params, buf)
  local slot, t0 = { done = false }, vim.uv.hrtime()
  local ok = pcall(client.request, client, method, params, function(_, result)
    slot.result, slot.done, slot.ms = result, true, (vim.uv.hrtime() - t0) / 1e6
  end, buf)
  if not ok then slot.done = true end
  return slot
end

local function wait(slot)
  if slot and not slot.done then vim.wait(M.inline_ms, function() return slot.done end, 5) end
  return slot and type(slot.result) == "table" and slot.result or {}
end

local function cs_params(uri, l, c)
  return { textDocument = { uri = uri }, range = { start = { line = l, character = c }, ["end"] = { line = l, character = c } },
    context = { diagnostics = {}, triggerKind = 1 } }
end

local function signature_info(client, buf, uri, l, c)
  local res, rerr = client:request_sync("java/getChangeSignatureInfo", cs_params(uri, l, c), M.inline_ms, buf)
  if not res then return nil, ("jdt.ls did not answer getChangeSignatureInfo in %d ms (%s)"):format(M.inline_ms, tostring(rerr)) end
  if res.err then return nil, ("jdt.ls refused getChangeSignatureInfo (%s)"):format(res.err.message or vim.inspect(res.err)) end
  return res.result or false
end

--- Asks jdt.ls to validate these open files again (it then publishes their diagnostics from the current
--- state of every open file). Returns the time (ms, hrtime) the request was sent.
function M.revalidate(client, paths)
  local t = vim.uv.hrtime() / 1e6
  for _, p in ipairs(paths) do
    local b = vim.fn.bufnr(p)
    if b ~= -1 and vim.api.nvim_buf_is_loaded(b) then
      client:notify("java/validateDocument", { textDocument = { uri = vim.uri_from_fname(p) } })
    end
  end
  return t
end

--- 0-based (l, c) of the method name `name` in its declaration header around the cursor line `l`.
local function header_name(lines, l, name)
  local pat = "%f[%w_$]" .. vim.pesc(name) .. "%s*%("
  local text = vim.split(blank(table.concat(lines, "\n")), "\n", { plain = true })
  for i = l + 1, math.max(1, l - 20), -1 do
    local c = (text[i] or ""):find(pat)
    if c then return i - 1, c - 1 end
  end
  for i = l + 2, math.min(#text, l + 10) do
    local c = (text[i] or ""):find(pat)
    if c then return i - 1, c - 1 end
  end
end

--- Changes the signature of the method at the cursor (on its declaration, or on a call of it):
--- opts.add = { { type, name, default, at? } } (default: what the call sites pass; at: 1-based position,
--- default the end, before a trailing varargs), opts.remove = { name or 1-based position }, opts.rename =
--- { old = "new" }, opts.retype = { name = "Type" }, opts.reorder = { names in the new order, all of
--- them }, opts.name, opts.returns, opts.visibility ("public"/"protected"/"private"/"package"), or
--- opts.signature = "public int total(Invoice invoice, int discount = 0)" (the prompt's form). Without
--- any of them the signature is asked with vim.ui.input in that form. opts.on_done(ok) afterwards.
--- Returns ok (nil while prompting).
function M.change_signature(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  local mine = false -- this call set `busy`: only it clears it
  local function done(ok)
    if mine then busy, mine = nil, false end
    if opts.on_done then opts.on_done(ok) end
    return ok
  end
  local function refuse(msg, level)
    M.last = { label = "Change signature", files = {}, ok = false, err = msg }
    notify("Change signature: " .. msg, level or vim.log.levels.WARN)
    return done(false)
  end
  if busy then return refuse(busy_msg() .. "; nothing changed") end
  local client = jdtls_for(path)
  if not client or #vim.lsp.get_clients({ bufnr = buf, name = "jdtls" }) == 0 then
    return refuse("jdt.ls is not attached to this buffer")
  end
  local root = root_of(client)
  local ms, t = {}, vim.uv.hrtime()
  local function lap(k)
    local n = vim.uv.hrtime()
    ms[k], t = (ms[k] or 0) + (n - t) / 1e6, n
  end
  local cur = vim.api.nvim_win_get_cursor(0)
  local l, c = cur[1] - 1, cur[2]
  local word = vim.fn.expand("<cword>")
  -- jdt.ls answers on the declaration header only (modifiers, return type, name, parameters)
  local uri = vim.uri_from_bufnr(buf)
  local info, ierr = signature_info(client, buf, uri, l, c)
  lap("info")
  if info == nil then return refuse(ierr .. "; nothing changed", vim.log.levels.ERROR) end
  local decl
  if info then
    decl = { uri = uri, path = path, lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false) }
    if info.methodName then decl.l, decl.c = header_name(decl.lines, l, info.methodName) end
  else
    -- on a call (`name(`, `new Name(`, `Type::name`): the called method, at its declaration
    local line = vim.api.nvim_get_current_line()
    local s, e = 1, nil
    repeat
      s, e = line:find(word, s, true)
      if s and c + 1 >= s and c + 1 <= e then break end
      if s then s = e + 1 end
    until not s
    local call = s and word:match("^[%a_$][%w_$]*$") and (line:sub(e + 1):match("^%s*%(") or line:sub(1, s - 1):match("::%s*$"))
    if not call then
      return refuse(("the cursor is not on a method: put it on a method's declaration (name, parameters, return type) or on a call of it (`%s` is neither); nothing changed"):format(word))
    end
    local d, derr = declaration(client, buf, l, c)
    lap("definition")
    if not d then return refuse(("cannot find the declaration of `%s`: %s; nothing changed"):format(word, derr)) end
    if not d.path or not (root and under(d.path, root)) then
      return refuse(("`%s` is declared outside this project (%s): only methods declared in the project's sources can change; nothing changed"):format(
        word, d.path or d.uri))
    end
    info, ierr = signature_info(client, buf, d.uri, d.l, d.c)
    lap("info")
    if info == nil then return refuse(ierr .. "; nothing changed", vim.log.levels.ERROR) end
    if not info then return refuse(("`%s` at %s:%d is not a method jdt.ls can change; nothing changed"):format(word, rel(d.path, root), d.l + 1)) end
    decl = { uri = d.uri, path = d.path, l = d.l, c = d.c, lines = lines_of(d.path) }
  end
  if not info then
    return refuse(("the cursor is not on a method: put it on a method's declaration (name, parameters, return type) or on a call of it; nothing changed"))
  end
  if info.errorMessage then
    local m = info.errorMessage:gsub("^Cannot change signature%.%s*", "")
    local hint = m:match("implementation of method") and ": change it at the declaration it implements (jdt.ls then changes every implementation)" or ""
    return refuse(("jdt.ls cannot change this method: %s%s; nothing changed"):format(m ~= "" and m or "no reason given", hint))
  end
  local name = info.methodName
  local decl_line = decl.l and (decl.lines[decl.l + 1] or "") or ""
  local pre = decl.c and decl_line:sub(1, decl.c) or ""
  local ctor = info.returnType == "void" and decl.c ~= nil and pre:gsub("@[%w_.]+%b()", ""):gsub("@[%w_.]+", "")
    :gsub("%f[%w](public)%f[^%w]", ""):gsub("%f[%w](protected)%f[^%w]", ""):gsub("%f[%w](private)%f[^%w]", ""):match("^%s*$") ~= nil
  local body = decl.l and body_identifiers(decl.lines, decl.l, name) or {}
  local static = pre:match("%f[%w]static%f[^%w]") ~= nil
  local async = false

  local function run(spec, serr)
    if spec == nil and serr == nil then return done(false) end -- prompt cancelled
    if not spec then return refuse(serr .. "; nothing changed", vim.log.levels.ERROR) end
    local bad = check_spec(spec, info, ctor, body)
    if bad then return refuse(bad .. "; nothing changed", vim.log.levels.ERROR) end
    if unchanged(spec, info) then return refuse(("the signature of %s is unchanged; nothing to do"):format(name), vim.log.levels.INFO) end
    local params = vim.tbl_map(function(p)
      return { type = p.type, name = p.name, defaultValue = p.orig == nil and p.default or "", originalIndex = p.orig or -1 }
    end, spec.params)
    -- what the call sites should look like afterwards: every reference in a touched file
    local calls_change = spec.name ~= name or #spec.params ~= #info.parameters
    for i, p in ipairs(spec.params) do
      if p.orig ~= i - 1 then calls_change = true end
    end
    local narrowed = VIS_RANK[spec.visibility] < VIS_RANK[vis_of(info)]
    -- references (calls jdt.ls must update) and implementations (changed with it) asked in parallel with
    -- the edit, on the state before it (they used to follow the edit: about 0.9 s more for Rule.apply)
    local refs_slot = (decl.l and (calls_change or narrowed)) and fire(client, "textDocument/references", { textDocument = { uri = decl.uri },
      position = { line = decl.l, character = decl.c }, context = { includeDeclaration = false } }, buf) or nil
    local impl_slot = (decl.l and not ctor and not static and vis_of(info) ~= "private") and fire(client, "textDocument/implementation",
      { textDocument = { uri = decl.uri }, position = { line = decl.l, character = decl.c } }, buf) or nil
    local t_req = vim.uv.hrtime()
    local finished, outcome = false, nil
    local ticks = {} -- path -> changedtick of every loaded buffer when the edit is asked for (filled below)
    local function finish(res, rerr, msgs)
      lap("edit")
      local said = #msgs > 0 and (": " .. table.concat(msgs, "; ")) or ""
      if not res then
        return refuse(("jdt.ls did not answer in %d ms (%s)%s; nothing changed"):format(M.signature_ms, tostring(rerr), said), vim.log.levels.ERROR)
      end
      if res.err then return refuse(("jdt.ls refused (%s)%s; nothing changed"):format(res.err.message or vim.inspect(res.err), said), vim.log.levels.ERROR) end
      local result = type(res.result) == "table" and res.result or nil -- null may come as nil or vim.NIL
      local edit = result and result.edit
      local n = 0
      if type(edit) == "table" then
        n = #(edit.documentChanges or {})
        for _, es in pairs(edit.changes or {}) do n = n + #es end
      end
      if n == 0 then
        return refuse(("jdt.ls gave no edit%s; nothing changed"):format(#msgs > 0 and (" and said" .. said) or ""), vim.log.levels.ERROR)
      end
      -- the edit was computed on the buffers as they were when it was asked for: a buffer it touches that
      -- changed since (typed into while jdt.ls worked) would get it at stale positions (Neovim skips a
      -- versioned edit for a newer buffer, with only a message): refused whole, nothing applied
      local moved = stale_buffers(edit, ticks, root)
      if #moved > 0 then
        return refuse(("%s changed while jdt.ls computed the edit; nothing changed (run it again)"):format(table.concat(moved, ", ")), vim.log.levels.WARN)
      end
      local edit_ms = (vim.uv.hrtime() - t_req) / 1e6
      local refs = {}
      for _, r in ipairs(wait(refs_slot)) do
        if r.uri and r.uri:match("^file:") then refs[#refs + 1] = { path = vim.uri_to_fname(r.uri), l = r.range.start.line } end
      end
      local impls = {}
      for _, loc in ipairs(wait(impl_slot)) do
        local u, rg = loc.uri or loc.targetUri, loc.range or loc.targetSelectionRange
        if u and rg and not (u == decl.uri and rg.start.line == decl.l) and u:match("^file:") then
          impls[#impls + 1] = ("%s:%d"):format(rel(vim.uri_to_fname(u), root), rg.start.line + 1)
        end
      end
      ms.references, ms.implementations = refs_slot and refs_slot.ms, impl_slot and impl_slot.ms -- in parallel with "edit"
      lap("wait")
      local before = M.error_counts()
      local ok, files, why = apply(client, edit, dirty_buffers())
      lap("apply")
      local old_sig = sig_text(name, vim.tbl_map(function(p) return { type = p.type, name = p.name, orig = p.originalIndex } end, info.parameters))
      local label = ("Changed signature %s -> %s"):format(old_sig, sig_text(spec.name, spec.params, true))
      if not ok then
        failed_part_way(label, why, files, root)
        return done(false)
      end
      local paths = vim.tbl_map(function(f) return f.path end, files)
      local validated_at = M.revalidate(client, paths)
      local warn, notes = {}, {}
      local left = calls_change and untouched_refs(refs, files, root) or {}
      if #left > 0 then
        warn[#warn + 1] = ("NOT updated by jdt.ls (it skips a file it cannot parse), still calling the old signature: %s"):format(table.concat(left, ", "))
      end
      if narrowed then
        local outside = {}
        local dir = vim.fs.dirname(decl.path)
        for _, r in ipairs(refs) do
          if (spec.visibility == "private" and r.path ~= decl.path) or (spec.visibility ~= "private" and vim.fs.dirname(r.path) ~= dir) then
            outside[#outside + 1] = ("%s:%d"):format(rel(r.path, root), r.l + 1)
          end
        end
        if #outside > 0 then
          warn[#warn + 1] = ("now %s, but called from where it is no longer visible%s: %s"):format(spec.visibility,
            spec.visibility == "protected" and " (unless from a subclass)" or "", table.concat(outside, ", "))
        end
      end
      if #impls > 0 then
        notes[#notes + 1] = ("jdt.ls also changed the %d method(s) that implement or override it: %s"):format(#impls, table.concat(impls, ", "))
      end
      -- Spring: who calls the method is the container (a @Bean method, a request handler), not the code
      local added = vim.tbl_filter(function(p) return p.orig == nil end, spec.params)
      local added_txt = table.concat(vim.tbl_map(param_text, added), ", ")
      if decl.l and is_bean(decl.lines, decl.l) then
        if #added > 0 then
          warn[#warn + 1] = ("Spring: %s is a @Bean method: Spring calls it and injects its parameters, it does not pass your default: `%s` must be a bean (or carry @Value), else the context fails to start; only direct calls got the default"):format(
            name, added_txt)
        end
        if spec.name ~= name then
          warn[#warn + 1] = ("Spring: the bean's name changes from `%s` to `%s` (injection by name, @Qualifier(\"%s\"), @DependsOn break)"):format(name, spec.name, name)
        end
      end
      local mapping = decl.l and annotated(decl.lines, decl.l, "@(%a*Mapping)%f[^%w_]")
      if mapping then
        local renamed = {}
        for _, p in ipairs(spec.params) do
          local o = p.orig and info.parameters[p.orig + 1]
          if o and o.name ~= p.name then renamed[#renamed + 1] = o.name .. " -> " .. p.name end
        end
        local removed = #spec.params - #added < #info.parameters
        if #added > 0 or #renamed > 0 or removed then
          warn[#warn + 1] = ("Spring: %s is a request handler (@%s): Spring binds its parameters from the request, not from your default%s%s%s; the HTTP API changes for its clients"):format(
            name, mapping, #added > 0 and ("; new `" .. added_txt .. "` is read from the request (a simple type: a required query parameter of that name, error 400 when missing; annotate it, e.g. @RequestParam(defaultValue = ...))") or "",
            #renamed > 0 and ("; renamed " .. table.concat(renamed, ", ") .. ": an unannotated parameter is bound by its name") or "",
            removed and "; a removed parameter is no longer read" or "")
        end
      end
      M.last = { label = label, files = files, ok = true, spec = spec, info = info, left = left, impls = impls, warn = warn, notes = notes,
        ms = ms, edit_ms = edit_ms, validated_at = validated_at, ctor = ctor }
      notify(summary(label, files, root) .. (#notes > 0 and (". " .. table.concat(notes, "; ")) or "")
        .. (#warn > 0 and (". WARNING: " .. table.concat(warn, "; ")) or ""), #warn > 0 and vim.log.levels.WARN or nil)
      follow_up(label, before, paths)
      return done(true)
    end
    ticks = tick_snapshot()
    busy, mine = { label = ("change signature of %s"):format(name) }, true
    if async then
      notify(("Changing signature of %s... (jdt.ls is computing it; a method with implementations takes a few seconds)"):format(name))
    end
    request_capturing(client, "java/getRefactorEdit", {
      command = "changeSignature", context = cs_params(decl.uri, decl.l or l, decl.c or c),
      options = { tabSize = vim.lsp.util.get_effective_tabstop(buf), insertSpaces = vim.bo[buf].expandtab },
      commandArguments = { info.methodIdentifier, false, spec.name, spec.visibility == "package" and "" or spec.visibility,
        spec.returns, params, info.exceptions or {}, false },
    }, M.signature_ms, buf, function(res, rerr, msgs)
      -- whatever goes wrong after the answer, the caller hears of it (on_done) and `busy` is cleared
      local ok, out = pcall(finish, res, rerr, msgs)
      if not ok then
        M.last = { label = "Change signature", files = {}, ok = false, err = tostring(out) }
        notify(("Change signature of %s FAILED after jdt.ls answered (%s); the files in an earlier summary line, if any, may be changed: undo with `u` there"):format(
          name, tostring(out)), vim.log.levels.ERROR)
        out = done(false)
      end
      outcome, finished = out, true
    end)
    if async then return nil end -- opts.on_done(ok) reports the outcome
    vim.wait(M.signature_ms + 1000, function() return finished end, 5)
    return outcome
  end

  local has_change = false
  for k in pairs(opts) do
    if k ~= "on_done" and k ~= "async" then has_change = true end
  end
  -- async: the edit request runs in the background (a progress message, the editor stays usable; the
  -- method with implementations takes jdt.ls 2.6-3.9 s), the function returns nil and opts.on_done(ok) follows.
  -- Default: synchronous for Lua callers with arguments (returns ok), asynchronous for the prompt (<leader>js).
  async = opts.async == true
  if opts.signature then return run(spec_from_form(info, opts.signature, ctor)) end
  if has_change then return run(spec_from_opts(info, opts)) end
  vim.ui.input({ prompt = "Change signature (new parameter: `Type name = default`): ", default = sig_form(info, ctor) }, function(s)
    if s == nil or vim.trim(s) == "" then return run(nil, nil) end
    async = opts.async ~= false
    run(spec_from_form(info, s, ctor))
  end)
end

-- ── safe delete (Task 4e) ────────────────────────────────────────────────────────────────────────
--
-- jdt.ls has no safe delete: own code on jdt.ls's requests (D23). The declaration under the cursor (or
-- the one a reference under the cursor resolves to, textDocument/definition) is found among jdt.ls's
-- document symbols (members and types; their `range` includes the javadoc and the annotations). Its
-- usages: textDocument/references (declaration excluded, main and test sources; references inside the
-- declaration itself, e.g. recursion, do not count), for a method also textDocument/implementation
-- (methods that implement/override it count as usages). Files jdt.ls may not have searched right are
-- read as text too: buffers with unsaved changes (jdt.ls may not have taken the change in yet) and files
-- with errors (jdt.ls skips what it cannot parse): a match of the name there is a "possible usage".
-- Any usage: nothing deleted, every usage in the quickfix list (opened), a message with the count.
-- None: the declaration's lines removed (with its javadoc/annotations, and one blank line next to it)
-- through apply() (written unless the buffer had unsaved changes, one `u`), or, for the only type of its
-- file, the file deleted (buffer wiped, jdt.ls told with didChangeWatchedFiles: it has no willDeleteFiles).
-- Refused (nothing deleted, reason shown): local variables and parameters (jdt.ls lists no symbols for
-- them), constructors (implicit super() calls and frameworks are not references), enum constants
-- (values()/valueOf() and switches), record components (the canonical constructor and accessors),
-- a field declared together with another (`int a, b;`), a method with @Override (deleting it changes
-- which method runs), a type file with unsaved changes. Framework entry points (a @Bean method, a
-- request handler, an @Value field, a stereotype class, a @Test...) have no references: deleted with
-- a WARNING, plus the strings/config still naming it (stale_refs).

M.delete_ms = 5000 -- per jdt.ls request (symbols, references, implementations); the first search of a session can take a while

local TYPE_WORD = { [5] = "class", [10] = "enum", [11] = "interface", [23] = "record" }
local KIND_WORD = { [6] = "method", [8] = "field", [14] = "constant", [7] = "field" }
-- framework annotations whose element is used by reflection (no reference in the code)
local ENTRY = { "Bean", "GetMapping", "PostMapping", "PutMapping", "DeleteMapping", "PatchMapping", "RequestMapping",
  "EventListener", "Scheduled", "PostConstruct", "PreDestroy", "ExceptionHandler", "ModelAttribute", "InitBinder",
  "Autowired", "Inject", "Value", "Resource", "KafkaListener", "RabbitListener", "JmsListener", "Component", "Service",
  "Repository", "Controller", "RestController", "Configuration", "ControllerAdvice", "RestControllerAdvice",
  "SpringBootApplication", "ConfigurationProperties", "Entity", "Embeddable", "MappedSuperclass", "Id", "Column",
  "JsonProperty", "Test", "ParameterizedTest", "BeforeEach", "AfterEach", "BeforeAll", "AfterAll" }

local function plain_name(n) return (tostring(n):gsub("[<(].*$", "")) end

local function before_pos(a, b) -- a < b (positions)
  return a.line < b.line or (a.line == b.line and a.character < b.character)
end

--- jdt.ls's document symbols of `uri` as a flat list { sym, parent } (depth first), or nil, reason.
local function symbols_of(client, uri, buf)
  local res, rerr = client:request_sync("textDocument/documentSymbol", { textDocument = { uri = uri } }, M.delete_ms, buf)
  if not res then return nil, ("jdt.ls did not answer the document symbol request in %d ms (%s)"):format(M.delete_ms, tostring(rerr)) end
  if res.err then return nil, ("jdt.ls refused the document symbol request (%s)"):format(res.err.message or vim.inspect(res.err)) end
  local syms = res.result
  if type(syms) ~= "table" or (syms[1] and not syms[1].range) then return nil, "jdt.ls gave no document symbols for this file" end
  local flat = {}
  local function walk(list, parent)
    for _, s in ipairs(list or {}) do
      flat[#flat + 1] = { sym = s, parent = parent }
      walk(s.children, s)
    end
  end
  walk(syms, nil)
  return flat
end

--- The text between two 0-based positions of `lines`.
local function text_between(lines, a, b)
  if a.line == b.line then return (lines[a.line + 1] or ""):sub(a.character + 1, b.character) end
  local out = { (lines[a.line + 1] or ""):sub(a.character + 1) }
  for i = a.line + 2, b.line do out[#out + 1] = lines[i] or "" end
  out[#out + 1] = (lines[b.line + 1] or ""):sub(1, b.character)
  return table.concat(out, "\n")
end

--- The whole-line (or exact) range to delete for `sym` in `lines`, with one blank line next to it:
--- { s = { line, character }, e = { line, character } } (0-based, end exclusive).
local function delete_range(lines, sym)
  local r = sym.range
  local first, last = lines[r.start.line + 1] or "", lines[r["end"].line + 1] or ""
  if first:sub(1, r.start.character):match("%S") or last:sub(r["end"].character + 1):match("%S") then
    return { s = r.start, e = r["end"] } -- shares its line(s) with other code: the exact range only
  end
  local s, e = r.start.line, r["end"].line -- whole lines s..e (0-based)
  local function blank_line(i) return i >= 0 and i < #lines and not lines[i + 1]:match("%S") end
  if blank_line(s - 1) and (blank_line(e + 1) or (lines[e + 2] or ""):match("^%s*}") or e + 1 >= #lines) then
    s = s - 1
  elseif blank_line(e + 1) and ((lines[s] or ""):match("{%s*$") or s == 0) then
    e = e + 1
  end
  if e + 1 >= #lines then -- the last line: from the end of the line before
    if s == 0 then return { s = { line = 0, character = 0 }, e = { line = e, character = #lines[e + 1] } } end
    return { s = { line = s - 1, character = #lines[s] }, e = { line = e, character = #lines[e + 1] } }
  end
  return { s = { line = s, character = 0 }, e = { line = e + 1, character = 0 } }
end

--- Imports of `lines` whose name the deleted text used and the rest of the file no longer does.
local function orphaned_imports(lines, gone)
  local kept, used, out = {}, blank(table.concat(gone, "\n")), {}
  local imports = {}
  for _, l in ipairs(lines) do
    local fqn = l:match("^%s*import%s+static%s+([%w_$.]+)%s*;") or l:match("^%s*import%s+([%w_$.]+)%s*;")
    if fqn then imports[#imports + 1] = fqn else kept[#kept + 1] = l end
  end
  local rest = blank(table.concat(kept, "\n"))
  for _, fqn in ipairs(imports) do
    local simple = fqn:match("([%w_$]+)$")
    if simple and used:find(word(simple)) and not rest:find(word(simple)) then out[#out + 1] = fqn end
  end
  return out
end

--- Trash for files deleted by safe delete (no `u` for a deleted file): <stdpath cache>/nv4j-trash/<stamp>/
--- holds the copy at its project-relative path and `.origin` (its absolute path). The newest
--- M.trash_keep entries are kept. M.trash_dir overrides the place (checks).
M.trash_keep = 20
M.trash_dir = nil
function M.trash_root() return M.trash_dir or (vim.fn.stdpath("cache") .. "/nv4j-trash") end

local function trash_entries()
  local root, out = M.trash_root(), {}
  if vim.fn.isdirectory(root) == 0 then return out end
  for name, kind in vim.fs.dir(root) do
    if kind == "directory" and vim.uv.fs_stat(root .. "/" .. name .. "/.origin") then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

local trash_seq = 0
--- Copies `path` (bytes from disk) into a new trash entry; returns entry dir, copy path, or nil, err.
local function to_trash(path, project)
  local f = io.open(path, "rb")
  if not f then return nil, nil, "cannot read it" end
  local bytes = f:read("*a")
  f:close()
  trash_seq = trash_seq + 1
  -- the name sorts in creation order (restore takes the last, pruning drops the first): the wall clock's
  -- seconds and microseconds from ONE reading, then the sequence (a monotonic counter's microseconds wrap
  -- at its own second boundary, not the wall clock's, so two entries of one second could sort reversed)
  local sec, usec = vim.uv.gettimeofday()
  local dir = ("%s/%s-%06d-%03d"):format(M.trash_root(), os.date("%Y%m%d-%H%M%S", sec), usec, trash_seq % 1000)
  local copy = dir .. "/" .. ((project and under(path, project)) and path:sub(#project + 2) or vim.fs.basename(path))
  if vim.fn.mkdir(vim.fs.dirname(copy), "p") == 0 then return nil, nil, "cannot create " .. dir end
  local w = io.open(copy, "wb")
  local o = io.open(dir .. "/.origin", "wb")
  if not (w and o) then
    if w then w:close() end
    if o then o:close() end
    vim.fn.delete(dir, "rf")
    return nil, nil, "cannot write into " .. dir
  end
  w:write(bytes); w:close()
  o:write(path .. "\n" .. copy:sub(#dir + 2) .. "\n"); o:close()
  local all = trash_entries()
  for i = 1, #all - M.trash_keep do vim.fn.delete(M.trash_root() .. "/" .. all[i], "rf") end
  return dir, copy
end

M._to_trash = to_trash -- checks
M._trash_entries = trash_entries -- checks

--- Puts the newest trash entry back at its original path (refused when that path exists), opens it,
--- tells jdt.ls, removes the entry. Returns ok, message.
function M.restore_deleted()
  local all = trash_entries()
  local function say(msg, level)
    notify("Restore deleted: " .. msg, level)
    return level ~= vim.log.levels.WARN and level ~= vim.log.levels.ERROR, msg
  end
  if #all == 0 then return say("the trash is empty (" .. M.trash_root() .. ")", vim.log.levels.WARN) end
  local dir = M.trash_root() .. "/" .. all[#all]
  local o = vim.fn.readfile(dir .. "/.origin")
  local dest, relp = o[1], o[2]
  local copy = dir .. "/" .. (relp or "")
  if not (dest and relp and vim.uv.fs_stat(copy)) then return say(dir .. " is not a complete trash entry", vim.log.levels.ERROR) end
  if vim.uv.fs_stat(dest) then
    return say(("%s exists again; the copy stays in %s"):format(dest, copy), vim.log.levels.WARN)
  end
  local f = io.open(copy, "rb")
  if not f then return say("cannot read the copy " .. copy, vim.log.levels.ERROR) end
  local bytes = f:read("*a")
  f:close()
  vim.fn.mkdir(vim.fs.dirname(dest), "p")
  local w = io.open(dest, "wb")
  if not w then return say("cannot write " .. dest .. "; the copy stays in " .. copy, vim.log.levels.ERROR) end
  -- the trash entry is the only copy: it is deleted only after the write and the close both succeeded
  local wok, werr = w:write(bytes)
  local cok, cerr = w:close()
  local st = vim.uv.fs_stat(dest)
  if not (wok and cok and st and st.size == #bytes) then
    os.remove(dest) -- never leave a partial file behind
    return say(("writing %s failed (%s); the copy stays in %s"):format(dest, tostring(werr or cerr or "short write"), copy), vim.log.levels.ERROR)
  end
  local client = jdtls_for(dest)
  if client then client:notify("workspace/didChangeWatchedFiles", { changes = { { uri = vim.uri_from_fname(dest), type = 1 } } }) end
  vim.fn.delete(dir, "rf")
  vim.cmd.edit(vim.fn.fnameescape(dest))
  return say(("%s restored from the trash"):format(dest))
end

--- Deletes the method, field, constant or type at the cursor (its declaration name, or a reference to it)
--- when nothing uses it; otherwise nothing is deleted and the usages are listed in the quickfix list.
--- See the section comment above. opts.on_done(ok) afterwards. Returns ok (true = deleted).
local function safe_delete_body(opts, st)
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  local mine = false
  local function done(ok)
    if mine then busy, mine = nil, false end
    st.finished = true
    if opts.on_done then opts.on_done(ok) end
    return ok
  end
  local function refuse(msg, level)
    M.last = { label = "Safe delete", files = {}, ok = false, err = msg }
    notify("Safe delete: " .. msg, level or vim.log.levels.WARN)
    return done(false)
  end
  if busy then return refuse(busy_msg() .. "; nothing deleted") end
  local client = jdtls_for(path)
  if not client or #vim.lsp.get_clients({ bufnr = buf, name = "jdtls" }) == 0 then
    return refuse("jdt.ls is not attached to this buffer")
  end
  local root = root_of(client)
  if not (root and under(path, root)) then
    return refuse(("%s is outside jdt.ls's project (%s): its usages cannot be searched; nothing deleted"):format(path, tostring(root)))
  end
  busy, mine = { label = "safe delete" }, true
  st.busy = busy
  local ms, t = {}, vim.uv.hrtime()
  local function lap(k)
    local n = vim.uv.hrtime()
    ms[k], t = (ms[k] or 0) + (n - t) / 1e6, n
  end
  local cur = vim.api.nvim_win_get_cursor(0)
  local l, c = cur[1] - 1, cur[2]
  local cword = vim.fn.expand("<cword>")
  local uri = vim.uri_from_bufnr(buf)

  -- 1. the declaration: a symbol whose name is under the cursor, else where the reference under it points
  local flat, serr = symbols_of(client, uri, buf)
  lap("symbols")
  if not flat then return refuse(serr .. "; nothing deleted", vim.log.levels.ERROR) end
  local hit, decl_path, decl_uri = nil, path, uri
  for _, x in ipairs(flat) do
    local sr = x.sym.selectionRange
    if x.sym.kind ~= 4 and contains({ start = sr.start, ["end"] = { line = sr.start.line, character = sr.start.character + #plain_name(x.sym.name) } }, l, c) then
      hit = x
    end
  end
  if not hit then
    local d, derr = declaration(client, buf, l, c)
    lap("definition")
    if not d then
      return refuse(("the cursor is not on a declaration or a reference (`%s`: %s): put it on the name of a method, field or type; nothing deleted"):format(cword, derr))
    end
    if not d.path or not under(d.path, root) then
      return refuse(("`%s` is declared outside this project (%s): only the project's own declarations can be deleted; nothing deleted"):format(cword, d.path or d.uri))
    end
    if d.uri ~= uri then
      flat, serr = symbols_of(client, d.uri, buf)
      lap("symbols")
      if not flat then return refuse(serr .. "; nothing deleted", vim.log.levels.ERROR) end
    end
    decl_path, decl_uri = d.path, d.uri
    for _, x in ipairs(flat) do
      local sr = x.sym.selectionRange.start
      if x.sym.kind ~= 4 and sr.line == d.range.start.line and sr.character == d.range.start.character then hit = x end
    end
    if not hit then
      return refuse(("`%s` is a local variable or a parameter (jdt.ls lists only types and members): inline a local with <leader>ji or delete its line; remove a parameter with change signature (<leader>js); nothing deleted"):format(cword))
    end
  end
  local sym, parent = hit.sym, hit.parent
  local name = plain_name(sym.name)
  local lines = lines_of(decl_path)
  local kind = sym.kind
  local header = text_between(lines, sym.range.start, sym.selectionRange.start)
  local is_type = TYPE_WORD[kind] ~= nil
  local what = is_type and (header:match("@interface%s*$") and "annotation" or blank(header):match("%f[%w](%a+)%s*$") or TYPE_WORD[kind])
    or KIND_WORD[kind]
  if kind == 9 then
    return refuse(("`%s` is a constructor: its callers include implicit super() calls and frameworks (Spring, JPA, Jackson) that create objects by reflection, which jdt.ls's references do not show; delete it by hand if you are sure; nothing deleted"):format(name))
  elseif kind == 22 then
    return refuse(("`%s` is an enum constant: values(), valueOf(\"%s\"), switches and serialized data use it without a reference jdt.ls can show; delete it by hand if you are sure; nothing deleted"):format(name, name))
  elseif not what then
    return refuse(("`%s` (symbol kind %d) is not something safe delete handles (methods, fields, constants, types); nothing deleted"):format(name, kind))
  end
  if (kind == 8 or kind == 7) and parent and TYPE_WORD[parent.kind]
      and not text_between(lines, parent.selectionRange["end"], sym.range.start):find("{", 1, true) then
    return refuse(("`%s` is a record component: it is the canonical constructor's parameter and an accessor too; remove it from the record header by hand (or with change signature on the constructor); nothing deleted"):format(name))
  end
  for _, x in ipairs(flat) do
    local o = x.sym
    if o ~= sym and o.kind ~= 4 and x.parent == parent and not (before_pos(o.range["end"], sym.range.start) or before_pos(sym.range["end"], o.range.start)
        or (o.range["end"].line == sym.range.start.line and o.range["end"].character == sym.range.start.character)) then
      return refuse(("`%s` is declared together with `%s` (%s:%d): split the declaration first; nothing deleted"):format(name, plain_name(o.name),
        rel(decl_path, root), sym.range.start.line + 1))
    end
  end
  local hb = blank(header) -- annotations and modifiers, javadoc/comments blanked
  local entry = {}
  for _, a in ipairs(ENTRY) do
    if hb:find("@" .. a .. "%f[^%w_]") then entry[#entry + 1] = a end
  end
  if kind == 6 and hb:find("@Override%f[^%w_]") then
    return refuse(("`%s` overrides or implements a method of a supertype (@Override): deleting it changes which method runs (or breaks the class when the supertype's is abstract); nothing deleted"):format(name))
  end
  -- the same without @Override (javac allows it): jdt.ls's "go to super implementation" (java/findLinks),
  -- which resolves the method binding against every supertype (Object and library types too)
  if kind == 6 and not hb:find("%f[%w]private%f[^%w]") and not hb:find("%f[%w]static%f[^%w]") then
    local sres, sre = client:request_sync("java/findLinks", { type = "superImplementation",
      position = { textDocument = { uri = decl_uri }, position = sym.selectionRange.start } }, M.delete_ms, nil)
    lap("supertypes")
    if not sres or sres.err or type(sres.result) ~= "table" then
      return refuse(("could not check the supertypes of `%s` (jdt.ls's super implementation request: %s): it may override or implement a method, deleting it could change which method runs; nothing deleted"):format(
        name, not sres and ("no answer in " .. M.delete_ms .. " ms: " .. tostring(sre)) or (sres.err and (sres.err.message or "error") or "no list")), vim.log.levels.ERROR)
    end
    if #sres.result > 0 then
      local supers = vim.tbl_map(function(x) return tostring(x.displayName or x.uri) end, sres.result)
      return refuse(("`%s` overrides or implements %s (no @Override on it): deleting it changes which method runs (or breaks the class when that one is abstract); nothing deleted"):format(
        name, table.concat(supers, ", ")))
    end
  end

  -- 2. usages: references (+ implementations of a method) and possible usages jdt.ls may have missed
  local spos = sym.selectionRange.start
  local res, rerr = client:request_sync("textDocument/references", { textDocument = { uri = decl_uri }, position = spos,
    context = { includeDeclaration = false } }, M.delete_ms, nil) -- no buffer: every buffer's pending changes are sent first
  lap("references")
  if not res then return refuse(("jdt.ls did not answer the references request in %d ms (%s): usages unknown; nothing deleted"):format(M.delete_ms, tostring(rerr)), vim.log.levels.ERROR) end
  if res.err then return refuse(("jdt.ls refused the references request (%s): usages unknown; nothing deleted"):format(res.err.message or vim.inspect(res.err)), vim.log.levels.ERROR) end
  local usages, seen, seen_line, self_refs = {}, {}, {}, 0
  local function add(p, lnum, col, tag)
    local key = p .. ":" .. lnum .. ":" .. col
    if seen[key] then return end
    seen[key], seen_line[p .. ":" .. lnum] = true, true
    usages[#usages + 1] = { path = p, l = lnum, c = col, tag = tag }
  end
  for _, r in ipairs(type(res.result) == "table" and res.result or {}) do
    if r.uri and r.uri:match("^file:") then
      local p = vim.uri_to_fname(r.uri)
      if p == decl_path and contains(sym.range, r.range.start.line, r.range.start.character) then
        self_refs = self_refs + 1 -- inside the declaration itself (recursion, its own field): goes with it
      else
        add(p, r.range.start.line, r.range.start.character, "usage")
      end
    end
  end
  local impls = 0
  if kind == 6 and not hb:find("%f[%w]private%f[^%w]") and not hb:find("%f[%w]static%f[^%w]") then
    local ires = client:request_sync("textDocument/implementation", { textDocument = { uri = decl_uri }, position = spos }, M.delete_ms, nil)
    lap("implementations")
    for _, loc in ipairs(ires and type(ires.result) == "table" and ires.result or {}) do
      local u, rg = loc.uri or loc.targetUri, loc.targetSelectionRange or loc.range
      if u and rg and u:match("^file:") and not (u == decl_uri and rg.start.line == spos.line) then
        impls = impls + 1
        add(vim.uri_to_fname(u), rg.start.line, rg.start.character, "implements or overrides it")
      end
    end
  end
  -- text of files jdt.ls may not have searched right: unsaved buffers and files with errors
  local errfiles = {}
  for _, d in ipairs(vim.diagnostic.get(nil, { severity = ERROR })) do
    local p = vim.api.nvim_buf_get_name(d.bufnr)
    if under(p, root) and p:match("%.java$") then errfiles[p] = true end
  end
  local scan = {}
  for p in pairs(dirty_buffers()) do
    if under(p, root) and p:match("%.java$") then scan[p] = "unsaved changes: jdt.ls may not have taken them in yet" end
  end
  for p in pairs(errfiles) do scan[p] = "this file has errors: jdt.ls may skip what it cannot parse" end
  local pats = kind == 6 and { "%f[%w_$]" .. vim.pesc(name) .. "%s*%(", "::%s*" .. vim.pesc(name) .. "%f[^%w_$]" } or { word(name) }
  local possible, err_named = 0, {}
  for p, why in pairs(scan) do
    local text = vim.split(blank(table.concat(lines_of(p), "\n")), "\n", { plain = true })
    for i, s in ipairs(text) do
      for _, pat in ipairs(pats) do
        local col = s:find(pat)
        if col and not (p == decl_path and i - 1 >= sym.range.start.line and i - 1 <= sym.range["end"].line) then
          if not seen_line[p .. ":" .. (i - 1)] then
            possible = possible + 1
            add(p, i - 1, col - 1, "possible usage: " .. why)
          end
          if errfiles[p] then err_named[p] = true end
          break
        end
      end
    end
  end
  lap("scan")
  local label_what = ("%s %s"):format(what, kind == 6 and sym.name or name)
  if #usages > 0 then
    table.sort(usages, function(a, b) if a.path ~= b.path then return a.path < b.path end return a.l < b.l end)
    local items, nfiles, files_seen = {}, 0, {}
    for _, u in ipairs(usages) do
      if not files_seen[u.path] then files_seen[u.path], nfiles = true, nfiles + 1 end
      local txt = vim.trim(lines_of(u.path)[u.l + 1] or "")
      items[#items + 1] = { filename = u.path, lnum = u.l + 1, col = u.c + 1, text = txt .. (u.tag ~= "usage" and (" [" .. u.tag .. "]") or "")
        .. (under(u.path, root) and "" or " [outside the project]") }
    end
    vim.fn.setqflist({}, " ", { title = ("Safe delete %s: usages (nothing deleted)"):format(name), items = items })
    local win = vim.api.nvim_get_current_win()
    pcall(vim.cmd, "botright copen")
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
    local n_use = #usages - impls - possible
    local parts = { ("%d usage(s)"):format(n_use) }
    if impls > 0 then parts[#parts + 1] = ("%d method(s) that implement or override it"):format(impls) end
    if possible > 0 then parts[#parts + 1] = ("%d possible usage(s) in unsaved or broken files (save them / fix their errors, then run it again)"):format(possible) end
    local listed = vim.tbl_map(function(u) return ("%s:%d"):format(rel(u.path, root), u.l + 1) end, vim.list_slice(usages, 1, 6))
    local msg = ("Safe delete: %s NOT deleted: %s in %d file(s), listed in the quickfix: %s%s; nothing changed"):format(label_what,
      table.concat(parts, ", "), nfiles, table.concat(listed, ", "), #usages > 6 and (", +" .. (#usages - 6) .. " more") or "")
    M.last = { label = "Safe delete " .. name, ok = false, blocked = true, files = {}, usages = usages, impls = impls, possible = possible,
      count = n_use, ms = ms, err = msg }
    notify(msg, vim.log.levels.WARN)
    return done(false)
  end

  -- 3. no usage: delete
  local warn, notes = {}, {}
  local nerr = vim.tbl_count(errfiles)
  if nerr > 0 then
    notes[#notes + 1] = ("jdt.ls reports errors in %d file(s) (%s): none of them names `%s` in its text"):format(nerr,
      table.concat(vim.tbl_map(function(p) return rel(p, root) end, vim.list_slice(vim.tbl_keys(errfiles), 1, 3)), ", "), name)
  end
  if self_refs > 0 then notes[#notes + 1] = ("%d reference(s) inside %s itself went with it"):format(self_refs, name) end
  local tops = vim.tbl_filter(function(x) return x.parent == nil and TYPE_WORD[x.sym.kind] end, flat)
  local whole_file = is_type and parent == nil and #tops == 1
  local back = whole_file and "`:Nv4jRestoreDeleted` brings the file back from the trash" or "`u` gives it back"
  if #entry > 0 then
    local extra = ""
    for _, a in ipairs(entry) do
      if a == "Bean" then extra = extra .. ("; the bean `%s` is no longer defined: whatever injects it (by type or name) fails at startup"):format(name)
      elseif a:match("Mapping$") then extra = extra .. "; its HTTP endpoint is gone"
      elseif a == "Value" then
        local key = header:match('@Value%s*%(%s*"([^"]*)"')
        extra = extra .. ("; the property %s is no longer read (it stays in the config)"):format(key and ("`" .. key .. "`") or "it named")
      end
    end
    warn[#warn + 1] = ("Spring/framework: %s carries @%s: the framework uses it by reflection, which jdt.ls's references do not show (deleted anyway; %s)%s"):format(
      name, table.concat(entry, ", @"), back, extra)
  end
  if kind == 6 and name == "main" and hb:find("%f[%w]void%s*$") then
    warn[#warn + 1] = ("%s is a `main` method: the JVM's entry point, called without a reference"):format(name)
  end
  local before = M.error_counts()
  local files
  if whole_file then
    local b = vim.fn.bufnr(decl_path)
    if b ~= -1 and vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified then
      return refuse(("%s has unsaved changes and deleting %s deletes the whole file: save or discard them first; nothing deleted"):format(rel(decl_path, root), name))
    end
    -- a copy in the trash first (no `u` for a deleted file), then the file, then its buffer: a failed
    -- removal leaves the buffer open
    local entry_dir, copy, terr = to_trash(decl_path, require("nv4j.root").project(decl_path))
    if not entry_dir then
      return refuse(("could not copy %s to the trash (%s); nothing deleted"):format(rel(decl_path, root), tostring(terr)), vim.log.levels.ERROR)
    end
    local okr, rmerr = os.remove(decl_path)
    if not okr then
      vim.fn.delete(entry_dir, "rf")
      return refuse(("could not delete %s (%s); its buffer is still open, nothing deleted"):format(rel(decl_path, root), tostring(rmerr)), vim.log.levels.ERROR)
    end
    for _, bb in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(bb) == decl_path then pcall(vim.api.nvim_buf_delete, bb, { force = true }) end
    end
    client:notify("workspace/didChangeWatchedFiles", { changes = { { uri = vim.uri_from_fname(decl_path), type = 3 } } })
    files = { { path = decl_path, deleted = true } }
    M.last_deleted_text = table.concat(lines, "\n") .. "\n"
    notes[#notes + 1] = ("the file is deleted (no `u` for a deleted file): a copy is in the trash, %s; restore it with :Nv4jRestoreDeleted (or require(\"nv4j.refactor\").restore_deleted())"):format(copy)
  else
    local r = delete_range(lines, sym)
    local gone = vim.list_slice(lines, sym.range.start.line + 1, sym.range["end"].line + 1)
    local edit = { documentChanges = { { textDocument = { uri = decl_uri, version = vim.NIL }, edits = { { range = { start = r.s, ["end"] = r.e }, newText = "" } } } } }
    local ok, fs, why = apply(client, edit, dirty_buffers())
    lap("apply")
    files = fs
    if not ok then
      failed_part_way("Deleted " .. label_what, why, files, root)
      return done(false)
    end
    local orphans = orphaned_imports(lines_of(decl_path), gone)
    if #orphans > 0 then
      notes[#notes + 1] = ("left unused import(s) in %s (remove them with organize imports, <leader>co): %s"):format(vim.fs.basename(decl_path), table.concat(orphans, ", "))
    end
  end
  local _, pkg = src_root_of(vim.fs.dirname(decl_path))
  local names = is_type and class_names(name, pkg ~= "" and pkg or nil) or { java = { word(name) }, config = { word(name) },
    bean = vim.tbl_contains(entry, "Bean") and word(name) or nil }
  local stale, cut, unread = M.stale_refs(require("nv4j.root").project(decl_path), names)
  if #unread > 0 then
    warn[#warn + 1] = ("could not read %d file(s), so they were not checked for `%s`: %s"):format(#unread, name,
      table.concat(vim.list_slice(unread, 1, 5), ", "))
  end
  if #stale > 0 then
    warn[#warn + 1] = ("still named in strings/config (reflection, JPQL, bean names, properties: not code usages, check them): %s%s"):format(
      table.concat(vim.list_slice(stale, 1, 8), ", "), #stale > 8 and (", +" .. (#stale - 8) .. " more") or "")
  end
  if cut then warn[#warn + 1] = ("the strings/config scan stopped after %d files"):format(M.scan_max_files) end
  local label = "Deleted " .. label_what
  M.last = { label = label, files = files, ok = true, whole_file = whole_file, warn = warn, notes = notes, stale = stale, entry = entry, ms = ms }
  notify(summary(label, files, root) .. (whole_file and " [file deleted]" or "") .. (#notes > 0 and (". " .. table.concat(notes, "; ")) or "")
    .. (#warn > 0 and (". WARNING: " .. table.concat(warn, "; ")) or ""), #warn > 0 and vim.log.levels.WARN or nil)
  follow_up(label, before, whole_file and {} or vim.tbl_map(function(f) return f.path end, files))
  return done(true)
end

function M.safe_delete(opts)
  opts = opts or {}
  local st = {}
  local ok, res = pcall(safe_delete_body, opts, st)
  if ok then return res end
  -- whatever threw, `busy` must not stay set (it would refuse every refactor until Neovim restarts)
  if st.busy and busy == st.busy then busy = nil end
  local msg = "Safe delete: an error stopped it part-way (" .. tostring(res):gsub("\n.*", "") .. "); check the file and the build with u / git diff"
  M.last = { label = "Safe delete", files = {}, ok = false, err = tostring(res) }
  notify(msg, vim.log.levels.ERROR)
  if not st.finished and opts.on_done then pcall(opts.on_done, false) end
  return false
end

-- ── neo-tree (plugins/neo-tree.lua) ──────────────────────────────────────────────────────────────

local handled = {} -- source -> destination renamed here; neo-tree's after-hooks (LazyVim's) skip them

--- neo-tree (4d55ed3) cannot cancel a rename/move from its before-event: `handled` only skips its own
--- fs_rename, then it still runs `complete` (re-points every buffer under the old path to the new, not
--- existing, path and deletes the originals; fires file_renamed; logs "Renamed X successfully"). After a
--- refusal we return NOT handled and make neo-tree's own uv.fs_rename fail instead, with a placeholder
--- at the destination and nothing written into any existing folder: a file is renamed onto an empty
--- placeholder FOLDER (EISDIR), a folder onto an empty placeholder FILE (ENOTDIR). neo-tree logs "Could
--- not rename the files" and changes nothing. The placeholder (and the parents made for it) goes 1 s later,
--- at VimLeavePre at the latest; a second refusal for the same destination keeps it 1 s more (the first
--- timer does not remove it). neo-tree checks that the destination does not exist before it fires the
--- event (rename_is_safe / get_unused_name, verified in fs_actions.lua), so an existing destination never
--- gets here; if it does, or the placeholder cannot be made, we return `handled` (its move cannot happen;
--- its `complete` then re-points the buffers, the lesser harm) and say so.
local placeholders = {} -- dest -> { token, created = { paths, deepest last }, kind }

local function remove_placeholder(dest)
  local ph = placeholders[dest]
  if not ph then return end
  placeholders[dest] = nil
  for i = #ph.created, 1, -1 do
    local p = ph.created[i]
    local st = vim.uv.fs_stat(p)
    if st and st.type == "directory" then vim.uv.fs_rmdir(p) elseif st then os.remove(p) end -- rmdir: only if empty
  end
end

local leave_hook = false
local function block_neotree_move(src, dest)
  local ph = placeholders[dest]
  if ph then
    ph.token = ph.token + 1
  else
    if vim.uv.fs_stat(dest) then return false end -- an existing (user) path is never used as a placeholder
    local created, d = {}, vim.fs.dirname(dest)
    while d and not vim.uv.fs_stat(d) do
      table.insert(created, 1, d)
      local parent = vim.fs.dirname(d)
      d = parent ~= d and parent or nil
    end
    for k, dir in ipairs(created) do
      if not vim.uv.fs_mkdir(dir, 493) then
        for j = k - 1, 1, -1 do vim.uv.fs_rmdir(created[j]) end -- the parents made so far
        return false
      end
    end
    local ok
    if vim.fn.isdirectory(src) == 1 then
      local f = io.open(dest, "w")
      ok = f ~= nil and (f:close() or true)
    else
      ok = vim.uv.fs_mkdir(dest, 493) ~= nil
    end
    created[#created + 1] = dest
    ph = { token = 1, created = created }
    placeholders[dest] = ph
    if not (ok and vim.uv.fs_stat(dest)) then
      remove_placeholder(dest)
      return false
    end
  end
  if not leave_hook then
    leave_hook = true
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = vim.api.nvim_create_augroup("nv4j_refactor_placeholders", { clear = true }),
      callback = function()
        for d in pairs(placeholders) do remove_placeholder(d) end
      end,
    })
  end
  local token = ph.token
  vim.defer_fn(function()
    if placeholders[dest] and placeholders[dest].token == token then remove_placeholder(dest) end
  end, 1000)
  return true
end

M._placeholders = placeholders -- checks: what is still on disk

--- A neo-tree rename/move jdt.ls must know first: a .java file, or a folder with a .java file, in a
--- jdt.ls project.
local function is_java(source)
  local st = vim.uv.fs_stat(source)
  if not st or not jdtls_for(source) then return false end
  if st.type == "file" then return source:match("%.java$") ~= nil end
  return st.type == "directory" and #vim.fs.find(function(n) return n:match("%.java$") ~= nil end, { path = source, limit = 1 }) > 0
end

local function label_for(source, dest)
  if source:match("%.java$") then
    local a, b = vim.fn.fnamemodify(source, ":t:r"), vim.fn.fnamemodify(dest, ":t:r")
    if a ~= b then return ("Renamed class %s -> %s"):format(a, b) end
    local _, p2 = src_root_of(vim.fs.dirname(dest))
    return ("Moved class %s to %s"):format(a, p2 and ("package " .. p2) or vim.fs.dirname(dest))
  end
  local _, p1 = src_root_of(source)
  local _, p2 = src_root_of(dest)
  if p1 and p2 and p1 ~= "" and p2 ~= "" then return ("Renamed package %s -> %s"):format(p1, p2) end
  return ("Renamed %s -> %s"):format(vim.fs.basename(source), vim.fs.basename(dest))
end

--- neo-tree before_file_rename / before_file_move handler: the whole rename is done here (jdt.ls asked
--- before the move) and neo-tree is told it is handled. On a refusal nothing moves: our message, and
--- neo-tree's own rename is made to fail (block_neotree_move).
function M.neotree_before(args)
  if not (args and args.source and args.destination) or not is_java(args.source) then return nil end
  local src, dest = vim.fs.normalize(args.source), vim.fs.normalize(args.destination)
  local moves, opts = { { src, dest } }, {}
  if vim.fn.isdirectory(src) == 1 then
    -- a package folder renamed/moved inside its source root: the namesake folders (src/test/java) follow,
    -- as with rename_package
    local r1, p1 = src_root_of(src)
    local r2, p2 = src_root_of(dest)
    if r1 and r1 == r2 and p1 ~= "" and p2 ~= "" then
      moves = namesake_moves(module_root(src), r1, p1, p2)
      opts.stale = { names = package_names(p1), old = p1 }
    end
  elseif src:match("%.java$") then
    local old = vim.fn.fnamemodify(src, ":t:r")
    local _, pkg = src_root_of(vim.fs.dirname(src))
    if old == vim.fn.fnamemodify(dest, ":t:r") then
      -- a move to another folder: only the old fully qualified name is stale (the simple name is not)
      opts.stale = { names = move_names(old, pkg), old = (pkg and pkg ~= "" and (pkg .. ".") or "") .. old }
    else
      opts.stale = { names = class_names(old, pkg ~= "" and pkg or nil), old = old }
    end
  end
  local ok = M.rename_paths(moves, label_for(src, dest), nil, opts)
  if not ok then
    if block_neotree_move(src, dest) then return nil end
    notify("neo-tree's own rename could not be blocked with a placeholder: it is skipped as handled; reopen the files if their buffers moved",
      vim.log.levels.WARN)
    return { handled = true }
  end
  handled[args.source] = args.destination
  return { handled = true }
end

--- neo-tree file_renamed / file_moved handler: stops LazyVim's after-the-move willRenameFiles for a
--- rename done above (it would ask jdt.ls again about paths that no longer exist).
function M.neotree_after(args)
  if args and handled[args.source] == args.destination then
    handled[args.source] = nil
    return { handled = true }
  end
end

return M
