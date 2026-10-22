-- Java-only completion re-ranking for blink.cmp. Wired in lua/plugins/blink.lua.
-- Design and measurements: specs/002-p1-completion.md, specs/features/completion-ranking.md.
-- Every function returns items unchanged for non-Java buffers, except snippets_should_show (Spring config files).
local M = {}

local Kind = vim.lsp.protocol.CompletionItemKind

-- java.completion.filteredTypes defaults: only packages measured as noise in the Spring fixture
-- (specs/002-p1-completion.md) or never public API. java.awt and javax.swing stay visible
-- (BufferedImage, Color, Graphics2D are used by server code); only java.awt.List is hidden, so
-- `List` completes and auto-imports java.util.List.
M.DEFAULT_FILTERED_TYPES = {
  "com.sun.*", "sun.*", -- JDK internals
  "jdk.internal.*", "jdk.javadoc.internal.*", -- JDK internals (standard_de, ... resource classes)
  "com.apple.*", "apple.*", -- macOS look-and-feel resources (aqua_de, aqua_fr, ...)
  "java.applet.*", -- removed from the JDK API, never wanted
  "aj.*", "org.aspectj.internal.*", -- AspectJ's shaded ASM and internal annotations (ajc*)
  "java.awt.List", -- the AWT widget: ranked above java.util.List when neither is imported
  "java.awt.peer.*", -- AWT implementation interfaces (ListPeer next to List)
}

--- Effective filteredTypes: the defaults, plus/minus the user's
--- vim.g.nv4j_filtered_types = { add = { "java.awt.*", "javax.swing.*" }, remove = { "java.awt.List" } }
--- (set it before jdtls starts, e.g. in lua/config/options.lua).
function M.filtered_types()
  local user = vim.g.nv4j_filtered_types or {}
  local remove = {}
  for _, f in ipairs(user.remove or {}) do remove[f] = true end
  local out = {}
  for _, list in ipairs({ M.DEFAULT_FILTERED_TYPES, user.add or {} }) do
    for _, f in ipairs(list) do
      if not remove[f] and not vim.tbl_contains(out, f) then out[#out + 1] = f end
    end
  end
  return out
end

-- A late completionItem/resolve answer is transformed again after its buffer may be gone (P3: wiped
-- between accept and resolve threw "Invalid buffer id").
local function is_java(ctx) return vim.api.nvim_buf_is_valid(ctx.bufnr) and vim.bo[ctx.bufnr].filetype == "java" end

--- Character just before the keyword under the cursor ("" at line start).
function M.char_before_keyword(ctx)
  local s = ctx.bounds.start_col
  return s > 1 and ctx.line:sub(s - 1, s - 1) or ""
end

-- Literal prefixes of java.completion.filteredTypes ("apple.*" -> "apple."), per client.
local filter_prefixes = {}
local function filtered_prefixes(client_id)
  if filter_prefixes[client_id] then return filter_prefixes[client_id] end
  local client = vim.lsp.get_client_by_id(client_id)
  local s = client and client.settings or {}
  local list = vim.tbl_get(s, "java", "completion", "filteredTypes") or {}
  local out = {}
  for _, f in ipairs(list) do
    out[#out + 1] = f:gsub("%*.*$", "")
  end
  filter_prefixes[client_id] = out
  return out
end

-- jdt.ls proposes every fully qualified package for a bare identifier (`s` gave 187 of 211 items:
-- sun.rmi.transport.tcp, ...); filteredTypes does not apply to packages. Keep only root packages
-- (`java`, `org`) to start a qualified name, minus roots that filteredTypes removes as a whole
-- (`sun`, `apple`, `jdk`, `aj`).
local function unwanted_package(it)
  if it.label:find(".", 1, true) then return true end
  for _, p in ipairs(filtered_prefixes(it.client_id)) do
    if vim.startswith(it.label .. ".", p) and p:find("^[%w_]+%.$") then return true end
  end
  return false
end

-- Postfix templates (`http.var`, `.nnull`, `.sysout`, ...) come from jdt.ls as Snippet items whose
-- filterText repeats the receiver ("http.var") and whose edit starts at the receiver. blink matches
-- that whole text against "http.", so they score far above every real member (89 vs 0 on `http.`).
-- IntelliJ lists postfix templates after the members. Match them on the template key only and
-- sink them below members and deprecated members (-2); a typed key ("http.va") still finds them.
local POSTFIX_OFFSET = -6

local MEMBER_KINDS = {
  [Kind.Method] = true, [Kind.Field] = true, [Kind.Constant] = true,
  [Kind.Property] = true, [Kind.EnumMember] = true,
}

-- IntelliJ's mostUsed weigher skips java.lang.Object's methods (PreferMostUsedWeigher
-- OBJECT_METHOD_PATTERN): `x.equals(` all over a project says nothing about `repository.`.
local OBJECT_METHODS = {
  hashCode = true, equals = true, finalize = true, wait = true, notify = true,
  notifyAll = true, getClass = true, clone = true, toString = true,
}

local roots = {} -- client id -> project root
local function project_counts(client_id)
  if roots[client_id] == nil then
    local client = vim.lsp.get_client_by_id(client_id)
    roots[client_id] = client and client.config.root_dir or false -- counted from java.lua on_attach
  end
  return roots[client_id] and require("nv4j.usage").get(roots[client_id])
end

local TYPE_KINDS = { [Kind.Class] = true, [Kind.Interface] = true, [Kind.Enum] = true, [Kind.Struct] = true }

-- jdt.ls writes sortText = 999999999 - (relevance * 16 + kind offset) (SortTextHelper). JDT adds
-- R_JAVA_LIBRARY = 2 to every type in a `java.` package (RelevanceConstants), which puts
-- java.lang's @Deprecated above the project's own annotations: the opposite of IntelliJ's
-- proximity weigher (project and explicitly imported before the SDK). Take that bonus back out.
local JAVA_LIBRARY_BONUS = 2 * 16
-- Only jdt.ls's sortText is that formula: another server's (the Spring Boot LS on Java buffers) would
-- read as a huge relevance and outrank every jdt.ls item.
local jdtls_ids = {}
local function from_jdtls(it)
  local id = it.client_id
  if not id then return false end
  if jdtls_ids[id] == nil then
    local c = vim.lsp.get_client_by_id(id)
    jdtls_ids[id] = c ~= nil and c.name == "jdtls"
  end
  return jdtls_ids[id]
end
local function relevance(it)
  if not from_jdtls(it) then return nil end
  local st = tonumber(it.sortText or "")
  if not st then return nil end
  local rel = 999999999 - st
  local pkg = it.labelDetails and it.labelDetails.description
  if TYPE_KINDS[it.kind] and type(pkg) == "string" and pkg:find("^java%.") then rel = rel - JAVA_LIBRARY_BONUS end
  return rel
end

--- lsp provider transform_items (Java only).
-- Inside `${...` of a Java string (`@Value("${`), keys set in the project's own application*.properties/yml come
-- first: +PROJECT_KEY_OFFSET per tier (2 = outside Boot's namespaces, e.g. demo.*, 1 = e.g. server.port), so the
-- about 1850 Boot keys (server order, alphabetical) never push them past blink's max_items (trial c9).
local PROJECT_KEY_OFFSET = 4
local function boost_project_keys(ctx, items)
  local before = ctx.line:sub(1, ctx.bounds.start_col - 1)
  if not before:find("%${[%w_%.%-]*$") then return end
  local keys
  for _, it in ipairs(items) do
    if not it.nv4j and it.client_id and not from_jdtls(it) then
      if keys == nil then
        local c = vim.lsp.get_client_by_id(it.client_id)
        keys = c and c.name == "spring-boot" and require("nv4j.spring").project_keys(c.config.root_dir) or false
      end
      if not keys then return end
      local tier = keys[it.label]
      if tier then it.score_offset = (it.score_offset or 0) + tier * PROJECT_KEY_OFFSET end
    end
  end
end

function M.transform_lsp(ctx, items)
  if not is_java(ctx) then return items end
  boost_project_keys(ctx, items)
  local before = M.char_before_keyword(ctx)
  local bare = before ~= "." -- not qualified by a receiver or package
  local counts = items[1] and items[1].client_id and project_counts(items[1].client_id)
  local uses = counts and (before == "." and counts.member or before == "@" and counts.anno) or nil
  local out = {}
  for i, it in ipairs(items) do
    local keep = true
    if not it.nv4j then
      it.nv4j = true -- transform also runs again on resolved items: apply once
      it.nv4j_idx = i
      it.nv4j_rel = relevance(it)
      if uses and (before == "@" or (MEMBER_KINDS[it.kind] and not OBJECT_METHODS[it.label])) then
        it.nv4j_uses = uses[it.label]
      end
      if it.kind == Kind.Snippet and it.filterText and it.filterText:find(".", 1, true) and it.filterText ~= it.label then
        it.filterText = it.label
        it.score_offset = (it.score_offset or 0) + POSTFIX_OFFSET
      elseif bare and it.kind == Kind.Module and unwanted_package(it) then
        keep = false
      end
    end
    if keep then out[#out + 1] = it end
  end
  return out
end

--- Sort step after blink's `score`, in place of `sort_text`, for items from jdt.ls:
--- 1. jdt.ls relevance (its sortText) without the java.* library bonus;
--- 2. project usage (nv4j.usage): more uses first. Only breaks relevance ties, like IntelliJ's
---    mostUsed weigher sits after its kind, expected-type and proximity weighers;
--- 3. jdt.ls's own order.
--- Other items (snippets, buffer) come after jdt.ls items of the same score, ordered by sortText.
--- A strict weak order on purpose: table.sort can fail on a comparator that is not.
function M.java_sort(a, b)
  local ra, rb = a.nv4j_rel, b.nv4j_rel
  if (ra == nil) ~= (rb == nil) then return ra ~= nil end
  if ra then
    if ra ~= rb then return ra > rb end
    local ua, ub = a.nv4j_uses or 0, b.nv4j_uses or 0
    if ua ~= ub then return ua > ub end
    if a.nv4j_idx ~= b.nv4j_idx then return a.nv4j_idx < b.nv4j_idx end
    return
  end
  local sa, sb = a.sortText or "", b.sortText or ""
  if sa ~= sb then return sa < sb end
  -- Then the server's own order: the Spring Boot LS sends `@Value("${` keys (about 1850) without sortText,
  -- in its intended order; without this tie breaker table.sort shuffled them and blink's max_items (200)
  -- cut the project's own keys (specs/features/spring-language-server.md, trial c2).
  local ia, ib = a.nv4j_idx or math.huge, b.nv4j_idx or math.huge
  if ia ~= ib then return ia < ib end
end

--- Sort for Java lists with nothing typed yet (`@`, `http.`, `repository.`, after `= `): blink's
--- `score` is then only score_offset plus blink's frecency bonus (up to +6 for every item whose
--- label and kind were accepted before, e.g. all the `@...List` container annotations after accepting
--- `java.util.List`; blink v1.10.2 adds it even with an empty keyword: its Rust `fuzzy` ignores
--- `use_frecency`). That outranked jdt.ls relevance and project usage (P1: `@` RestController
--- 4 -> 27; P3: 1 -> 24). Here frecency only breaks ties: score_offset (deprecated -2, postfix, snippet
--- offsets), then java_sort's relevance and usage, then score (= the frecency bonus), then jdt.ls order.
--- With a typed prefix the fuzzy match dominates and blink's `score` stays first (JAVA_SORTS).
local SNIPPET_KIND = Kind.Snippet
local function offset(it)
  local o = it.score_offset or 0
  if it.kind == SNIPPET_KIND then o = o + (require("blink.cmp.config").snippets.score_offset or 0) end
  return o
end
function M.java_sort_empty(a, b)
  local oa, ob = offset(a), offset(b)
  if oa ~= ob then return oa > ob end
  local ra, rb = a.nv4j_rel, b.nv4j_rel
  if (ra == nil) ~= (rb == nil) then return ra ~= nil end
  if ra then
    if ra ~= rb then return ra > rb end
    local ua, ub = a.nv4j_uses or 0, b.nv4j_uses or 0
    if ua ~= ub then return ua > ub end
  else
    local sa, sb = a.sortText or "", b.sortText or ""
    if sa ~= sb then return sa < sb end
  end
  local fa, fb = a.score or 0, b.score or 0
  if fa ~= fb then return fa > fb end
  local ia, ib = a.nv4j_idx or math.huge, b.nv4j_idx or math.huge
  if ia ~= ib then return ia < ib end
end

local JAVA_SORTS = { "score", M.java_sort }
local JAVA_SORTS_EMPTY = { M.java_sort_empty }
local DEFAULT_SORTS = { "score", "sort_text" }
--- fuzzy.sorts: Java buffers use java_sort (a Lua step: blink sorts in Lua there, about 1 ms
--- for 200 items), or java_sort_empty when no keyword character is typed before the cursor (blink
--- calls this at each fuzzy pass, with the cursor where the list is shown); other filetypes keep
--- blink's default, sorted in Rust.
function M.sorts()
  -- blink's cmdline completion runs with the Java buffer current: its items are not Java items.
  if vim.bo.filetype ~= "java" or vim.api.nvim_get_mode().mode:sub(1, 1) == "c" then return DEFAULT_SORTS end
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local before = vim.api.nvim_get_current_line():sub(1, col)
  return before:find("[%w_$]$") and JAVA_SORTS or JAVA_SORTS_EMPTY
end

--- snippets provider should_show_items: no live templates after `.` or `@` in Java (member
--- and annotation positions), like IntelliJ's template contexts.
--- Spring config files (application*.yml/.properties with the Spring Boot LS attached): no snippets either.
--- friendly-snippets' YAML set is docker-compose/k8s (`po` -> `ports:`), which outranked `port` (trial c3).
--- Java string literals (`@Profile("")`, `@Value("${}")`): no snippets, the Spring LS fills those (trial c3).
function M.snippets_should_show(ctx, _)
  if not vim.api.nvim_buf_is_valid(ctx.bufnr) then return false end
  local ft = vim.bo[ctx.bufnr].filetype
  if ft == "yaml" or ft == "jproperties" then
    return #vim.lsp.get_clients({ bufnr = ctx.bufnr, name = "spring-boot" }) == 0
  end
  if ft ~= "java" then return true end
  local before = M.char_before_keyword(ctx)
  return before ~= "." and before ~= "@" and not M.in_string(ctx.line:sub(1, ctx.bounds.start_col - 1))
end

--- Whether the end of `text` (a line up to the cursor) is inside a "..." literal: an odd number of
--- unescaped quotes. One line only: inside a text block's body (no quote on the line) it says no.
function M.in_string(text)
  local n = select(2, text:gsub('\\.', ""):gsub('"', ""))
  return n % 2 == 1
end

-- Asynchronous import on accept (P3, decision D24, specs/features/async-import.md).
-- jdt.ls sends a type's import (additionalTextEdits) only in completionItem/resolve, the request
-- that also renders the javadoc (0.4-0.8 s for List/HashMap). blink waits resolve_timeout_ms for it
-- (plugins/blink.lua: now 50 ms) and then inserts the item without it. The resolve keeps running
-- (blink's task:timeout does not cancel it; the provider caches it per context), so this wrapper
-- around blink's accept picks up that same task and applies the late import itself, once, guarded.
-- Every outcome is appended to M.async_log ({ status = "applied"|"placed"|"present"|"dropped"|"none",
-- why, ms, edits }); M.async_count counts them all (the log keeps the last 20).
M.async_log = {}
M.async_count = 0
local ASYNC_LOG_MAX = 20

local function async_note(status, why, t0, edits)
  M.async_count = M.async_count + 1
  M.async_log[#M.async_log + 1] = { status = status, why = why, ms = t0 and (vim.uv.hrtime() / 1e6 - t0) or nil, edits = edits }
  if #M.async_log > ASYNC_LOG_MAX then table.remove(M.async_log, 1) end
end

local IMPORT_LINE = "^%s*import%s+[%w_$.%s]*[%w_$*]%s*;%s*$" -- also `import static a.B.c;`
--- The non-blank lines of an edit's newText, or nil when one of them is not an import.
local function import_lines(edit)
  local out = {}
  for l in (edit.newText or ""):gmatch("[^\n]+") do
    if l:find("%S") then
      if not l:find(IMPORT_LINE) then return nil end
      out[#out + 1] = vim.trim(l)
    end
  end
  return out
end

--- Header of a Java buffer: 0-based index of the package line (or nil), of every import line, and
--- of the first line that is neither blank, a comment, `package` nor `import` (the type).
local function java_header(lines)
  local pkg, imports, in_block = nil, {}, false
  for i, l in ipairs(lines) do
    local t = vim.trim(l)
    if in_block then
      if t:find("%*/") then in_block = false end
    elseif t == "" or t:find("^//") then -- skip
    elseif t:find("^/%*") then
      in_block = not t:find("%*/")
    elseif t:find("^package%s") then
      pkg = i - 1
    elseif t:find("^import%s") then
      imports[#imports + 1] = i - 1
    else
      return pkg, imports, i - 1
    end
  end
  return pkg, imports, #lines
end

--- Insert `import` lines into the header ourselves (used when the import region changed since the
--- accept, so jdt.ls's ranges may no longer point where it meant): each line in sorted position
--- among the imports of the same kind (static or not), else after the last import, else after the
--- package line with a blank line around it. Pure line insertions before the first type line.
--- Returns false (nothing changed) when the header cannot hold it before `limit` (the accepted line).
local function place_imports(buf, imports_txt, limit)
  for _, imp in ipairs(imports_txt) do
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local pkg, imps, first_code = java_header(lines)
    if first_code > limit then return false end
    local static = imp:find("^import%s+static%s") ~= nil
    local at, block
    if #imps > 0 then
      local last_same, before
      for _, i in ipairs(imps) do
        local t = vim.trim(lines[i + 1])
        if (t:find("^import%s+static%s") ~= nil) == static then
          last_same = i
          if not before and t > imp then before = i end
        end
      end
      at = before or ((last_same or imps[#imps]) + 1)
      block = { imp }
    elseif pkg then
      at, block = pkg + 1, { "", imp }
      if vim.trim(lines[pkg + 2] or "") ~= "" then block[#block + 1] = "" end
    else
      at, block = 0, { imp, "" }
    end
    if at > limit then return false end
    vim.api.nvim_buf_set_lines(buf, at, at, false, block)
    limit = limit + #block
  end
  return true
end

--- The late resolve answered: apply its import once, if it is still wanted and safe (D24 guards).
local function late_import(st, resolved)
  local buf = st.buf
  local edits = resolved and resolved.additionalTextEdits
  if type(edits) ~= "table" or #edits == 0 then return async_note("none", "no additionalTextEdits", st.t0) end
  if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)) then
    return async_note("dropped", "buffer closed", st.t0)
  end
  -- 1. Imports only: anything else (a rewrite of code) is never applied late.
  local present = {}
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do present[vim.trim(l)] = true end
  local todo, missing_txt, max_line = {}, {}, -1
  for _, e in ipairs(edits) do
    local ls = import_lines(e)
    if not ls then return async_note("dropped", "edit is not an import: " .. vim.inspect(e.newText), st.t0) end
    local missing = false
    for _, l in ipairs(ls) do
      if not present[l] then
        missing = true
        missing_txt[#missing_txt + 1] = l
      end
    end
    -- 2. Never a duplicate: an edit whose imports are all in the buffer already (blink applied it in
    -- time, or the user typed it) is skipped.
    if missing then
      todo[#todo + 1] = e
      max_line = math.max(max_line, e.range["end"].line, e.range.start.line)
    end
  end
  if #todo == 0 then return async_note("present", "import already in the buffer", st.t0) end
  -- 3. The accepted text is still there (an undo of the accept drops its import). The extmark spans
  -- the accepted line and grows with text typed or inserted around it (lines opened above, the
  -- line replaced).
  local m = vim.api.nvim_buf_get_extmark_by_id(buf, st.ns, st.mark, { details = true })
  local row = m[1]
  local region = row and table.concat(vim.api.nvim_buf_get_text(buf, row, m[2], m[3].end_row, m[3].end_col, {}), "\n")
  if not region or not region:find(st.word, 1, true) then
    return async_note("dropped", "accepted text no longer in the buffer (undone or edited)", st.t0)
  end
  -- 4. jdt.ls's ranges are positions in the text before the accept: used as they are only when they
  -- lie above the accepted line and that region is unchanged since the accept. Otherwise (the
  -- user edited the imports, or an earlier late import landed there) the import lines are placed
  -- by place_imports instead; never applied on stale ranges.
  local verbatim = max_line < st.row
  if verbatim then
    local now_lines = vim.api.nvim_buf_get_lines(buf, 0, max_line + 1, false)
    for i = 1, max_line + 1 do
      if now_lines[i] ~= st.top[i] then verbatim = false break end
    end
  end
  -- 5. Additive only: an edit that would remove a non-blank line (seen once: jdt.ls's late edit for
  -- `HashMap` replaced the `import java.util.List;` line, trial t1-l) is not applied as sent.
  local why_placed = "import region changed since the accept"
  if verbatim then
    for _, e in ipairs(todo) do
      local sr, er = e.range.start.line, e.range["end"].line
      local ls = vim.api.nvim_buf_get_lines(buf, sr, er + 1, false)
      if #ls > 0 then
        -- import lines are ASCII: LSP characters are bytes there
        ls[#ls] = ls[#ls]:sub(1, e.range["end"].character)
        ls[1] = ls[1]:sub(e.range.start.character + 1)
      end
      local kept = {}
      for l in (e.newText or ""):gmatch("[^\n]+") do kept[vim.trim(l)] = true end
      for _, l in ipairs(ls) do
        if l:find("%S") and not kept[vim.trim(l)] then
          verbatim, why_placed = false, "jdt.ls's edit would remove " .. vim.inspect(vim.trim(l))
        end
      end
    end
  end
  -- One `u` removes the item and its import when nothing changed since the accept's own edit
  -- (changedtick recorded when blink applied it), else the import is its own undo step.
  local ut = vim.fn.undotree(buf)
  local join = st.tick ~= nil and vim.b[buf].changedtick == st.tick and ut.seq_cur == ut.seq_last
  local client = vim.lsp.get_client_by_id(st.client_id)
  local placed = true
  vim.api.nvim_buf_call(buf, function()
    if join then pcall(vim.cmd.undojoin) end
    if verbatim then
      vim.lsp.util.apply_text_edits(todo, buf, client and client.offset_encoding or "utf-16")
    else
      placed = place_imports(buf, missing_txt, row)
    end
  end)
  local how = join and "joined to the accept's undo step" or "own undo step"
  if verbatim then return async_note("applied", how, st.t0, todo) end
  if not placed then return async_note("dropped", "no place for the import above the accepted line", st.t0) end
  async_note("placed", why_placed .. "; " .. how, st.t0, missing_txt)
end

--- Wrap blink's accept function (module blink.cmp.completion.accept).
function M.wrap_accept(accept)
  return function(ctx, item, callback)
    local buf = ctx and ctx.bufnr
    local java = buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "java"
    if not java or not item or not from_jdtls(item) or (item.additionalTextEdits and #item.additionalTextEdits > 0) then
      return accept(ctx, item, callback)
    end
    local text = (type(item.textEdit) == "table" and item.textEdit.newText) or item.insertText or item.label or ""
    local word = text:match("[%w_$]+")
    local row = ctx.cursor[1] - 1
    if not word or row < 0 then return accept(ctx, item, callback) end
    local ns = vim.api.nvim_create_namespace("nv4j_async_import")
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    local st = {
      buf = buf, row = row, word = word, client_id = item.client_id, ns = ns,
      top = vim.api.nvim_buf_get_lines(buf, 0, row, false),
      mark = vim.api.nvim_buf_set_extmark(buf, ns, row, 0,
        { end_row = row, end_col = #line, right_gravity = false, end_right_gravity = true, strict = false }),
      t0 = vim.uv.hrtime() / 1e6,
    }
    -- The changedtick right after blink's own edit of the accepted line (for the undo join).
    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, _, tick, first)
        if st.done then return true end
        if first == row then
          st.tick = tick
          return true
        end
      end,
    })
    accept(ctx, item, callback)
    -- Same context and item: blink's cached resolve task, no second request to jdt.ls.
    require("blink.cmp.sources.lib").resolve(ctx, item):map(function(resolved)
      -- After blink's own handler: if the answer came within its timeout, blink applied the import
      -- and the "present" guard skips it here.
      vim.schedule(function()
        st.done = true
        local ok, err = pcall(late_import, st, resolved)
        if not ok then async_note("dropped", "error: " .. tostring(err), st.t0) end
        if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_del_extmark, buf, ns, st.mark) end
      end)
    end)
  end
end

--- Install the wrapper: blink's list.accept and the checks require the module at call time.
function M.install_async_import()
  local name = "blink.cmp.completion.accept"
  local function wrap(mod)
    if type(mod) == "function" then
      local w = M.wrap_accept(mod)
      package.loaded[name] = w
      return w
    end
    return mod
  end
  if package.loaded[name] then return wrap(package.loaded[name]) end
  package.preload[name] = function()
    package.preload[name] = nil
    local file = vim.api.nvim_get_runtime_file("lua/blink/cmp/completion/accept/init.lua", false)[1]
    return wrap(assert(loadfile(assert(file, "blink.cmp accept module not on runtimepath")))())
  end
end

return M
