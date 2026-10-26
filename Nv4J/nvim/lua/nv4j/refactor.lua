-- Refactors (decision D23, specs/features/refactors.md, check 62_refactor). P3 Task 4a: rename class and
-- rename package. Move, inline, change signature and safe delete come in later sub-tasks.
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
      M.last = { label = label, files = files, ok = true }
      notify(summary(label, files, root_of(client)))
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

--- Fallback edit for a package folder: the `package` line of every .java file under `from` (subpackages
--- too) set for its place under `to`. Text from the loaded buffer, else the disk.
local function package_lines_edit(from, to)
  local _, old_pkg = require("nv4j.scaffold").source_root(from)
  local _, new_pkg = require("nv4j.scaffold").source_root(to)
  if not (old_pkg and new_pkg) then return false end
  local changes = {}
  for name, kind in vim.fs.dir(from, { depth = 32 }) do
    if kind == "file" and name:match("%.java$") then
      local p = from .. "/" .. name
      local sub = vim.fs.dirname(name)
      sub = sub ~= "." and ("." .. sub:gsub("/", ".")) or ""
      local b = vim.fn.bufnr(p)
      local lines = (b ~= -1 and vim.api.nvim_buf_is_loaded(b)) and vim.api.nvim_buf_get_lines(b, 0, -1, false) or vim.fn.readfile(p)
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
function M.rename_paths(moves, label, client)
  local function fail(msg, level)
    msg = label:gsub("^Renamed", "Rename") .. ": " .. msg .. "; nothing changed"
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
    while edit == false and i > 1 and has_java(from) and tries < 10 do
      vim.wait(100)
      edit, err = will_rename(client, from, to)
      tries = tries + 1
    end
    tries_by[from] = tries
    lap("will")
    if edit == false and i > 1 and has_java(from) then
      edit = package_lines_edit(from, to)
      notes[#notes + 1] = ("package lines in %s set by Nv4J (jdt.ls gave no edit): references to its classes from other packages were not updated"):format(rel(from, root))
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
  M.last = { label = label, files = files, ok = true, moves = moves, tries = tries_by, notes = notes, ms = ms }
  notify(summary(("%s (moved %s)"):format(label, moved), files, root) .. (#notes > 0 and (". NOTE: " .. table.concat(notes, "; ")) or ""),
    #notes > 0 and vim.log.levels.WARN or nil)
  follow_up(label, before, vim.tbl_map(function(f) return f.path end, files))
  return true
end

--- Package of `dir` when it is inside a `src/<set>/java` source root: root, package ("" = default).
local function source_root(dir)
  return require("nv4j.scaffold").source_root(dir)
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
    local new_path = name:gsub("%.", "/")
    -- this source root and the namesake package folders in the project's other roots, src/main/java
    -- first (see M.rename_paths)
    local roots = { src_root }
    local project = require("nv4j.root").project(path)
    for _, r in ipairs(vim.fn.glob(project .. "/src/*/java", false, true)) do
      r = vim.fs.normalize(r)
      if r ~= src_root and vim.fn.isdirectory(r .. "/" .. pkg_path) == 1 then roots[#roots + 1] = r end
    end
    table.sort(roots, function(a, b)
      local ma, mb = a:match("/src/main/java$") ~= nil, b:match("/src/main/java$") ~= nil
      if ma ~= mb then return ma end
      return a < b
    end)
    local moves = vim.tbl_map(function(r) return { r .. "/" .. pkg_path, r .. "/" .. new_path } end, roots)
    local ok = M.rename_paths(moves, ("Renamed package %s -> %s"):format(pkg, name))
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

-- ── neo-tree (plugins/neo-tree.lua) ──────────────────────────────────────────────────────────────

local handled = {} -- source -> destination renamed here; neo-tree's after-hooks (LazyVim's) skip them

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
    local _, p2 = source_root(vim.fs.dirname(dest))
    return ("Moved class %s to %s"):format(a, p2 and ("package " .. p2) or vim.fs.dirname(dest))
  end
  local _, p1 = source_root(source)
  local _, p2 = source_root(dest)
  if p1 and p2 and p1 ~= "" and p2 ~= "" then return ("Renamed package %s -> %s"):format(p1, p2) end
  return ("Renamed %s -> %s"):format(vim.fs.basename(source), vim.fs.basename(dest))
end

--- neo-tree before_file_rename / before_file_move handler: the whole rename is done here (jdt.ls asked
--- before the move) and neo-tree is told it is handled. On a refusal nothing moves (message shown).
function M.neotree_before(args)
  if not (args and args.source and args.destination) or not is_java(args.source) then return nil end
  M.rename_paths({ { args.source, args.destination } }, label_for(args.source, args.destination))
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
