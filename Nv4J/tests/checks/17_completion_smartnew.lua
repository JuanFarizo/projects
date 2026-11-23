-- Smart `new` (specs/features/completion-ranking.md, "Smart new"): after `Type x = ` the `new` keyword, and after
-- `Type x = new ` the constructor of the declared type (or the usual JDK implementation of an interface) come first,
-- like IntelliJ's smart completion. Ranks are the order the user sees (blink's pipeline, C.menu); each case wants
-- an exact rank. NV4J_SMARTNEW_CONTROL=1 switches the feature off (vim.g.nv4j_no_smart_new): the cases marked
-- `fixed` must then FAIL (the others already ranked first from jdt.ls's own relevance).
vim.o.confirm = false
local lsp = require("lsp")
local C = require("completion")
local K = vim.lsp.protocol.CompletionItemKind
if vim.env.NV4J_SMARTNEW_CONTROL == "1" then vim.g.nv4j_no_smart_new = true end
local src = vim.env.NV4J_FIXTURE .. "/src/main/java/demo/"

local function ctor(l, p)
  return function(it)
    return it.kind == K.Constructor and it.label == l
      and ((it.labelDetails and it.labelDetails.description) or it.detail or ""):find("^" .. p) ~= nil
  end
end
local function kw_new(it) return it.kind == K.Keyword and it.label == "new" end
local cases = {
  { name = "person_n", line = "        Person p = n", expect = kw_new, what = "keyword new", rank = 1, fixed = true },
  { name = "person_ne", line = "        Person p = ne", expect = kw_new, what = "keyword new", rank = 1 },
  { name = "person_new_empty", line = "        Person p = new ", expect = ctor("Person", "demo%.Person"), what = "demo.Person ctor", rank = 1 },
  { name = "person_new_Pe", line = "        Person p = new Pe", expect = ctor("Person", "demo%.Person"), what = "demo.Person ctor", rank = 1 },
  { name = "list_ne", line = "        List<String> l = ne", expect = kw_new, what = "keyword new", rank = 1 },
  { name = "list_new_Arr", line = "        List<String> l = new Arr", expect = ctor("ArrayList", "java%.util%."), what = "java.util.ArrayList ctor", rank = 1, fixed = true },
  { name = "map_new_H", line = "        Map<String,Integer> m = new H", expect = ctor("HashMap", "java%.util%."), what = "java.util.HashMap ctor", rank = 1, fixed = true },
  { name = "map_new_Ha", line = "        Map<String,Integer> m = new Ha", expect = ctor("HashMap", "java%.util%."), what = "java.util.HashMap ctor", rank = 1, fixed = true },
}

-- declared_type parsing (pure)
local N = require("nv4j.completion")
local function dt(s, want_t, want_new)
  local t, n = N.declared_type(s)
  lsp.report("17_completion_smartnew.declared_type[" .. s .. "]", t == want_t and n == want_new, tostring(t) .. "," .. tostring(n))
end
dt("        Person p = ", "Person", false)
dt("        Map<String, List<Integer>> m = new ", "Map", true)
dt("        final Person p =  ", "Person", false)
dt("        p = ", nil, nil)
dt("        return ", nil, nil)
dt("        if (a == ", nil, nil)
dt("        var x = ", nil, nil)
dt("        int[] a = ", nil, nil)

local fuzzy = C.blink()
for _, cs in ipairs(cases) do
  local tag = "17_completion_smartnew." .. cs.name
  local buf = C.open_ready(lsp, src .. "App.java", 120000)
  if not buf then
    lsp.report(tag, false, "jdtls not ready")
  elseif not fuzzy then
    lsp.report(tag, false, "blink.cmp unavailable")
  else
    C.scratch(buf, function()
      local at = C.find_line(buf, "Repo repo = new Repo") + 1
      vim.api.nvim_buf_set_lines(buf, at, at, false, { cs.line })
      local m, err = C.menu(buf, at, #cs.line)
      if not m then return lsp.report(tag, false, "menu: " .. tostring(err)) end
      local rank = C.rank(m.items, cs.expect)
      lsp.report(tag, rank == cs.rank, ("rank(%s)=%s want %d shown=[%s]"):format(cs.what, tostring(rank), cs.rank, C.labels(m.items, 5)))
    end)
  end
end
lsp.finish()
