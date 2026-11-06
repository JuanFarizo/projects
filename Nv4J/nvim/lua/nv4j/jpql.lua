-- JPQL / HQL completion inside @Query strings (specs/features/jpa.md, J8). Pure part: no Neovim API, no LSP.
-- The Spring LS checks the syntax of @Query strings but completes nothing in them; IntelliJ Ultimate completes entity names,
-- aliases and the fields of an alias (`b.` -> fields of Branch, `b.business.` -> fields of Business).
--
--   M.aliases(query)            alias -> { entity = "Branch" } | { parent = "b", path = { "business" } }
--   M.analyze(query, offset)    what is under the cursor: { kind = "member"|"entity"|"alias"|"expr"|"param"|"none",
--                                 prefix = typed part of the word, path = { "b", "business" } (member only) }
--   M.members(path, aliases, ctx)  { { name =, type = key|false } } sorted by name, nil when the path cannot be resolved
--     ctx.entity_type(name) -> type key | nil     ctx.props(key) -> { [property] = type key | false } | nil
-- Unknown is never guessed: an alias or type that cannot be resolved gives nil, so the menu shows nothing wrong.
local M = {}

-- Words that end a FROM entry or cannot be an alias.
local RESERVED = {}
for w in ([[FROM JOIN INNER LEFT RIGHT OUTER FULL CROSS FETCH ON WITH WHERE GROUP ORDER HAVING UNION INTERSECT EXCEPT SET
  SELECT AS AND OR NOT IN IS NULL BETWEEN LIKE EXISTS DISTINCT UPDATE DELETE INSERT INTO VALUES BY LIMIT OFFSET FETCH]])
  :gmatch("%S+") do RESERVED[w] = true end

M.KEYWORDS = {
  "SELECT", "DISTINCT", "FROM", "WHERE", "JOIN", "LEFT JOIN", "INNER JOIN", "JOIN FETCH", "LEFT JOIN FETCH", "ON", "AND",
  "OR", "NOT", "IN", "IS NULL", "IS NOT NULL", "IS EMPTY", "MEMBER OF", "BETWEEN", "LIKE", "EXISTS", "ORDER BY", "GROUP BY",
  "HAVING", "ASC", "DESC", "COUNT", "SUM", "AVG", "MIN", "MAX", "UPPER", "LOWER", "LENGTH", "CONCAT", "COALESCE", "CASE",
  "WHEN", "THEN", "ELSE", "END", "NEW", "AS", "UPDATE", "SET", "DELETE FROM", "CURRENT_DATE", "CURRENT_TIMESTAMP",
}

--- Tokens of `s`: identifiers (letters, digits, _, $), single punctuation chars. String literals ('..', '' escapes) are one
--- token of kind "str". Each token: { text =, s =, e = } 1-based inclusive offsets.
local function tokens(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif c == "'" then
      local j = i + 1
      while j <= n do
        if s:sub(j, j) == "'" then
          if s:sub(j + 1, j + 1) == "'" then j = j + 2 else break end
        else
          j = j + 1
        end
      end
      out[#out + 1] = { text = s:sub(i, math.min(j, n)), s = i, e = math.min(j, n), str = true }
      i = j + 1
    elseif c:match("[%w_$]") then
      local j = i
      while j < n and s:sub(j + 1, j + 1):match("[%w_$]") do j = j + 1 end
      out[#out + 1] = { text = s:sub(i, j), s = i, e = j }
      i = j + 1
    else
      out[#out + 1] = { text = c, s = i, e = i }
      i = i + 1
    end
  end
  return out
end

local function is_ident(t) return t and not t.str and t.text:match("^[%a_$][%w_$]*$") ~= nil end
local function up(t) return t and t.text:upper() end
local function is_alias_word(t) return is_ident(t) and not RESERVED[up(t)] end

--- `a.b.c` starting at token `i`. Returns { "a", "b", "c" }, next index.
local function read_path(toks, i)
  local path = {}
  if not is_ident(toks[i]) then return path, i end
  path[1] = toks[i].text
  i = i + 1
  while toks[i] and toks[i].text == "." and is_ident(toks[i + 1]) do
    path[#path + 1] = toks[i + 1].text
    i = i + 2
  end
  return path, i
end

--- alias -> { entity = Name } | { parent = alias, path = { prop, ... } }.
function M.aliases(query)
  local toks, map = tokens(query), {}
  local i = 1
  -- `Entity [AS] alias` at i. Returns next index.
  local function entry(j)
    local path, k = read_path(toks, j)
    if #path == 0 then return j end
    if up(toks[k]) == "AS" then k = k + 1 end
    if is_alias_word(toks[k]) then
      map[toks[k].text] = { entity = path[#path] }
      return k + 1
    end
    return k
  end
  local in_from = false -- a "," here separates FROM entries (also after a JOIN)
  while i <= #toks do
    local w = not toks[i].str and up(toks[i])
    if w == "WHERE" or w == "GROUP" or w == "ORDER" or w == "HAVING" or w == "SET" or w == "SELECT" or w == "UNION" then
      in_from = false
      i = i + 1
    elseif toks[i].text == "," and in_from and up(toks[i + 1]) ~= "IN" then
      i = entry(i + 1)
    elseif w == "FROM" or w == "UPDATE" then
      in_from = true
      i = entry(i + 1)
    elseif not toks[i].str and w == "JOIN" then
      i = i + 1
      if up(toks[i]) == "FETCH" then i = i + 1 end
      local path, k = read_path(toks, i)
      if up(toks[k]) == "AS" then k = k + 1 end
      if #path > 0 and is_alias_word(toks[k]) then
        if map[path[1]] and #path > 1 then
          map[toks[k].text] = { parent = path[1], path = { unpack(path, 2) } }
        elseif not map[path[1]] and #path == 1 then
          map[toks[k].text] = { entity = path[1] } -- Hibernate 6: JOIN Entity alias ON ...
        end
        i = k + 1
      else
        i = k
      end
    elseif not toks[i].str and w == "IN" and toks[i + 1] and toks[i + 1].text == "(" then
      -- legacy: IN (b.orders) o
      local path, k = read_path(toks, i + 2)
      if toks[k] and toks[k].text == ")" and is_alias_word(toks[k + 1]) and #path > 1 and map[path[1]] then
        map[toks[k + 1].text] = { parent = path[1], path = { unpack(path, 2) } }
        i = k + 2
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return map
end

--- What the cursor (after `offset` characters of `query`) is completing.
function M.analyze(query, offset)
  local before = query:sub(1, offset)
  local toks = tokens(before)
  -- cursor inside a string literal: an odd number of quotes before it ('' inside a literal counts twice)
  if select(2, before:gsub("'", "")) % 2 == 1 then return { kind = "none", prefix = "" } end
  local word = before:match("[%w_$%.]*$")
  local colon = before:sub(#before - #word, #before - #word) == ":" and (#before - #word) >= 1
  if colon and not word:find(".", 1, true) then
    return { kind = "param", prefix = word }
  end
  if word:find(".", 1, true) then
    local path = {}
    for seg in word:gmatch("[^%.]+") do path[#path + 1] = seg end
    local prefix = ""
    if word:sub(-1) ~= "." then prefix = table.remove(path) end
    if #path == 0 or word:sub(1, 1) == "." then return { kind = "none", prefix = prefix } end
    return { kind = "member", path = path, prefix = prefix }
  end
  -- the tokens before the word being typed
  local n = #toks
  if word ~= "" and toks[n] and toks[n].e == #before and is_ident(toks[n]) then n = n - 1 end
  local prev, prev2 = toks[n], toks[n - 1]
  local clause
  for k = n, 1, -1 do
    local w = not toks[k].str and up(toks[k])
    if w == "FROM" or w == "UPDATE" or w == "WHERE" or w == "SELECT" or w == "GROUP" or w == "ORDER" or w == "HAVING"
      or w == "SET" or w == "ON" or w == "JOIN" then
      clause = w
      break
    end
  end
  local pw = prev and not prev.str and up(prev)
  if pw == "AS" then return { kind = "none", prefix = word } end
  if pw == "FROM" or pw == "UPDATE" or (clause == "FROM" and prev and prev.text == ",") then
    return { kind = "entity", prefix = word }
  end
  if pw == "JOIN" or (pw == "FETCH" and prev2 and up(prev2) == "JOIN") then
    return { kind = "alias", prefix = word }
  end
  -- `FROM Branch |` or `JOIN b.business |`: the alias is being declared
  if (clause == "FROM" or clause == "JOIN") and is_alias_word(prev) then
    local before_prev = toks[n - 1]
    local text = before_prev and before_prev.text
    if clause == "FROM" and (up(before_prev) == "FROM" or text == "," or text == ".") then return { kind = "none", prefix = word } end
    if clause == "JOIN" and (text == "." or up(before_prev) == "JOIN" or up(before_prev) == "FETCH") then return { kind = "none", prefix = word } end
  end
  return { kind = "expr", prefix = word }
end

--- The type key of `alias`, or nil.
local function alias_type(alias, map, ctx, depth)
  depth = depth or 0
  local a = map[alias]
  if not a or depth > 8 then return nil end
  if a.entity then return ctx.entity_type(a.entity) end
  local t = alias_type(a.parent, map, ctx, depth + 1)
  for _, seg in ipairs(a.path) do
    if not t then return nil end
    local props = ctx.props(t)
    if not props then return nil end
    t = props[seg]
    if not t then return nil end -- property missing or a value type: no members
  end
  return t
end

--- Members offered after `path` (e.g. { "b", "business" }): the properties of the type the path ends at.
function M.members(path, map, ctx)
  local t = alias_type(path[1], map, ctx)
  for k = 2, #path do
    if not t then return nil end
    local props = ctx.props(t)
    if not props then return nil end
    t = props[path[k]]
    if not t then return nil end
  end
  if not t then return nil end
  local props = ctx.props(t)
  if not props then return nil end
  local out = {}
  for name, ptype in pairs(props) do out[#out + 1] = { name = name, type = ptype } end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- Aliases in scope, sorted: { { name =, type = key|nil } }.
function M.alias_list(map, ctx)
  local out = {}
  for name in pairs(map) do out[#out + 1] = { name = name, type = alias_type(name, map, ctx) } end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

return M
