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
local function walk(seg, type_key, resolver, off)
  local props = resolver(type_key)
  if props == nil then return nil, false end
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
      if tail == "" then return nil, ptype end
      if ptype == false then return nil, false end
      return walk(tail, ptype, resolver, off + #head)
    end
  end
  return { property = decap(seg), type = type_key, text = seg, off = off }
end

--- A property path ("Address_City" or "AddressCity") from `type_key`. nil when it resolves or cannot be judged.
local function resolve_path(path, type_key, resolver)
  local t, pos = type_key, 0
  for seg in (path .. "_"):gmatch("(.-)_") do
    if seg ~= "" then
      local err, nt = walk(seg, t, resolver, pos)
      if err then return err end
      if not nt then return nil end
      t = nt
    end
    pos = pos + #seg + 1
  end
  return nil
end

--- Check one method name against the entity type `entity`.
--- Returns nil when fine (or not a derived query), else { message =, from =, to = } with 0-based, end-exclusive
--- offsets of the bad property text inside `name`.
function M.check(name, entity, resolver)
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
            message = ("No property '%s' found for type '%s'"):format(err.property, err.type),
            from = part.off + err.off,
            to = part.off + err.off + #err.text,
          }
        end
      end
    end
  end
  return nil
end

return M
