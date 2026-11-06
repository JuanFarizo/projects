-- nv4j/aot.lua, the client commands behind the Spring Data AOT lens: command line only (no build runs, no jdt.ls).
--  maven_wrapper   a mvnw in the pom folder (or above) is used before `mvn`; `-q` and the goals split on spaces
--  gradle_wrapper  gradlew likewise, no -q
--  no_tool         no wrapper and no tool on PATH: nil plus a reason naming the folder
--  empty_goal      an empty goal string is refused
--  registered      setup() puts maven.goal.custom and gradle.runBuild in vim.lsp.commands
--  bad_args        run() with nonsense arguments does not start anything (false), no error
local lsp = require("lsp")
local aot = require("nv4j.aot")
local P = "83_aot_cmd."
local TMP = "/tmp/nv4j/aot-cmd-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
local function touch(p, exe)
  vim.fn.mkdir(vim.fs.dirname(p), "p")
  io.open(p, "w"):close()
  if exe then vim.uv.fs_chmod(p, tonumber("755", 8)) end
end
touch(TMP .. "/a/pom.xml"); touch(TMP .. "/a/mvnw", true)
touch(TMP .. "/m/app/pom.xml"); touch(TMP .. "/m/mvnw", true)
touch(TMP .. "/g/build.gradle"); touch(TMP .. "/g/gradlew", true)
touch(TMP .. "/n/pom.xml")

local cmd, cwd = aot.command("maven", TMP .. "/a/pom.xml", "compile org.springframework.boot:spring-boot-maven-plugin:process-aot")
lsp.report(P .. "maven_wrapper", cmd and cmd[1] == TMP .. "/a/mvnw" and cmd[2] == "-q" and cmd[3] == "compile" and cmd[4]:find("process%-aot") and cwd == TMP .. "/a", vim.inspect(cmd))
local up = aot.command("maven", TMP .. "/m/app/pom.xml", "process-aot")
lsp.report(P .. "maven_wrapper_above", up and up[1] == TMP .. "/m/mvnw", vim.inspect(up))
local g = aot.command("gradle", TMP .. "/g/build.gradle", "classes aotClasses")
lsp.report(P .. "gradle_wrapper", g and g[1] == TMP .. "/g/gradlew" and g[2] == "classes" and g[3] == "aotClasses" and #g == 3, vim.inspect(g))
-- no wrapper: PATH without mvn
local old = vim.env.PATH
vim.env.PATH = "/nonexistent"
local none, reason = aot.command("maven", TMP .. "/n/pom.xml", "compile")
vim.env.PATH = old
lsp.report(P .. "no_tool", none == nil and tostring(reason):find(TMP .. "/n", 1, true) ~= nil, tostring(reason))
local e1, why = aot.command("maven", TMP .. "/a/pom.xml", "  ")
lsp.report(P .. "empty_goal", e1 == nil, tostring(why))
aot.setup()
lsp.report(P .. "registered", type(vim.lsp.commands["maven.goal.custom"]) == "function" and type(vim.lsp.commands["gradle.runBuild"]) == "function", "both")
local started = aot.run("maven", { 1, 2 })
local started2 = aot.run("maven", nil)
lsp.report(P .. "bad_args", started == false and started2 == false, ("%s %s"):format(tostring(started), tostring(started2)))
vim.fn.delete(TMP, "rf")
lsp.finish()
