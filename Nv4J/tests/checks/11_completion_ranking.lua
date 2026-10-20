-- P1 completion ranking. Run via tests/run.sh. Budget: expected item in the top 5 of the order the
-- user sees (blink.cmp's own pipeline, see completion.lua M.menu: every source enabled for Java,
-- transform_items, fuzzy, sorts, max_items), plus a relative condition per case. The jdtls order
-- (sortText) of a plain request is reported alongside for diagnosis.
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
  -- Member lists after a typed prefix (what follows `http.`/`repository.` one keystroke later).
  { name = "http_dsl_prefix", file = "SecurityConfig.java", after = "public SecurityFilterChain filterChain", lines = { "        http.au" }, label = "authorizeHttpRequests" },
  { name = "jpa_repo_prefix", file = "CustomerController.java", after = "public Customer create", lines = { "        repository.sa" }, label = "save" },
  -- jdt.ls postfix templates stay reachable by their key after the re-ranking.
  { name = "postfix_by_key", file = "SecurityConfig.java", after = "public SecurityFilterChain filterChain", lines = { "        http.va" }, label = "var" },
  -- Same, the way it is typed: list fetched at `http.`, "va" filtered by blink without a request.
  { name = "postfix_by_key_typed", file = "SecurityConfig.java", after = "public SecurityFilterChain filterChain", lines = { "        http.va" }, typed_after = "        http.", label = "var" },
  { name = "http_dsl_prefix_typed", file = "SecurityConfig.java", after = "public SecurityFilterChain filterChain", lines = { "        http.au" }, typed_after = "        http.", label = "authorizeHttpRequests" },
}
for _, s in ipairs(spring) do
  s.expect, s.expect_label = label_is(s.label), s.label
  if s.worse then s.worse, s.worse_label = is_foreign_type, "first non-project type" else s.worse = nil end
  cases[#cases + 1] = s
end

-- Rule cases: a condition on the whole visible list instead of one item's rank.
local Kk = vim.lsp.protocol.CompletionItemKind
local function snippets_after_members(shown)
  local last_member, first_snippet = 0, nil
  for i, it in ipairs(shown) do
    if it.kind == Kk.Method or it.kind == Kk.Field or it.kind == Kk.Constant then last_member = i end
    if it.kind == Kk.Snippet and not first_snippet then first_snippet = i end
  end
  return first_snippet == nil or first_snippet > last_member,
    ("last member=%d first snippet=%s"):format(last_member, tostring(first_snippet))
end
-- Types filtered by java.completion.filteredTypes and fully qualified package names must not be
-- listed for a bare identifier (blink transform in nv4j/completion.lua drops the packages).
local NOISE = { "^com%.apple", "^apple%.", "^sun%.", "^com%.sun%.", "^jdk%.", "^java%.awt", "^javax%.swing", "^aj%.", "^org%.aspectj%.internal" }
local function no_noise(shown)
  local bad = {}
  for _, it in ipairs(shown) do
    local d = pkg(it)
    local noisy = it.kind == Kk.Module and it.label:find(".", 1, true)
    for _, pat in ipairs(NOISE) do
      if d:find(pat) or (it.kind == Kk.Module and it.label:find(pat)) then noisy = true end
    end
    if noisy and #bad < 5 then bad[#bad + 1] = it.label .. "(" .. d .. ")" end
  end
  return #bad == 0, ("%d shown, noise=[%s]"):format(#shown, table.concat(bad, ", "))
end
local rules = {
  { name = "snippets_after_members_http", file = "SecurityConfig.java", after = "public SecurityFilterChain filterChain", lines = { "        http." }, rule = snippets_after_members },
  { name = "snippets_after_members_repo", file = "CustomerController.java", after = "public Customer create", lines = { "        repository." }, rule = snippets_after_members },
  { name = "no_noise_a", file = "CustomerController.java", after = "public ResponseEntity<Customer> update", lines = { "        a" }, rule = no_noise },
  { name = "no_noise_s", file = "CustomerController.java", after = "public List<Customer> search", lines = { "        s" }, rule = no_noise },
  { name = "no_noise_m", file = "CustomerController.java", after = "public List<Customer> search", lines = { "        m" }, rule = no_noise },
}
for _, r in ipairs(rules) do cases[#cases + 1] = r end

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
      local m, merr
      if cs.typed_after then
        -- Real typing: the list is fetched at `typed_after` and the rest is filtered locally.
        vim.api.nvim_buf_set_lines(buf, lnum, lnum + 1, false, { cs.typed_after })
        m, merr = C.menu(buf, lnum, #cs.typed_after)
        vim.api.nvim_buf_set_lines(buf, lnum, lnum + 1, false, { cs.lines[#cs.lines] })
        if m then m.items = C.refilter(buf, lnum, col, m.by_source) end
      else
        m, merr = C.menu(buf, lnum, col)
      end
      if not m then
        lsp.report(tag, false, "menu: " .. tostring(merr))
        return
      end
      local shown = m.items
      if cs.rule then
        local ok, d = cs.rule(shown)
        lsp.report(tag, ok, d .. " shown=[" .. C.labels(shown, 6) .. "]")
        return
      end
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
