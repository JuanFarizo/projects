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
    if keep then
      M.take_imports(it)
      out[#out + 1] = it
    end
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
-- around blink's accept picks up that same task and adds the late import itself, once, guarded, at a
-- place computed from the current buffer (jdt.ls's ranges are never applied late).
-- Every outcome is appended to M.async_log ({ status = "applied"|"present"|"dropped"|"none", why, ms,
-- edits = what jdt.ls sent, placed = the import lines added }); M.async_count counts them all (the log
-- keeps the last 20). Outcomes other than applied/present are also sent to vim.notify at DEBUG level.
M.async_log = {}
M.async_count = 0
M.ASYNC_WAIT_MS = 10000 -- give up on a resolve that never answers (jdt.ls died or hung)
local ASYNC_LOG_MAX = 20

local function async_note(status, why, t0, edits, placed)
  M.async_count = M.async_count + 1
  M.async_log[#M.async_log + 1] = { status = status, why = why, ms = t0 and (vim.uv.hrtime() / 1e6 - t0) or nil, edits = edits, placed = placed }
  if status ~= "applied" and status ~= "present" then
    vim.notify(("nv4j async import: %s (%s)"):format(status, why), vim.log.levels.DEBUG)
  end
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

--- `import [static] a.b.C;` -> { name = "a.b.C", static = bool, module = bool, text = normalized } or nil.
--- Resolved jdt.ls items: import-only additionalTextEdits move to `nv4j_imports`, so blink never
--- applies jdt.ls's ranges (they can be stale or lossy: measured 22 of 50 `HashMap` resolves sent
--- 2:0-2:22 "import java.util.HashMap;", which replaces the `import java.util.List;` line); the
--- accept wrapper adds the statements itself (place_import). Mixed edits stay for blink, as in P1.
function M.take_imports(it)
  local edits = it.additionalTextEdits
  if type(edits) ~= "table" or #edits == 0 or not from_jdtls(it) then return end
  for _, e in ipairs(edits) do
    if not import_lines(e) then return end
  end
  it.nv4j_imports, it.additionalTextEdits = edits, nil
end

local function parse_import(line)
  local t = vim.trim(line)
  local m = t:match("^import%s+module%s+([%w_$.]+)%s*;")
  if m then return { name = m, module = true, static = false, text = "import module " .. m .. ";" } end
  local st = t:match("^import%s+static%s+([%w_$.%*]+)%s*;")
  if st then return { name = st, static = true, text = "import static " .. st .. ";" } end
  local n = t:match("^import%s+([%w_$.%*]+)%s*;")
  if n then return { name = n, static = false, text = "import " .. n .. ";" } end
end

--- Header of a Java buffer, comment aware (import-looking text inside comments is not an import):
--- { pkg = row or nil, imports = { {row, name, static, module, text} }, first_code = row of the first
--- line that is neither blank, a comment, `package` nor `import` }. Rows are 0-based.
local function java_header(lines)
  local h, in_block = { imports = {} }, false
  for i, l in ipairs(lines) do
    local t = vim.trim(l)
    if in_block then
      if t:find("%*/") then in_block = false end
    elseif t == "" or t:find("^//") then -- skip
    elseif t:find("^/%*") then
      in_block = not t:find("%*/", 3)
    elseif t:find("^package%s") then
      h.pkg = i - 1
    elseif t:find("^import%s") then
      local imp = parse_import(t)
      if imp then
        imp.row = i - 1
        h.imports[#h.imports + 1] = imp
      end
    else
      h.first_code = i - 1
      return h
    end
  end
  h.first_code = #lines
  return h
end

-- Import groups: java.completion.importOrder, the same list plugins/java.lua sends to jdt.ls
-- (used by its auto-import, quick fix and organize imports). "" = every other package, "#" = static.
M.IMPORT_ORDER = { "", "javax", "jakarta", "java", "#" }
local function import_order(client_id)
  local c = client_id and vim.lsp.get_client_by_id(client_id)
  return (c and vim.tbl_get(c.settings or {}, "java", "completion", "importOrder")) or M.IMPORT_ORDER
end
local function group_of(order, imp)
  if imp.static then
    for i, e in ipairs(order) do
      if e == "#" then return i end
    end
    return #order + 1
  end
  local best, best_len = #order + 1, -1
  for i, e in ipairs(order) do
    if e == "" and best_len < 0 then
      best, best_len = i, 0
    elseif e ~= "" and e ~= "#" and (imp.name == e or imp.name:sub(1, #e + 1) == e .. ".") and #e > best_len then
      best, best_len = i, #e
    end
  end
  return best
end

--- Insert one import line into the header, computed from the CURRENT buffer only (jdt.ls's
--- ranges are never used: they refer to the text jdt.ls saw, which an earlier late import or the
--- user may have changed). Like organize imports with importOrder: sorted within its group, a blank
--- line between groups, statics last; no imports yet: after `package` (or, without one, at the top
--- of the code, below any leading license comment). `import module` lines are left alone.
--- Returns false (nothing changed) when the place would be below `limit` (the accepted line).
local function place_import(buf, imp, order, limit)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local h = java_header(lines)
  imp.group = group_of(order, imp)
  local regular, modules = {}, {}
  for _, it in ipairs(h.imports) do
    if it.module then modules[#modules + 1] = it else
      it.group = group_of(order, it)
      regular[#regular + 1] = it
    end
  end
  local at, block
  local function blank_after()
    -- keep a blank line between the new import and a following non-blank line of another group
    if lines[at + 1] and lines[at + 1]:find("%S") then block[#block + 1] = "" end
  end
  if #regular > 0 then
    local last_same
    for _, it in ipairs(regular) do
      if it.group == imp.group then
        if not at and it.name > imp.name then at, block = it.row, { imp.text } end
        last_same = it
      end
    end
    if not at and last_same then at, block = last_same.row + 1, { imp.text } end
    if not at then
      local lower, higher
      for _, it in ipairs(regular) do
        if it.group < imp.group then lower = it end
        if it.group > imp.group and not higher then higher = it end
      end
      if lower then
        at, block = lower.row + 1, { "", imp.text }
        blank_after()
      else
        at, block = higher.row, { imp.text, "" }
      end
    end
  elseif #modules > 0 then
    at, block = modules[#modules].row + 1, { "", imp.text }
    blank_after()
  elseif h.pkg then
    at, block = h.pkg + 1, { "", imp.text }
    blank_after()
  else
    at, block = h.first_code, { imp.text, "" }
  end
  if at > limit then return false end
  vim.api.nvim_buf_set_lines(buf, at, at, false, block)
  return true
end

--- The late resolve answered: add its import(s) once, if still wanted (D24 guards). Only the import
--- statements are taken from jdt.ls's edits; where they go is computed by place_import.
local function late_import(st, resolved)
  local buf = st.buf
  local edits = resolved and (resolved.nv4j_imports or resolved.additionalTextEdits)
  if type(edits) ~= "table" or #edits == 0 then return async_note("none", "no additionalTextEdits", st.t0) end
  if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)) then
    return async_note("dropped", "buffer closed", st.t0, edits)
  end
  if vim.api.nvim_buf_get_name(buf):find("module%-info%.java$") then
    return async_note("dropped", "module-info.java is left alone", st.t0, edits)
  end
  -- 1. Imports only: anything else (a rewrite of code) is never applied late.
  local wanted = {}
  for _, e in ipairs(edits) do
    local ls = import_lines(e)
    if not ls then return async_note("dropped", "edit is not an import: " .. vim.inspect(e.newText), st.t0, edits) end
    for _, l in ipairs(ls) do
      local imp = parse_import(l)
      if imp and not imp.module then wanted[#wanted + 1] = imp end
    end
  end
  -- 2. Never a duplicate: imports already in the header (blink applied it in time, or the user typed
  -- it) are skipped; import-looking text in comments does not count.
  local present = {}
  for _, it in ipairs(java_header(vim.api.nvim_buf_get_lines(buf, 0, -1, false)).imports) do present[it.text] = true end
  local missing = {}
  for _, imp in ipairs(wanted) do
    if not present[imp.text] then
      present[imp.text] = true
      missing[#missing + 1] = imp
    end
  end
  if #missing == 0 then return async_note("present", "import already in the buffer", st.t0, edits) end
  -- 3. The accepted text is still there (an undo of the accept drops its import). The extmark spans
  -- the accepted line and grows with text typed or inserted around it.
  local m = vim.api.nvim_buf_get_extmark_by_id(buf, st.ns, st.mark, { details = true })
  local row = m[1]
  local region = row and table.concat(vim.api.nvim_buf_get_text(buf, row, m[2], m[3].end_row, m[3].end_col, {}), "\n")
  if not region or not region:find(st.word, 1, true) then
    return async_note("dropped", "accepted text no longer in the buffer (undone or edited)", st.t0, edits)
  end
  -- One `u` removes the item and its import when nothing changed since the accept's own edit
  -- (changedtick recorded when blink applied it), else the import is its own undo step.
  local ut = vim.fn.undotree(buf)
  local join = st.tick ~= nil and vim.b[buf].changedtick == st.tick and ut.seq_cur == ut.seq_last
  local order = import_order(st.client_id)
  local placed, limit = {}, row
  vim.api.nvim_buf_call(buf, function()
    if join then pcall(vim.cmd.undojoin) end
    for _, imp in ipairs(missing) do
      if place_import(buf, imp, order, limit) then
        placed[#placed + 1] = imp.text
        limit = vim.api.nvim_buf_get_extmark_by_id(buf, st.ns, st.mark, {})[1] or limit
      end
    end
  end)
  if #placed == 0 then return async_note("dropped", "no place for the import above the accepted line", st.t0, edits) end
  async_note("applied", join and "joined to the accept's undo step" or "own undo step", st.t0, edits, placed)
end

--- Wrap blink's accept function (module blink.cmp.completion.accept).
function M.wrap_accept(accept)
  return function(ctx, item, callback)
    local buf = ctx and ctx.bufnr
    local java = buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "java"
    -- mixed (non-import) edits already resolved: blink applies them, as in P1
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
    local function finish()
      st.done = true
      if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_del_extmark, buf, ns, st.mark) end
    end
    -- No answer at all (jdt.ls died or hung, the resolve was cancelled): drop and clear the extmark.
    vim.defer_fn(function()
      if not st.done then
        finish()
        async_note("dropped", ("no resolve answer within %d ms"):format(M.ASYNC_WAIT_MS), st.t0)
      end
    end, M.ASYNC_WAIT_MS)
    -- Same context and item: blink's cached resolve task, no second request to jdt.ls.
    require("blink.cmp.sources.lib").resolve(ctx, item):map(function(resolved)
      -- After blink's own handler: if the answer came within its timeout, blink applied the import
      -- and the "present" guard skips it here.
      vim.schedule(function()
        if st.done then return end -- the watchdog gave up already
        local ok, err = pcall(late_import, st, resolved)
        if not ok then async_note("dropped", "error: " .. tostring(err), st.t0) end
        finish()
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
