-- Name suggestions after extract variable / constant and introduce parameter (nv4j/extract.lua, specs/features/code-actions.md
-- "Name suggestions"). jdt.ls names the new thing `i` / `INT`; its answer carries no alternatives. Parts:
--  1. pure: M.suggest(expr, type, kind) for the expressions in the spec (no jdt.ls);
--  2. live (one jdt.ls on /tmp/nv4j/en120): the same code path the keys use (require("nv4j.extract").run(kind, true) = what
--     <leader>cxv / cxc call with the selection marks set; the key itself needs tmux, not installed here; introduce parameter
--     through the code action list like <leader>ca). vim.ui.select is stubbed: it records the items and answers with the
--     wanted name (or Esc). Asserted: the offered items, and the EXACT file text after the rename.
-- NV4J_EN_PROBE=1 prints the items and the text of every case instead of asserting.
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local X = require("nv4j.extract")
local P = "120_extract_names."
local PROBE = vim.env.NV4J_EN_PROBE == "1"

-- 1. pure
local function same(a, b) return vim.inspect(a) == vim.inspect(b) end
for _, c in ipairs({
  { "getter", "p.getName()", "String", "variable", { "name", "string" } },
  { "new_generic", "new ArrayList<String>()", "ArrayList<String>", "variable", { "arrayList", "strings" } },
  { "collection_plural", "people.stream().toList()", "List<Person>", "variable", { "toList", "persons" } },
  { "is_getter", "a.isActive()", "boolean", "variable", { "active", "b" } },
  { "string_constant", '"hello world"', "String", "constant", { "HELLO_WORLD", "STRING" } },
  { "string_escape_only", '"\\r\\n"', "String", "constant", { "STRING" } },
  { "number_constant", "2 * 3", "int", "constant", {} },
  { "array", "items", "Person[]", "variable", { "items", "persons" } },
  { "ctor_param", 'new Person("x")', "Person", "parameter", { "person" } },
}) do
  local got = X.suggest(c[2], c[3], c[4])
  lsp.report(P .. "pure_" .. c[1], same(got, c[5]), vim.inspect(got) .. " want " .. vim.inspect(c[5]))
end

-- 2. live
local dir = vim.uv.fs_realpath("/tmp") .. "/nv4j/en120"
vim.fn.delete(dir, "rf")
vim.fn.mkdir(dir .. "/src/main/java/en", "p")
vim.fn.writefile({
  '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>',
  "<groupId>en</groupId><artifactId>en120</artifactId><version>1</version>",
  "<properties><maven.compiler.release>25</maven.compiler.release>",
  "<project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>",
  "</project>",
}, dir .. "/pom.xml")
vim.fn.writefile({ "package en;", "", "public class Person {", "    public String getName() { return \"n\"; }", "    public Person(String n) {}", "}" }, dir .. "/src/main/java/en/Person.java")
local FILE = dir .. "/src/main/java/en/Ca.java"
local HEAD = { "package en;", "", "import java.util.*;", "", "public class Ca {" }
vim.fn.writefile(vim.list_extend(vim.deepcopy(HEAD), { "}" }), FILE)

local buf = lsp.open(FILE)
local client = lsp.wait_ready(buf, 180000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready (en120)" or "jdtls not ready")
if not client then return lsp.finish() end
local orig = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

local asked -- { items = , prompt = } of the last vim.ui.select, nil when none
local want  -- name to answer with, nil = Esc
vim.ui.select = function(items, o, cb)
  asked = { items = vim.deepcopy(items), prompt = o and o.prompt }
  if want == "Rename..." then return cb("Rename...") end
  cb(want, want and 1 or nil)
end
vim.ui.input = function(o, cb) cb(nil) end

local function plant(body)
  local lines = vim.list_extend(vim.deepcopy(HEAD), vim.split(body, "\n", { plain = true }))
  lines[#lines + 1] = "}"
  local sl, sc, el, ec
  for i, l in ipairs(lines) do
    local a = l:find("@@", 1, true)
    if a then sl, sc = i - 1, a - 1; lines[i] = l:sub(1, a - 1) .. l:sub(a + 2); l = lines[i] end
    local b = l:find("##", 1, true)
    if b then el, ec = i - 1, b - 1; lines[i] = l:sub(1, b - 1) .. l:sub(b + 2) end
  end
  return lines, sl, sc, el, ec
end

--- c: name, kind (variable|constant|param), src, pick (name or nil = Esc), items (exact list offered, nil = no prompt), expect (class body)
local function run(c)
  local ok_case, err = pcall(function()
    local lines, sl, sc, el, ec = plant(c.src)
    E.set(buf, lines)
    vim.wait(1500)
    asked, want = nil, c.pick
    vim.api.nvim_set_current_buf(buf)
    local before = E.text(buf)
    vim.api.nvim_buf_set_mark(buf, "<", sl + 1, sc, {})
    vim.api.nvim_buf_set_mark(buf, ">", el + 1, ec - 1, {})
    if c.kind == "param" then
      local ok = E.apply(buf, "^Introduce Parameter", sl, sc, el, ec, 12000)
      if not ok then return lsp.report(P .. c.name, false, "Introduce Parameter not applied") end
    else
      X.run(c.kind, true)
    end
    vim.wait(12000, function() return E.text(buf) ~= before end, 20)
    local want_text = table.concat(HEAD, "\n") .. "\n" .. c.expect .. "\n}"
    if c.items ~= nil or PROBE then vim.wait(8000, function() return asked ~= nil end, 20) end
    if c.pick then vim.wait(12000, function() return E.text(buf) == want_text end, 50) else vim.wait(1500) end
    local t = E.text(buf)
    if PROBE then print("== " .. c.name .. "\n items=" .. vim.inspect(asked and asked.items) .. "\n" .. t) return end
    local items_ok = c.items == nil and asked == nil or (asked ~= nil and same(asked.items, c.items))
    lsp.report(P .. c.name, items_ok and t == want_text,
      not items_ok and ("items " .. vim.inspect(asked and asked.items) .. " want " .. vim.inspect(c.items))
        or t ~= want_text and ("text differs. got:\n" .. t .. "\n--- want:\n" .. want_text)
        or ("items " .. table.concat(asked and asked.items or {}, ",") .. "; text exact"))
  end)
  if not ok_case then lsp.report(P .. c.name, false, "error: " .. tostring(err)) end
end

local PERSON = "    String f(Person p) {\n        return @@p.getName()## + \"!\";\n    }"
-- jdt.ls already names this one `name` (it has its own getter rule); the picker adds `string` and a rename prompt.
run({ name = "var_getter_pick", kind = "variable", pick = "string", src = PERSON,
  items = { "name", "string", "Rename..." },
  expect = "    String f(Person p) {\n        String string = p.getName();\n        return string + \"!\";\n    }" })
run({ name = "var_getter_esc", kind = "variable", pick = nil, src = PERSON,
  items = { "name", "string", "Rename..." },
  expect = "    String f(Person p) {\n        String name = p.getName();\n        return name + \"!\";\n    }" })
run({ name = "var_new_generic", kind = "variable", pick = "arrayList",
  src = "    int f() {\n        return @@new ArrayList<String>()##.size();\n    }",
  items = { "arrayList", "strings", "Rename..." },
  expect = "    int f() {\n        ArrayList<String> arrayList = new ArrayList<String>();\n        return arrayList.size();\n    }" })
-- jdt.ls names a string constant from its words itself (HELLO_WORLD); the picker adds the type name.
run({ name = "const_string_pick", kind = "constant", pick = "STRING",
  src = "    String f() {\n        return @@\"hello world\"##;\n    }",
  items = { "HELLO_WORLD", "STRING", "Rename..." },
  expect = "    private static final String STRING = \"hello world\";\n\n    String f() {\n        return STRING;\n    }" })
run({ name = "const_string_esc", kind = "constant", pick = nil,
  src = "    String f() {\n        return @@\"hello world\"##;\n    }",
  items = { "HELLO_WORLD", "STRING", "Rename..." },
  expect = "    private static final String HELLO_WORLD = \"hello world\";\n\n    String f() {\n        return HELLO_WORLD;\n    }" })
run({ name = "const_number_only_default", kind = "constant", pick = nil, -- only jdt.ls's INT: no prompt
  src = "    int f() {\n        int a = @@2 * 3##;\n        return a + 2 * 3;\n    }",
  items = nil,
  expect = "    private static final int INT = 2 * 3;\n\n    int f() {\n        int a = INT;\n        return a + INT;\n    }" })
run({ name = "param_call", kind = "param", pick = "parseInt",
  src = "    int f() {\n        return @@Integer.parseInt(\"5\")## + 1;\n    }",
  items = { "parseInt", "i", "Rename..." },
  expect = "    int f(int parseInt) {\n        return parseInt + 1;\n    }" })
run({ name = "param_literal_only_default", kind = "param", pick = nil, -- `i` is the only candidate: no prompt
  src = "    int f() {\n        return @@42## + 1;\n    }",
  items = nil,
  expect = "    int f(int i) {\n        return i + 1;\n    }" })

E.restore(buf, orig)
lsp.finish()
