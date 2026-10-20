-- Java-only completion re-ranking for blink.cmp. Wired in lua/plugins/blink.lua.
-- Design and measurements: specs/002-p1-completion.md, specs/features/completion-ranking.md.
-- Every function returns items unchanged for non-Java buffers.
local M = {}

local Kind = vim.lsp.protocol.CompletionItemKind

local function is_java(ctx) return vim.bo[ctx.bufnr].filetype == "java" end

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
    roots[client_id] = client and client.config.root_dir or false
    if roots[client_id] then require("nv4j.usage").watch(roots[client_id]) end
  end
  return roots[client_id] and require("nv4j.usage").get(roots[client_id])
end

local TYPE_KINDS = { [Kind.Class] = true, [Kind.Interface] = true, [Kind.Enum] = true, [Kind.Struct] = true }

-- jdt.ls writes sortText = 999999999 - (relevance * 16 + kind offset) (SortTextHelper). JDT adds
-- R_JAVA_LIBRARY = 2 to every type in a `java.` package (RelevanceConstants), which puts
-- java.lang's @Deprecated above the project's own annotations: the opposite of IntelliJ's
-- proximity weigher (project and explicitly imported before the SDK). Take that bonus back out.
local JAVA_LIBRARY_BONUS = 2 * 16
local function relevance(it)
  local st = tonumber(it.sortText or "")
  if not st then return nil end
  local rel = 999999999 - st
  local pkg = it.labelDetails and it.labelDetails.description
  if TYPE_KINDS[it.kind] and type(pkg) == "string" and pkg:find("^java%.") then rel = rel - JAVA_LIBRARY_BONUS end
  return rel
end

--- lsp provider transform_items (Java only).
function M.transform_lsp(ctx, items)
  if not is_java(ctx) then return items end
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
end

local JAVA_SORTS = { "score", M.java_sort }
local DEFAULT_SORTS = { "score", "sort_text" }
--- fuzzy.sorts: Java buffers use java_sort (a Lua step: blink sorts in Lua there, about 1 ms
--- for 200 items); other filetypes keep blink's default, sorted in Rust.
function M.sorts() return vim.bo.filetype == "java" and JAVA_SORTS or DEFAULT_SORTS end

--- snippets provider should_show_items: no live templates after `.` or `@` in Java (member
--- and annotation positions), like IntelliJ's template contexts.
function M.snippets_should_show(ctx, _)
  if not is_java(ctx) then return true end
  local before = M.char_before_keyword(ctx)
  return before ~= "." and before ~= "@"
end

return M
