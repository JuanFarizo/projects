-- Derived query method names (Spring Data): "No property 'x' found for type 'T'" while you type.
-- IntelliJ Ultimate flags a derived query method (findByEmial) whose property the entity does not have; the Spring LS
-- has only the syntax problems of @Query strings (QueryProblemType), not this one (specs/features/jpa.md, J7).
-- This file is the pure part: the name parser, with the rules of Spring Data's PartTree/Part/PropertyPath
-- (spring-data-commons, same behaviour that fails the application at startup with PropertyReferenceException):
--   prefix  ^(find|read|get|query|search|stream|count|exists|delete|remove) [Uppercase subject] By   (first "By")
--   no "By" -> no criteria, nothing to check (findAll, count, deleteAll)
--   predicate = text after By, cut at "OrderBy" (followed by an uppercase letter), split at Or then And (each
--     only where an uppercase letter follows, so "findByOrderNumber" is one part)
--   part = property + optional keyword suffix (longest match: IsNotNull, LessThanEqual, Containing, IgnoreCase ...)
--   property path: decapitalized head tried against the type's properties; on failure the last camel-case word moves
--     to the tail and the head is retried; the tail is resolved against the head's type; "_" forces a split.
-- Unknown is never an error: a type the resolver cannot see (library class, not found) accepts any property, so a
-- diagnostic exists only where we are sure.
local M = {}

local PREFIXES = { "find", "read", "get", "query", "search", "stream", "count", "exists", "delete", "remove" }

-- Part.Type keywords + IgnoreCase forms, longest first (the longest suffix wins: LessThanEqual before LessThan).
local KEYWORDS = {
  "IsGreaterThanEqual", "IsLessThanEqual", "GreaterThanEqual", "LessThanEqual", "IsNotContaining", "IsStartingWith",
  "IsGreaterThan", "IsEndingWith", "IsNotEmpty", "IsContaining", "IsLessThan", "NotContaining", "NotContains",
  "StartingWith", "AllIgnoreCase", "IgnoringCase", "MatchesRegex", "EndingWith", "StartsWith", "IsNotNull",
  "IsBetween", "IsNotLike", "IsNotIn", "IsNotNull", "GreaterThan", "IgnoreCase", "IsContains", "IsBefore", "IsEmpty",
  "IsFalse", "IsWithin", "NotEmpty", "NotNull", "LessThan", "Containing", "EndsWith", "IsAfter", "IsLike", "IsNear",
  "IsNull", "IsTrue", "Between", "Contains", "NotLike", "Matches", "Exists", "Equals", "IsNot", "NotIn", "Regex",
  "Before", "Empty", "False", "Within", "After", "IsIn", "Like", "Near", "Null", "True", "Not", "Is", "In",
}
table.sort(KEYWORDS, function(a, b) return #a > #b end)

local function upper_at(s, i) return s:sub(i, i):match("^%u$") ~= nil end

--- Cut `s` where `kw` is followed by an uppercase letter. Returns { {text=, off=}, ... }, off = 0-based offset in `s`
--- plus `base`. The first part may be empty only when `s` starts with kw (kept as an empty first part, like Spring).
local function split_at(s, kw, base)
  local parts, from, i = {}, 1, 1
  while true do
    local a, b = s:find(kw, i, true)
    if not a then break end
    if a > 1 and upper_at(s, b + 1) then
      parts[#parts + 1] = { text = s:sub(from, a - 1), off = base + from - 1 }
      from = b + 1
    end
    i = b + 1
  end
  parts[#parts + 1] = { text = s:sub(from), off = base + from - 1 }
  return parts
end

--- java.beans.Introspector.decapitalize
local function decap(s)
  if #s > 1 and upper_at(s, 1) and upper_at(s, 2) then return s end
  return s:sub(1, 1):lower() .. s:sub(2)
end

--- Strip one keyword suffix. Returns the property text and the keyword (or nil).
local function strip_keyword(text)
  for _, kw in ipairs(KEYWORDS) do
    if #text > #kw and text:sub(-#kw) == kw then return text:sub(1, #text - #kw), kw end
  end
  return text, nil
end

--- `resolver(type_key)` -> { [property_name] = type_key|false } or nil when the type is unknown (anything goes).
--- A property whose own type is unknown has the value false.

--- One path segment (no "_") against `type_key`: Spring's PropertyPath.create. The whole text is tried first, then the
--- last camel-case word moves to the tail; the FIRST head that is a property decides, and a failing tail is the answer.
--- Returns err|nil, end_type (false = unknown, stop judging).
local function walk(seg, type_key, resolver, off, trail)
  trail = trail or {}
  local props = resolver(type_key)
  if props == nil then return nil, false, trail end
  local words = {}
  local lead = seg:match("^[^%u]+")
  if lead then words[1] = lead end
  for w in seg:gmatch("%u[^%u]*") do words[#words + 1] = w end
  if #words == 0 then words = { seg } end
  for cut = #words, 1, -1 do
    local head = table.concat(words, "", 1, cut)
    local key = props[decap(head)] ~= nil and decap(head) or (props[head] ~= nil and head or nil)
    if key then
      local tail = table.concat(words, "", cut + 1)
      local ptype = props[key]
      local trail2 = { unpack(trail) }
      trail2[#trail2 + 1] = key
      if tail == "" then return nil, ptype, trail2 end
      if ptype == false then return nil, false, trail2 end
      return walk(tail, ptype, resolver, off + #head, trail2)
    end
  end
  return { property = decap(seg), type = type_key, text = seg, off = off, trail = trail, props = props }
end

--- A property path ("Address_City" or "AddressCity") from `type_key`. nil when it resolves or cannot be judged.
local function resolve_path(path, type_key, resolver)
  local t, pos, trail = type_key, 0, {}
  for seg in (path .. "_"):gmatch("(.-)_") do
    if seg ~= "" then
      local err, nt, tr = walk(seg, t, resolver, pos, trail)
      if err then return err end
      if not nt then return nil end
      t, trail = nt, tr
    end
    pos = pos + #seg + 1
  end
  return nil
end

--- Levenshtein distance (spring-beans PropertyMatches.calculateStringDistance, case-sensitive).
local function distance(a, b)
  local d = {}
  for i = 0, #a do d[i] = { [0] = i } end
  for j = 0, #b do d[0][j] = j end
  for i = 1, #a do
    for j = 1, #b do
      local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
      d[i][j] = math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
    end
  end
  return d[#a][#b]
end

--- Spring's PropertyReferenceException message: "No property 'x' found for type 'T'[; Did you mean 'a','b'][; Traversed path: Root.a.b]".
--- Suggestions: the type's properties within edit distance 2 (PropertyMatches, DEFAULT_MAX_DISTANCE), sorted (Spring prints a
--- HashSet, so with two or more suggestions its order is not defined; one suggestion is the usual case).
local function message(err, entity, label)
  local msg = ("No property '%s' found for type '%s'"):format(err.property, label(err.type))
  local near = {}
  for name in pairs(err.props or {}) do
    if distance(err.property, name) <= 2 then near[#near + 1] = "'" .. name .. "'" end
  end
  table.sort(near)
  if #near > 0 then msg = msg .. "; Did you mean " .. table.concat(near, ",") end
  if err.trail and #err.trail > 0 then msg = msg .. "; Traversed path: " .. label(entity) .. "." .. table.concat(err.trail, ".") end
  return msg
end

--- Check one method name against the entity type `entity`.
--- Returns nil when fine (or not a derived query), else { message =, from =, to = } with 0-based, end-exclusive
--- offsets of the bad property text inside `name`.
function M.check(name, entity, resolver, label)
  label = label or tostring
  local prefix
  for _, p in ipairs(PREFIXES) do
    if name:sub(1, #p) == p then prefix = p break end
  end
  if not prefix then return nil end
  -- first "By" after the prefix whose subject (text between) is empty or starts uppercase
  local by
  local i = #prefix + 1
  while true do
    local a = name:find("By", i, true)
    if not a then return nil end
    local subject = name:sub(#prefix + 1, a - 1)
    if subject == "" or upper_at(subject, 1) then by = a break end
    i = a + 1
  end
  local base = by + 1 -- 0-based offset of the predicate in `name` (after "By")
  local predicate = name:sub(by + 2)
  if predicate == "" then return nil end
  local order_at
  do
    local j = 1
    while true do
      local a, b = predicate:find("OrderBy", j, true)
      if not a then break end
      if upper_at(predicate, b + 1) then order_at = a break end
      j = b + 1
    end
  end
  local where = order_at and predicate:sub(1, order_at - 1) or predicate
  local parts = {}
  for _, orp in ipairs(split_at(where, "Or", base)) do
    for _, andp in ipairs(split_at(orp.text, "And", orp.off)) do parts[#parts + 1] = andp end
  end
  if order_at then
    -- OrderBy<Prop>[Asc|Desc]... : each property is a path too (Spring OrderBySource splits after Asc/Desc + uppercase)
    local o = predicate:sub(order_at + 7)
    local off = base + order_at + 6
    local from = 1
    while from <= #o do
      local cut = #o
      for _, dir in ipairs({ "Asc", "Desc" }) do
        local a2, b2 = o:find(dir, from, true)
        while a2 do
          if b2 == #o or upper_at(o, b2 + 1) then
            if b2 < cut then cut = b2 end
            break
          end
          a2, b2 = o:find(dir, b2 + 1, true)
        end
      end
      local seg = o:sub(from, cut):gsub("Asc$", ""):gsub("Desc$", "")
      parts[#parts + 1] = { text = seg, off = off + from - 1, order = true }
      from = cut + 1
    end
  end
  for _, part in ipairs(parts) do
    local text = part.text
    if text ~= "" then
      local prop = text
      if not part.order then
        local kw
        prop, kw = strip_keyword(text)
        -- IgnoreCase comes after another keyword: findByNameContainingIgnoreCase
        if kw and kw:find("IgnoreCase$") or kw == "IgnoringCase" then prop = strip_keyword(prop) end
      end
      if prop ~= "" then
        local err = resolve_path(prop, entity, resolver)
        if err then
          return {
            message = message(err, entity, label),
            from = part.off + err.off,
            to = part.off + err.off + #err.text,
          }
        end
      end
    end
  end
  return nil
end

-- ── Buffer layer ───────────────────────────────────────────────────────────────────────────────────────────────
-- A repository interface (`interface X extends ...Repository<Entity, Id>`) in a Java buffer: every derived method is checked
-- against the properties of Entity. Entity and its superclasses/nested types are found with jdt.ls
-- (`textDocument/definition` on the type reference) and READ with treesitter (fields, record components, getters). The
-- request is async: a type not loaded yet is "unknown" (accepted) and the check runs again when it arrives, so a
-- diagnostic only ever appears when every type on the path was read. Types from jars (jdt:// uris), generic
-- parameters and anything jdt.ls does not locate stay unknown. A superclass that is unknown makes the whole entity unknown.
-- Own namespace "nv4j.dataquery", ERROR like the startup failure Spring Data would give.
M.ns = vim.api.nvim_create_namespace("nv4j.dataquery")
M.DEBOUNCE_MS = 400

local SIMPLE = {}
for t in ([[String boolean byte short int long float double char Boolean Byte Short Integer Long Float Double Character
  BigDecimal BigInteger UUID LocalDate LocalDateTime LocalTime Instant ZonedDateTime OffsetDateTime Date Duration Period
  Timestamp Locale Currency URI URL Class Object]]):gmatch("%S+") do SIMPLE[t] = true end

local SKIP_ANNOT = { Query = true, NamedQuery = true, Procedure = true, Aggregation = true }

local cache = {} -- key -> { props=, super=, tick=, buf= } | { unknown = true }
local loading = {} -- key -> true while a request is in flight
local waiting = {} -- key -> { [buf] = true } buffers to re-run when the key arrives
M._requests = 0 -- definition requests sent (tests)

local function text_of(uri)
  local b = vim.uri_to_bufnr(uri)
  if vim.api.nvim_buf_is_loaded(b) then
    return table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n"), b, vim.api.nvim_buf_get_changedtick(b)
  end
  local f = io.open(vim.uri_to_fname(uri))
  if not f then return nil end
  local t = f:read("*a")
  f:close()
  return t
end

--- An entry is current while the file's text is what was read: a loaded buffer must still have the changedtick seen at
--- read time (an entry read from disk has none, so opening or editing the file later re-reads it).
local function valid(e)
  if not e then return false end
  if not e.uri then return true end
  local b = vim.fn.bufnr(vim.uri_to_fname(e.uri))
  if b > 0 and vim.api.nvim_buf_is_loaded(b) then return e.tick == vim.api.nvim_buf_get_changedtick(b) end
  return e.tick == nil
end

--- The type node to use for a member type: generics give their last argument (List<Order> -> Order, Map<K,V> -> V),
--- arrays their element. Returns nil for primitives and well-known value types.
local function member_type(tn, src)
  if not tn then return nil end
  local t = tn:type()
  if t == "generic_type" then
    local args
    for c in tn:iter_children() do if c:type() == "type_arguments" then args = c end end
    local last
    if args then for c in args:iter_children() do if c:named() then last = c end end end
    return member_type(last, src)
  elseif t == "array_type" then
    return member_type(tn:field("element")[1], src)
  elseif t == "scoped_type_identifier" then
    local last
    for c in tn:iter_children() do if c:type() == "type_identifier" then last = c end end
    return member_type(last, src)
  elseif t == "type_identifier" then
    if SIMPLE[vim.treesitter.get_node_text(tn, src)] then return nil end
    return tn
  end
  return nil
end

local names = {} -- key -> simple type name, for messages
local function key_of(uri, node, src)
  local r, c = node:range()
  local key = ("%s|%d|%d"):format(uri, r, c)
  if src then names[key] = vim.treesitter.get_node_text(node, src) end
  return key
end
local function label(key) return names[key] or key end
function M.label(key) return label(key) end

local DECLS = { class_declaration = true, record_declaration = true, interface_declaration = true, enum_declaration = true }

--- Parse the declaration of `row,col` (the definition target) in `text`. Returns { props=, super= } or nil.
local function read_class(uri, text, row, col, byname)
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, "java")
  if not ok then return nil end
  local root = parser:parse()[1]:root()
  local decl, npos
  local function find(n)
    if DECLS[n:type()] then
      local nm = n:field("name")[1]
      if nm then
        local sr, sc, er, ec = nm:range()
        if byname then
          if not decl and vim.treesitter.get_node_text(nm, text) == byname then decl = n; npos = { sr, sc } end
        elseif (row > sr or (row == sr and col >= sc)) and (row < er or (row == er and col <= ec)) then
          decl = n
        end
      end
    end
    for c in n:iter_children() do find(c) end
  end
  find(root)
  if not decl or decl:type() == "interface_declaration" or decl:type() == "enum_declaration" then return nil end
  local props, super = {}, nil
  local function add(name, type_node)
    local tn = member_type(type_node, text)
    props[name] = tn and key_of(uri, tn, text) or false
  end
  if decl:type() == "record_declaration" then
    local params = decl:field("parameters")[1]
    if params then
      for p in params:iter_children() do
        if p:type() == "formal_parameter" then
          add(vim.treesitter.get_node_text(p:field("name")[1], text), p:field("type")[1])
        end
      end
    end
  end
  local sc_node = decl:field("superclass")[1]
  if sc_node then
    for c in sc_node:iter_children() do
      if c:named() then
        local tn = c:type() == "generic_type" and c:child(0) or c
        if tn and (tn:type() == "type_identifier" or tn:type() == "scoped_type_identifier") then
          super = key_of(uri, tn, text)
        else
          return nil
        end
      end
    end
  end
  local body = decl:field("body")[1]
  if body then
    for m in body:iter_children() do
      local static = false
      for c in m:iter_children() do
        if c:type() == "modifiers" and vim.treesitter.get_node_text(c, text):find("%f[%w]static%f[%W]") then static = true end
      end
      if not static then
        if m:type() == "field_declaration" then
          local tn = m:field("type")[1]
          for d in m:iter_children() do
            if d:type() == "variable_declarator" then
              add(vim.treesitter.get_node_text(d:field("name")[1], text), tn)
            end
          end
        elseif m:type() == "method_declaration" then
          local nm = vim.treesitter.get_node_text(m:field("name")[1], text)
          local params = m:field("parameters")[1]
          local no_params = params and params:named_child_count() == 0
          local prop = no_params and (nm:match("^get(%u.*)$") or nm:match("^is(%u.*)$"))
          if prop then add(decap(prop), m:field("type")[1]) end
        end
      end
    end
  end
  return { props = props, super = super, npos = npos }
end

--- The jdt.ls client for `buf` (tests replace it with a stub).
function M.client_of(buf)
  return vim.lsp.get_clients({ bufnr = buf, name = "jdtls" })[1]
end
local function client_of(buf) return M.client_of(buf) end

local listeners = {}
--- Run `fn` once, the next time any type finishes loading (completion waits on this).
function M.on_arrival(fn) listeners[#listeners + 1] = fn end
--- True while a type is being fetched from jdt.ls.
function M.pending() return next(loading) ~= nil end

local function arrived(key)
  loading[key] = nil
  local bufs = waiting[key] or {}
  waiting[key] = nil
  for b in pairs(bufs) do M.schedule(b) end
  local ls = listeners
  listeners = {}
  for _, fn in ipairs(ls) do pcall(fn) end
end

local name_index = {} -- simple class name -> type key (read through workspace/symbol)

--- Key of a class read by name (nil when not read yet).
function M.named_key(name)
  local k = name_index[name]
  if k and valid(cache[k]) then return k end
  name_index[name] = nil
  return nil
end

--- Find class `name` with jdt.ls workspace/symbol, read it, remember it under its simple name. Async, unknown on failure.
function M.load_named(buf, name)
  local lk = "name:" .. name
  if loading[lk] or M.named_key(name) then return end
  local client = client_of(buf)
  if not client then return end
  loading[lk] = true
  M._requests = M._requests + 1
  client:request("workspace/symbol", { query = name }, function(err, res)
    vim.schedule(function()
      for _, sym in ipairs((not err and res) or {}) do
        local loc = sym.location
        if sym.name == name and (sym.kind == 5 or sym.kind == 23) and loc and loc.uri and loc.uri:sub(1, 5) == "file:" then
          local text, _, tick = text_of(loc.uri)
          local cls = text and read_class(loc.uri, text, nil, nil, name)
          if cls and cls.npos then
            local key = ("%s|%d|%d"):format(loc.uri, cls.npos[1], cls.npos[2])
            cache[key] = { props = cls.props, super = cls.super, uri = loc.uri, tick = tick }
            names[key] = name
            name_index[name] = key
            break
          end
        end
      end
      arrived(lk)
    end)
  end, buf)
end

--- Ask jdt.ls where the type referenced at `key` is declared, read it, cache it. Unknown on any failure.
local function load(key, buf)
  waiting[key] = waiting[key] or {}
  waiting[key][buf] = true
  if loading[key] then return end
  local uri, row, col = key:match("^(.*)|(%d+)|(%d+)$")
  local client = client_of(buf)
  if not client then return end
  loading[key] = true
  M._requests = M._requests + 1
  client:request("textDocument/definition", {
    textDocument = { uri = uri }, position = { line = tonumber(row), character = tonumber(col) },
  }, function(err, result)
    vim.schedule(function()
      local loc = (not err) and result
      if loc and loc[1] then loc = loc[1] end
      local turi = loc and (loc.uri or loc.targetUri)
      local rng = loc and (loc.range or loc.targetSelectionRange)
      local entry = { unknown = true }
      if turi and rng and turi:sub(1, 5) == "file:" then
        local text, _, tick = text_of(turi)
        local cls = text and read_class(turi, text, rng.start.line, rng.start.character)
        if cls then entry = { props = cls.props, super = cls.super, uri = turi, tick = tick } end
      end
      cache[key] = entry
      arrived(key)
    end)
  end, buf)
end

--- Resolver for `buf`: properties of a type key (own + inherited), nil while unknown.
function M.resolver_for(buf)
  local function resolve(key, depth)
    if depth > 8 then return nil end
    local e = cache[key]
    if not valid(e) then
      cache[key] = nil
      load(key, buf)
      return nil
    end
    if e.unknown then return nil end
    if not e.super then return e.props end
    local sup = resolve(e.super, depth + 1)
    if sup == nil then return nil end
    return vim.tbl_extend("keep", e.props, sup)
  end
  return function(key) return resolve(key, 0) end
end

--- The entity key of `interface X extends ...Repository<Entity, Id>` (node n), nil when it is not one.
local function iface_entity(n, src, uri)
  local entity
  for c in n:iter_children() do
    if c:type() == "extends_interfaces" then
      for tl in c:iter_children() do
        for g in tl:iter_children() do
          if g:type() == "generic_type" then
            local base = vim.treesitter.get_node_text(g:child(0), src)
            if base:match("Repository$") and not entity then
              local args
              for gc in g:iter_children() do if gc:type() == "type_arguments" then args = gc end end
              local first = args and args:named_child(0)
              local tn = first and member_type(first, src)
              if tn then entity = key_of(uri, tn, src) end
            end
          end
        end
      end
    end
  end
  return entity
end

--- Entity key (and its simple name) of the repository interface that contains line `row` (0-based) of `buf`.
function M.repository_at(buf, row)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "java")
  if not ok or not parser then return nil end
  local uri, found, fname = vim.uri_from_bufnr(buf), nil, nil
  local function walk(n)
    if n:type() == "interface_declaration" then
      local sr, _, er = n:range()
      if row >= sr and row <= er then
        found = iface_entity(n, buf, uri)
        fname = found and names[found]
      end
    end
    for c in n:iter_children() do walk(c) end
  end
  walk(parser:parse()[1]:root())
  return found, fname
end

--- Derived methods of the repository interfaces in `buf`: { { name=, lnum=, col=, entity = key } }.
function M.methods(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "java")
  if not ok or not parser then return {} end
  local src = buf
  local uri = vim.uri_from_bufnr(buf)
  local out = {}
  local function walk(n)
    if n:type() == "interface_declaration" then
      local entity = iface_entity(n, src, uri)
      local body = n:field("body")[1]
      if entity and body then
        for m in body:iter_children() do
          if m:type() == "method_declaration" and not m:field("body")[1] then
            local skip = false
            for c in m:iter_children() do
              if c:type() == "modifiers" then
                for a in c:iter_children() do
                  if a:type() == "default" or (a:type():find("annotation$") and SKIP_ANNOT[vim.treesitter.get_node_text(a:field("name")[1], src)]) then skip = true end
                end
              end
            end
            if not skip then
              local nm = m:field("name")[1]
              local r, c = nm:range()
              out[#out + 1] = { name = vim.treesitter.get_node_text(nm, src), lnum = r, col = c, entity = entity }
            end
          end
        end
      end
    end
    for c in n:iter_children() do walk(c) end
  end
  walk(parser:parse()[1]:root())
  return out
end

local busy = {}
--- Recompute and publish the diagnostics for `buf`.
function M.run(buf)
  if busy[buf] or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "java" then return end
  busy[buf] = true
  local ok, err = pcall(function()
    local diags = {}
    local resolver = M.resolver_for(buf)
    for _, m in ipairs(M.methods(buf)) do
      local bad = M.check(m.name, m.entity, resolver, label)
      if bad then
        diags[#diags + 1] = {
          lnum = m.lnum, col = m.col + bad.from, end_lnum = m.lnum, end_col = m.col + bad.to,
          severity = vim.diagnostic.severity.ERROR, message = bad.message, source = "nv4j",
        }
      end
    end
    if #diags > 0 or #vim.diagnostic.get(buf, { namespace = M.ns }) > 0 then
      vim.diagnostic.set(M.ns, buf, require("nv4j.diagfix").fit(buf, diags))
    end
  end)
  busy[buf] = nil
  if not ok then vim.notify("nv4j.dataquery: " .. tostring(err), vim.log.levels.DEBUG) end
end

local timers = {}
function M.schedule(buf)
  local t = timers[buf]
  if not t then
    t = vim.uv.new_timer()
    timers[buf] = t
  end
  t:stop()
  t:start(M.DEBOUNCE_MS, 0, vim.schedule_wrap(function() M.run(buf) end))
end

function M.setup()
  local g = vim.api.nvim_create_augroup("nv4j_dataquery", { clear = true })
  vim.api.nvim_create_autocmd({ "LspAttach", "BufEnter", "BufWritePost", "TextChanged", "TextChangedI" }, {
    group = g,
    callback = function(args)
      if vim.bo[args.buf].filetype == "java" then M.schedule(args.buf) end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = g,
    callback = function(args)
      local t = timers[args.buf]
      if t then t:stop(); t:close(); timers[args.buf] = nil end
    end,
  })
end

--- Forget everything read (tests).
function M.reset() cache, loading, waiting, names, name_index, listeners = {}, {}, {}, {}, {}, {} end

return M
