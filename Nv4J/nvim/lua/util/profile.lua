-- Opt-in completion profiler. Nothing is installed until `:CompletionProfile on`
-- (and it is always off after a restart), so it costs nothing in daily use.
-- Writes JSON lines to stdpath("state")/completion-profile.jsonl.
local M = {}

local uv = vim.uv
local path = vim.fn.stdpath("state") .. "/completion-profile.jsonl"
local STALL_TICK_MS, STALL_MIN_MS = 50, 30

local state = { on = false, fd = nil, last_key = nil, augroup = nil, timer = nil, wrapped = {}, orig_fuzzy = nil, list = nil }

local function now_ms() return uv.hrtime() / 1e6 end

local function log(ev, fields)
  if not state.fd then return end
  fields.ev, fields.t = ev, math.floor(now_ms())
  fields.ft, fields.buf_lines = vim.bo.filetype, vim.api.nvim_buf_line_count(0)
  uv.fs_write(state.fd, vim.json.encode(fields) .. "\n")
end

-- Time every textDocument/completion round trip (jdtls latency, item count,
-- isIncomplete = blink must re-query on the next keystroke).
-- Wrapped per client: each client instance carries its own `request`, so
-- patching the shared Client class has no effect.
local function wrap_client(client)
  if state.wrapped[client.id] then return end
  local orig = client.request
  state.wrapped[client.id] = { client = client, orig = orig }
  client.request = function(self, method, params, handler, bufnr)
    if method ~= "textDocument/completion" or not handler then
      return orig(self, method, params, handler, bufnr)
    end
    local t0 = now_ms()
    return orig(self, method, params, function(err, result, ...)
      local items = result and (result.items or result) or {}
      log("lsp_completion", {
        client = self.name, ms = now_ms() - t0, items = #items,
        incomplete = result and result.isIncomplete or false, err = err and true or false,
      })
      return handler(err, result, ...)
    end, bufnr)
  end
end

local function patch_lsp_request()
  for _, c in ipairs(vim.lsp.get_clients()) do wrap_client(c) end
  vim.api.nvim_create_autocmd("LspAttach", {
    group = state.augroup,
    callback = function(args)
      local c = vim.lsp.get_client_by_id(args.data.client_id)
      if c then wrap_client(c) end
    end,
  })
end

-- Time blink's Rust fuzzy match + sort.
local function patch_fuzzy()
  local fuzzy = require("blink.cmp.fuzzy")
  state.orig_fuzzy = fuzzy.fuzzy
  fuzzy.fuzzy = function(...)
    local t0 = now_ms()
    local res = state.orig_fuzzy(...)
    log("fuzzy", { ms = now_ms() - t0, out = #res })
    return res
  end
end

-- What the menu actually showed after every update: the top 10 as blink ranked them,
-- with score and the jdtls sortText that decided ties.
local function on_list_show(ev)
  local top = {}
  for i = 1, math.min(10, #ev.items) do
    local it = ev.items[i]
    top[i] = {
      l = it.label, k = it.kind, score = it.score, st = it.sortText,
      d = it.labelDetails and it.labelDetails.description or nil, src = it.source_id,
    }
  end
  log("menu_snapshot", { keyword = ev.context.get_keyword(), total = #ev.items, top = top })
end

local function patch_list()
  local ok, list = pcall(require, "blink.cmp.completion.list")
  if ok then list.show_emitter:on(on_list_show) end
  state.list = ok and list or nil
end

local function unpatch()
  if state.list then state.list.show_emitter:off(on_list_show); state.list = nil end
  for _, w in pairs(state.wrapped) do w.client.request = w.orig end
  state.wrapped = {}
  if state.orig_fuzzy then require("blink.cmp.fuzzy").fuzzy = state.orig_fuzzy end
  state.orig_fuzzy = nil
end

function M.on()
  if state.on then return end
  state.fd = assert(uv.fs_open(path, "a", 420))
  state.on = true
  state.augroup = vim.api.nvim_create_augroup("CompletionProfile", { clear = true })

  patch_lsp_request()
  patch_list()
  if package.loaded["blink.cmp.fuzzy"] or pcall(require, "blink.cmp.fuzzy") then patch_fuzzy() end

  -- Keystroke -> menu latency: stamp every typed key in insert mode.
  vim.on_key(function(key)
    if vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then state.last_key = now_ms() end
  end, vim.api.nvim_create_namespace("CompletionProfile"))

  vim.api.nvim_create_autocmd("User", {
    group = state.augroup,
    pattern = "BlinkCmpMenuOpen",
    callback = function()
      log("menu_open", { since_key_ms = state.last_key and (now_ms() - state.last_key) or vim.NIL })
    end,
  })
  -- jdtls "Building"/"Publish Diagnostics" work that overlaps typing.
  vim.api.nvim_create_autocmd("LspProgress", {
    group = state.augroup,
    callback = function(args)
      local v = args.data and args.data.params and args.data.params.value or {}
      log("lsp_progress", { kind = v.kind, title = v.title, message = v.message })
    end,
  })

  -- Event-loop stall detector: a tick that fires late means the editor was
  -- blocked (any cause), which is what typing lag feels like.
  local expected = now_ms() + STALL_TICK_MS
  state.timer = uv.new_timer()
  state.timer:start(STALL_TICK_MS, STALL_TICK_MS, function()
    local t = now_ms()
    local late = t - expected
    expected = t + STALL_TICK_MS
    if late > STALL_MIN_MS then
      vim.schedule(function() log("stall", { late_ms = late, mode = vim.fn.mode() }) end)
    end
  end)

  log("profile_on", { nvim = tostring(vim.version()) })
  vim.notify("Completion profiling ON -> " .. path, vim.log.levels.INFO)
end

function M.off()
  if not state.on then return end
  log("profile_off", {})
  state.on = false
  unpatch()
  if state.timer then state.timer:stop(); state.timer:close(); state.timer = nil end
  if state.augroup then vim.api.nvim_del_augroup_by_id(state.augroup); state.augroup = nil end
  vim.on_key(nil, vim.api.nvim_create_namespace("CompletionProfile"))
  uv.fs_close(state.fd)
  state.fd = nil
  vim.notify("Completion profiling OFF", vim.log.levels.INFO)
end

function M.status()
  local st = uv.fs_stat(path)
  vim.notify(("Completion profiling %s\nlog: %s (%s KB)"):format(state.on and "ON" or "off", path,
    st and math.floor(st.size / 1024) or 0))
end

function M.clear()
  if state.on then return vim.notify("Turn profiling off before clearing", vim.log.levels.WARN) end
  os.remove(path)
end

function M.setup()
  vim.api.nvim_create_user_command("CompletionProfile", function(opts)
    local fn = M[opts.args == "" and "status" or opts.args]
    if not fn or opts.args == "setup" then return vim.notify("Usage: :CompletionProfile on|off|status|clear", vim.log.levels.ERROR) end
    fn()
  end, {
    nargs = "?",
    complete = function() return { "on", "off", "status", "clear" } end,
    desc = "Opt-in completion profiler (off by default)",
  })
end

return M
