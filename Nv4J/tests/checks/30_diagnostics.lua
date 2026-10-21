-- P1 diagnostics. Run via tests/run.sh. Spec: specs/features/diagnostics-imports-actions.md.
-- Planted sources (tests/fixtures/planted) replace App.java's buffer in memory; every case is timed
-- from the edit until the diagnostics are in vim.diagnostic (what the user sees), budget 3 s.
--  unused   : unused import / local / private field / private method -> warnings (Unnecessary tag)
--  errors   : type error + undefined method -> errors
--  unique   : no duplicated diagnostic, one diagnostic namespace, one inline renderer
--  typing   : a burst of edits ending in valid code -> no stale error from an earlier keystroke
--  cleared  : fixing the code clears the diagnostics
--  java25   : Java 25 code (module import, flexible constructor, `_`, record patterns, Markdown
--             doc comments) -> no diagnostic at all
--  maven    : temp project /tmp/nv4j/pomcase: malformed pom.xml -> error on pom.xml AND a visible
--             notification; fixed pom -> errors gone and no "may need reload" leftover (pom changes
--             are applied automatically); missing artifact -> error + notification.
-- Timings: /tmp/nv4j/logs/latency.jsonl (diag_*, pom_*).
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local S = vim.diagnostic.severity
local BUDGET_MS = 3000
local P = "30_diagnostics."

local notes = E.capture_notify()
local buf = lsp.open(vim.env.NV4J_FIXTURE .. "/src/main/java/demo/App.java")
local client = lsp.wait_ready(buf, 120000)
lsp.report(P .. "attached", client ~= nil, client and "jdtls ready" or "jdtls not ready")
if not client then return lsp.finish() end
vim.wait(1000) -- let the first publish settle
local orig = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

local function timed(case, lines, pred, detail_f)
  local t0 = E.set(buf, lines)
  local ok, ms, d = E.wait_diags(buf, pred, 10000, t0)
  E.log("diag_" .. case, ms, #d)
  lsp.report(P .. case, ok and ms <= BUDGET_MS,
    ("%.0f ms (budget %d) %s"):format(ms, BUDGET_MS, detail_f and detail_f(d) or E.fmt(d)))
  return ok, d
end

local function unique(case, d)
  local seen, dup = {}, nil
  local ns = {}
  for _, x in ipairs(d) do
    local k = ("%d:%d:%s"):format(x.lnum, x.col, x.message)
    if seen[k] then dup = k end
    seen[k] = true
    ns[x.namespace] = true
  end
  local names = vim.tbl_map(function(n) return vim.diagnostic.get_namespace(n).name end, vim.tbl_keys(ns))
  lsp.report(P .. case .. "_unique", dup == nil and #names <= 1,
    ("duplicate=%s namespaces=%s"):format(tostring(dup), table.concat(names, ",")))
end

local ok_all, err = pcall(function()
  -- unused: all four warnings, each a Warning with the Unnecessary tag (faded by Neovim)
  local want = {
    "import java.util.Map is never used",
    "local variable unused is not used",
    "field App.neverRead is not used",
    "method helper%(%) from the type App is never used",
  }
  local function all_unused(d)
    for _, w in ipairs(want) do
      local x = E.has(d, S.WARN, w)
      if not x or not (x._tags and x._tags.unnecessary) then return false end
    end
    return E.count(d, S.ERROR) == 0
  end
  local _, d = timed("unused_warnings", E.planted("unused.java.txt"), all_unused)
  unique("unused", d)

  -- errors
  local _, d2 = timed("errors", E.planted("errors.java.txt"), function(x)
    return E.has(x, S.ERROR, "Type mismatch: cannot convert from int to String") ~= nil
      and E.has(x, S.ERROR, "doesNotExist%(%) is undefined for the type Repo") ~= nil
  end)
  unique("errors", d2)

  -- one inline renderer: tiny-inline-diagnostic draws, built-in virtual text/lines stay off
  local cfg = vim.diagnostic.config()
  local tiny = package.loaded["tiny-inline-diagnostic"] ~= nil
  lsp.report(P .. "one_renderer", tiny and not cfg.virtual_text and not cfg.virtual_lines,
    ("tiny-inline loaded=%s virtual_text=%s virtual_lines=%s (update_in_insert=%s severity_sort=%s)"):format(tostring(tiny),
      vim.inspect(cfg.virtual_text), vim.inspect(cfg.virtual_lines), tostring(cfg.update_in_insert), tostring(cfg.severity_sort)))

  -- cleared: back to the original (valid) file
  timed("cleared", orig, function(x) return #x == 0 end)

  -- typing: keystroke-sized edits 80 ms apart; the intermediate states do not compile, the last one
  -- compiles with exactly one warning (unused local), so settling needs a fresh publish
  local at = E.line_of(buf, "Repo repo = new Repo") + 1
  local steps = { "        int t", "        int typed", "        int typed =", "        int typed = 1", "        int typed = 1;" }
  local t0
  for i, s in ipairs(steps) do
    vim.api.nvim_buf_set_lines(buf, at, i == 1 and at or at + 1, false, { s })
    t0 = E.now()
    vim.wait(80)
  end
  -- Intermediate states may be published on the way (a request such as semantic tokens flushes
  -- didChange early, and jdt.ls validates what it got). What matters: the shown diagnostics settle
  -- on the final text within the budget and stay there. Watch for 5 s, note the last change.
  local last_change, last_set, seen = t0, nil, {}
  vim.wait(5000, function()
    local cur = E.fmt(vim.diagnostic.get(buf))
    if cur ~= last_set then
      if last_set ~= nil then last_change = E.now() end
      last_set = cur
      if cur ~= "" then seen[#seen + 1] = cur end
    end
    return false
  end, 5)
  local final = vim.diagnostic.get(buf)
  local ms = last_change - t0
  local right = #final == 1 and E.has(final, S.WARN, "local variable typed is not used") ~= nil
  E.log("diag_typing", ms, #final)
  lsp.report(P .. "typing_no_stale", right and ms <= BUDGET_MS,
    ("settled %.0f ms after the last keystroke (budget %d) on [%s]; intermediate states shown: %d"):format(
      ms, BUDGET_MS, E.fmt(final), math.max(0, #seen - 1)))

  -- java25: from a state with an error, so a fresh publish is needed to reach 0
  E.set(buf, E.planted("errors.java.txt"))
  E.wait_diags(buf, function(x) return E.count(x, S.ERROR) > 0 end, 10000)
  local _, d4 = timed("java25_no_false_diagnostics", E.planted("java25.java.txt"), function(x) return #x == 0 end)
  local stays25, bad25 = E.stays(buf, function(x) return #x == 0 end, 1500)
  lsp.report(P .. "java25_stays_clean", stays25, bad25 and E.fmt(bad25) or "0 diagnostics for 1.5 s")
end)
E.restore(buf, orig)
if not ok_all then lsp.report(P .. "in_memory_cases", false, "error: " .. tostring(err)) end

-- maven: a temp project, pom.xml rewritten on disk like a user saving it
local dir = "/tmp/nv4j/pomcase"
local function pom(deps)
  return {
    '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>',
    "<groupId>pomcase</groupId><artifactId>pomcase</artifactId><version>1</version>",
    "<properties><maven.compiler.release>25</maven.compiler.release>",
    "<project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>",
    "<dependencies>" .. (deps or "") .. "</dependencies>",
    "</project>",
  }
end
vim.fn.delete(dir, "rf")
vim.fn.mkdir(dir .. "/src/main/java/pc", "p")
vim.fn.writefile(pom(), dir .. "/pom.xml")
vim.fn.writefile({ "package pc;", "public class Hello {", "    static String hi() { return \"hi\"; }", "}" },
  dir .. "/src/main/java/pc/Hello.java")
local ok_mvn, err_mvn = pcall(function()
  local jbuf = lsp.open(dir .. "/src/main/java/pc/Hello.java")
  local c2 = lsp.wait_ready(jbuf, 120000)
  lsp.report(P .. "maven_attached", c2 ~= nil, c2 and "jdtls ready (pomcase)" or "jdtls not ready")
  if not c2 then return end
  vim.wait(1500)
  local pbuf = vim.uri_to_bufnr(vim.uri_from_fname(dir .. "/pom.xml"))
  local function pom_case(case, lines, pred, note_pat)
    local n0 = #notes
    local t0 = E.now()
    vim.fn.writefile(lines, dir .. "/pom.xml")
    local ok, ms, d = E.wait_diags(pbuf, pred, 30000, t0)
    local noted
    if note_pat then
      vim.wait(3000, function()
        for i = n0 + 1, #notes do
          if notes[i].msg:find("pom.xml", 1, true) and notes[i].msg:find(note_pat) then noted = notes[i] return true end
        end
      end, 20)
    end
    E.log("pom_" .. case, ms, #d)
    lsp.report(P .. "maven_" .. case, ok and (note_pat == nil or noted ~= nil),
      ("%.0f ms; pom.xml: %s; notified=%s"):format(ms, E.fmt(d), noted and noted.msg:gsub("\n", " "):sub(1, 120) or "no"))
  end
  pom_case("malformed", { "<project><modelVersion>4.0.0</modelVersion><groupId>pc" }, function(d)
    return E.has(d, S.ERROR, "Non%-readable POM") ~= nil or E.has(d, S.ERROR, "Non%-parseable POM") ~= nil
  end, "POM")
  pom_case("fixed", pom(), function(d) return #d == 0 end)
  -- interactive mode would leave an Information diagnostic asking for a reload
  local leftover = E.stays(pbuf, function(d) return E.has(d, nil, "may need reload") == nil end, 2000)
  lsp.report(P .. "maven_auto_update", leftover, leftover and "no 'may need reload' diagnostic" or E.fmt(vim.diagnostic.get(pbuf)))
  pom_case("missing_artifact",
    pom("<dependency><groupId>org.nv4j.nope</groupId><artifactId>nope</artifactId><version>9.9.9</version></dependency>"),
    function(d) return E.has(d, S.ERROR, "Missing artifact org.nv4j.nope:nope") ~= nil end, "Missing artifact")
  vim.fn.writefile(pom(), dir .. "/pom.xml")
end)
if not ok_mvn then lsp.report(P .. "maven", false, "error: " .. tostring(err_mvn)) end
lsp.finish()
