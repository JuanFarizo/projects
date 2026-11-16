-- Live: nvim STARTED with JAVA_HOME = a real JDK 23 (tests/run.sh sets it for 21_* checks; SDKMAN `sdk use java 23.0.2-amzn`
-- does this for a Java 23 project) must not make it jdt.ls's JVM: jdt.ls needs >= nv4j.jdk.SERVER_MIN_JAVA (25 for Mason jdtls 1.63.0), else it
-- exits with code 13. A temp Maven project (release 21, under /tmp/nv4j, never a real project): jdt.ls attaches and is
-- initialized, and the server process's java is a JDK >= 25, not JAVA_HOME's. Pure rules: 20_java25 case 0.
-- Control: tests/lib/control_20.sh (the old ">= 21" rule makes this case fail).
local lsp = require("lsp")
local J = require("nv4j.jdk")
local MIN = 25 -- the measured need of Mason jdtls 1.63.0, literal on purpose: the check must not follow the constant it tests
local jh = vim.env.JAVA_HOME
local jd = jh and jh ~= "" and J.describe(jh)
if not jd or jd.major >= MIN then
  print("SKIP 21_server_jdk.java_home_23_live no JAVA_HOME below " .. MIN .. " at start (run through tests/run.sh with a JDK 23 installed): JAVA_HOME=" .. tostring(jh))
  return lsp.finish()
end
local d3 = "/tmp/nv4j/projj23"
vim.fn.delete(d3, "rf")
vim.fn.mkdir(d3 .. "/src/main/java/pj", "p")
vim.fn.writefile({
  '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>',
  "<groupId>pj</groupId><artifactId>projj23</artifactId><version>1</version>",
  "<properties><maven.compiler.release>21</maven.compiler.release>",
  "<project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties></project>",
}, d3 .. "/pom.xml")
vim.fn.writefile({ "package pj;", "class Hi { String f() { return \"x\"; } }" }, d3 .. "/src/main/java/pj/Hi.java")
local b3 = lsp.open(d3 .. "/src/main/java/pj/Hi.java")
local c3 = lsp.wait_ready(b3, 120000)
local jvm3
for _, l in ipairs(vim.fn.systemlist({ "ps", "-axo", "command=" })) do
  local exe = l:match("^(%S+/bin/java) ")
  if exe and l:find("org.eclipse.equinox.launcher", 1, true) and l:find(require("nv4j.paths").jdtls_data .. "/projj23", 1, true) then jvm3 = exe break end
end
local info = jvm3 and J.describe(vim.fn.fnamemodify(jvm3, ":h:h"))
lsp.report("21_server_jdk.java_home_23_live", c3 ~= nil and info ~= nil and info.major >= MIN and jvm3:find(jh, 1, true) == nil,
  ("JAVA_HOME=%s, jdtls ready=%s, server java=%s (%s)"):format(jh, tostring(c3 ~= nil), tostring(jvm3), info and info.version or "?"))
lsp.finish()
