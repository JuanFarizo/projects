-- Debug-only capture of raw language server stdout (flake A, `INVALID_SERVER_JSON`, docs/HANDOFF-p3.md).
-- OFF by default and then costs nothing: nothing is wrapped and this module is only required, never started.
-- On with `vim.g.nv4j_lsp_capture = true` (before the first Java file) or env `NV4J_LSP_CAPTURE=1`.
--
-- Hook (no private Neovim internals): `vim.lsp.rpc.start` (public) is wrapped once. For a jdt.ls or Spring Boot LS
-- command only, `vim.system` (public) is replaced for the duration of that one synchronous call, so the `stdout`
-- callback Neovim hands it is teed into a ring of the last 128 KB. The client's `on_error` / `on_exit` dispatchers are
-- wrapped to dump the ring. This relies on rpc.start calling vim.system synchronously (Neovim 0.12.4:
-- `lsp/_transport.lua`); if it does not, the capture says so once (WARN) and the server still starts untouched.
-- Every step is pcall-guarded: a broken capture never stops a server.
--
-- Dump: `/tmp/nv4j/logs/lsp-capture-<client>-<YYYYmmdd-HHMMSS>[-exit].bin` (raw bytes, at most 128 KB, the tail of
-- the stream) and one WARN with the path. Written when `on_error` reports INVALID_SERVER_JSON (once per client)
-- and when the server exits abnormally (non-zero code or a signal), suffix `-exit`.
local M = {}

M.CAP = 128 * 1024

local state = {} ---@type table[] one per captured client: { name, chunks, bytes, json_dumped }
local installed ---@type function|nil the original vim.lsp.rpc.start while the wrapper is installed
local warned_nohook = false

--- Whether the capture is on (re-read at each use).
function M.enabled()
  return vim.g.nv4j_lsp_capture == true or vim.env.NV4J_LSP_CAPTURE == "1"
end

--- "jdtls" / "spring-boot" for a server command line, nil for any other server.
---@param cmd any
---@return string?
function M.name_of(cmd)
  if type(cmd) ~= "table" or type(cmd[1]) ~= "string" then return nil end
  if vim.fs.basename(cmd[1]) == "jdtls" then return "jdtls" end
  for _, a in ipairs(cmd) do
    if type(a) == "string" and (vim.fs.basename(a) == "language-server.jar" or a:find("BootLanguageServerBootApp", 1, true)
      or a:find("vscode-spring-boot", 1, true)) then
      return "spring-boot"
    end
  end
end

local function push(st, chunk)
  if type(chunk) ~= "string" or chunk == "" then return end
  st.chunks[#st.chunks + 1] = chunk
  st.bytes = st.bytes + #chunk
  while #st.chunks > 1 and st.bytes - #st.chunks[1] >= M.CAP do
    st.bytes = st.bytes - #table.remove(st.chunks, 1)
  end
end

--- The last up to 128 KB of raw stdout seen by `st`.
function M.tail(st)
  local all = table.concat(st.chunks)
  return #all > M.CAP and all:sub(-M.CAP) or all
end

--- Write the ring of `st` to the log dir and WARN with the path. Safe in a fast (libuv) context.
---@param st table
---@param reason string text for the WARN
---@param suffix? string "-exit" for a server exit
---@return string? path
function M.dump(st, reason, suffix)
  local dir = require("nv4j.paths").logs
  local path = ("%s/lsp-capture-%s-%s%s.bin"):format(dir, st.name, os.date("%Y%m%d-%H%M%S"), suffix or "")
  local n = 0
  while vim.uv.fs_stat(path) do -- two dumps in one second
    n = n + 1
    path = ("%s/lsp-capture-%s-%s%s-%d.bin"):format(dir, st.name, os.date("%Y%m%d-%H%M%S"), suffix or "", n)
  end
  local f = io.open(path, "wb")
  if not f then return nil end
  local data = M.tail(st)
  f:write(data)
  f:close()
  st.last_dump = path
  vim.schedule(function()
    vim.notify(("%s (%s): last %d bytes of its stdout saved to %s"):format(st.name, reason, #data, path),
      vim.log.levels.WARN, { title = "Nv4J" })
  end)
  return path
end

--- Captured clients (tests, :lua inspection): { name, bytes, last_dump, ... }.
function M.states() return state end

local function wrap_dispatchers(st, dispatchers)
  dispatchers = dispatchers or {}
  local d = vim.tbl_extend("force", {}, dispatchers)
  local on_error, on_exit = dispatchers.on_error, dispatchers.on_exit
  d.on_error = function(code, ...)
    if code == vim.lsp.rpc.client_errors.INVALID_SERVER_JSON and not st.json_dumped then
      st.json_dumped = true
      pcall(M.dump, st, "INVALID_SERVER_JSON")
    end
    if on_error then return on_error(code, ...) end
  end
  d.on_exit = function(code, signal, ...)
    if (code ~= 0 or (signal or 0) ~= 0) and not st.exit_dumped then
      st.exit_dumped = true
      pcall(M.dump, st, ("server exited, code %s, signal %s"):format(tostring(code), tostring(signal)), "-exit")
    end
    if on_exit then return on_exit(code, signal, ...) end
  end
  return d
end

--- Start `orig_start(cmd, dispatchers, extra)` with the stdout of the spawned server teed into `st`.
local function start_captured(orig_start, st, cmd, dispatchers, extra)
  local real_system, hooked = vim.system, false
  vim.system = function(c, o, ...)
    if not hooked and type(o) == "table" and type(o.stdout) == "function" then
      hooked = true
      local out = o.stdout
      o = vim.tbl_extend("force", o, { stdout = function(err, data)
        pcall(push, st, data)
        return out(err, data)
      end })
    end
    return real_system(c, o, ...)
  end
  local ok, res = pcall(orig_start, cmd, wrap_dispatchers(st, dispatchers), extra)
  vim.system = real_system
  if not ok then error(res, 0) end
  if not hooked and not warned_nohook then
    warned_nohook = true
    vim.schedule(function()
      vim.notify("nv4j: LSP capture could not hook the stdout of " .. st.name .. " (vim.system was not used by rpc.start in this Neovim)",
        vim.log.levels.WARN, { title = "Nv4J" })
    end)
  end
  return res
end

--- Install the rpc.start wrapper when the capture is enabled (idempotent, a no-op when off).
---@return boolean installed
function M.install()
  if installed then return true end
  if not M.enabled() then return false end
  local rpc = vim.lsp.rpc
  if type(rpc) ~= "table" or type(rpc.start) ~= "function" then return false end
  local orig = rpc.start
  installed = orig
  rpc.start = function(cmd, dispatchers, extra, ...)
    local name = M.enabled() and M.name_of(cmd)
    if not name then return orig(cmd, dispatchers, extra, ...) end
    local st = { name = name, chunks = {}, bytes = 0 }
    state[#state + 1] = st
    local ok, res = pcall(start_captured, orig, st, cmd, dispatchers, extra)
    if ok then return res end
    return orig(cmd, dispatchers, extra, ...) -- the capture itself failed before spawning: start untouched
  end
  return true
end

--- Remove the wrapper (tests).
function M.uninstall()
  if installed then vim.lsp.rpc.start = installed end
  installed = nil
  state = {}
  warned_nohook = false
end

return M
