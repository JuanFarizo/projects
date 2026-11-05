-- Derived query names (nv4j/dataquery.lua, Spring Data PartTree rules): pure unit cases, a stub entity model, no jdt.ls.
-- Model: Customer { id, email, fullName, active, address: Address, orders: Order, createdAt, URL, base: Base? }
--        Address { city, zip, country: Country }   Order { number, total, status }   Country { code }
-- ok_*       names that Spring Data accepts (no diagnostic): plain, And/Or, keywords, IgnoreCase, OrderBy, nested, "_" path,
--            "findByOrderNumber" (Or inside a word is not a split), no "By" (findAll, count), incomplete "findBy".
-- bad_*      a wrong property: message names the uncapitalized property and the type, range covers exactly that text
--            (also after And, in OrderBy, nested: the type is the nested one).
-- unknown_*  a type the resolver cannot see accepts anything (no false positive).
local lsp = require("lsp")
local D = require("nv4j.dataquery")
local P = "76_dataquery."

local MODEL = {
  Customer = { id = false, email = false, fullName = false, active = false, address = "Address", orders = "Order",
    createdAt = false, URL = false, ext = false, backOrder = false },
  Address = { city = false, zip = false, country = "Country" },
  Order = { number = false, total = false, status = false },
  Country = { code = false },
}
local function resolver(t) return MODEL[t] end

local function ok(name)
  local r = D.check(name, "Customer", resolver)
  lsp.report(P .. "ok_" .. name, r == nil, r and ("unexpected: " .. r.message) or "accepted")
end
local function bad(name, prop, typ, text)
  local r = D.check(name, "Customer", resolver)
  local want = ("No property '%s' found for type '%s'"):format(prop, typ)
  local range = r and name:sub(r.from + 1, r.to) or "?"
  lsp.report(P .. "bad_" .. name, r ~= nil and r.message == want and range == text,
    ("got %s, range '%s' (want '%s', '%s')"):format(r and r.message or "nil", range, want, text))
end

for _, n in ipairs({
  "findByEmail", "findByFullNameContainingIgnoreCase", "findByEmailAndActive", "findByEmailOrFullName",
  "findByActiveTrue", "findByCreatedAtBetween", "findByCreatedAtLessThanEqual", "findByAddressCity",
  "findByAddress_City", "findByAddressCountryCode", "findByOrdersNumber", "findByOrdersStatusIn",
  "findByEmailOrderByFullNameAsc", "findByActiveOrderByFullNameDescEmailAsc", "findTop3ByOrderByCreatedAtDesc",
  "findAllByEmailIgnoreCase", "findDistinctByEmail", "countByActive", "existsByEmail", "deleteByEmail",
  "findByEmailIsNotNull", "findByURL", "findByAddressCityAndAddressZip", "findAll", "count", "deleteAll", "findBy",
  "findByBackOrder", "findByBackOrderAndActive", "findByIdIn", "findByFullNameNot", "findByEmailAllIgnoreCase", "save", "toString",
}) do ok(n) end

bad("findByEmial", "emial", "Customer", "Emial")
bad("findByEmailAndAktive", "aktive", "Customer", "Aktive")
bad("findByFullNme", "fullNme", "Customer", "FullNme")
bad("findByAddressCty", "cty", "Address", "Cty")
bad("findByAddressCountryCde", "cde", "Country", "Cde")
bad("findByAddress_Cty", "cty", "Address", "Cty")
bad("findByEmailOrderByFullNmeAsc", "fullNme", "Customer", "FullNme")
bad("findByNmeContainingIgnoreCase", "nme", "Customer", "Nme")
bad("findAllByStatuz", "statuz", "Customer", "Statuz")
bad("readByZip", "zip", "Customer", "Zip")

-- unknown types: no judgement
local function unknown(name)
  local r = D.check(name, "Missing", resolver)
  lsp.report(P .. "unknown_" .. name, r == nil, r and r.message or "accepted")
end
unknown("findByAnything")
local r = D.check("findByExtFoo", "Customer", resolver)
lsp.report(P .. "unknown_property_type", r == nil, r and r.message or "accepted (property type unknown)")
lsp.finish()
