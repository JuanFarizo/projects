-- Completion ranking, client tie-breakers and list shape (specs/features/completion-ranking.md, "Experiments
-- after the reference map"). Run via tests/run.sh. Ranks come from blink's own pipeline (C.menu).
-- Cases name the order inside a group of items that jdt.ls scores the same (same relevance, no usage):
--   shorter  - shorter label first (IntelliJ PreferShorter)
--   near     - a type of the file's own package (or sibling package) before other packages (proximity)
--   generic  - a method returning a bare type variable (`C apply(C)`) after plain methods (PreferNonGeneric)
-- Each case fails on the baseline ordering (alphabetical inside the group) and passes with the tie-breaker.
vim.o.confirm = false
local lsp = require("lsp")
local C = require("completion")

local src = vim.env.NV4J_FIXTURE .. "/src/main/java/demo/"
local K = vim.lsp.protocol.CompletionItemKind
local function pkg(it)
  local ld = it.labelDetails
  return (ld and ld.description) or it.detail or ""
end
local function is_type(it) return it.kind == K.Class or it.kind == K.Interface or it.kind == K.Enum end
local function label_pkg(l, p) return function(it) return it.label == l and pkg(it) == p end end
local function label_is(l) return function(it) return it.label == l end end
local function first_demo(it) return is_type(it) and pkg(it):find("^demo") ~= nil end

local after_main = "Repo repo = new Repo"
local cases = {
  -- near: in package demo, a project type of the typed prefix beats java.lang/java.awt types of the same relevance.
  { name = "near_C", tag = "near", file = "App.java", after = after_main, line = "        C", expect = first_demo, what = "first demo type", max = 3 },
  { name = "near_S", tag = "near", file = "App.java", after = after_main, line = "        S", expect = first_demo, what = "first demo type", max = 3 },
  { name = "near_Mod", tag = "near", file = "App.java", after = after_main, line = "        Mod", expect = label_pkg("Modern", "demo"), what = "demo.Modern", max = 1 },
  { name = "near_Se", tag = "near", file = "App.java", after = after_main, line = "        Se", expect = label_pkg("SecurityConfig", "demo"), what = "demo.SecurityConfig", max = 1 },
  -- shorter: java.util has 124 types of one relevance; the short, common names come before AbstractSequentialList.
  { name = "shorter_java_util", tag = "shorter", file = "App.java", after = after_main, line = "        java.util.", expect = label_pkg("List", "java.util"), what = "java.util.List", max = 8 },
  { name = "shorter_java_io", tag = "shorter", file = "App.java", after = after_main, line = "        java.io.", expect = label_pkg("File", "java.io"), what = "java.io.File", max = 5 },
  -- generic: apply(C) returns a method type variable; it goes after every plain method of the same tier.
  { name = "generic_last_http", tag = "generic", file = "SecurityConfig.java", after = "public SecurityFilterChain filterChain", line = "        http.",
    expect = label_is("apply"), what = "apply (C apply(C))", after_label = "userDetailsService" },
  -- tuses: a type the project's own sources name (IntelliJ PreferMostUsed, counted by nv4j.usage) before unused types of
  -- the same relevance. NV4J_TUSES_CONTROL=1 switches the type counts off: these cases then FAIL.
  { name = "tuses_Op", tag = "tuses", file = "App.java", after = after_main, line = "        Op", expect = label_pkg("Optional", "java.util"), what = "java.util.Optional", max = 3 },
  { name = "tuses_Resp", tag = "tuses", file = "App.java", after = after_main, line = "        Resp", expect = label_pkg("ResponseEntity", "org.springframework.http"), what = "ResponseEntity", max = 3 },
  { name = "tuses_Ret", tag = "tuses", file = "App.java", after = after_main, line = "        Ret", expect = label_pkg("RetentionPolicy", "java.lang.annotation"), what = "RetentionPolicy", max = 3 },
  { name = "tuses_Val", tag = "tuses", file = "App.java", after = after_main, line = "        Val", expect = label_pkg("Valid", "jakarta.validation"), what = "jakarta.validation.Valid (used as @Valid)", max = 3 },
}
if vim.env.NV4J_TUSES_CONTROL == "1" then vim.g.nv4j_no_type_usage = true end

local fuzzy = C.blink()
lsp.report("13_completion_tiebreak.blink_loaded", fuzzy ~= nil and fuzzy.implementation_type == "rust",
  fuzzy and fuzzy.implementation_type or "blink.cmp not loaded")

for _, cs in ipairs(cases) do
  if cs.tag == "tuses" then vim.wait(15000, function() return require("nv4j.usage").runs > 0 end, 50) end
  local tag = "13_completion_tiebreak." .. cs.name
  local buf = C.open_ready(lsp, src .. cs.file, 120000)
  if not buf then
    lsp.report(tag, false, "jdtls not ready within 120 s")
  elseif not fuzzy then
    lsp.report(tag, false, "blink.cmp unavailable")
  else
    C.scratch(buf, function()
      local at = C.find_line(buf, cs.after) + 1
      vim.api.nvim_buf_set_lines(buf, at, at, false, { cs.line })
      local m, merr = C.menu(buf, at, #cs.line)
      if not m then return lsp.report(tag, false, "menu: " .. tostring(merr)) end
      local rank = C.rank(m.items, cs.expect)
      local ok, detail
      if cs.after_label then
        local other = C.rank(m.items, label_is(cs.after_label))
        ok = rank ~= nil and other ~= nil and rank > other
        detail = ("rank(%s)=%s must be after rank(%s)=%s of %d"):format(cs.what, tostring(rank), cs.after_label, tostring(other), #m.items)
      else
        ok = rank ~= nil and rank <= cs.max
        detail = ("rank(%s)=%s (budget <= %d) of %d"):format(cs.what, tostring(rank), cs.max, #m.items)
      end
      lsp.report(tag, ok, detail .. " [" .. cs.tag .. "] shown=[" .. C.labels(m.items, 8) .. "]")
    end)
  end
end

lsp.finish()
