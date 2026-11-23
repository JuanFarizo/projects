-- Type and call hierarchy as a Telescope picker (<leader>cS subtypes, <leader>cP supertypes, <leader>ci incoming calls,
-- <leader>cO outgoing calls; check 98_hierarchy, spec specs/features/hierarchy.md). Neovim 0.12's own vim.lsp.buf.typehierarchy /
-- incoming_calls / outgoing_calls end in the quickfix list (`path|line col| Name detail`: the path first, the name last); here the
-- row starts with the kind icon and the NAME, the package / relative path follows dimmed, the preview shows the target.
-- Loaded lazily (the keys require it on first use). Pure part first (item -> row, sort, display, jump target: no UI, no LSP),
-- then the request chain and the picker. Only the requests the view needs are sent: prepare (one per client that supports
-- it), then ONE subtypes/supertypes/incoming/outgoing request per prepared item (normally one). Nothing per row.
local M = {}

M.TIMEOUT_MS = 15000
-- The picker opens with a `loading ...` row when the answer is not there after this many ms (a fast answer opens it directly,
-- no flicker); the rows replace the row when they arrive, closing the picker cancels the request.
M.LOADING_MS = 120

-- kind -> { prepare method, hierarchy method, title, empty message }
M.KINDS = {
  subtypes = { prepare = "textDocument/prepareTypeHierarchy", method = "typeHierarchy/subtypes", type = true,
    title = "Subtypes of %s", empty = "No subtypes of %s" },
  supertypes = { prepare = "textDocument/prepareTypeHierarchy", method = "typeHierarchy/supertypes", type = true,
    title = "Supertypes of %s", empty = "No supertypes of %s" },
  incoming = { prepare = "textDocument/prepareCallHierarchy", method = "callHierarchy/incomingCalls", field = "from",
    title = "Callers of %s", empty = "No callers of %s" },
  outgoing = { prepare = "textDocument/prepareCallHierarchy", method = "callHierarchy/outgoingCalls", field = "to",
    title = "Callees of %s", empty = "No callees of %s" },
}

-- ── pure part ────────────────────────────────────────────────────────────────────────────────

local FALLBACK_ICON = { Class = "C ", Interface = "I ", Enum = "E ", Method = "m ", Function = "f ", Constructor = "c ",
  Struct = "S ", Module = "M ", Field = "f ", Constant = "K ", Package = "P " }

--- Icon (with its trailing space) of an LSP SymbolKind number: LazyVim's kind icons when loaded, else a letter.
function M.icon(kind)
  local name = vim.lsp.protocol.SymbolKind[kind] or "Class"
  local ok, icons = pcall(function() return require("lazyvim.config").icons.kinds end)
  if ok and icons and icons[name] then return icons[name] end
  return FALLBACK_ICON[name] or "? "
end

--- Last segment of a dotted/`$` name: "demo.billing.PriceCalculator$Rule" -> "Rule".
function M.simple(name)
  return (tostring(name or ""):match("([^%.%$]+)$")) or tostring(name or "")
end

--- Path to show for a document URI: relative to `root` for a file inside it, the full path for another file, the
--- `jar/package/Class.java` part of a jdt:// content URI for a library class.
function M.display_path(uri, root)
  if not uri then return "" end
  if uri:sub(1, 5) == "file:" then
    local p = vim.uri_to_fname(uri)
    if root and root ~= "" and vim.startswith(p, root .. "/") then return p:sub(#root + 2) end
    return p
  end
  return uri:match("contents/([^?]+)") or uri
end

local function pos_lt(a, b)
  if a.line ~= b.line then return a.line < b.line end
  return a.character < b.character
end

--- Range the jump lands on: the item's selectionRange (the name), else range.
local function decl_range(item)
  return item.selectionRange or item.range
end

--- LSP hierarchy item (+ fromRanges of a call) -> display row.
--- `opts.calls` marks a call item: the name becomes `Class#method` (jdt.ls puts the container in `detail`, the signature
--- `method(Type)` in `name`); `opts.ranges` are the call sites (a call's `fromRanges`).
--- Jump target: the first call site when the call sites are in the item's own document (incoming calls), else the
--- declaration (selectionRange).
---@return table row { name, detail, pkg, path, uri, kind, range, target = {uri, range}, sites }
function M.row(item, opts)
  opts = opts or {}
  local name, pkg = item.name or "?", item.detail or ""
  if opts.calls then
    local cls = M.simple(pkg)
    local method = name:gsub("%(.*$", "")
    name = (cls ~= "" and (cls .. "#") or "") .. method
    pkg = pkg:gsub("[%.%$]?[^%.%$]+$", "") -- the package of the container class
    if pkg == "" then pkg = item.detail or "" end
  end
  local range = decl_range(item)
  local target = { uri = item.uri, range = range }
  local sites = opts.ranges and #opts.ranges or 0
  if sites > 0 and opts.sites_in_item then
    local first = opts.ranges[1]
    for _, r in ipairs(opts.ranges) do if pos_lt(r.start, first.start) then first = r end end
    target.range = first
  end
  return {
    name = name, detail = item.detail or "", pkg = pkg, kind = item.kind, uri = item.uri,
    path = M.display_path(item.uri, opts.root), range = range, target = target, sites = sites,
  }
end

--- Rows sorted by name (case-insensitive), then package, then path, then line.
function M.sort(rows)
  table.sort(rows, function(a, b)
    local an, bn = a.name:lower(), b.name:lower()
    if an ~= bn then return an < bn end
    if a.pkg ~= b.pkg then return a.pkg < b.pkg end
    if a.path ~= b.path then return a.path < b.path end
    return (a.target.range and a.target.range.start.line or 0) < (b.target.range and b.target.range.start.line or 0)
  end)
  return rows
end

--- Display text and highlight ranges of a row: `<icon>Name  package  path:line  xN` (name first, the rest dimmed).
function M.display(row)
  local icon = M.icon(row.kind)
  local text = icon .. row.name
  local dim_from = #text
  local parts = {}
  if row.pkg ~= "" then parts[#parts + 1] = row.pkg end
  local line = row.target.range and (row.target.range.start.line + 1) or nil
  if row.path ~= "" then parts[#parts + 1] = row.path .. (line and (":" .. line) or "") end
  if row.sites > 1 then parts[#parts + 1] = "x" .. row.sites end
  if #parts > 0 then text = text .. "  " .. table.concat(parts, "  ") end
  return text, { { { #icon, dim_from }, "Function" }, { { dim_from, #text }, "TelescopeResultsComment" } }
end

--- Telescope entry of a row (quickfix fields filled: <C-q> and the previewer use filename/lnum/col/text).
function M.entry_maker(row)
  -- Always a STRING: telescope's from_entry.path falls back to entry.value (our row TABLE) when path and filename are nil, and
  -- the grep previewer then crashes ("path: expected string, got table"). A library class (jdt:// URI) gets the URI: the
  -- previewer's readable check fails (empty preview, no extra request) and <C-q> gets a filename that :cfirst can open
  -- (jdt.ls's BufReadCmd); a row without a URI gets "" (previewer returns at once).
  local file = row.uri and row.uri:sub(1, 5) == "file:" and vim.uri_to_fname(row.uri) or row.uri or ""
  local r = row.target.range
  return {
    value = row, ordinal = row.name .. " " .. row.pkg .. " " .. row.path,
    display = function(entry) return M.display(entry.value) end,
    filename = file, path = file, lnum = r and (r.start.line + 1) or 1, col = r and (r.start.character + 1) or 1,
    text = row.name .. (row.pkg ~= "" and ("  " .. row.pkg) or ""),
  }
end

--- Jumps to a row's target (selectionRange of the declaration, first call site for incoming calls).
function M.jump(row, encoding)
  local t = row.target
  if not t or not t.uri then return false end
  return vim.lsp.util.show_document({ uri = t.uri, range = t.range }, encoding or "utf-16", { reuse_win = true, focus = true })
end

-- ── requests ─────────────────────────────────────────────────────────────────────────────────

local state = { gen = 0, pending = {} } -- pending: { {client, id}, ... } of the run in flight

-- Level-1 cache. The slow request is the one per prepared item (subtypes build a workspace type hierarchy in jdt.ls: 68 to
-- 1300 ms), so its rows are kept per item (method + uri + name + selection range), and the prepare answer per cursor
-- position (buffer, changedtick, line/col, client). A repeat press then sends nothing and opens at once. LRU of CACHE_MAX
-- entries. Everything is dropped when the workspace may have changed: any didChange / didSave / didChangeWatchedFiles the
-- client sends, the end of a jdt.ls build / import / refresh progress, a client attaching or detaching. A request that was
-- in flight across such an event is not stored (epoch).
M.CACHE_MAX = 64
local cache, order, epoch = {}, {}, 0
local hooked = false

function M.invalidate(reason) cache, order, epoch = {}, {}, epoch + 1; M.last_reason = reason end
function M.cache_size() return #order end

local function cache_get(key)
  local v = cache[key]
  if v ~= nil then
    for i, k in ipairs(order) do if k == key then table.remove(order, i); break end end
    order[#order + 1] = key
  end
  return v
end
local function cache_put(key, v)
  if cache[key] == nil then order[#order + 1] = key end
  cache[key] = v
  while #order > M.CACHE_MAX do cache[table.remove(order, 1)] = nil end
end

local function item_key(def, item, client)
  return vim.json.encode({ def.method, client and client.id or 0, item.uri, item.name, item.selectionRange or item.range })
end

local INVALIDATING = { ["textDocument/didChange"] = true, ["textDocument/didSave"] = true, ["workspace/didChangeWatchedFiles"] = true }
local function ensure_hooks()
  if hooked then return end
  hooked = true
  local g = vim.api.nvim_create_augroup("nv4j_hierarchy_cache", { clear = true })
  vim.api.nvim_create_autocmd("LspNotify", { group = g, callback = function(a)
    if INVALIDATING[a.data and a.data.method] then M.invalidate(a.data.method) end
  end })
  vim.api.nvim_create_autocmd("LspProgress", { group = g, callback = function(a)
    local v = a.data and a.data.params and a.data.params.value
    -- Only jdt.ls's build / import / refresh jobs: "Validate documents" and "Publish Diagnostics" end after every edit and
    -- every buffer switch (measured), and an edit has told us already through didChange.
    local t = v and v.kind == "end" and (v.title or v.message or "")
    if t and (t:find("Build") or t:find("Updat") or t:find("Import") or t:find("Initializ") or t:find("Refresh")) then M.invalidate("progress end: " .. t) end
  end })
  vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, { group = g, callback = function(a) M.invalidate(a.event) end })
end

local function cancel_pending()
  if state.stop then state.stop(); state.stop = nil end
  for _, p in ipairs(state.pending) do pcall(function() p.client:cancel_request(p.id) end) end
  state.pending = {}
end

local function warn(msg) vim.notify("nv4j: " .. msg, vim.log.levels.WARN) end

--- Rows -> Telescope picker. `title` is the prompt title; `encoding` the offset encoding for the jump. Returns the picker.
--- `<CR>` on the placeholder row of a still-loading picker does nothing.
function M.show(rows, title, encoding)
  local conf = require("telescope.config").values
  local actions, state_a = require("telescope.actions"), require("telescope.actions.state")
  local picker = require("telescope.pickers").new({}, {
    prompt_title = title,
    finder = require("telescope.finders").new_table({ results = rows, entry_maker = M.entry_maker }),
    sorter = conf.generic_sorter({}),
    previewer = conf.grep_previewer({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local cur = state_a.get_selected_entry()
        if cur and cur.value.loading then return end
        actions.close(prompt_bufnr)
        if cur then M.jump(cur.value, encoding) end
      end)
      return true
    end,
  })
  picker:find()
  return picker
end

--- Placeholder row of the picker opened before the answer is there (a row table the entry maker accepts, no jump target).
local function loading_row() return { name = "loading ...", pkg = "", path = "", kind = 0, sites = 0, loading = true, target = {} } end

--- Replaces the content (rows + title) of a picker opened by M.show; false when it is gone.
function M.fill(picker, rows, title)
  if not picker or not picker.prompt_bufnr or not vim.api.nvim_buf_is_valid(picker.prompt_bufnr) then return false end
  pcall(function() picker.layout.prompt.border:change_title(title) end)
  picker:refresh(require("telescope.finders").new_table({ results = rows, entry_maker = M.entry_maker }), { reset_prompt = false })
  return true
end

--- Closes a picker opened by M.show (no error when it is gone).
function M.close(picker)
  if picker and picker.prompt_bufnr and vim.api.nvim_buf_is_valid(picker.prompt_bufnr) then
    pcall(require("telescope.actions").close, picker.prompt_bufnr)
  end
end

--- Starts one hierarchy view for the symbol under the cursor. `kind`: subtypes | supertypes | incoming | outgoing.
--- `hooks` (tests): on_rows(rows, title, encoding) replaces the picker; the return value is the cancel function.
function M.run(kind, hooks)
  local def = M.KINDS[kind]
  if not def then return warn("unknown hierarchy kind " .. tostring(kind)) end
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local clients = vim.lsp.get_clients({ bufnr = buf, method = def.prepare })
  if #clients == 0 then return warn(("no language server attached to this buffer supports %s"):format(def.prepare)) end
  ensure_hooks()
  cancel_pending()
  state.gen = state.gen + 1
  local gen = state.gen
  local epoch0 = epoch
  local root = vim.uv.cwd()
  local rows, left, done, names, enc = {}, 0, false, {}, nil
  local timer, ltimer, ui
  local function alive() return gen == state.gen and not done end
  local function stop_timers()
    for _, t in ipairs({ timer, ltimer }) do
      if t and not t:is_closing() then t:stop(); t:close() end
    end
  end
  local function close_ui() local u = ui; ui = nil; if u then M.close(u) end end
  local function finish()
    if not alive() then return end
    done = true
    state.stop = nil
    stop_timers()
    state.pending = {}
    local what = names[1] or "this symbol"
    if #rows == 0 then close_ui(); return vim.notify((def.empty):format(what), vim.log.levels.INFO) end
    M.sort(rows)
    local title = (def.title):format(what) .. ("  (%d)"):format(#rows)
    if hooks and hooks.on_rows then return hooks.on_rows(rows, title, enc) end
    if ui then
      local u = ui
      ui = nil
      if M.fill(u, rows, title) then return end
    end
    M.show(rows, title, enc)
  end
  local function step() left = left - 1; if left <= 0 then finish() end end
  local function track(client, id) if id then state.pending[#state.pending + 1] = { client = client, id = id } end end

  timer, ltimer = vim.uv.new_timer(), vim.uv.new_timer()
  state.stop = function() stop_timers(); close_ui() end
  timer:start(M.TIMEOUT_MS, 0, vim.schedule_wrap(function()
    if not alive() then return end
    done = true
    stop_timers()
    close_ui()
    cancel_pending()
    warn(("no answer to %s within %.4g s"):format(def.method, M.TIMEOUT_MS / 1000))
  end))

  left = #clients -- prepare requests; each prepared item adds one more below
  local function on_items(client, items)
    if not items or #items == 0 then return step() end
    enc = enc or client.offset_encoding
    names[#names + 1] = def.type and items[1].name or (items[1].name:gsub("%(.*$", ""))
    left = left + #items
    for _, item in ipairs(items) do
      local ikey = item_key(def, item, client)
      local hit = cache_get(ikey)
      if hit then
        for _, r in ipairs(hit) do rows[#rows + 1] = r end
        step()
      else
        local ok2, id2 = client:request(def.method, { item = item }, function(err2, res)
          if not alive() then return end
          local mine = {}
          if err2 then
            warn(def.method .. ": " .. tostring(err2.message or err2))
          else
            for _, r in ipairs(res or {}) do
              if def.type then
                mine[#mine + 1] = M.row(r, { root = root })
              else
                local target = r[def.field]
                if target then
                  mine[#mine + 1] = M.row(target, { calls = true, root = root, ranges = r.fromRanges, sites_in_item = kind == "incoming" })
                end
              end
            end
            if epoch == epoch0 then cache_put(ikey, mine) end
          end
          for _, r in ipairs(mine) do rows[#rows + 1] = r end
          step()
        end, buf)
        if ok2 then track(client, id2) else step() end
      end
    end
    step() -- this prepare answer is handled
  end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  for _, client in ipairs(clients) do
    local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
    local pkey = vim.json.encode({ def.prepare, buf, tick, params.position, client.id })
    local phit = cache_get(pkey)
    if phit then
      on_items(client, phit)
    else
      local ok, id = client:request(def.prepare, params, function(err, items)
        if not alive() then return end
        if err then warn(def.prepare .. ": " .. tostring(err.message or err)); return step() end
        if epoch == epoch0 and items then cache_put(pkey, items) end
        on_items(client, items)
      end, buf)
      if ok then track(client, id) else step() end
    end
  end
  -- Slow answer: open the picker with a placeholder row; finish() fills it. Closing it by hand cancels the request.
  if alive() then
    ltimer:start(M.LOADING_MS, 0, vim.schedule_wrap(function()
      if not alive() or ui then return end
      local title = (def.title):format(names[1] or "this symbol") .. "  (loading ...)"
      if hooks and hooks.on_loading then return hooks.on_loading(title) end
      local picker = M.show({ loading_row() }, title, enc)
      ui = picker
      vim.api.nvim_create_autocmd("BufWipeout", { buffer = picker.prompt_bufnr, once = true, callback = function()
        if ui == picker then ui = nil; if alive() then done = true; stop_timers(); cancel_pending() end end
      end })
    end))
  end
  return function() if alive() then done = true; stop_timers(); close_ui(); cancel_pending() end end
end

return M
