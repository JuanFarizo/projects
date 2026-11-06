-- Derived query names in a real buffer (nv4j/dataquery.lua buffer layer): treesitter reads the repository interface and the
-- entity classes, a STUB jdt.ls client answers textDocument/definition (finds `class|record <Name>` in the temp project), so no
-- jdt.ls runs here. The live twin with the real jdt.ls is check 80 (to run when the machine is free).
--  bad_flagged       repository `findByEmial` -> one ERROR "No property 'emial' found for type 'Customer'" on exactly `Emial`;
--                    the good methods (findByEmail, findByFullNameContaining..., OrderBy) get none.
--  nested            findByAddressCty -> ERROR for type 'Address' on `Cty` (second request, nested type read from its file).
--  inherited         `id` lives in superclass BaseEntity: findById fine, findByIdd flagged for 'Customer'.
--  getter            a property that exists only as getter getNick() is accepted.
--  record            a record entity: components are properties.
--  super_unknown     superclass the stub cannot locate (a library class): no diagnostics at all, even for a wrong name.
--  entity_unknown    entity type not found: no diagnostics.
--  skipped           @Query method with a nonsense name, a default method and a static-less non-derived name are not checked.
--  cache_no_request  second run sends 0 definition requests.
--  entity_edit       adding the missing field to the (unsaved) entity buffer makes the diagnostic go away (changedtick).
--  dedupe_wait       the diagnostic appears only after the async answers (first run before them has none).
local lsp = require("lsp")
local D = require("nv4j.dataquery")
local P = "77_dataquery_buf."
local TMP = "/tmp/nv4j/dq-buf-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
TMP = vim.uv.fs_realpath(TMP)
local function write(name, text)
  local f = assert(io.open(TMP .. "/" .. name, "w"))
  f:write(text)
  f:close()
end

write("BaseEntity.java", [[
package d;
public class BaseEntity { private Long id; }
]])
write("Address.java", [[
package d;
public class Address { private String city; private String zip; }
]])
write("Customer.java", [[
package d;
import java.util.List;
public class Customer extends BaseEntity {
    private String email;
    private String fullName;
    private Address address;
    private static String CONST;
    public String getNick() { return null; }
}
]])
write("Person.java", [[
package d;
public record Person(String name, int age) {}
]])
write("Lib.java", [[
package d;
public class Lib extends com.acme.External { private String own; }
]])
write("CustomerRepository.java", [[
package d;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
public interface CustomerRepository extends JpaRepository<Customer, Long> {
    Customer findByEmail(String e);
    Customer findByEmial(String e);
    Customer findByFullNameContainingIgnoreCaseOrderByEmailAsc(String e);
    Customer findByAddressCty(String e);
    Customer findByAddressCity(String e);
    Customer findById(Long i);
    Customer findByIdd(Long i);
    Customer findByNick(String e);
    @Query("select c from Customer c")
    Customer findByNonsenseName(String e);
    default Customer findByAlsoNonsense(String e) { return null; }
    Customer lookupSomething(String e);
}
]])
write("PersonRepository.java", [[
package d;
import org.springframework.data.repository.CrudRepository;
public interface PersonRepository extends CrudRepository<Person, Long> {
    Person findByName(String n);
    Person findByNmae(String n);
    Person findByAge(int a);
}
]])
write("LibRepository.java", [[
package d;
import org.springframework.data.repository.CrudRepository;
public interface LibRepository extends CrudRepository<Lib, Long> {
    Lib findByAnythingAtAll(String n);
}
]])
write("GhostRepository.java", [[
package d;
import org.springframework.data.repository.CrudRepository;
public interface GhostRepository extends CrudRepository<Ghost, Long> {
    Ghost findByAnythingAtAll(String n);
}
]])

-- stub jdt.ls: definition = the file that declares `class|record <word under the cursor>`; "Ext"/library = jdt:// uri; none = nil
local sent = 0
local function word_at(uri, line, col)
  local f = io.open(vim.uri_to_fname(uri))
  local text = f:read("*a")
  f:close()
  local b = vim.uri_to_bufnr(uri)
  local lines = vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_lines(b, 0, -1, false) or vim.split(text, "\n")
  return (lines[line + 1] or ""):sub(col + 1):match("^[%w_]+")
end
local fake = {}
function fake:request(method, params, handler)
  sent = sent + 1
  vim.schedule(function()
    local w = word_at(params.textDocument.uri, params.position.line, params.position.character)
    if w == "External" then return handler(nil, { { uri = "jdt://contents/x/External.class", range = { start = { line = 0, character = 0 } } } }) end
    for _, f in ipairs(vim.fn.glob(TMP .. "/*.java", false, true)) do
      local lines = vim.fn.readfile(f)
      local b = vim.fn.bufnr(f)
      if b > 0 and vim.api.nvim_buf_is_loaded(b) then lines = vim.api.nvim_buf_get_lines(b, 0, -1, false) end
      for i, l in ipairs(lines) do
        local s, e = l:find("%f[%w](class) " .. (w or "?") .. "%f[%W]")
        if not s then s, e = l:find("%f[%w](record) " .. (w or "?") .. "%f[%W]") end
        if s then
          local c = l:find(w, s, true) - 1
          return handler(nil, { { uri = vim.uri_from_fname(f), range = { start = { line = i - 1, character = c }, ["end"] = { line = i - 1, character = c + #w } } } })
        end
      end
    end
    handler(nil, nil)
  end)
end
D.client_of = function() return fake end

local function open(name)
  vim.cmd("noautocmd edit " .. vim.fn.fnameescape(TMP .. "/" .. name)) -- no FileType: the config would start a real jdt.ls
  vim.cmd("noautocmd set filetype=java")
  return vim.api.nvim_get_current_buf()
end
local function diags(buf)
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(buf, { namespace = D.ns })) do
    local line = vim.api.nvim_buf_get_lines(buf, d.lnum, d.lnum + 1, false)[1] or ""
    out[#out + 1] = { msg = d.message, text = line:sub(d.col + 1, d.end_col), line = line:match("[%w]+%s*%(") or "" }
  end
  return out
end
local function settle(buf, want)
  D.run(buf)
  vim.wait(4000, function() return false end, 50) -- let the async answers arrive and the re-runs fire
  D.run(buf)
  return diags(buf)
end
local function find(ds, text) for _, d in ipairs(ds) do if d.text == text then return d end end end

-- dedupe_wait: first run, before any answer, publishes nothing
D.reset()
local rb = open("CustomerRepository.java")
D.run(rb)
local first = diags(rb)
local ds = settle(rb)
lsp.report(P .. "dedupe_wait", #first == 0 and #ds > 0, ("before answers %d diagnostic(s), after %d"):format(#first, #ds))

local emial, cty, idd = find(ds, "Emial"), find(ds, "Cty"), find(ds, "Idd")
lsp.report(P .. "bad_flagged", emial and emial.msg == "No property 'emial' found for type 'Customer'" and #ds == 3,
  ("%d diagnostic(s): %s"):format(#ds, vim.inspect(vim.tbl_map(function(d) return d.text .. ": " .. d.msg end, ds))))
lsp.report(P .. "nested", cty and cty.msg == "No property 'cty' found for type 'Address'", cty and cty.msg or "none")
lsp.report(P .. "inherited", idd and idd.msg == "No property 'idd' found for type 'Customer'" and not find(ds, "Id") and not find(ds, "Nick"),
  ("findByIdd %s; findById/findByNick not flagged %s"):format(idd and idd.msg or "none", tostring(not find(ds, "Id") and not find(ds, "Nick"))))
lsp.report(P .. "getter", find(ds, "Nick") == nil, "findByNick accepted (getNick)")
local skipped = true
for _, d in ipairs(ds) do if d.text:find("Nonsense") or d.text:find("Also") or d.text:find("ookup") then skipped = false end end
lsp.report(P .. "skipped", skipped, "@Query / default / non-derived names are not checked")

local before = sent
D.run(rb)
vim.wait(500, function() return false end, 50)
lsp.report(P .. "cache_no_request", sent == before, ("%d request(s) on a second run (want 0)"):format(sent - before))

local pb = open("PersonRepository.java")
local pds = settle(pb)
lsp.report(P .. "record", #pds == 1 and pds[1].text == "Nmae" and pds[1].msg == "No property 'nmae' found for type 'Person'", vim.inspect(pds))

local lb = open("LibRepository.java")
lsp.report(P .. "super_unknown", #settle(lb) == 0, "library superclass: no judgement")
local gb = open("GhostRepository.java")
lsp.report(P .. "entity_unknown", #settle(gb) == 0, "entity not located: no judgement")

-- entity_edit: add `emial` to the open, unsaved Customer buffer
local cb = open("Customer.java")
local lines = vim.api.nvim_buf_get_lines(cb, 0, -1, false)
table.insert(lines, 5, "    private String emial;")
vim.api.nvim_buf_set_lines(cb, 0, -1, false, lines)
vim.cmd("buffer " .. rb)
local after = settle(rb)
lsp.report(P .. "entity_edit", find(after, "Emial") == nil and find(after, "Cty") ~= nil,
  ("after adding the field: Emial flagged %s, Cty still flagged %s"):format(tostring(find(after, "Emial") ~= nil), tostring(find(after, "Cty") ~= nil)))

vim.fn.delete(TMP, "rf")
lsp.finish()
