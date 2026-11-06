-- JPQL completion inside @Query (nv4j/jpql.lua, specs/features/jpa.md J8): pure unit cases, a stub entity model, no jdt.ls.
-- Model (the shapes of a real project): Branch { id, slug, deletedAt, business: Business, bookings: Booking }
--   Business { id, slug, name, owner: User }   Booking { id, date }   User { id, email }
-- Cursor is marked with "|" in the query text.
-- alias_*   the alias map of FROM / JOIN / JOIN FETCH / comma / Hibernate 6 `JOIN Entity` / legacy IN forms.
-- member_*  `alias.` and `alias.path.` give the fields of the type the path ends at, also for a join of another entity and a
--           collection; the alias may be declared AFTER the cursor (SELECT b.| FROM Branch b).
-- ctx_*     what is under the cursor: entity names after FROM, aliases after JOIN, nothing where an alias is declared or
--           inside a string literal, parameter after ":".
-- unknown_* an alias or type that cannot be resolved gives nil (no wrong item).
local lsp = require("lsp")
local J = require("nv4j.jpql")
local P = "78_jpql."

local MODEL = {
  Branch = { id = false, slug = false, deletedAt = false, business = "Business", bookings = "Booking" },
  Business = { id = false, slug = false, name = false, owner = "User" },
  Booking = { id = false, date = false },
  User = { id = false, email = false },
}
local ctx = {
  entity_type = function(n) return MODEL[n] and n or nil end,
  props = function(k) return MODEL[k] end,
}

--- Query text and cursor offset from a string with one "|".
local function split(q)
  local at = q:find("|", 1, true)
  return q:sub(1, at - 1) .. q:sub(at + 1), at - 1
end
local function names(list)
  local out = {}
  for _, m in ipairs(list or {}) do out[#out + 1] = m.name end
  return table.concat(out, ",")
end

local function members(name, q, want)
  local query, off = split(q)
  local a = J.analyze(query, off)
  local got = a.kind == "member" and names(J.members(a.path, J.aliases(query), ctx)) or ("kind=" .. a.kind)
  lsp.report(P .. "member_" .. name, got == want, ("got '%s' want '%s'"):format(got, want))
end
local function kind(name, q, want_kind, want_prefix)
  local query, off = split(q)
  local a = J.analyze(query, off)
  lsp.report(P .. "ctx_" .. name, a.kind == want_kind and (want_prefix == nil or a.prefix == want_prefix),
    ("got %s '%s' want %s '%s'"):format(a.kind, a.prefix, want_kind, tostring(want_prefix)))
end

local BRANCH = "bookings,business,deletedAt,id,slug"
local BUSINESS = "id,name,owner,slug"

members("root_alias", "SELECT b FROM Branch b WHERE b.|", BRANCH)
members("prefix", "SELECT b FROM Branch b WHERE b.sl|", BRANCH)
members("nested", "SELECT b FROM Branch b WHERE b.business.|", BUSINESS)
members("nested_prefix", "SELECT b FROM Branch b WHERE b.business.na|", BUSINESS)
members("nested_two", "SELECT b FROM Branch b WHERE b.business.owner.|", "email,id")
members("alias_after_cursor", "SELECT b.| FROM Branch b", BRANCH)
members("as_keyword", "SELECT b FROM Branch AS b WHERE b.|", BRANCH)
members("join_fetch_alias", "SELECT b FROM Branch b JOIN FETCH b.business biz WHERE biz.|", BUSINESS)
members("join_alias_as", "SELECT b FROM Branch b LEFT JOIN b.business AS biz WHERE biz.|", BUSINESS)
members("join_collection", "SELECT b FROM Branch b JOIN b.bookings bk WHERE bk.|", "date,id")
members("join_chain", "SELECT b FROM Branch b JOIN b.business biz JOIN biz.owner o WHERE o.|", "email,id")
members("comma_from", "SELECT b FROM Branch b, Business x WHERE x.|", BUSINESS)
members("join_entity", "SELECT b FROM Branch b JOIN Business x ON x.id = b.business.id WHERE x.|", BUSINESS)
members("legacy_in", "SELECT o FROM Branch b, IN (b.bookings) o WHERE o.|", "date,id")
members("fqn_entity", "SELECT b FROM com.acme.model.Branch b WHERE b.|", BRANCH)
members("multiline", "SELECT CASE WHEN COUNT(b) > 0 THEN true ELSE false END\n  FROM Branch b\n  WHERE b.business.id = :businessId AND b.|", BRANCH)
members("after_in_param", "SELECT b FROM Branch b WHERE b.id IN :ids AND b.|", BRANCH)
members("update", "UPDATE Branch b SET b.|", BRANCH)
members("delete", "DELETE FROM Branch b WHERE b.|", BRANCH)
members("subquery_alias", "SELECT b FROM Branch b WHERE EXISTS (SELECT 1 FROM Booking k WHERE k.|", "date,id")

-- alias map shapes
do
  local m = J.aliases("SELECT b FROM Branch b JOIN FETCH b.business biz WHERE b.slug = :s")
  lsp.report(P .. "alias_map", m.b and m.b.entity == "Branch" and m.biz and m.biz.parent == "b" and m.biz.path[1] == "business",
    vim.inspect(m))
  local c = J.aliases("SELECT x FROM Branch b JOIN b.business x")
  lsp.report(P .. "alias_skip_keywords", c.b and c.b.entity == "Branch" and c.x and c.x.parent == "b" and c.JOIN == nil and c.WHERE == nil, vim.inspect(c))
  local d = J.aliases("SELECT b FROM Branch b WHERE b.slug = 'FROM Fake f'")
  lsp.report(P .. "alias_string_ignored", d.f == nil and d.b ~= nil, vim.inspect(d))
end

-- context
kind("entity", "SELECT b FROM |", "entity", "")
kind("entity_prefix", "SELECT b FROM Bra|", "entity", "Bra")
kind("entity_comma", "SELECT b FROM Branch b, |", "entity", "")
kind("entity_update", "UPDATE |", "entity", "")
kind("alias_join", "SELECT b FROM Branch b JOIN |", "alias", "")
kind("alias_join_fetch", "SELECT b FROM Branch b JOIN FETCH b|", "alias", "b")
kind("alias_left_join", "SELECT b FROM Branch b LEFT JOIN |", "alias", "")
kind("expr_where", "SELECT b FROM Branch b WHERE |", "expr", "")
kind("expr_select", "SELECT |", "expr", "")
kind("expr_prefix", "SELECT b FROM Branch b WHERE b.id = 1 AN|", "expr", "AN")
kind("declare_alias", "SELECT b FROM Branch |", "none")
kind("declare_alias_prefix", "SELECT b FROM Branch bb|", "none")
kind("declare_join_alias", "SELECT b FROM Branch b JOIN b.business |", "none")
kind("after_as", "SELECT b FROM Branch AS |", "none")
kind("in_string", "SELECT b FROM Branch b WHERE b.slug = 'abc.|", "none")
kind("in_string_escaped", "SELECT b FROM Branch b WHERE b.slug = 'it''s b.|", "none")
kind("after_string", "SELECT b FROM Branch b WHERE b.slug = 'x' AND b.|", "member")
kind("param", "SELECT b FROM Branch b WHERE b.id = :bus|", "param", "bus")
kind("param_empty", "SELECT b FROM Branch b WHERE b.id = :|", "param", "")
kind("leading_dot", "SELECT b FROM Branch b WHERE .|", "none")

-- unresolved: nothing offered
do
  local function none(name, q)
    local query, off = split(q)
    local a = J.analyze(query, off)
    local got = J.members(a.path or { "?" }, J.aliases(query), ctx)
    lsp.report(P .. "unknown_" .. name, got == nil, got and names(got) or "nil")
  end
  none("alias", "SELECT b FROM Branch b WHERE z.|")
  none("entity", "SELECT f FROM Foo f WHERE f.|")
  none("value_type", "SELECT b FROM Branch b WHERE b.slug.|")
  none("missing_property", "SELECT b FROM Branch b WHERE b.nothing.|")
  none("join_unknown_property", "SELECT b FROM Branch b JOIN b.nothing n WHERE n.|")
  local al = J.alias_list(J.aliases("SELECT b FROM Branch b JOIN b.business biz, Foo f"), ctx)
  local got = {}
  for _, a in ipairs(al) do got[#got + 1] = a.name .. ":" .. tostring(a.type) end
  lsp.report(P .. "alias_list", table.concat(got, ",") == "b:Branch,biz:Business,f:nil", table.concat(got, ","))
end
lsp.finish()
