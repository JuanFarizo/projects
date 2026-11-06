-- PROBE, not run by tests/run.sh (it fails: see specs/features/jpa.md "Gradle live"). Move to tests/checks when the Spring LS shows the lens for the Gradle fixture.
-- Spring Data AOT lens on a GRADLE Boot 4 project, live (tests/fixtures/jpa4-gradle copied to /tmp). HEAVY: real jdt.ls + Gradle import.
--  no_aot_lens   before any metadata the lens over findByEmail runs gradle.runBuild (the Spring LS leaves the build to the client)
--  aot_command   that command through nv4j.aot (gradlew classes aotClasses): exit 0, build/generated/aotResources/.../CustomerRepository.json
--  lens_query    afterwards the lens carries the generated query and "Turn into @Query"
--  add_query     "Add `@Query`" on the derived method inserts the generated query
local lsp = require("lsp")
local P = "87_aot_gradle_live."
local SRC = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures/jpa4-gradle"
local TMP = "/tmp/nv4j/jpa4-gradle-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
vim.fn.system({ "cp", "-R", SRC .. "/.", TMP })
vim.fn.delete(TMP .. "/build", "rf")
vim.fn.delete(TMP .. "/.gradle", "rf")
TMP = vim.uv.fs_realpath(TMP)
local FILE = TMP .. "/src/main/java/jpa4/CustomerRepository.java"
local JSON = TMP .. "/build/generated/aotResources/jpa4/CustomerRepository.json"

local buf = lsp.open(FILE)
local jdtls, why = lsp.wait_ready(buf, 600000)
if not jdtls then lsp.report(P .. "ready", false, why) return lsp.finish() end
vim.wait(60000, function() local c = vim.lsp.get_clients({ bufnr = buf, name = "spring-boot" })[1] return c ~= nil and c.initialized end, 100)
local c = vim.lsp.get_clients({ bufnr = buf, name = "spring-boot" })[1]
if not c then lsp.report(P .. "client", false, "no spring-boot client") return lsp.finish() end
local uri = vim.uri_from_bufnr(buf)
local function req(method, params)
  local r = c:request_sync(method, params, 30000, buf)
  if not r or r.err then return nil end
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
  -- own deadline loop with a real sleep per round: a reply that returns at once made vim.wait spin without ever timing out
  local deadline, got = vim.uv.hrtime() + (timeout_ms or 60000) * 1e6, nil
  while vim.uv.hrtime() < deadline do
    got = req("textDocument/codeLens", { textDocument = { uri = uri } })
    if got and pred(got) then break end
    vim.wait(2000, function() return false end, 100)
  end
  return got
end
local r_email = line_of("findByEmail(")

local l0 = lenses_with(function(l) return #titles_at(l, r_email) > 0 end, 180000)
local cmd0
for _, l in ipairs(l0 or {}) do if l.range.start.line == r_email and l.command then cmd0 = l.command end end
lsp.report(P .. "no_aot_lens", cmd0 ~= nil and cmd0.command == "gradle.runBuild" and not vim.uv.fs_stat(JSON),
  cmd0 and (cmd0.title .. " / " .. cmd0.command .. " " .. vim.inspect(cmd0.arguments):gsub("%s+", " "):sub(1, 300)) or "no lens")

local code
local aot = require("nv4j.aot")
local orig_run = aot.run
aot.run = function(tool, args, on_done) return orig_run(tool, args, function(x) code = x if on_done then on_done(x) end end) end
if cmd0 then c:exec_cmd(cmd0, { bufnr = buf }) end
vim.wait(900000, function() return code ~= nil end, 500)
lsp.report(P .. "aot_command", code == 0 and vim.uv.fs_stat(JSON) ~= nil, ("exit %s, json %s"):format(tostring(code), tostring(vim.uv.fs_stat(JSON) ~= nil)))

local l1 = lenses_with(function(l) return has(titles_at(l, r_email), "SELECT") end, 120000)
local te = titles_at(l1, r_email)
lsp.report(P .. "lens_query", has(te, "SELECT c FROM Customer c WHERE c.email = :email") and has(te, "Turn into"), table.concat(te, ", "))

local ae = req("textDocument/codeAction", { textDocument = { uri = uri },
  range = { start = { line = r_email, character = 24 }, ["end"] = { line = r_email, character = 24 } }, context = { diagnostics = {} } }) or {}
local applied = false
local orig_apply = c.handlers["workspace/applyEdit"] or vim.lsp.handlers["workspace/applyEdit"]
c.handlers["workspace/applyEdit"] = function(err, params, ctx, ...) applied = true return orig_apply(err, params, ctx, ...) end
if ae[1] and ae[1].command then c:exec_cmd(ae[1].command, { bufnr = buf }) end
vim.wait(20000, function() return applied end, 200)
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
lsp.report(P .. "add_query", text:find('@Query("SELECT c FROM Customer c WHERE c.email = :email")', 1, true) ~= nil,
  applied and "edit applied" or ("no edit; actions " .. #ae))
lsp.finish()
