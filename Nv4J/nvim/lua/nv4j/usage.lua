-- Project usage counts for Java completion ranking: how often each member name is used after a
-- `.` and each annotation after `@` in the project's own .java sources (import/package lines
-- excluded). Adapted from IntelliJ's PreferMostUsedWeigher (java-impl, compile-time occurrence
-- count of a member in the project); this is a name-level text count, not resolved references.
-- Built with ripgrep in the background (no ripgrep: no counts, ranking falls back to jdt.ls order),
-- rebuilt after a .java file is written. See specs/002-p1-completion.md.
local M = {}

local by_root = {} -- root -> { member = {name=n}, anno = {name=n}, busy, dirty }

-- One pipeline, all filtering outside Lua so a large project costs no main-loop time:
-- every non-import line of every .java file, then each `.name`/`@Name` token, counted.
local SCRIPT = [[rg --no-filename --no-line-number --no-messages -g '*.java' -v '^\s*(import|package)\s' -- "$1" ]]
  .. [[| rg --only-matching --no-line-number '[.@][A-Za-z_][A-Za-z0-9_]*' | sort | uniq -c]]

function M.build(root)
  if not root or root == "" or vim.fn.executable("rg") == 0 then return end
  local entry = by_root[root] or {}
  by_root[root] = entry
  if entry.busy then
    entry.dirty = true
    return
  end
  entry.busy = true
  vim.system({ "sh", "-c", SCRIPT, "sh", root }, { text = true }, function(res)
    local member, anno = {}, {}
    for n, sigil, name in (res.stdout or ""):gmatch("(%d+) ([.@])([%w_]+)") do
      local t = sigil == "@" and anno or member
      t[name] = (t[name] or 0) + tonumber(n)
    end
    vim.schedule(function()
      entry.member, entry.anno, entry.busy = member, anno, false
      if entry.dirty then
        entry.dirty = false
        M.build(root)
      end
    end)
  end)
end

--- Counts for a project root, or nil while not built yet.
function M.get(root) return by_root[root] and by_root[root].member and by_root[root] end

local group = vim.api.nvim_create_augroup("nv4j_usage", { clear = true })
--- Start counting for `root` now and keep it current on every .java write under it.
function M.watch(root)
  if not root or vim.fn.executable("rg") == 0 or (by_root[root] and by_root[root].watched) then return end
  M.build(root)
  by_root[root].watched = true
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.java",
    callback = function(args)
      if vim.startswith(vim.fn.fnamemodify(args.file, ":p"), root .. "/") then M.build(root) end
    end,
  })
end

return M
