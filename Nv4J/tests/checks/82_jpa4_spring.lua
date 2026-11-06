-- Spring Data support of the Spring LS in Nv4J, on the Boot 4 fixture (tests/fixtures/jpa4 copied to /tmp; edits in memory only).
-- Observed with the real jdt.ls + Spring LS (2026-11-06 probe), now asserted. HEAVY: run when the machine is free.
--  no_aot_lens      before any AOT metadata the lens over a query method is "Show AOT-generated Implementation, ..." with the VS Code
--                   command maven.goal.custom (the Spring LS leaves the build to the client)
--  aot_command      running that lens command (Nv4J's nv4j.aot handler) builds the metadata: exit 0, the JSON exists
--  lens_query       afterwards the lens over findByEmail carries the generated query `SELECT c FROM Customer c WHERE c.email = :email`
--                   and "Turn into @Query"; the @Query method has "Go To Implementation" but no "Turn into @Query"
--  add_query_offered "Add `@Query`" on a derived method; none on the @Query method
--  add_query_applied executing it inserts `@Query("SELECT c FROM Customer c WHERE c.email = :email")` above the method
--  findby_completion `findBy` offers the entity's properties (Email, FullName, ...) and the OrderBy/And keywords
--  jpql_error       a planted `@Query("SELEC ...")` gets an ERROR diagnostic from the vscode-spring-boot source (HQL syntax)
--  semantic_tokens  the Spring LS answers textDocument/semanticTokens/full for the repository
local lsp = require("lsp")
local P = "82_jpa4_spring."
local SRC = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures/jpa4"
local TMP = "/tmp/nv4j/jpa4-spring-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
vim.fn.system({ "cp", "-R", SRC .. "/.", TMP })
vim.fn.delete(TMP .. "/target", "rf")
TMP = vim.uv.fs_realpath(TMP)
local FILE = TMP .. "/src/main/java/jpa4/CustomerRepository.java"
local JSON = TMP .. "/target/spring-aot/main/resources/jpa4/CustomerRepository.json"

local buf = lsp.open(FILE)
local jdtls, why = lsp.wait_ready(buf, 300000)
if not jdtls then lsp.report(P .. "ready", false, why) return lsp.finish() end
local function spring() return vim.lsp.get_clients({ bufnr = buf, name = "spring-boot" })[1] end
vim.wait(60000, function() local c = spring() return c ~= nil and c.initialized end, 100)
local c = spring()
if not c then lsp.report(P .. "client", false, "no spring-boot client") return lsp.finish() end
local uri = vim.uri_from_bufnr(buf)
local function req(method, params)
  local r = c:request_sync(method, params, 30000, buf)
  if not r or r.err then return nil, r and vim.inspect(r.err) or "timeout" end
  return r.result
end
local function line_of(pat)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do if l:find(pat, 1, true) then return i - 1 end end
end
local function titles_at(lenses, row)
  local t = {}
  for _, l in ipairs(lenses or {}) do if l.range.start.line == row and l.command then t[#t + 1] = l.command.title end end
  return t
end
local function has(list, pat) for _, t in ipairs(list) do if t:find(pat, 1, true) then return true end end return false end
local function lenses_with(pred, timeout_ms)
  local got
  vim.wait(timeout_ms or 30000, function()
    got = req("textDocument/codeLens", { textDocument = { uri = uri } })
    return got and pred(got)
  end, 1500)
  return got
end

local r_email = line_of("findByEmail(")
local r_query = line_of('@Query("select') -- the lens sits on the first line of the method, its annotation

-- 1. no AOT metadata yet: the lens only offers to generate it, through the client
local l0 = lenses_with(function(l) return #titles_at(l, r_email) > 0 end)
local cmd0
for _, l in ipairs(l0 or {}) do if l.range.start.line == r_email and l.command then cmd0 = l.command end end
lsp.report(P .. "no_aot_lens", cmd0 ~= nil and cmd0.command == "maven.goal.custom" and not vim.uv.fs_stat(JSON),
  cmd0 and (cmd0.title .. " / " .. cmd0.command) or "no lens")

-- 2. run it like a click: Neovim's command table -> nv4j.aot -> mvn process-aot
local code
local aot = require("nv4j.aot")
local orig_run = aot.run
aot.run = function(tool, args, on_done) return orig_run(tool, args, function(x) code = x if on_done then on_done(x) end end) end
if cmd0 then c:exec_cmd(cmd0, { bufnr = buf }) end
vim.wait(600000, function() return code ~= nil end, 500)
lsp.report(P .. "aot_command", code == 0 and vim.uv.fs_stat(JSON) ~= nil, ("exit %s, json %s"):format(tostring(code), tostring(vim.uv.fs_stat(JSON) ~= nil)))

-- 3. the lens now has the query
local l1 = lenses_with(function(l) return has(titles_at(l, r_email), "SELECT") and #titles_at(l, r_query) > 0 end, 60000)
local te, tq = titles_at(l1, r_email), titles_at(l1, r_query)
lsp.report(P .. "lens_query", has(te, "SELECT c FROM Customer c WHERE c.email = :email") and has(te, "Turn into") and has(tq, "Go To Implementation") and not has(tq, "Turn into"),
  ("findByEmail: %s | activeCustomers(row %d): %s | all rows: %s"):format(table.concat(te, ", "), r_query, table.concat(tq, ", "), vim.inspect(vim.tbl_map(function(l) return l.range.start.line .. ":" .. (l.command and l.command.title or "?"):sub(1, 18) end, l1 or {})):gsub("%s+", " ")))

-- 4. code actions
local function actions(row)
  local a = req("textDocument/codeAction", { textDocument = { uri = uri },
    range = { start = { line = row, character = 24 }, ["end"] = { line = row, character = 24 } }, context = { diagnostics = {} } })
  return a or {}
end
local ae, aq = actions(r_email), actions(r_query)
lsp.report(P .. "add_query_offered", #ae == 1 and ae[1].title == "Add `@Query`" and #aq == 0, ("derived: %d (%s), @Query method: %d"):format(#ae, ae[1] and ae[1].title or "-", #aq))

local applied = false
local orig_apply = c.handlers["workspace/applyEdit"] or vim.lsp.handlers["workspace/applyEdit"]
c.handlers["workspace/applyEdit"] = function(err, params, ctx, ...) applied = true return orig_apply(err, params, ctx, ...) end
if ae[1] and ae[1].command then c:exec_cmd(ae[1].command, { bufnr = buf }) end
vim.wait(20000, function() return applied end, 200)
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
lsp.report(P .. "add_query_applied", text:find('@Query("SELECT c FROM Customer c WHERE c.email = :email")\n    Optional<Customer> findByEmail', 1, true) ~= nil,
  applied and "edit applied" or "no workspace/applyEdit from the server")

-- 5. completion of a derived name
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
table.insert(lines, #lines, "    List<Customer> findBy")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.wait(3000, function() return false end, 200)
local comp = req("textDocument/completion", { textDocument = { uri = uri }, position = { line = #lines - 2, character = #"    List<Customer> findBy" } })
local labs = {}
for _, it in ipairs(comp and (comp.items or comp) or {}) do labs[it.label] = true end
lsp.report(P .. "findby_completion", labs.Email and labs.FullName and labs.OrderBy and labs.And, vim.inspect(vim.tbl_keys(labs)):gsub("%s+", " "):sub(1, 300))

-- 6. JPQL error
lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
lines[#lines - 1] = '    @Query("SELEC c FROM Customer c WHERE") List<Customer> broken();'
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
local bad
vim.wait(30000, function()
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    if d.source == "vscode-spring-boot" and d.severity == vim.diagnostic.severity.ERROR then bad = d end
  end
  return bad ~= nil
end, 500)
lsp.report(P .. "jpql_error", bad ~= nil, bad and bad.message:sub(1, 100) or "no diagnostic")

-- 7. semantic tokens
local st = req("textDocument/semanticTokens/full", { textDocument = { uri = uri } })
lsp.report(P .. "semantic_tokens", st ~= nil and #(st.data or {}) > 0, st and (#st.data .. " ints") or "none")

vim.bo[buf].modified = false
vim.fn.delete(TMP, "rf")
lsp.finish()
