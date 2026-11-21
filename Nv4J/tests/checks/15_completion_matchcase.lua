-- java.completion.matchCase = firstLetter, behind vim.g.nv4j_match_case_first (default off).
-- Run via tests/run.sh. The flag is set here, before the first Java file starts jdt.ls (the settings are read at start).
-- Cases: with the flag a lower-case identifier prefix lists no `A...` type and the list is complete
-- (isIncomplete = false: blink filters the next keystrokes itself, no round trip), `age` stays first;
-- an upper-case prefix still lists types; the setting really is firstLetter on the client.
-- The control is the same check without the flag: `lower_prefix_no_types` and `list_complete` FAIL (runs of
-- the experiment: specs/features/completion-ranking.md).
vim.o.confirm = false
local want = vim.env.NV4J_MATCHCASE_CONTROL ~= "1"
vim.g.nv4j_match_case_first = want and true or nil
local lsp = require("lsp")
local C = require("completion")

local src = vim.env.NV4J_FIXTURE .. "/src/main/java/demo/"
local K = vim.lsp.protocol.CompletionItemKind
local function is_type(it) return it.kind == K.Class or it.kind == K.Interface or it.kind == K.Enum end

local fuzzy = C.blink()
local buf = C.open_ready(lsp, src .. "Person.java", 120000)
if not buf then
  lsp.report("15_completion_matchcase.client_setting", false, "jdtls not ready within 120 s")
  lsp.finish()
  return
end
local client = vim.lsp.get_clients({ bufnr = buf, name = "jdtls" })[1]
local mc = vim.tbl_get(client.config.settings or {}, "java", "completion", "matchCase")
lsp.report("15_completion_matchcase.client_setting", mc == "firstLetter", "matchCase=" .. tostring(mc))

local function menu(line, back)
  local out
  C.scratch(buf, function()
    local at = C.find_line(buf, "public String getName") + 1
    vim.api.nvim_buf_set_lines(buf, at, at, false, { line })
    local ms, last, raw = {}, nil, nil
    for i = 1, 33 do
      vim.api.nvim_buf_set_lines(buf, at, at + 1, false, { line })
      local m = C.menu(buf, at, #line - (back or 0))
      if m then last = m.items; if i > 3 then ms[#ms + 1] = m.ms end end
    end
    raw = C.raw(buf, at, #line)
    out = { items = last or {}, p95 = C.pct(ms, 95), incomplete = raw and raw.isIncomplete, count = raw and #raw.items or 0 }
  end)
  return out
end

local r = menu("        a")
local types = 0
for _, it in ipairs(r.items) do if is_type(it) then types = types + 1 end end
local age = C.rank(r.items, function(it) return it.label == "age" end)
lsp.report("15_completion_matchcase.lower_prefix_no_types", types == 0 and age == 1,
  ("prefix a: %d types of %d shown, rank(age)=%s, server items=%d, menu_p95=%.0f ms [%s]"):format(types, #r.items, tostring(age), r.count, r.p95, C.labels(r.items, 6)))
lsp.report("15_completion_matchcase.list_complete", r.incomplete == false,
  ("isIncomplete=%s (without the flag: true, 203 items, every keystroke is a request)"):format(tostring(r.incomplete)))

local u = menu("        A")
local utypes = 0
for _, it in ipairs(u.items) do if is_type(it) then utypes = utypes + 1 end end
lsp.report("15_completion_matchcase.upper_prefix_types", utypes > 0,
  ("prefix A: %d types of %d shown, server items=%d [%s]"):format(utypes, #u.items, u.count, C.labels(u.items, 5)))

lsp.finish()
