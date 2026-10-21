-- P1 code actions. Run via tests/run.sh. Spec: specs/features/diagnostics-imports-actions.md.
-- Planted sources replace App.java's buffer in memory. Actions are listed with
-- textDocument/codeAction (diagnostics at the range as context, like <leader>ca) and applied
-- through Neovim's own vim.lsp.buf.code_action (resolve + edit or client command). Only UI prompts
-- are stubbed: nvim-jdtls's field picker (select all) and the rename prompt after an extract.
--  quickfix  : undefined method (same class / other class), undefined variable, undefined class,
--              missing import, missing interface method, unused import, unused local
--  generate  : getters/setters, constructors, toString (IntelliJ-like template), equals/hashCode
--              (java.util.Objects, braces)
--  extract   : variable / constant / method on a selected expression
--  lombok    : temp project /tmp/nv4j/lombokcase with @Getter/@RequiredArgsConstructor: the
--              generated members resolve (no errors, `item.` completes getName), jdtls runs with the
--              lombok agent.
-- Timings: /tmp/nv4j/logs/latency.jsonl (code_action_*).
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local S = vim.diagnostic.severity
local P = "32_code_actions."
local BUDGET_MS = 1000 -- one codeAction round trip

local buf = lsp.open(vim.env.NV4J_FIXTURE .. "/src/main/java/demo/App.java")
local client = lsp.wait_ready(buf, 120000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready" or "jdtls not ready")
if not client then return lsp.finish() end
local orig = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

-- UI stubs (prompts only): the user presses Enter in nvim-jdtls's field picker (keeps the
-- preselection) and cancels the rename prompt that follows an extract.
vim.fn.input = function() return "" end
vim.ui.input = function(_, on_confirm) on_confirm(nil) end

local function offered(case, line, col, pats, el, ec)
  local r = E.code_actions(client, buf, line, col, el, ec)
  E.log("code_action_" .. case, r.ms, #r.actions)
  local missing = {}
  for _, p in ipairs(pats) do
    if not E.find(r.actions, p) then missing[#missing + 1] = p end
  end
  lsp.report(P .. case, not r.err and #missing == 0 and r.ms <= BUDGET_MS,
    ("%.0f ms (budget %d); missing=[%s] offered: %s"):format(r.ms, BUDGET_MS, table.concat(missing, ", "),
      r.err or E.titles(r.actions):sub(1, 400)))
  return r
end

local function wait_errors(pred)
  return E.wait_diags(buf, pred, 10000)
end

local ok_all, err = pcall(function()
  ---------------------------------------------------------------- quick fixes on errors
  E.set(buf, E.planted("actions.java.txt"))
  local ok = wait_errors(function(d)
    return E.has(d, S.ERROR, "must implement the inherited abstract method Runnable.run") ~= nil
      and E.has(d, S.ERROR, "List cannot be resolved") ~= nil
  end)
  lsp.report(P .. "planted_errors", ok, E.fmt(vim.diagnostic.get(buf)))
  local L = function(pat) return E.line_of(buf, pat) end
  offered("create_method_other_class", L("doesNotExist"), 14, { "^Create method 'doesNotExist%(%)' in type 'Repo'" })
  offered("create_method", L("twice%(21%)"), 23, { "^Create method 'twice%(int%)'" })
  offered("create_variable", L("undefinedVar"), 10, { "^Create local variable 'undefinedVar'", "^Create field 'undefinedVar'" })
  offered("create_class", L("Undef thing"), 9, { "^Create class 'Undef'" })
  local r = offered("import_type", L("List<String> names"), 9, { "^Import 'List' %(java%.util%)" })
  local first_import = E.find(r.actions, "^Import '")
  lsp.report(P .. "import_type_first", first_import and first_import.title:find("java%.util") ~= nil,
    "first import proposal: " .. tostring(first_import and first_import.title))
  offered("implement_methods", L("class App implements Runnable"), 14, { "^Add unimplemented methods" })

  -- apply three of them and check the result compiles further
  local okm, msm = E.apply(buf, "^Add unimplemented methods", L("class App implements Runnable"), 14)
  local okd = wait_errors(function(d) return E.has(d, S.ERROR, "Runnable.run") == nil end)
  lsp.report(P .. "apply_implement_methods", okm and okd and E.text(buf):find("public void run%(%)") ~= nil,
    ("%.0f ms; run() %s"):format(msm, E.text(buf):find("public void run%(%)") and "added" or "MISSING"))
  local oki = E.apply(buf, "^Import 'List' %(java%.util%)", L("List<String> names"), 9)
  wait_errors(function(d) return E.has(d, S.ERROR, "List cannot be resolved") == nil end)
  lsp.report(P .. "apply_import", oki and E.text(buf):find("\nimport java.util.List;\n", 1, true) ~= nil,
    E.text(buf):find("import java.util.List;", 1, true) and "import added" or "import MISSING")
  local okc = E.apply(buf, "^Create method 'twice%(int%)'", L("twice%(21%)"), 23)
  local okc2 = wait_errors(function(d) return E.has(d, S.ERROR, "twice") == nil end)
  lsp.report(P .. "apply_create_method", okc and okc2 and E.text(buf):find("int twice%(int ") ~= nil,
    E.text(buf):find("int twice%(int ") and "twice(int) created" or "MISSING: " .. E.fmt(vim.diagnostic.get(buf)))

  ---------------------------------------------------------------- quick fixes on warnings
  E.set(buf, E.planted("unused.java.txt"))
  wait_errors(function(d) return E.has(d, S.WARN, "import java.util.Map is never used") ~= nil end)
  offered("remove_unused_import", L("^import java.util.Map"), 10, { "^Remove unused import" })
  offered("remove_unused_local", L("int unused"), 13, { "^Remove 'unused' and all assignments" })
  local oku = E.apply(buf, "^Remove unused import", L("^import java.util.Map"), 10)
  lsp.report(P .. "apply_remove_unused_import", oku and not E.text(buf):find("java.util.Map", 1, true),
    E.text(buf):find("java.util.Map", 1, true) and "import still there" or "import removed")

  ---------------------------------------------------------------- generate
  E.set(buf, E.planted("bean.java.txt"))
  wait_errors(function(d) return E.has(d, S.WARN, "App.name is not used") ~= nil end)
  local fl = L("private String name")
  offered("generate_menu", fl, 20, {
    "^Generate Getters and Setters", "^Generate Constructors", "^Generate toString%(%)", "^Generate hashCode%(%) and equals%(%)",
  })
  local okg = E.apply(buf, "^Generate Getters and Setters$", fl, 20)
  local t = E.text(buf)
  lsp.report(P .. "apply_getters_setters", okg and t:find("public String getName%(%)") ~= nil and t:find("public void setAge%(int age%)") ~= nil,
    ("getName %s, setAge %s"):format(t:find("public String getName%(%)") and "yes" or "NO", t:find("public void setAge%(int age%)") and "yes" or "NO"))
  local okt = E.apply(buf, "^Generate toString%(%)", L("private String name"), 20)
  t = E.text(buf)
  -- IntelliJ's default is App{name='x', age=1}; jdt.ls templates cannot quote only strings, so the
  -- closest is App{name=x, age=1}: all fields preselected (Enter), no getters/methods, `{...}` form.
  local ts = t:match("public String toString%(%) {(.-)\n    }")
  lsp.report(P .. "apply_tostring_intellij_style", okt and ts ~= nil and ts:find('"App{name=" + name + ", age=" + age + "}"', 1, true) ~= nil,
    "toString body: " .. tostring(ts and ts:gsub("%s+", " ")))
  local okh = E.apply(buf, "^Generate hashCode%(%) and equals%(%)", L("private String name"), 20)
  t = E.text(buf)
  -- JDT boxes primitives explicitly: Objects.hash(name, Integer.valueOf(age)) (IntelliJ: (name, age))
  lsp.report(P .. "apply_equals_hashcode", okh and t:find("Objects%.hash%(name, ") ~= nil and t:find("Objects%.equals%(name, other%.name%)") ~= nil
    and t:find("if %(this == obj%) {") ~= nil,
    ("Objects.hash %s, Objects.equals %s, braces %s; hashCode: %s"):format(t:find("Objects%.hash%(name, ") and "yes" or "NO", t:find("Objects%.equals%(name, other%.name%)") and "yes" or "NO", t:find("if %(this == obj%) {") and "yes" or "NO",
      ((t:match("public int hashCode%(%) {(.-)\n    }") or "none"):gsub("%s+", " "))))

  ---------------------------------------------------------------- constructor (fresh bean)
  E.set(buf, E.planted("bean.java.txt"))
  wait_errors(function(d) return E.has(d, S.WARN, "App.name is not used") ~= nil end)
  local okk = E.apply(buf, "^Generate Constructors", L("private String name"), 20)
  local ctor = E.text(buf):match("\n%s*(public App%([^)]*%))")
  -- jdt.ls preselects the field under the cursor (IntelliJ: the final fields); Enter keeps it
  lsp.report(P .. "apply_constructor", okk and ctor == "public App(String name)",
    "generated: " .. tostring(ctor))

  ---------------------------------------------------------------- extract
  E.set(buf, E.planted("bean.java.txt"))
  wait_errors(function(d) return E.has(d, S.WARN, "App.name is not used") ~= nil end)
  local el = L("return base %+ 2 %* 3")
  local line = vim.api.nvim_buf_get_lines(buf, el, el + 1, false)[1]
  local s = line:find("2 * 3", 1, true) - 1
  offered("extract_menu", el, s, { "^Extract to local variable$", "^Extract to constant", "^Extract to method" }, el, s + 5)
  local okx = E.apply(buf, "^Extract to local variable$", el, s, el, s + 5)
  vim.wait(500)
  t = E.text(buf)
  lsp.report(P .. "apply_extract_variable", okx and t:find("int %w+ = 2 %* 3;") ~= nil,
    "after extract: " .. (t:match("public int score%(%) {(.-)\n    }") or ""):gsub("%s+", " "))

  for _, x in ipairs({
    { case = "apply_extract_constant", title = "^Extract to constant", want = "static final int %w+ = 2 %* 3;" },
    { case = "apply_extract_method", title = "^Extract to method", want = "private int %w+%(%) {%s*return 2 %* 3;" },
  }) do
    E.set(buf, E.planted("bean.java.txt"))
    wait_errors(function(d) return E.has(d, S.WARN, "App.name is not used") ~= nil end)
    local okc = E.apply(buf, x.title, el, s, el, s + 5)
    vim.wait(500)
    local tt = E.text(buf)
    lsp.report(P .. x.case, okc and tt:find(x.want) ~= nil, "after: " .. (tt:match("\n(.-)\n}$") or tt):gsub("%s+", " "):sub(-200))
  end
end)
E.restore(buf, orig)
if not ok_all then lsp.report(P .. "in_memory_cases", false, "error: " .. tostring(err)) end

---------------------------------------------------------------- lombok (temp project)
local dir = "/tmp/nv4j/lombokcase"
vim.fn.delete(dir, "rf")
vim.fn.mkdir(dir .. "/src/main/java/lc", "p")
vim.fn.writefile({
  '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>',
  "<groupId>lc</groupId><artifactId>lombokcase</artifactId><version>1</version>",
  "<properties><maven.compiler.release>25</maven.compiler.release>",
  "<project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>",
  "<dependencies><dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId>",
  "<version>1.18.46</version><scope>provided</scope></dependency></dependencies>",
  "</project>",
}, dir .. "/pom.xml")
vim.fn.writefile({
  "package lc;",
  "import lombok.Getter;",
  "import lombok.RequiredArgsConstructor;",
  "@Getter",
  "@RequiredArgsConstructor",
  "public class Item {",
  "    private final String name;",
  "    private final int count;",
  "}",
}, dir .. "/src/main/java/lc/Item.java")
vim.fn.writefile({
  "package lc;",
  "public class Use {",
  "    static String describe() {",
  "        Item item = new Item(\"pen\", 2);",
  "        return item.getName() + item.getCount();",
  "    }",
  "}",
}, dir .. "/src/main/java/lc/Use.java")
local ok_l, err_l = pcall(function()
  local ubuf = lsp.open(dir .. "/src/main/java/lc/Use.java")
  local c2 = lsp.wait_ready(ubuf, 120000)
  lsp.report(P .. "lombok_attached", c2 ~= nil, c2 and "jdtls ready (lombokcase)" or "jdtls not ready")
  if not c2 then return end
  local okd, _, d = E.wait_diags(ubuf, function(x) return #x == 0 end, 15000)
  lsp.report(P .. "lombok_members_resolve", okd, okd and "0 diagnostics in Use.java (getName/getCount/ctor from Lombok)" or E.fmt(d))
  local lnum = 4
  local lorig = vim.api.nvim_buf_get_lines(ubuf, 0, -1, false)
  vim.api.nvim_buf_set_lines(ubuf, lnum, lnum + 1, false, { "        return item." })
  local r = lsp.complete(ubuf, lnum, #"        return item.")
  local labels = vim.tbl_map(function(i) return i.label end, r.items)
  local has = vim.tbl_contains(labels, "getName") or vim.tbl_contains(vim.tbl_map(function(l) return l:match("^(getName)%(") or "" end, labels), "getName")
  lsp.report(P .. "lombok_completion", not r.err and has, ("item. -> getName %s (%d items: %s)"):format(has and "listed" or "MISSING", #r.items, table.concat(vim.list_slice(labels, 1, 12), ", ")))
  E.restore(ubuf, lorig)
  local agent
  for _, l in ipairs(vim.fn.systemlist({ "ps", "-axo", "command=" })) do
    if l:find("org.eclipse.equinox.launcher", 1, true) and l:find("/tmp/nv4j/jdtls-data/lombokcase", 1, true) then
      agent = l:match("%-javaagent:(%S*lombok%S*%.jar)")
    end
  end
  lsp.report(P .. "lombok_agent", agent ~= nil and vim.uv.fs_stat(agent) ~= nil, "jdtls -javaagent: " .. tostring(agent))
end)
if not ok_l then lsp.report(P .. "lombok", false, "error: " .. tostring(err_l)) end
lsp.finish()
