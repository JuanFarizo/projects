-- JPQL completion in a real buffer (nv4j/jpqlcomplete.lua): treesitter finds the @Query literal, a STUB jdt.ls answers
-- textDocument/definition and workspace/symbol from the temp project, rg lists the @Entity classes. No real jdt.ls runs.
-- Model: Branch { id, slug, deletedAt, business: Business, bookings: List<Booking> }  Business { id, slug, name }  Booking { id, date }
--   member_root       `WHERE b.|` offers the fields of the repository's own entity (and not another entity's)
--   member_join       `JOIN FETCH b.business biz WHERE biz.|` offers the fields of Business (read through Branch's field type)
--   member_collection `JOIN b.bookings bk WHERE bk.|` offers the fields of Booking (List<Booking> element)
--   member_other      `FROM Branch b, Business x WHERE x.|` offers Business (found by workspace/symbol, not a field)
--   member_nested     `b.business.|` offers Business fields
--   text_block        the same inside a """ text block, cursor on a later line
--   expr / alias      `WHERE |` offers aliases and keywords; `JOIN |` aliases only
--   entity            `FROM |` offers the @Entity classes of the project
--   param             `:|` offers the method's parameter names (@Param value wins)
--   not_applicable    nativeQuery = true, a string that is not @Query, text after the closing quote: nil
--   unknown_entity    `FROM Foo f WHERE f.|`: no items (no wrong ones)
--   in_string_literal 'abc.| inside a JPQL string literal: no items
local lsp = require("lsp")
local D = require("nv4j.dataquery")
local C = require("nv4j.jpqlcomplete")
local P = "79_jpql_buf."
local TMP = "/tmp/nv4j/jpql-buf-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
TMP = vim.uv.fs_realpath(TMP)
local function write(name, text)
  local f = assert(io.open(TMP .. "/" .. name, "w"))
  f:write(text)
  f:close()
end
write(".nv4j", "")
write("Business.java", [[
package d;
@Entity
public class Business { private Long id; private String slug; private String name; }
]])
write("Booking.java", [[
package d;
@Entity
public class Booking { private Long id; private java.time.Instant date; }
]])
write("Branch.java", [[
package d;
import java.util.List;
@Entity
public class Branch {
    private Long id;
    private String slug;
    private java.time.Instant deletedAt;
    private Business business;
    private List<Booking> bookings;
}
]])
write("BranchRepository.java", [=[
package d;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
public interface BranchRepository extends JpaRepository<Branch, Long> {
    @Query("SELECT b FROM Branch b WHERE b.§1 AND b.deletedAt IS NULL")
    Branch one(@Param("businessId") Long businessId, String slug);
    @Query("SELECT b FROM Branch b JOIN FETCH b.business biz WHERE biz.§2")
    Branch two();
    @Query("SELECT b FROM Branch b JOIN b.bookings bk WHERE bk.§3")
    Branch three();
    @Query("SELECT b FROM Branch b, Business x WHERE x.§4")
    Branch four();
    @Query("SELECT b FROM Branch b WHERE b.business.§5")
    Branch five();
    @Query("""
            SELECT b FROM Branch b
            JOIN FETCH b.business biz
            WHERE b.slug = :slug AND biz.§6
            """)
    Branch six();
    @Query("SELECT b FROM Branch b WHERE §7")
    Branch seven();
    @Query("SELECT b FROM Branch b JOIN §8")
    Branch eight();
    @Query("SELECT b FROM §9")
    Branch nine();
    @Query("SELECT b FROM Branch b WHERE b.id = :§10")
    Branch ten(@Param("businessId") Long x, String slug);
    @Query(value = "SELECT * FROM branch b WHERE b.§11", nativeQuery = true)
    Branch eleven();
    @Deprecated("b.§12")
    Branch twelve();
    @Query("SELECT b FROM Branch b")§13
    Branch thirteen();
    @Query("SELECT f FROM Foo f WHERE f.§14")
    Branch fourteen();
    @Query("SELECT b FROM Branch b WHERE b.slug = 'abc.§15'")
    Branch fifteen();
}
]=])

-- stub jdt.ls: definition (class named under the cursor) and workspace/symbol (class named by the query)
local function java_files() return vim.fn.glob(TMP .. "/*.java", false, true) end
local function find_class(name)
  for _, f in ipairs(java_files()) do
    for i, l in ipairs(vim.fn.readfile(f)) do
      local s = l:find("%f[%w]class " .. name .. "%f[%W]")
      if s then return f, i - 1, l:find(name, s, true) - 1 end
    end
  end
end
local fake = {}
function fake:request(method, params, handler)
  vim.schedule(function()
    if method == "workspace/symbol" then
      local f, r, c = find_class(params.query)
      if not f then return handler(nil, {}) end
      return handler(nil, { { name = params.query, kind = 5, location = { uri = vim.uri_from_fname(f),
        range = { start = { line = r, character = c }, ["end"] = { line = r, character = c + #params.query } } } } })
    end
    local lines = vim.fn.readfile(vim.uri_to_fname(params.textDocument.uri))
    local w = (lines[params.position.line + 1] or ""):sub(params.position.character + 1):match("^[%w_]+")
    local f, r, c = find_class(w or "?")
    if not f then return handler(nil, nil) end
    handler(nil, { { uri = vim.uri_from_fname(f), range = { start = { line = r, character = c }, ["end"] = { line = r, character = c + #w } } } })
  end)
end
D.client_of = function() return fake end

vim.cmd("noautocmd edit " .. vim.fn.fnameescape(TMP .. "/BranchRepository.java"))
vim.cmd("noautocmd set filetype=java")
local buf = vim.api.nvim_get_current_buf()
local clean = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

--- Run completion at marker §n (removed for the call). Returns the items (nil = not applicable) or "timeout".
local function at(n)
  local lines = clean
  local row, col
  for i, l in ipairs(lines) do
    local s = l:find("§" .. n .. "%f[%D]") or l:find("§" .. n .. "$")
    if s then row, col = i - 1, s - 1 break end
  end
  assert(row, "marker " .. n)
  local edited = vim.deepcopy(lines)
  edited[row + 1] = edited[row + 1]:gsub("§%d+", "")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, edited)
  local got, done
  C.complete(buf, row, col, function(items) got, done = items, true end)
  if not vim.wait(4000, function() return done end, 20) then return "timeout" end
  return got
end
local function labels(items)
  local t = {}
  for _, it in ipairs(items or {}) do t[it.label] = true end
  return t
end
local function has(items, ...)
  local t = labels(items)
  for _, l in ipairs({ ... }) do if not t[l] then return false end end
  return true
end
local function show(items) return type(items) == "table" and table.concat(vim.tbl_map(function(i) return i.label end, items), ",") or tostring(items) end

local r = at(1)
lsp.report(P .. "member_root", has(r, "id", "slug", "deletedAt", "business", "bookings") and not has(r, "name"), show(r))
r = at(2)
lsp.report(P .. "member_join", has(r, "id", "slug", "name") and not has(r, "business", "deletedAt"), show(r))
r = at(3)
lsp.report(P .. "member_collection", has(r, "id", "date") and not has(r, "slug"), show(r))
r = at(4)
lsp.report(P .. "member_other", has(r, "id", "slug", "name") and not has(r, "business"), show(r))
r = at(5)
lsp.report(P .. "member_nested", has(r, "id", "slug", "name") and not has(r, "bookings"), show(r))
r = at(6)
lsp.report(P .. "text_block", has(r, "id", "slug", "name") and not has(r, "bookings"), show(r))
r = at(7)
lsp.report(P .. "expr", has(r, "b", "WHERE", "AND", "ORDER BY") and not has(r, "slug"), show(r):sub(1, 60))
r = at(8)
lsp.report(P .. "alias", has(r, "b") and not has(r, "WHERE"), show(r))
r = at(9)
lsp.report(P .. "entity", has(r, "Branch", "Business", "Booking") and not has(r, "WHERE"), show(r))
r = at(10)
lsp.report(P .. "param", has(r, "businessId", "slug") and not has(r, "x"), show(r))
lsp.report(P .. "not_native", at(11) == nil, tostring(at(11)))
lsp.report(P .. "not_query_annotation", at(12) == nil, tostring(at(12)))
lsp.report(P .. "after_literal", at(13) == nil, tostring(at(13)))
r = at(14)
lsp.report(P .. "unknown_entity", type(r) == "table" and #r == 0, show(r))
r = at(15)
lsp.report(P .. "in_string_literal", type(r) == "table" and #r == 0, show(r))

vim.fn.delete(TMP, "rf")
lsp.finish()
