-- Project usage counts for Java completion ranking: how often each member name is used after a
-- `.` and each annotation after `@` in the project's own .java sources (import/package lines
-- excluded). Adapted from IntelliJ's PreferMostUsedWeigher (java-impl, compile-time occurrence
-- count of a member in the project); this is a name-level text count, not resolved references.
-- Built with ripgrep in the background, rebuilt (debounced) after a .java file is written.
-- No ripgrep, or a failed/timed-out run: the previous counts stay (none at first) and ranking
-- falls back to jdt.ls order. See specs/002-p1-completion.md.
local M = {}

M.TIMEOUT_MS = 10000 -- a run longer than this is killed and its result ignored
M.DEBOUNCE_MS = 1500 -- trailing delay after the last .java write before counting again
M.runs = 0 -- finished runs (tests)

local by_root = {} -- root -> { member = {name=n}, anno = {name=n}, busy, dirty, timer, watched }

-- One pipeline, all filtering outside Lua so a large project costs no main-loop time: every
-- non-import line of every .java file, then each `.name`/`@Name` token, counted. The first rg's
-- exit status goes to stderr ("RGRC n"; 0 = found, 1 = nothing found, 2+ = error) because a
-- POSIX sh pipeline only reports the last command's status.
local SCRIPT = [[{ rg --no-filename --no-line-number --no-messages -g '*.java' -v '^\s*(import|package)\s' -- "$1"; ]]
  .. [[echo "RGRC $?" >&2; } | rg --only-matching --no-line-number '[.@][A-Za-z_][A-Za-z0-9_]*' | sort | uniq -c]]

local function entry_for(root)
  by_root[root] = by_root[root] or {}
  return by_root[root]
end

function M.build(root)
  if not root or root == "" or vim.fn.executable("rg") == 0 then return end
  local entry = entry_for(root)
  if entry.busy then
    entry.dirty = true
    return
  end
  entry.busy = true
  -- Own process group (detach) so the timeout kills sh and both rg processes: killing only sh
  -- (vim.system's `timeout`) leaves rg holding the pipe open until it finishes.
  local timer = vim.uv.new_timer()
  local timed_out = false
  local ok, proc = pcall(vim.system, { "sh", "-c", SCRIPT, "sh", root }, { text = true, detach = true }, function(res)
    timer:stop()
    timer:close()
    local rgrc = tonumber((res.stderr or ""):match("RGRC (%d+)"))
    local good = not timed_out and res.code == 0 and res.signal == 0 and rgrc ~= nil and rgrc <= 1
    local member, anno = {}, {}
    if good then
      for n, sigil, name in (res.stdout or ""):gmatch("(%d+) ([.@])([%w_]+)") do
        local t = sigil == "@" and anno or member
        t[name] = (t[name] or 0) + tonumber(n)
      end
    end
    vim.schedule(function()
      if good then entry.member, entry.anno = member, anno end -- else keep the previous counts
      entry.busy, entry.last_ok = false, good
      M.runs = M.runs + 1
      if entry.dirty then
        entry.dirty = false
        M.build(root)
      end
    end)
  end)
  if not ok then
    timer:close()
    entry.busy = false
    return
  end
  timer:start(M.TIMEOUT_MS, 0, function()
    timed_out = true
    pcall(vim.uv.kill, -proc.pid, "sigterm")
  end)
end

--- Counts for a project root, or nil while none were ever built.
function M.get(root) return by_root[root] and by_root[root].member and by_root[root] end

--- Count again `DEBOUNCE_MS` after the last call (a burst of writes costs one run).
function M.schedule(root)
  local entry = entry_for(root)
  entry.timer = entry.timer or vim.uv.new_timer()
  entry.timer:stop()
  entry.timer:start(M.DEBOUNCE_MS, 0, vim.schedule_wrap(function() M.build(root) end))
end

local group = vim.api.nvim_create_augroup("nv4j_usage", { clear = true })
--- Start counting for `root` now and keep it current on every .java write under it.
function M.watch(root)
  if not root or vim.fn.executable("rg") == 0 or (by_root[root] and by_root[root].watched) then return end
  M.build(root)
  entry_for(root).watched = true
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.java",
    callback = function(args)
      if vim.startswith(vim.fn.fnamemodify(args.file, ":p"), root .. "/") then M.schedule(root) end
    end,
  })
end

return M
