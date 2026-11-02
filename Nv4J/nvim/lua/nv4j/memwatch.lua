-- Memory warning for jdt.ls (user ruling 2026-11-02, specs/001 D25): NO limit and no cap on jdt.ls memory.
-- One WARN per jdt.ls client per session once its process reaches vim.g.nv4j_jdtls_warn_mb (default 2048 MB RSS;
-- 0 = never warn). It never blocks, restarts or limits anything. Spring LS and other clients are not looked at.
-- One vim.uv timer every vim.g.nv4j_memwatch_ms (default 60000), started when the first jdtls client attaches
-- (M.start), stopped when no jdtls client runs and on VimLeavePre. Reads use vim.system (async), never :wait().
local M = {}

local timer ---@type uv.uv_timer_t|nil
local warned = {} ---@type table<string, boolean> client key -> already warned (this session)
local pids = {} ---@type table<integer, string> client id -> pid (cached, jdt.ls is a child of this nvim)
local busy = false

local function threshold() return tonumber(vim.g.nv4j_jdtls_warn_mb) or 2048 end

local function key(c) return tostring(c.id) end

--- Pure: warn for each jdtls client in `clients` whose `rss_of(client)` (MB, or nil) is >= the threshold, once per
--- client key in `warned` (mutated). `notify` defaults to vim.notify. Returns the messages sent.
---@param clients table[] LSP clients (`id`, `name`, `config.root_dir`)
---@param rss_of fun(c: table): number|nil
---@param warned table<string, boolean>
---@param notify? fun(msg: string, level: integer, opts: table)
---@param limit_mb? number threshold, default vim.g.nv4j_jdtls_warn_mb or 2048
function M.check(clients, rss_of, warned, notify, limit_mb)
  limit_mb = limit_mb or threshold()
  notify = notify or vim.notify
  local sent = {}
  if limit_mb <= 0 then return sent end
  for _, c in ipairs(clients) do
    local k = key(c)
    if c.name == "jdtls" and not warned[k] then
      local mb = rss_of(c)
      if mb and mb >= limit_mb then
        warned[k] = true
        local msg = ("jdt.ls for %s uses %d MB (warning at %d MB; nothing is limited or restarted). Several jdt.ls running? "
          .. "Put an empty .nv4j in the project's top folder. Or restart it with :LspRestart, or quit and reopen."):format(
          c.config and c.config.root_dir or "?", mb, limit_mb)
        sent[#sent + 1] = msg
        notify(msg, vim.log.levels.WARN, { title = "Nv4J" })
      end
    end
  end
  return sent
end

local function jdtls_clients() return vim.lsp.get_clients({ name = "jdtls" }) end

local function data_dir(c)
  local cmd = c.config and c.config.cmd or {}
  for i, a in ipairs(cmd) do
    if a == "-data" then return cmd[i + 1] end
  end
end

--- Async: find the jdt.ls pid of `c` (child of this nvim whose command line ends with its -data dir).
local function find_pid(c, cb)
  if pids[c.id] then return cb(pids[c.id]) end
  local d = data_dir(c)
  if not d then return cb(nil) end
  vim.system({ "pgrep", "-P", tostring(vim.fn.getpid()), "-f", "-data " .. d .. "$" }, { text = true }, function(r)
    local pid = (r.stdout or ""):match("^(%d+)")
    if pid then pids[c.id] = pid end
    cb(pid)
  end)
end

local function stop()
  if timer then
    timer:stop()
    if not timer:is_closing() then timer:close() end
    timer = nil
  end
end
M.stop = stop
--- Whether the sampling timer exists (tests).
function M._timer_active() return timer ~= nil end

local function sample()
  if busy then return end
  local clients = jdtls_clients()
  if #clients == 0 then return stop() end
  if threshold() <= 0 then return end
  busy = true
  local rss, left = {}, #clients
  local function done()
    busy = false
    vim.schedule(function()
      M.check(jdtls_clients(), function(c) return rss[c.id] end, warned)
    end)
  end
  for _, c in ipairs(clients) do
    find_pid(c, function(pid)
      if not pid then
        left = left - 1
        if left == 0 then done() end
        return
      end
      vim.system({ "ps", "-o", "rss=", "-p", pid }, { text = true }, function(r)
        local kb = tonumber(vim.trim(r.stdout or ""))
        if kb then rss[c.id] = kb / 1024 end
        left = left - 1
        if left == 0 then done() end
      end)
    end)
  end
end

--- Called on every jdtls attach: starts the timer once (no-op while it runs).
function M.start()
  if timer or threshold() <= 0 then return end
  timer = vim.uv.new_timer()
  local ms = tonumber(vim.g.nv4j_memwatch_ms) or 60000
  timer:start(ms, ms, vim.schedule_wrap(sample))
  if not M._au then
    M._au = vim.api.nvim_create_autocmd("VimLeavePre", { callback = stop })
  end
end

return M
