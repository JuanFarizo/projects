-- P1 completion ranking. Run via tests/run.sh. Budget: expected item in the top 5 of the order the
-- user sees (blink.cmp's configured fuzzy + sorts applied to the jdtls items), plus a relative
-- condition per case. The jdtls order (sortText) is reported alongside for diagnosis.
vim.o.confirm = false
local lsp = require("lsp")
local C = require("completion")

local TOP_N = 5
local src = vim.env.NV4J_FIXTURE .. "/src/main/java/demo/"
local K = vim.lsp.protocol.CompletionItemKind

local function kind(it) return K[it.kind] end
local function pkg(it)
  local ld = it.labelDetails
  return (ld and ld.description) or it.detail or ""
end
-- Types and packages that do not come from the project (JDK/library noise for these cases).
local function is_foreign_type(it)
  local k = kind(it)
  return (k == "Class" or k == "Interface" or k == "Enum" or k == "Module") and not pkg(it):find("^demo")
end

local nobody = '        Person nobody = new Person("Nobody", 0);'
local cases = {
  {
    -- Expected-type locality: a local of the expected type beats keywords such as new/null.
    name = "local_expected_type",
    file = "App.java", after = "Repo repo = new Repo",
    lines = { nobody, "        Person best = n" },
    expect = function(it) return it.label == "nobody" end, expect_label = "nobody",
    worse = function(it) return kind(it) == "Keyword" end, worse_label = "first keyword",
  },
  {
    -- Same, with nothing typed yet after `=`.
    name = "local_expected_type_empty",
    file = "App.java", after = "Repo repo = new Repo",
    lines = { nobody, "        Person best = " },
    expect = function(it) return it.label == "nobody" end, expect_label = "nobody",
    worse = function(it) return kind(it) == "Keyword" end, worse_label = "first keyword",
  },
  {
    -- Locality: a field of the enclosing class beats JDK types sharing the prefix.
    name = "field_over_jdk_noise",
    file = "Person.java", after = "public String getName",
    lines = { "        a" },
    expect = function(it) return it.label == "age" and kind(it) == "Field" end, expect_label = "age",
    worse = is_foreign_type, worse_label = "first non-project type",
  },
  {
    -- Project annotation reachable by prefix.
    name = "annotation_prefix",
    file = "Person.java", after = "^    }",
    lines = { "    @My" },
    expect = function(it) return it.label == "MyAnno" end, expect_label = "MyAnno",
  },
}

-- Spring-scale cases (Boot 3.5 web, data-jpa, security, validation on the classpath).
-- `replace`: the case line replaces the first line matching it instead of being inserted.
local function label_is(l) return function(it) return it.label == l end end
local spring = {
  { name = "spring_annotation_list", file = "CustomerController.java", after = "^@RequestMapping", lines = { "@" }, label = "RestController" },
  { name = "spring_anno_auto", file = "CustomerController.java", after = "private final CustomerRepository repository;", lines = { "    @Auto" }, label = "Autowired" },
  { name = "spring_anno_rest", file = "CustomerController.java", after = "^@RequestMapping", lines = { "@Rest" }, label = "RestController" },
  { name = "table_attrs", file = "Customer.java", replace = "^@Table%(", lines = { "@Table()" }, back = 1, label = "name" },
  { name = "column_attrs", file = "Customer.java", replace = '@Column%(name = "email"', lines = { "    @Column()" }, back = 1, label = "nullable" },
  { name = "http_dsl", file = "SecurityConfig.java", after = "public SecurityFilterChain filterChain", lines = { "        http." }, label = "authorizeHttpRequests" },
  { name = "jpa_repo_members", file = "CustomerController.java", after = "public Customer create", lines = { "        repository." }, label = "save" },
  { name = "spring_identifier_a", file = "CustomerController.java", after = "public ResponseEntity<Customer> update", lines = { "        a" }, label = "amended", worse = true },
  { name = "spring_identifier_s", file = "CustomerController.java", after = "public List<Customer> search", lines = { "        s" }, label = "search", worse = true },
}
for _, s in ipairs(spring) do
  s.expect, s.expect_label = label_is(s.label), s.label
  if s.worse then s.worse, s.worse_label = is_foreign_type, "first non-project type" else s.worse = nil end
  cases[#cases + 1] = s
end

local fuzzy = C.blink()
lsp.report("11_completion_ranking.blink_loaded", fuzzy ~= nil and fuzzy.implementation_type == "rust",
  fuzzy and fuzzy.implementation_type or "blink.cmp not loaded")

for _, cs in ipairs(cases) do
  local tag = "11_completion_ranking." .. cs.name
  local buf = C.open_ready(lsp, src .. cs.file, 120000)
  if not buf then
    lsp.report(tag, false, "jdtls not ready within 120 s")
  elseif not fuzzy then
    lsp.report(tag, false, "blink.cmp unavailable, cannot compute the visible order")
  else
    C.scratch(buf, function()
      local at
      if cs.replace then
        at = C.find_line(buf, cs.replace)
        vim.api.nvim_buf_set_lines(buf, at, at + 1, false, cs.lines)
      else
        at = C.find_line(buf, cs.after) + 1
        vim.api.nvim_buf_set_lines(buf, at, at, false, cs.lines)
      end
      local lnum = at + #cs.lines - 1
      local col = #cs.lines[#cs.lines] - (cs.back or 0)
      local r = lsp.complete(buf, lnum, col)
      if r.err then
        lsp.report(tag, false, "err=" .. r.err)
        return
      end
      local shown = C.blink_order(fuzzy, buf, lnum, col, r.items)
      local by_lsp = C.lsp_order(r.items)
      local rank = C.rank(shown, cs.expect)
      local lsp_rank = C.rank(by_lsp, cs.expect)
      local worse = cs.worse and C.rank(shown, cs.worse)
      local ok = rank ~= nil and rank <= TOP_N and (worse == nil or rank < worse)
      local detail = ("rank(%s)=%s (budget <= %d) jdtls_rank=%s%s count=%d/%d shown=[%s]"):format(
        cs.expect_label, tostring(rank), TOP_N, tostring(lsp_rank),
        cs.worse and (" " .. cs.worse_label .. "=" .. tostring(worse)) or "",
        #shown, #r.items, C.labels(shown, 6))
      lsp.report(tag, ok, detail)
    end)
  end
end

lsp.finish()
