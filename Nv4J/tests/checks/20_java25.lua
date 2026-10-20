-- JDK correctness. Runs with JAVA_HOME unset and a JDK 21 `java` first on PATH (tests/run.sh):
--  case 1: fixture (release 25, Java 25 syntax) -> zero errors, JavaSE-25 / release 25 in jdtls,
--          and jdtls itself runs on a JDK >= 21 chosen by nv4j.jdk (not PATH's java).
--  case 2: temp minimal Maven project (release 21) -> jdtls reports release 21 and a JavaSE-21 JRE,
--          zero errors (proves per-project runtime selection).
local lsp = require("lsp")

local function errors(buf)
  local errs = vim.tbl_filter(function(d) return d.severity == vim.diagnostic.severity.ERROR end, lsp.diagnostics(buf))
  local msgs = {}
  for _, d in ipairs(errs) do msgs[#msgs + 1] = ("L%d %s"):format(d.lnum + 1, d.message) end
  return #errs, table.concat(msgs, "; ")
end

local keys = {
  "org.eclipse.jdt.core.compiler.source",
  "org.eclipse.jdt.core.compiler.compliance",
  "org.eclipse.jdt.core.compiler.codegen.targetPlatform",
  "org.eclipse.jdt.ls.core.vm.location",
}

local function check_case(tag, file, project_dir, release, buf)
  local client = lsp.wait_ready(buf, 120000)
  lsp.report(tag .. ".attached", client ~= nil, client and "jdtls ready" or "jdtls not ready")
  if not client then return end
  local n, msgs = errors(buf)
  lsp.report(tag .. ".no_errors", n == 0, n .. " errors " .. msgs)
  local res = client:request_sync("workspace/executeCommand", {
    command = "java.project.getSettings",
    arguments = { vim.uri_from_fname(project_dir), keys },
  }, 20000, buf)
  local s = res and res.result or {}
  local r = tostring(release)
  lsp.report(tag .. ".release", s[keys[1]] == r and s[keys[2]] == r and s[keys[3]] == r,
    ("source=%s compliance=%s target=%s (want %s)"):format(tostring(s[keys[1]]), tostring(s[keys[2]]), tostring(s[keys[3]]), r))
  local vm = s[keys[4]]
  lsp.report(tag .. ".project_jre", type(vm) == "string" and vm:find("[%-/]" .. r .. "[%.%-]") ~= nil,
    "project vm.location=" .. tostring(vm))
end

-- case 1
local fixture = vim.env.NV4J_FIXTURE
local buf1 = lsp.open(fixture .. "/src/main/java/demo/Modern.java")
check_case("20_java25", nil, fixture, 25, buf1)

-- JVM jdtls itself runs on: first word of its process command line.
local jvm
for _, l in ipairs(vim.fn.systemlist({ "ps", "-axo", "command=" })) do
  local exe = l:match("^(%S+/bin/java) ")
  if exe and l:find("org.eclipse.equinox.launcher", 1, true) and l:find("/tmp/nv4j/jdtls-data/", 1, true) then
    jvm = exe
    break
  end
end
local expect = require("nv4j.jdk").server_home()
lsp.report("20_java25.server_jvm", jvm ~= nil and jvm == expect .. "/bin/java", "jdtls runs on " .. tostring(jvm) .. " (expected " .. expect .. ")")
local jv = jvm and vim.fn.system({ jvm, "-version" }) or ""
lsp.report("20_java25.server_not_path_java", jvm ~= nil and not jv:find('version "21%.') , "server java: " .. (jv:match('version "[^"]+"') or "?"))

-- case 2: release 21 project
local dir = "/tmp/nv4j/proj21"
vim.fn.delete(dir, "rf")
vim.fn.mkdir(dir .. "/src/main/java/p21", "p")
vim.fn.writefile({
  '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>',
  "<groupId>p21</groupId><artifactId>p21</artifactId><version>1</version>",
  "<properties><maven.compiler.release>21</maven.compiler.release>",
  "<project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties></project>",
}, dir .. "/pom.xml")
vim.fn.writefile({
  "package p21;",
  "sealed interface S permits A, B {}",
  "record A(int x) implements S {}",
  "record B(String y) implements S {}",
  "class Hello {",
  "    static String f(S s) {",
  "        return switch (s) { case A a -> \"a\" + a.x(); case B b -> b.y(); };",
  "    }",
  "}",
}, dir .. "/src/main/java/p21/Hello.java")
local buf2 = lsp.open(dir .. "/src/main/java/p21/Hello.java")
check_case("20_java21", nil, dir, 21, buf2)
lsp.finish()
