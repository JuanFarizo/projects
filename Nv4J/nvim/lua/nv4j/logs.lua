-- :Nv4JLogs: one registry of every log Nv4J (and the tools under it) writes, a picker over it, and "save for analysis".
-- Logs STAY where their writers put them (/tmp/nv4j/logs, jdt.ls data dir, stdpath("state")); this module only reads them. Saving
-- copies into stdpath("state")/nv4j/saved-logs/<YYYYmmdd-HHMMSS>/; originals are never modified or deleted.
-- Add a source = add one entry to M.SOURCES (or M.register at runtime):
--   { id, label, kind, files = function(dirs) -> { path | { path=, label= } ... } }
-- `kind = "test"` sources are hidden unless opts.tests. A path claimed by an earlier source is not listed again.
local M = {}

local uv = vim.uv

--- Directories the sources are looked up in (override all of them in tests).
function M.dirs()
  local paths = require("nv4j.paths")
  return { logs = paths.logs, state = vim.fn.stdpath("state"), jdtls_data = paths.jdtls_data }
end

local function glob(pattern) return vim.fn.glob(pattern, true, true) end
local function join(...)
  local out = {}
  for _, l in ipairs({ ... }) do vim.list_extend(out, l) end
  return out
end

---@type { id: string, label: string, kind: string, files: fun(d: table): any[] }[]
M.SOURCES = {
  { id = "lsp-projects", label = "nvim LSP log (no project)", kind = "lsp", files = function(d) return glob(d.logs .. "/lsp-projects-*.log") end },
  { id = "lsp", label = "nvim LSP log", kind = "lsp",
    files = function(d) return join(glob(d.logs .. "/lsp-*.log"), glob(d.logs .. "/lsp-*.log.1"), glob(d.logs .. "/lsp.log"), glob(d.logs .. "/lsp.log.1")) end },
  { id = "spring-ls", label = "Spring LS", kind = "spring", files = function(d) return join(glob(d.logs .. "/spring-boot-ls.log"), glob(d.logs .. "/spring-boot-ls.log.1")) end },
  { id = "spring-route", label = "Spring routing", kind = "spring", files = function(d) return join(glob(d.logs .. "/spring-route.log"), glob(d.logs .. "/spring-route.log.1")) end },
  { id = "jdtls", label = "jdt.ls", kind = "jdtls",
    files = function(d)
      local out = {}
      for _, p in ipairs(glob(d.jdtls_data .. "/*/.metadata/.log")) do
        out[#out + 1] = { path = p, label = "jdt.ls " .. vim.fs.basename(vim.fs.dirname(vim.fs.dirname(p))) }
      end
      return out
    end },
  { id = "dap", label = "nvim-dap", kind = "dap", files = function(d) return glob(d.state .. "/dap.log") end },
  { id = "lsp-capture", label = "LSP raw capture", kind = "capture", files = function(d) return glob(d.logs .. "/lsp-capture-*.bin") end },
  { id = "latency", label = "test latency", kind = "latency", files = function(d) return join(glob(d.logs .. "/latency.jsonl"), glob(d.logs .. "/latency.prev.jsonl")) end },
  { id = "completion-profile", label = "completion profile", kind = "profile", files = function(d) return glob(d.state .. "/completion-profile.jsonl") end },
  { id = "test", label = "test run", kind = "test", files = function(d) return glob(d.logs .. "/test-*.log") end },
}

--- Adds (or replaces, same id) a source at runtime.
function M.register(src)
  for i, s in ipairs(M.SOURCES) do
    if s.id == src.id then M.SOURCES[i] = src; return end
  end
  M.SOURCES[#M.SOURCES + 1] = src
end

--- "30m", "2h", "1d", "7d" -> seconds; nil (or anything else) -> nil.
function M.parse_period(s)
  if type(s) ~= "string" then return nil end
  local n, u = s:match("^(%d+)([mhd])$")
  if not n then return nil end
  return tonumber(n) * ({ m = 60, h = 3600, d = 86400 })[u]
end

function M.age_str(sec)
  if sec < 90 then return sec .. "s" end
  if sec < 5400 then return math.floor(sec / 60 + 0.5) .. "m" end
  if sec < 129600 then return math.floor(sec / 3600 + 0.5) .. "h" end
  return math.floor(sec / 86400 + 0.5) .. "d"
end

--- Entries of every existing log, newest first.
---@param opts? { since?: string, id?: string, tests?: boolean, dirs?: table, now?: integer }
---@return { id: string, label: string, kind: string, path: string, size: integer, mtime: integer, age: integer }[]
function M.entries(opts)
  opts = opts or {}
  local dirs = vim.tbl_extend("force", M.dirs(), opts.dirs or {})
  local now = opts.now or os.time()
  local window = M.parse_period(opts.since)
  local seen, out = {}, {}
  for _, src in ipairs(M.SOURCES) do
    if (src.kind ~= "test" or opts.tests or opts.id == src.id) and (not opts.id or opts.id == src.id) then
      local ok, list = pcall(src.files, dirs)
      for _, f in ipairs(ok and list or {}) do
        local path = type(f) == "table" and f.path or f
        local st = not seen[path] and uv.fs_stat(path) or nil
        if st and st.type == "file" and (not window or now - st.mtime.sec <= window) then
          seen[path] = true
          local label = type(f) == "table" and f.label or ((src.label .. " " .. vim.fs.basename(path)):gsub("%s+$", ""))
          out[#out + 1] = { id = src.id, kind = src.kind, label = label, path = path, size = st.size, mtime = st.mtime.sec,
            age = math.max(0, now - st.mtime.sec) }
        end
      end
    end
  end
  table.sort(out, function(a, b) if a.mtime ~= b.mtime then return a.mtime > b.mtime end return a.path < b.path end)
  return out
end

--- Copies the files (paths or entries) into <dest_root>/<YYYYmmdd-HHMMSS>/ byte for byte; originals untouched.
--- Name clashes (same basename from two dirs) get a numeric prefix. Returns the folder and the copied paths.
---@param items (string|table)[]
---@param opts? { dest_root?: string, now?: integer }
function M.save(items, opts)
  opts = opts or {}
  local root = opts.dest_root or (vim.fn.stdpath("state") .. "/nv4j/saved-logs")
  local dest = root .. "/" .. os.date("%Y%m%d-%H%M%S", opts.now)
  local copied = {}
  if #items == 0 then return dest, copied end
  local n = 1
  while uv.fs_stat(dest) do dest = ("%s/%s-%d"):format(root, os.date("%Y%m%d-%H%M%S", opts.now), n); n = n + 1 end
  vim.fn.mkdir(dest, "p")
  local used = {}
  for i, it in ipairs(items) do
    local src = type(it) == "table" and it.path or it
    local name = vim.fs.basename(src)
    if name:sub(1, 1) == "." and type(it) == "table" then name = (it.label:gsub("[^%w%._-]", "_")) .. name:gsub("^%.", ".") end -- jdt.ls ".log" of each project
    if used[name] then name = i .. "-" .. name end
    used[name] = true
    local target = dest .. "/" .. name
    if uv.fs_copyfile(src, target) then copied[#copied + 1] = target end
  end
  return dest, copied
end

--- `:JdtShowLogs` replacement: nvim-jdtls opens stdpath("log")/lsp.log, which init.lua no longer writes. Opens the jdt.ls log of
--- the current buffer's project and the real Neovim LSP log.
function M.show_jdt_logs()
  local data
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0, name = "jdtls" })) do
    local cmd = c.config.cmd
    for i, a in ipairs(type(cmd) == "table" and cmd or {}) do
      if a == "-data" then data = cmd[i + 1] end
    end
    if data then break end
  end
  if data then vim.cmd("split | e " .. vim.fn.fnameescape(data .. "/.metadata/.log") .. " | normal G") end
  vim.cmd("vsplit | e " .. vim.fn.fnameescape(vim.lsp.log.get_filename()) .. " | normal G")
end

--- Defines :Nv4JLogs (idempotent). The picker lives in nv4j/logsui.lua and loads on first use.
function M.setup()
  vim.api.nvim_create_user_command("Nv4JLogs", function(o) require("nv4j.logsui").command(o.fargs) end, {
    nargs = "*",
    desc = "Nv4J logs: picker over every log (period 30m 2h 1d 7d; `save [period]`; `tests` adds test logs)",
    complete = function() return { "30m", "2h", "1d", "7d", "save", "tests" } end,
  })
end

return M
