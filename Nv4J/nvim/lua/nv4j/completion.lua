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
  -- Then the server's own order: the Spring Boot LS sends `@Value("${` keys (about 1850) without sortText,
  -- in its intended order; without this tie breaker table.sort shuffled them and blink's max_items (200)
  -- cut the project's own keys (specs/features/spring-language-server.md, trial c2).
  local ia, ib = a.nv4j_idx or math.huge, b.nv4j_idx or math.huge
  if ia ~= ib then return ia < ib end
end

local JAVA_SORTS = { "score", M.java_sort }
local DEFAULT_SORTS = { "score", "sort_text" }
--- fuzzy.sorts: Java buffers use java_sort (a Lua step: blink sorts in Lua there, about 1 ms
--- for 200 items); other filetypes keep blink's default, sorted in Rust.
function M.sorts() return vim.bo.filetype == "java" and JAVA_SORTS or DEFAULT_SORTS end

--- snippets provider should_show_items: no live templates after `.` or `@` in Java (member
--- and annotation positions), like IntelliJ's template contexts.
--- Spring config files (application*.yml/.properties with the Spring Boot LS attached): no snippets either.
--- friendly-snippets' YAML set is docker-compose/k8s (`po` -> `ports:`), which outranked `port` (trial c3).
--- Java string literals (`@Profile("")`, `@Value("${}")`): no snippets, the Spring LS fills those (trial c3).
function M.snippets_should_show(ctx, _)
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

return M
