-- Snapshot and restore of the fixture's source tree for checks that change files on disk (P3:
-- 61_scaffold creates files, 62_refactor renames and moves them through jdt.ls workspace edits).
-- restore() puts every file back byte for byte, removes what the check added, drops the buffers,
-- and tells the running jdt.ls (didChangeWatchedFiles + refresh + build, nv4j.debug) so its
-- workspace does not keep a renamed or deleted file into the next session (jdt.ls does not see
-- disk changes made while it is down, specs/features/debug-run.md).
local M = {}

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write(path, s)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "wb"))
  f:write(s)
  f:close()
end

--- Files and directories under <root>/src: { files = { [abs] = content }, dirs = { [abs] = true } }.
function M.snapshot(root)
  root = root or vim.env.NV4J_FIXTURE
  local snap = { root = root, files = {}, dirs = {} }
  for rel, kind in vim.fs.dir(root .. "/src", { depth = 32 }) do
    local abs = root .. "/src/" .. rel
    if kind == "file" then snap.files[abs] = read(abs) elseif kind == "directory" then snap.dirs[abs] = true end
  end
  return snap
end

--- What differs from the snapshot now: { added = {abs...}, changed = {abs...}, missing = {abs...}, dirs = {abs...} }.
function M.diff(snap)
  local now = M.snapshot(snap.root)
  local d = { added = {}, changed = {}, missing = {}, dirs = {} }
  for abs, s in pairs(now.files) do
    if snap.files[abs] == nil then d.added[#d.added + 1] = abs elseif snap.files[abs] ~= s then d.changed[#d.changed + 1] = abs end
  end
  for abs in pairs(snap.files) do
    if now.files[abs] == nil then d.missing[#d.missing + 1] = abs end
  end
  for abs in pairs(now.dirs) do
    if not snap.dirs[abs] then d.dirs[#d.dirs + 1] = abs end
  end
  return d
end

--- Class files compiled from `src` (main or test) by jdt.ls or mvn: Name.class and Name$*.class.
local function class_files(root, src)
  local rel = src:match("/src/main/java/(.+)%.java$")
  local out = rel and "target/classes" or "target/test-classes"
  rel = rel or src:match("/src/test/java/(.+)%.java$")
  if not rel then return {} end
  local base = root .. "/" .. out .. "/" .. rel
  local list = vim.fn.glob(base .. "$*.class", false, true)
  list[#list + 1] = base .. ".class"
  return list
end

--- Restore the snapshot. `client` (optional): the jdtls client to notify; waits for its build
--- (at most 60 s). Returns the diff that was undone.
function M.restore(snap, client)
  local root = snap.root
  -- buffers first: a modified buffer of a moved file must not be written back later
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name:sub(1, #root + 1) == root .. "/" and vim.api.nvim_buf_is_valid(b) then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
  local d = M.diff(snap)
  local changes = {}
  for _, abs in ipairs(d.added) do
    os.remove(abs)
    for _, c in ipairs(class_files(root, abs)) do os.remove(c) end
    changes[#changes + 1] = { uri = vim.uri_from_fname(abs), type = 3 }
  end
  for _, abs in ipairs(d.changed) do
    write(abs, snap.files[abs])
    changes[#changes + 1] = { uri = vim.uri_from_fname(abs), type = 2 }
  end
  for _, abs in ipairs(d.missing) do
    write(abs, snap.files[abs])
    changes[#changes + 1] = { uri = vim.uri_from_fname(abs), type = 1 }
  end
  -- deepest first, only if empty
  table.sort(d.dirs, function(a, b) return #a > #b end)
  for _, abs in ipairs(d.dirs) do
    vim.uv.fs_rmdir(abs)
    changes[#changes + 1] = { uri = vim.uri_from_fname(abs), type = 3 }
  end
  if client and not client:is_stopped() and #changes > 0 then
    client:notify("workspace/didChangeWatchedFiles", { changes = changes })
    local done = false
    require("nv4j.debug").refresh_and_build(root, function() done = true end, "fixture restore")
    vim.wait(60000, function() return done end, 50)
  end
  return d
end

--- Short text of a diff for case details.
function M.fmt(d)
  local function names(list)
    return table.concat(vim.tbl_map(function(p) return (p:gsub("^.*/src/", "src/")) end, list), ",")
  end
  return ("added [%s] changed [%s] missing [%s]"):format(names(d.added), names(d.changed), names(d.missing))
end

return M
