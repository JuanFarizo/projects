-- Refactors (decision D23, specs/features/refactors.md, check 62_refactor). P3 Task 4a: rename class and
-- rename package; Task 4b: move a class to another package; Task 4c: inline a method call, local variable
-- or constant (jdt.ls's inline code actions, see M.inline). Change signature and safe delete come in
-- later sub-tasks.
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

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = TITLE })
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
  local out, n, truncated = {}, 0, false
  local function scan(path, ext)
    local b = vim.fn.bufnr(path)
    local lines = (b ~= -1 and vim.api.nvim_buf_is_loaded(b)) and vim.api.nvim_buf_get_lines(b, 0, -1, false)
      or (vim.fn.getfsize(path) < 1048576 and vim.fn.readfile(path)) or {}
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
  return out, truncated
end

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

local function stale_note(stale, old, truncated)
  local cut = truncated and (". The strings/config scan stopped after %d files: the rest of the project was not checked")
    :format(M.scan_max_files) or ""
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

local function failed_part_way(label, why, files, root)
  local msg = ("%s FAILED part-way (%s). %s. Undo with `u` in each file listed."):format(label, why,
    summary("Changed so far", files, root))
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

--- Renames the class at the cursor (or the file's class) to opts.name (prompted when missing): the file
--- is renamed, references and imports in every file updated. opts.on_done(ok) is called afterwards.
function M.rename_class(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  local client = jdtls_for(path)
  local function done(ok)
    if opts.on_done then opts.on_done(ok) end
    return ok
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
    -- an existing class of that name: jdt.ls refuses ("Compilation unit 'X.java' already exists"), shown below
    local label = ("Renamed class %s -> %s"):format(old, name)
    local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = l, character = c }, newName = name }
    client:request("textDocument/rename", params, function(err, edit)
      if err then
        notify(("Rename class %s -> %s: jdt.ls refused (%s); nothing changed"):format(old, name, err.message or vim.inspect(err)),
          vim.log.levels.ERROR)
        return done(false)
      end
      if not edit then
        notify(("Rename class %s -> %s: jdt.ls returned no change"):format(old, name), vim.log.levels.WARN)
        return done(false)
      end
      local before = M.error_counts()
      local ok, files, why = apply(client, edit, dirty_buffers())
      if not ok then
        failed_part_way(label, why, files, root_of(client))
        return done(false)
      end
      local t_scan = vim.uv.hrtime()
      local _, pkg = src_root_of(vim.fs.dirname(path))
      local stale, cut = M.stale_refs(require("nv4j.root").project(path), class_names(old, pkg ~= "" and pkg or nil))
      M.last = { label = label, files = files, ok = true, stale = stale, scan_ms = (vim.uv.hrtime() - t_scan) / 1e6, truncated = cut }
      notify(summary(label, files, root_of(client)) .. stale_note(stale, old, cut), (#stale > 0 or cut) and vim.log.levels.WARN or nil)
      follow_up(label, before, vim.tbl_map(function(f) return f.path end, files))
      done(true)
    end, buf)
  end
  if opts.name then return run(opts.name) end
  vim.ui.input({ prompt = ("Rename class %s to: "):format(old), default = old }, run)
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
local function lines_of(p)
  local b = vim.fn.bufnr(p)
  if b ~= -1 and vim.api.nvim_buf_is_loaded(b) then return vim.api.nvim_buf_get_lines(b, 0, -1, false) end
  return vim.uv.fs_stat(p) and vim.fn.readfile(p) or {}
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
  -- per-step ms (M.last.ms, profiling): will = willRenameFiles, apply = edit + writes, move = folder + :saveas
  local ms, t = { will = 0, apply = 0, move = 0 }, vim.uv.hrtime()
  local function lap(k)
    local n = vim.uv.hrtime()
    ms[k], t = ms[k] + (n - t) / 1e6, n
  end
  for i, m in ipairs(moves) do
    local from, to = m[1], m[2]
    local edit, err = will_rename(client, from, to)
    -- a later root right after the previous move: jdt.ls sometimes answers null while it is still taking
    -- that move in (measured in the check run, not alone): ask again for up to 1 s, then fall back to the
    -- package lines only (said in the summary)
    local tries = 1
    local needs = needs_edit(from, to)
    while edit == false and needs and tries < 10 do
      vim.wait(100)
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
      return failed_part_way(label, err .. " for " .. rel(from, root), files, root)
    end
    if edit and edit.documentChanges then
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
    if edit then
      local ok, fs, why = apply(client, edit, dirty, moving)
      for _, f in ipairs(fs) do
        local dup = vim.iter(files):find(function(g) return g.path == f.path end)
        if not dup then files[#files + 1] = f end
      end
      if not ok then return failed_part_way(label, why, files, root) end
    end
    lap("apply")
    -- the edit may have moved it already (a RenameFile in jdt.ls's answer)
    if vim.uv.fs_stat(from) then
      local mok, merr = pcall(vim.lsp.util.rename, from, to, { overwrite = false })
      if not mok or vim.uv.fs_stat(from) or not vim.uv.fs_stat(to) then
        return failed_part_way(label, ("moving %s to %s failed: %s; the edits above are applied"):format(rel(from, root),
          rel(to, root), tostring(merr or "not moved")), files, root)
      end
    end
    lap("move")
    local change = { oldUri = vim.uri_from_fname(from), newUri = vim.uri_from_fname(to) }
    changes.files[#changes.files + 1] = change
    client:notify("workspace/didRenameFiles", { files = { change } })
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
  local moved = table.concat(vim.tbl_map(function(m) return rel(m[1], root) .. " -> " .. rel(m[2], root) end, moves), ", ")
  local stale, cut = {}, false
  if opts.stale then stale, cut = M.stale_refs(root, opts.stale.names) end
  M.last = { label = label, files = files, ok = true, moves = moves, tries = tries_by, notes = notes, ms = ms, stale = stale,
    truncated = cut, info = opts.info }
  -- opts.warn: caller's warnings (WARN level); opts.info: caller's notes (level unchanged)
  vim.list_extend(notes, opts.warn or {})
  local warn = #notes > 0 or #stale > 0 or cut
  notify(summary(("%s (moved %s)"):format(label, moved), files, root) .. (#notes > 0 and (". NOTE: " .. table.concat(notes, "; ")) or "")
    .. stale_note(stale, opts.stale and opts.stale.old, cut) .. ((opts.info and #opts.info > 0) and (". " .. table.concat(opts.info, "; ")) or ""),
    warn and vim.log.levels.WARN or nil)
  follow_up(label, before, vim.tbl_map(function(f) return f.path end, files))
  return true
end

--- Moves for renaming package `pkg` to `name`: its folder in `src_root` and the namesake folders in the
--- project's other source roots (`src/*/java`), src/main/java first (see M.rename_paths).
local function namesake_moves(project, src_root, pkg, name)
  local pkg_path, new_path = pkg:gsub("%.", "/"), name:gsub("%.", "/")
  local roots = { src_root }
  for _, r in ipairs(vim.fn.glob(project .. "/src/*/java", false, true)) do
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

--- Package of the current buffer from its `package` line.
local function current_package(buf)
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, math.min(200, vim.api.nvim_buf_line_count(buf)), false)) do
    local p = l:match("^%s*package%s+([%w_$.]+)%s*;")
    if p then return p end
  end
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
    local moves = namesake_moves(require("nv4j.root").project(path), src_root, pkg, name)
    local ok = M.rename_paths(moves, ("Renamed package %s -> %s"):format(pkg, name), nil,
      { stale = { names = package_names(pkg), old = pkg } })
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

--- The project's source roots (`src/*/java`), `first` (the current file's) first.
local function source_roots(project, first)
  local roots = { first }
  for _, r in ipairs(vim.fn.glob(project .. "/src/*/java", false, true)) do
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
local function spring_scan_warning(path, project, name, target)
  local ann
  for _, l in ipairs(lines_of(path)) do
    for _, a in ipairs(STEREOTYPES) do
      if l:match("^%s*@" .. a .. "%f[^%w_]") then ann = ann or a end
    end
  end
  if not ann then return nil end
  local bases, n = {}, 0
  for _, r in ipairs(vim.fn.glob(project .. "/src/main/java", false, true)) do
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

--- Moves the class at the cursor (the file's own top-level type) to package opts.package (picked with
--- vim.ui.select / vim.ui.input when missing): the file moves to that package's folder in the same source
--- root (created when missing), its `package` line and every import/reference updated by jdt.ls, touched
--- files written (unsaved ones left unsaved), the buffer re-pointed (undo kept), a summary shown.
--- Refused with nothing changed: invalid package, same package (a message), a class of that name already
--- in the target package (any source root), cursor in a nested/second type. opts.on_done(ok) afterwards.
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
  local client = jdtls_for(path)
  if not client or #vim.lsp.get_clients({ bufnr = buf, name = "jdtls" }) == 0 then
    return refuse("jdt.ls is not attached to this buffer")
  end
  local src_root, pkg = src_root_of(vim.fs.dirname(path))
  if not (path:match("%.java$") and src_root) then
    return refuse("this file is not a .java file in a source root (src/<set>/java)")
  end
  local t_sym = vim.uv.hrtime()
  local name, why = movable_type(buf, client, path)
  local symbols_ms = (vim.uv.hrtime() - t_sym) / 1e6
  if not name then return refuse(why .. "; nothing changed") end
  local project = require("nv4j.root").project(path)
  local roots = source_roots(project, src_root)
  local function run(target)
    if target == nil then return done(false) end -- cancelled
    target = vim.trim(target)
    if target == "" then return done(false) end
    for _, part in ipairs(vim.split(target, ".", { plain = true })) do
      if not valid_identifier(part) then
        return refuse(("'%s' is not a valid package name; nothing changed"):format(target), vim.log.levels.ERROR)
      end
    end
    if target == pkg then
      return refuse(("%s is already in package %s; nothing to do"):format(name, target), vim.log.levels.INFO)
    end
    local rel_to = target:gsub("%.", "/") .. "/" .. name .. ".java"
    for _, r in ipairs(roots) do
      if vim.uv.fs_stat(r .. "/" .. rel_to) then
        return refuse(("%s.%s already exists (%s); nothing changed, nothing overwritten"):format(target, name,
          rel(r .. "/" .. rel_to, project)), vim.log.levels.ERROR)
      end
    end
    local to = src_root .. "/" .. rel_to
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
    if #created > 0 then
      info[#info + 1] = ("created package folder %s"):format(rel(created[#created], project))
    end
    for _, r in ipairs(roots) do
      if r ~= src_root then
        for _, suffix in ipairs({ "Test", "Tests", "IT" }) do
          local t = r .. "/" .. (pkg or ""):gsub("%.", "/") .. "/" .. name .. suffix .. ".java"
          if vim.uv.fs_stat(t) then
            info[#info + 1] = ("%s stays in package %s (only %s moves; move it too with <leader>jm to keep them together)"):format(
              rel(t, project), pkg ~= "" and pkg or "(default)", name)
          end
        end
      end
    end
    local sw = spring_scan_warning(path, project, name, target)
    if sw then warn[#warn + 1] = sw end
    local label = ("Moved class %s to package %s"):format(name, target)
    local ok = M.rename_paths({ { path, to } }, label, client,
      { stale = { names = move_names(name, pkg), old = (pkg ~= "" and (pkg .. ".") or "") .. name }, info = info, warn = warn })
    if not ok then
      -- nothing moved (or part-way): the folders made for it go when empty
      local gone = {}
      for j = #created, 1, -1 do
        if vim.uv.fs_rmdir(created[j]) then gone[#gone + 1] = { uri = vim.uri_from_fname(created[j]), type = 3 } end
      end
      if #gone > 0 then client:notify("workspace/didChangeWatchedFiles", { changes = gone }) end
    elseif M.last then
      M.last.created, M.last.symbols_ms = created, symbols_ms
    end
    return done(ok)
  end
  if opts.package then return run(opts.package) end
  local NEW = "New package..."
  local items = vim.tbl_filter(function(p) return p ~= pkg end, project_packages(roots))
  items[#items + 1] = NEW
  vim.ui.select(items, { prompt = ("Move class %s (package %s) to:"):format(name, pkg ~= "" and pkg or "(default)") }, function(choice)
    if choice == NEW then
      vim.ui.input({ prompt = ("Move class %s to package: "):format(name), default = pkg }, run)
    else
      run(choice)
    end
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

--- `@Bean` on the method declared at 0-based line `l` of `lines` (annotation lines above it, or the same line).
local function is_bean(lines, l)
  local function bean(s) return s:find("@Bean%f[^%w_]") ~= nil end
  if bean(lines[l + 1] or "") then return true end
  for i = l, math.max(1, l - 8), -1 do
    local s = lines[i] or ""
    if bean(s) then return true end
    if not (s:match("^%s*@") or s:match("^%s*$") or s:match("^%s*//") or s:match("^%s*%*") or s:match("^%s*/%*")) then return false end
  end
  return false
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
      local res = client:request_sync("textDocument/references", { textDocument = { uri = decl.uri },
        position = { line = decl.l, character = decl.c }, context = { includeDeclaration = false } }, M.inline_ms, buf)
      for _, r in ipairs(res and type(res.result) == "table" and res.result or {}) do
        if r.uri and r.uri:match("^file:") then refs[#refs + 1] = { path = vim.uri_to_fname(r.uri), l = r.range.start.line } end
      end
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
    local touched = {}
    for _, f in ipairs(files) do touched[f.path] = true end
    local left = {}
    for _, r in ipairs(refs) do
      if not touched[r.path] then left[#left + 1] = ("%s:%d"):format(rel(r.path, root), r.l + 1) end
    end
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
      moves = namesake_moves(require("nv4j.root").project(src), r1, p1, p2)
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
