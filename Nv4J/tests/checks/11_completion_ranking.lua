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
      local at = C.find_line(buf, cs.after) + 1
      vim.api.nvim_buf_set_lines(buf, at, at, false, cs.lines)
      local lnum = at + #cs.lines - 1
      local col = #cs.lines[#cs.lines]
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
