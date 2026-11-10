-- Framework-agnostic jdt.ls code actions and generators that checks 31/32/62 do not cover. Run via tests/run.sh.
-- Spec: specs/features/code-actions.md (table: action | offered | proven by | limits | key).
-- Plain Maven project /tmp/nv4j/ca91 (no Spring); each case plants a source in the Ca.java buffer (memory only),
-- requests textDocument/codeAction at a range (diagnostics of the range as context, like <leader>ca), applies the
-- action with Neovim's own vim.lsp.buf.code_action (resolve, edit or client command, so nvim-jdtls's handlers run),
-- asserts the EXACT resulting file text, then that jdt.ls reports no ERROR diagnostics (polled, real sleep per round).
-- A case with `absent = true` passes only when the codeAction list verifiably lacks every listed title pattern
-- (NOT OFFERED is a finding, not a failure). Only UI prompts are stubbed (vim.fn.input / inputlist / ui.input / ui.select).
-- NV4J_CA_PROBE=1 writes titles + results of every case to /tmp/nv4j/ca91_probe.txt instead of asserting.
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local S = vim.diagnostic.severity
local P = "91_codeactions."
local PROBE = vim.env.NV4J_CA_PROBE == "1"
local probe_lines, dump = {}, {}

local dir = vim.uv.fs_realpath("/tmp") .. "/nv4j/ca91"
vim.fn.delete(dir, "rf")
vim.fn.mkdir(dir .. "/src/main/java/ca", "p")
vim.fn.writefile({
  '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>',
  "<groupId>ca</groupId><artifactId>ca91</artifactId><version>1</version>",
  "<properties><maven.compiler.release>25</maven.compiler.release>",
  "<project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>",
  "</project>",
}, dir .. "/pom.xml")
vim.fn.writefile({
  "package ca;", "", "public class Helper {",
  "    public String shout(String s) { return s.toUpperCase(); }",
  "    public int twice(int n) { return n * 2; }", "}",
}, dir .. "/src/main/java/ca/Helper.java")
vim.fn.writefile({ "package ca;", "", "public interface Shape {", "    double area();", "    String name();", "}" }, dir .. "/src/main/java/ca/Shape.java")
local FILE = dir .. "/src/main/java/ca/Ca.java"
local HEAD = { "package ca;", "", "import java.util.*;", "", "public class Ca {" }
vim.fn.writefile(vim.list_extend(vim.deepcopy(HEAD), { "}" }), FILE)

local buf = lsp.open(FILE)
local client = lsp.wait_ready(buf, 180000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready (ca91)" or "jdtls not ready")
if not client then return lsp.finish() end
local orig = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

-- UI stubs. nvim-jdtls pickers: inputlist (pick one), input (pick many: a number toggles, "" ends),
-- vim.ui.input (rename after extract: cancelled), vim.ui.select (first item, or ask.select(items)).
local ask = { many = nil, select = nil, log = {} }
vim.fn.inputlist = function(choices) ask.log[#ask.log + 1] = "inputlist"; return 1 end
vim.fn.input = function(p)
  local s = type(p) == "table" and (p.prompt or "") or tostring(p)
  ask.log[#ask.log + 1] = "input"
  if ask.many then return ask.many(s) end
  return ""
end
vim.ui.input = function(_, cb) cb(nil) end
vim.ui.select = function(items, _, cb)
  ask.log[#ask.log + 1] = "select"
  local i = ask.select and ask.select(items) or 1
  cb(items[i], i)
end

-- Source with markers: `@@` start, `##` end of the selection (no `##` -> cursor at `@@`).
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
  return lines, sl, sc, el or sl, ec or sc
end

local function now() return vim.uv.hrtime() / 1e6 end
local function sleep_until(timeout_ms, pred)
  local deadline = now() + timeout_ms
  while now() < deadline do
    if pred() then return true end
    vim.wait(250) -- a real sleep per round, no callback
  end
  return pred()
end

local publishes = 0
vim.api.nvim_create_autocmd("DiagnosticChanged", { callback = function(a) if a.buf == buf then publishes = publishes + 1 end end })
local function errors() return vim.tbl_filter(function(d) return d.severity == S.ERROR end, vim.diagnostic.get(buf)) end

-- No ERROR once jdt.ls re-published after the edit (publish counter moved), and still none 1.5 s later.
local function no_errors_after(mark)
  local ok = sleep_until(25000, function() return publishes > mark and #errors() == 0 end)
  if not ok then return false, E.fmt(errors()) end
  vim.wait(1500)
  return #errors() == 0, E.fmt(errors())
end

local function body_of(t)
  local b = t:gsub("^.-public class Ca {\n", ""):gsub("\n}\n?$", "")
  return b == "}" and "" or b
end

--- case: name, title (pattern), src, expect (exact class body), diag (message to wait for), many/select (prompt stubs),
--- absent (list of title patterns that must NOT be offered), only (code action kinds), keep (errors expected after)
local function run(c)
  local ok_case, err = pcall(function()
    local lines, sl, sc, el, ec = plant(c.src)
    if c.cursor then sl, sc, el, ec = c.cursor[1], c.cursor[2], c.cursor[1], c.cursor[2] end
    ask.many, ask.select, ask.log = c.many, c.select, {}
    E.set(buf, lines)
    if c.diag then
      sleep_until(15000, function() return E.has(vim.diagnostic.get(buf), nil, c.diag) ~= nil end)
    else
      sleep_until(1200, function() return false end)
    end
    local r = E.code_actions(client, buf, sl, sc, el, ec, c.only)
    if r.err then lsp.report(P .. c.name, false, r.err) return end
    local titles = E.titles(r.actions)
    if PROBE then probe_lines[#probe_lines + 1] = ("== %s\n   offered: %s"):format(c.name, titles) end
    if c.absent then
      local present = {}
      local lists = { r.actions }
      for _, rg in ipairs(c.ranges or {}) do -- more positions the action could hang on (class keyword, whole type)
        local sl2, sc2, el2, ec2 = unpack(rg == "all" and { 0, 0, #lines - 1, #lines[#lines] } or rg)
        local r2 = E.code_actions(client, buf, sl2, sc2, el2, ec2)
        if r2.err then lsp.report(P .. c.name, false, r2.err) return end
        lists[#lists + 1] = r2.actions
      end
      for _, p in ipairs(c.absent) do
        for _, l in ipairs(lists) do if E.find(l, p) then present[#present + 1] = p break end end
      end
      lsp.report(P .. c.name, not PROBE and #present == 0, ("verified absent (%d positions asked, %d actions at the first, none matches %s); present=[%s]; offered: %s"):format(#lists, #r.actions, table.concat(c.absent, ", "), table.concat(present, ", "), titles:sub(1, 300)))
      return
    end
    local mark = publishes
    local ok, ms
    if c.call then
      -- the product's own key function (LazyVim jdtls extra: <leader>cxv / cxc call these), selection as marks
      vim.api.nvim_set_current_buf(buf)
      local before = E.text(buf)
      local t0 = now()
      vim.api.nvim_buf_set_mark(buf, "<", sl + 1, sc, {})
      vim.api.nvim_buf_set_mark(buf, ">", el + 1, ec - 1, {})
      c.call()
      ok = vim.wait(12000, function() return E.text(buf) ~= before end, 20)
      ms = now() - t0
    else
      ok, ms = E.apply(buf, c.title, sl, sc, el, ec, 12000)
    end
    local t = E.text(buf)
    if PROBE then
      probe_lines[#probe_lines + 1] = ("   applied=%s\n   prompts: %s"):format(tostring(ok), table.concat(ask.log, ","))
      dump[c.name] = body_of(t)
      if c.after then dump[c.name .. "@after"] = c.after() end
      return
    end
    if not ok then lsp.report(P .. c.name, false, "no edit applied for " .. tostring(c.title or "the key function") .. "; offered: " .. titles:sub(1, 400)) return end
    -- the whole file, imports included: the planted header plus the expected class body
    local want = (c.head or table.concat(HEAD, "\n") .. "\n") .. (c.expect == "" and "" or c.expect .. "\n") .. "}"
    local same = t == want
    if same and c.after then
      local aok, adet = c.after()
      if not aok then lsp.report(P .. c.name, false, "after-check: " .. tostring(adet)) return end
    end
    local clean, why = no_errors_after(mark)
    lsp.report(P .. c.name, same and clean,
      not same and ("text differs. got:\n" .. t .. "\n--- want:\n" .. want)
        or not clean and ("text exact but ERROR diagnostics remain: " .. why)
        or ("%.0f ms; text exact, no ERROR diagnostics"):format(ms))
  end)
  if not ok_case then lsp.report(P .. c.name, false, "error: " .. tostring(err)) end
end

-- Case table. src: class body with `@@` (selection start / cursor) and `##` (selection end); expect: the exact class
-- body after the action. Expected texts were read off a real jdt.ls 1.63.0 run and reviewed (names like `i`, `INT`,
-- `element`, `getZ` are jdt.ls's own choices).
local function pick_by(pat) -- nvim-jdtls pick_many prompt: toggle the line matching `pat`, then Enter (empty) ends
  local n = 0
  return function(prompt)
    n = n + 1
    if n > 1 then return "" end
    for line in (prompt .. "\n"):gmatch("(.-)\n") do
      local idx = line:match("^(%d+)%. .*" .. pat)
      if idx then return idx end
    end
    return ""
  end
end
local function pick_new_file(items) for i, v in ipairs(items) do if v == "newFile" then return i end end return 1 end
local function inner_file() -- the moved type is a new, unsaved buffer Inner.java
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):match("/ca91/src/main/java/ca/Inner%.java$") then
      local t = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
      return t == "package ca;\n\nclass Inner {}", "Inner.java buffer: " .. vim.inspect(t)
    end
  end
  return false, "no Inner.java buffer"
end
local cases = {
  { name = "extract_field", title = "^Extract to field", src = "    int f() {\n        return @@2 * 3##;\n    }", expect = "    private int i;\n\n    int f() {\n        i = 2 * 3;\n        return i;\n    }" },
  { name = "extract_variable_all", title = "^Extract to local variable %(replace all", src = "    int f() {\n        int a = @@2 * 3##;\n        int b = 2 * 3 + 1;\n        return a + b;\n    }", expect = "    int f() {\n        int i = 2 * 3;\n        int a = i;\n        int b = i + 1;\n        return a + b;\n    }" },
  { name = "extract_method_params", title = "^Extract to method", src = "    int f(int x) {\n        int y = x + 1;\n        @@int z = y * x;\n        z = z + y;##\n        return z;\n    }", expect = "    int f(int x) {\n        int y = x + 1;\n        int z = getZ(x, y);\n        return z;\n    }\n\n    private int getZ(int x, int y) {\n        int z = y * x;\n        z = z + y;\n        return z;\n    }" },
  { name = "anon_to_lambda", title = "^Convert to lambda expression", src = '    Runnable r = @@new Runnable() {\n        public void run() {\n            System.out.println("hi");\n        }\n    };', expect = '    Runnable r = () -> System.out.println("hi");' },
  { name = "for_to_foreach", title = "^Convert to enhanced 'for' loop", src = "    void f(List<String> l) {\n        @@for (int i = 0; i < l.size(); i++) {\n            System.out.println(l.get(i));\n        }\n    }", expect = "    void f(List<String> l) {\n        for (String element : l) {\n            System.out.println(element);\n        }\n    }" },
  { name = "switch_to_expression", title = "^Convert to switch expression", src = '    String f(int k) {\n        String r;\n        @@switch (k) {\n            case 1: r = "one"; break;\n            case 2: r = "two"; break;\n            default: r = "many"; break;\n        }\n        return r;\n    }', expect = '    String f(int k) {\n        String r = switch (k) {\n            case 1 -> "one";\n            case 2 -> "two";\n            default -> "many";\n        };\n        return r;\n    }' },
  { name = "sort_members", title = "^Sort Members", src = "    void b() {}\n    @@int z;\n    void a() {}\n    int y;", expect = "    int z;\n    int y;\n    void a() {}\n    void b() {}" },
  { name = "add_missing_cases", title = "^Add missing case statements", diag = "does not cover all possible input values|not exhaustive", src = "    enum Color { RED, GREEN }\n    int f(Color c) {\n        return @@switch (c) {\n            case RED -> 1;\n        };\n    }", expect = '    enum Color { RED, GREEN }\n    int f(Color c) {\n        return switch (c) {\n            case RED -> 1;\n            case GREEN -> throw new UnsupportedOperationException("Unimplemented case: " + c);\n            default -> throw new IllegalArgumentException("Unexpected value: " + c);\n        };\n    }' },
  { name = "invert_condition", title = "^Invert conditions", src = "    void f(int a, int b) {\n        if (@@a < b) {\n            System.out.println(1);\n        }\n    }", expect = "    void f(int a, int b) {\n        if (a >= b) {\n            System.out.println(1);\n        }\n    }" },
  { name = "split_declaration", title = "^Split variable declaration", src = "    void f() {\n        int @@x = 5;\n        x++;\n    }", expect = "    void f() {\n        int x;\n        x = 5;\n        x++;\n    }" },
  { name = "join_declaration", title = "^Join variable declaration", src = "    void f() {\n        int @@x;\n        x = 5;\n        x++;\n    }", expect = "    void f() {\n        int x = 5;\n        x++;\n    }" },
  { name = "assign_to_local", title = "^Assign statement to new local", src = "    void f(List<String> l) {\n        @@l.size();\n    }", expect = "    void f(List<String> l) {\n        int size = l.size();\n    }" },
  { name = "assign_to_field", title = "^Assign statement to new field", src = "    void f(List<String> l) {\n        @@l.size();\n    }", expect = "    private int size;\n\n    void f(List<String> l) {\n        size = l.size();\n    }" },
  { name = "surround_try", title = "^Surround with try/catch", src = "    void f() throws Exception {\n        @@Thread.sleep(1);##\n    }", expect = "    void f() throws Exception {\n        try {\n            Thread.sleep(1);\n        } catch (InterruptedException e) {\n        }\n    }" },
  { name = "add_throws", title = "^Add throws declaration", diag = "Unhandled exception", src = "    void f() {\n        @@Thread.sleep(1);\n    }", expect = "    void f() throws InterruptedException {\n        Thread.sleep(1);\n    }" },
  { name = "change_type", title = "^Change type of 'x' to 'String'", diag = "Type mismatch", src = '    void f() {\n        int x = @@"s";\n    }', expect = '    void f() {\n        String x = "s";\n    }' },
  { name = "extract_constant_all", title = "^Extract to constant", src = "    int f() {\n        int a = @@2 * 3##;\n        int b = 2 * 3 + 1;\n        return a + b;\n    }", expect = "    private static final int INT = 2 * 3;\n\n    int f() {\n        int a = INT;\n        int b = INT + 1;\n        return a + b;\n    }" },
  { name = "introduce_parameter", title = "^Introduce Parameter", src = "    int f(int x) {\n        return x + @@42##;\n    }", expect = "    int f(int x, int i) {\n        return x + i;\n    }" },
  { name = "lambda_mref_arrow", title = "^Convert to method reference", src = "    void f(List<String> l) {\n        l.forEach(s @@-> System.out.println(s));\n    }", expect = "    void f(List<String> l) {\n        l.forEach(System.out::println);\n    }" },
  { name = "lambda_mref_func", title = "^Convert to method reference", src = "    java.util.function.Function<String, Integer> g = s @@-> s.length();", expect = "    java.util.function.Function<String, Integer> g = String::length;" },
  { name = "lambda_mref_sel", title = "^Convert to method reference", src = "    java.util.function.Function<String, Integer> g = @@s -> s.length()##;", expect = "    java.util.function.Function<String, Integer> g = String::length;" },
  { name = "foreach_to_indexed_for_not_offered", absent = { "indexed", "[Ii]terator", "^Convert to .*for" }, src = "    void f(List<String> l) {\n        for @@(String s : l) {\n            System.out.println(s);\n        }\n    }" },
  { name = "concat_stringbuilder", title = "^Use 'StringBuilder' for string", src = '    String f(String a, int b) {\n        return "a" + @@a + b;\n    }', expect = '    String f(String a, int b) {\n        StringBuilder stringBuilder = new StringBuilder();\n        stringBuilder.append("a");\n        stringBuilder.append(a);\n        stringBuilder.append(b);\n        return stringBuilder.toString();\n    }' },
  { name = "concat_string_format", title = "^Use 'String.format' for string", src = '    String f(String a, int b) {\n        return "a" + @@a + b;\n    }', expect = '    String f(String a, int b) {\n        return String.format("a%s%d", a, b);\n    }' },
  { name = "concat_messageformat", title = "^Use 'MessageFormat' for string", src = '    String f(String a, int b) {\n        return "a" + @@a + b;\n    }', head = "package ca;\n\nimport java.text.MessageFormat;\nimport java.util.*;\n\npublic class Ca {\n", expect = '    String f(String a, int b) {\n        return MessageFormat.format("a{0}{1}", a, b);\n    }' },
  { name = "convert_to_text_block_not_offered", absent = { "[Tt]ext block" }, src = '    String f() {\n        return @@"line1\\n" + "line2\\n";\n    }' },
  { name = "delegate_methods", title = "^Generate Delegate", many = pick_by("shout"), src = "    private Helper helper;\n    @@", expect = "    private Helper helper;\n\n    public String shout(String s) {\n        return helper.shout(s);\n    }\n    " },
  { name = "add_braces_not_offered", absent = { "[Bb]race", "[Bb]lock", "curly" }, src = "    void f(boolean b) {\n        @@if (b) System.out.println(1);\n    }" },
  { name = "remove_braces_not_offered", absent = { "[Bb]race", "[Bb]lock", "curly" }, src = "    void f(boolean b) {\n        @@if (b) { System.out.println(1); }\n    }" },
  { name = "override_methods", title = "^Override/Implement", many = pick_by("toString"), src = "    @@", expect = "\n    @Override\n    public String toString() {\n        return super.toString();\n    }\n    " },
  { name = "extract_interface_not_offered", absent = { "[Ee]xtract [Ii]nterface" }, cursor = { 4, 14 }, ranges = { { 4, 7, 4, 7 }, "all" }, src = "    int a;\n    void f() {}" },
  { name = "move_inner", title = "^Move 'Inner'", select = pick_new_file, after = inner_file, src = "    static class @@Inner {}", expect = "" },
  { name = "var_to_explicit", title = "^Change type of 'x' to 'ArrayList<String>'", src = '    void f() {\n        var @@x = new ArrayList<String>();\n        x.add("a");\n    }', expect = '    void f() {\n        ArrayList<String> x = new ArrayList<String>();\n        x.add("a");\n    }' },
  { name = "explicit_to_var", title = "^Change type of 'x' to 'var'", src = "    void f() {\n        int @@x = 5;\n        x++;\n    }", expect = "    void f() {\n        var x = 5;\n        x++;\n    }" },
  { name = "class_to_record_not_offered", absent = { "[Rr]ecord" }, src = "    static class @@P {\n        final int x;\n        P(int x) { this.x = x; }\n        int x() { return x; }\n    }" },
  { name = "local_to_field", title = "^Extract to field", src = "    void f() {\n        int @@x = 5;\n        x++;\n    }", expect = "    private int x;\n\n    void f() {\n        x = 5;\n        x++;\n    }" },
  { name = "encapsulate_field_not_offered", absent = { "^Encapsulate" }, src = "    int @@x;" },
  { name = "getter_setter_one_field", title = "^Generate Getter and Setter for 'x'", src = "    int @@x;", expect = "    int x;\n\n    public int getX() {\n        return x;\n    }\n\n    public void setX(int x) {\n        this.x = x;\n    }" },
  { name = "final_local", title = "^Add final modifier for 'b'", src = "    int f(int a) {\n        int @@b = a;\n        return b;\n    }", expect = "    int f(int a) {\n        final int b = a;\n        return b;\n    }" },
  { name = "final_where_possible", title = "^Change modifiers to final where possible", src = "    int f(int a) {\n        int b = a;\n        @@return b;\n    }", expect = "    int f(final int a) {\n        final int b = a;\n        return b;\n    }" },
  { name = "anon_to_nested", title = "^Convert anonymous to nested class", src = "    Runnable r = @@new Runnable() {\n        public void run() {}\n    };", expect = "    private final class RunnableImplementation implements Runnable {\n        public void run() {}\n    }\n\n    Runnable r = new RunnableImplementation();" },
  { name = "javadoc", title = "^Add Javadoc comment", src = "    int f(int a) {\n        @@return a;\n    }", expect = "    /**\n     * @param a\n     * @return\n     */\n    int f(int a) {\n        return a;\n    }" },
  { name = "lambda_infer_types", title = "^Add inferred lambda parameter types", src = "    java.util.function.Function<String, Integer> g = @@s -> s.length();", expect = "    java.util.function.Function<String, Integer> g = (String s) -> s.length();" },
  { name = "suppress_warnings", title = "^Add @SuppressWarnings 'unused' to 'x'", src = "    void f() {\n        int @@x = 5;\n    }", expect = '    void f() {\n        @SuppressWarnings("unused")\n        int x = 5;\n    }' },
  { name = "add_default_case", title = "^Add 'default' case", diag = "does not cover all possible input values|not exhaustive", src = "    enum Color { RED, GREEN }\n    int f(Color c) {\n        return @@switch (c) {\n            case RED -> 1;\n        };\n    }", expect = '    enum Color { RED, GREEN }\n    int f(Color c) {\n        return switch (c) {\n            case RED -> 1;\n            default -> throw new IllegalArgumentException("Unexpected value: " + c);\n        };\n    }' },
  { name = "add_access_modifier", title = "^Add Access Modifier", src = "    int @@x;", expect = "    private int x;" },
  { name = "make_static", title = "^Make Static", src = "    @@void f() {}", expect = "    static void f() {}" },
  { name = "extract_variable_key", call = function() require("jdtls").extract_variable_all(true) end, src = "    int f() {\n        int a = @@2 * 3##;\n        int b = 2 * 3 + 1;\n        return a + b;\n    }", expect = "    int f() {\n        int i = 2 * 3;\n        int a = i;\n        int b = i + 1;\n        return a + b;\n    }" },
  { name = "extract_constant_key", call = function() require("jdtls").extract_constant(true) end, src = "    int f() {\n        int a = @@2 * 3##;\n        int b = 2 * 3 + 1;\n        return a + b;\n    }", expect = "    private static final int INT = 2 * 3;\n\n    int f() {\n        int a = INT;\n        int b = INT + 1;\n        return a + b;\n    }" },
  { name = "extract_method_key", call = function() require("jdtls").extract_method(true) end, src = "    int f(int x) {\n        int y = x + 1;\n        @@int z = y * x;\n        z = z + y;##\n        return z;\n    }", expect = "    int f(int x) {\n        int y = x + 1;\n        int z = getZ(x, y);\n        return z;\n    }\n\n    private int getZ(int x, int y) {\n        int z = y * x;\n        z = z + y;\n        return z;\n    }" },
  { name = "inline_local", title = "^Inline local variable", src = "    int f(int a) {\n        int @@b = a + 1;\n        return b * 2;\n    }", expect = "    int f(int a) {\n        return (a + 1) * 2;\n    }" },
  { name = "lambda_to_anon", title = "^Convert to anonymous class creation", src = '    Runnable r = () @@-> System.out.println("hi");', expect = '    Runnable r = new Runnable() {\n        @Override\n        public void run() {\n            System.out.println("hi");\n        }\n    };' },
  { name = "lambda_expr_to_block", title = "^Change body expression to block", src = "    java.util.function.Function<String, Integer> g = s @@-> s.length();", expect = "    java.util.function.Function<String, Integer> g = s -> {\n        return s.length();\n    };" },
  { name = "lambda_block_to_expr", title = "^Change body block to expression", src = "    java.util.function.Function<String, Integer> g = s @@-> { return s.length(); };", expect = "    java.util.function.Function<String, Integer> g = s -> s.length();" },
  { name = "extract_lambda_body", title = "^Extract lambda body to method", src = "    java.util.function.Function<String, Integer> g = @@s -> s.length();", expect = "    java.util.function.Function<String, Integer> g = s -> extracted(s);\n\n    private int extracted(String s) {\n        return s.length();\n    }" },
  { name = "introduce_parameter_object_not_offered", absent = { "[Pp]arameter [Oo]bject" }, src = "    int f(int x, int y) {\n        return @@x + y;\n    }" },

}
-- Negative controls (NV4J_CA_CONTROL, with NV4J_CA_NAMES=<one case>): each breaks the trigger or the product and the
-- case must FAIL. noinput: the nvim-jdtls pickers answer nothing; nokey: the key function is not called; noedit: the
-- workspace edit is not applied; keeperror: a type error stays in the file after the action.
local CONTROL = vim.env.NV4J_CA_CONTROL
if CONTROL == "noinput" then vim.fn.input = function() return "" end end
if CONTROL == "noedit" then vim.lsp.util.apply_workspace_edit = function() end end
if CONTROL == "nokey" then for _, c in ipairs(cases) do if c.call then c.call = function() end end end end
if CONTROL == "keeperror" then for _, c in ipairs(cases) do c.src = c.src .. '\n    int broken_ctrl = "x";' ; c.expect = c.expect and (c.expect .. '\n    int broken_ctrl = "x";') end end
local only = vim.env.NV4J_CA_NAMES and vim.split(vim.env.NV4J_CA_NAMES, ",") or nil
for _, c in ipairs(cases) do
  if not only or vim.tbl_contains(only, c.name) then run(c) end
end

-- the keys that reach these actions in a Java buffer of the config: <leader>ca (LazyVim, any code action), <leader>co,
-- <leader>cxv / cxc / cxm (LazyVim jdtls extra: extract variable / constant / method, cases *_key above call their functions)
if not only then
  for _, k in ipairs({ { "<leader>ca", "ode" }, { "<leader>co", "Organize" }, { "<leader>cxv", "Extract Variable" }, { "<leader>cxc", "Extract Constant" } }) do
    local m = E.keymap(k[1], buf)
    lsp.report(P .. "key_" .. k[1]:gsub("<leader>", "leader_"), m ~= nil and (m.desc or ""):find(k[2], 1, true) ~= nil, "mapping: " .. tostring(m and m.desc))
  end
end
E.restore(buf, orig)
if PROBE then
  vim.fn.writefile(probe_lines, "/tmp/nv4j/ca91_probe.txt")
  vim.fn.writefile({ "return " .. vim.inspect(dump) }, "/tmp/nv4j/ca91_dump.lua")
end
lsp.finish()
