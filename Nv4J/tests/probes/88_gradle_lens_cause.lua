-- PROBE (not run by tests/run.sh): why the Spring LS answers no codeLens for tests/fixtures/jpa4-gradle.
--  A: the build record (type, buildFile, tasks) in the classpath events the Spring LS receives
--  B: java.project.getClasspaths / listSourcePaths for the fixture: is a build/generated/aotResources source folder listed
-- Output: lines "PROBE ..." on stdout. NV4J_PROBE_DIR (default /tmp/nv4j/probe88) holds the copied fixture.
local lsp = require("lsp")
local SRC = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures/jpa4-gradle"
local TMP = (os.getenv("NV4J_PROBE_DIR") or "/tmp/nv4j/probe88")
vim.fn.delete(TMP, "rf"); vim.fn.mkdir(TMP, "p")
vim.fn.system({ "cp", "-R", SRC .. "/.", TMP })
TMP = vim.uv.fs_realpath(TMP)
local function say(...) io.stdout:write("PROBE ", table.concat(vim.tbl_map(tostring, { ... }), " "), "\n") end
local seen = {}
require("nv4j.spring")._state.event_filter = function(cid, n, param)
  local ok, s = pcall(vim.json.encode, param)
  seen[#seen + 1] = ok and s or vim.inspect(param)
  return nil
end
if os.getenv("NV4J_PROBE_PREMKDIR") == "1" then vim.fn.mkdir(TMP .. "/build/generated/aotResources", "p") end
local FILE = TMP .. "/src/main/java/jpa4/CustomerRepository.java"
local buf = lsp.open(FILE)
local jdtls, why = lsp.wait_ready(buf, 600000)
if not jdtls then say("not ready", why) return lsp.finish() end
vim.wait(90000, function() return #seen > 0 end, 200)
vim.wait(15000, function() return false end, 200)
say("events", #seen)
for i, s in ipairs(seen) do
  say("event", i, "len", #s)
  for _, key in ipairs({ "projectBuild", "build", "type", "buildFile", "tasks" }) do
    for m in s:gmatch('"' .. key .. '":%b{}') do say("  ", m:sub(1, 400)) end
    for m in s:gmatch('"' .. key .. '":"[^"]*"') do say("  ", m:sub(1, 300)) end
    for m in s:gmatch('"' .. key .. '":%b[]') do say("  ", m:sub(1, 400)) end
  end
  for m in s:gmatch('"[^"]*aotResources[^"]*"') do say("  aot-path", m) end
  say("  head", s:sub(1, 600))
end
local r = jdtls:request_sync("workspace/executeCommand", { command = "java.project.getClasspaths",
  arguments = { vim.uri_from_fname(FILE), vim.json.encode({ scope = "runtime" }) } }, 60000, buf)
local txt = r and vim.json.encode(r.result or r.err) or "nil"
say("getClasspaths len", #txt)
for m in txt:gmatch('"[^"]*aotResources[^"]*"') do say("  getClasspaths aot", m) end
local sf = jdtls:request_sync("workspace/executeCommand", { command = "java.project.listSourcePaths", arguments = {} }, 60000, buf)
say("listSourcePaths", sf and vim.json.encode(sf.result or sf.err) or "nil")

-- C: the lens itself (spring-boot client), before any AOT metadata and, if NV4J_PROBE_BUILD=1, after a manual ./gradlew classes aotClasses
vim.wait(60000, function() local c = vim.lsp.get_clients({ bufnr = buf, name = "spring-boot" })[1] return c ~= nil and c.initialized end, 100)
local sc = vim.lsp.get_clients({ bufnr = buf, name = "spring-boot" })[1]
say("spring client", sc and sc.name or "none")
local function lenses(tag)
  if not sc then return end
  local deadline = vim.uv.hrtime() + 90e9
  local got
  repeat
    local r2 = sc:request_sync("textDocument/codeLens", { textDocument = { uri = vim.uri_from_bufnr(buf) } }, 30000, buf)
    got = r2 and r2.result
    if got and #got > 0 then break end
    vim.wait(3000, function() return false end, 100)
  until vim.uv.hrtime() > deadline
  local t = {}
  for _, l in ipairs(got or {}) do t[#t + 1] = (l.range.start.line + 1) .. ":" .. (l.command and l.command.title or "?") .. "/" .. (l.command and l.command.command or "?") end
  say("lenses " .. tag, #t, table.concat(t, " | "))
end
lenses("before-build")
if os.getenv("NV4J_PROBE_BUILD") == "1" then
  local out = vim.fn.system({ "sh", "-c", "cd " .. vim.fn.shellescape(TMP) .. " && ./gradlew --console=plain -q classes aotClasses 2>&1 | tail -5" })
  say("manual gradle", vim.v.shell_error, out)
  say("json exists", vim.uv.fs_stat(TMP .. "/build/generated/aotResources/jpa4/CustomerRepository.json") ~= nil)
  vim.wait(20000, function() return false end, 100)
  lenses("after-build")
  if os.getenv("NV4J_PROBE_UPDATE") == "1" then
    -- does a Gradle re-sync make Buildship list build/generated/aotResources as a source folder?
    jdtls:notify("java/projectConfigurationUpdate", { uri = vim.uri_from_fname(FILE) })
    vim.wait(60000, function() return false end, 200)
    local sp = jdtls:request_sync("workspace/executeCommand", { command = "java.project.listSourcePaths", arguments = {} }, 60000, buf)
    say("listSourcePaths after update", sp and vim.json.encode(sp.result or sp.err) or "nil")
    lenses("after-update")
  end
end
lsp.finish()
