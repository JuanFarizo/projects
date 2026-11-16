-- JDK correctness. Runs with JAVA_HOME unset and a JDK 21 `java` first on PATH (tests/run.sh):
--  case 1: fixture (release 25, Java 25 syntax) -> zero errors, JavaSE-25 / release 25 in jdtls,
--          and jdtls itself runs on a JDK >= 25 chosen by nv4j.jdk (not PATH's java).
--  case 0 (pure): jdt.ls JVM must be >= nv4j.jdk.SERVER_MIN_JAVA (25), JAVA_HOME 23/24 ignored, error text, health ERROR (NV4J_JDK_ROOT stubs).
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

-- case 0 (pure, NV4J_JDK_ROOT stubs, nothing on this machine matters): the JDK jdtls runs on must be >= SERVER_MIN_JAVA
-- (25 for Mason jdtls 1.63.0), whatever JAVA_HOME says; the project's JDK is a separate choice.
--  min_const / java_home_23 / java_home_24 : JAVA_HOME 23 or 24 is skipped, the newest >= 25 is used.
--  java_home_25 : JAVA_HOME 25 is kept even when a newer JDK exists.   no_25 : only 21 and 23 installed -> error text
--  (needs JDK >= 25, lists what is installed, project JDK can stay, `sdk install java 25-amzn`).   health_error : :Nv4JHealth ERROR.
do
  local J = require("nv4j.jdk")
  local root = "/tmp/nv4j/j20-" .. vim.fn.getpid()
  local function jdk(base, name, ver)
    vim.fn.mkdir(base .. "/" .. name .. "/bin", "p")
    vim.fn.writefile({ "#!/bin/sh" }, base .. "/" .. name .. "/bin/java")
    vim.fn.writefile({ 'JAVA_VERSION="' .. ver .. '"' }, base .. "/" .. name .. "/release")
    return base .. "/" .. name
  end
  vim.fn.delete(root, "rf")
  local full, poor = root .. "/full", root .. "/poor"
  local h21, h23, h24 = jdk(full, "21.0.7-x", "21.0.7"), jdk(full, "23.0.2-x", "23.0.2"), jdk(full, "24.0.2-x", "24.0.2")
  local h25, h26 = jdk(full, "25.0.1-x", "25.0.1"), jdk(full, "26.0.1-x", "26.0.1")
  jdk(poor, "21.0.7-x", "21.0.7"); local p23 = jdk(poor, "23.0.2-x", "23.0.2")
  local sv_root, sv_jh = vim.env.NV4J_JDK_ROOT, vim.env.JAVA_HOME
  local function with(rootdir, jh, f)
    vim.env.NV4J_JDK_ROOT, vim.env.JAVA_HOME = rootdir, jh
    local ok, a, b = pcall(f)
    vim.env.NV4J_JDK_ROOT, vim.env.JAVA_HOME = sv_root, sv_jh
    return ok, a, b
  end
  local function home() return J.server_home() end
  lsp.report("20_java25.min_const", J.SERVER_MIN_JAVA == 25, "SERVER_MIN_JAVA=" .. tostring(J.SERVER_MIN_JAVA))
  local ok, got = with(full, h23, home)
  lsp.report("20_java25.java_home_23", ok and got == h26, "JAVA_HOME=23 -> " .. tostring(got) .. " (want newest >= 25: " .. h26 .. ")")
  ok, got = with(full, h24, home)
  lsp.report("20_java25.java_home_24", ok and got == h26, "JAVA_HOME=24 -> " .. tostring(got) .. " (want " .. h26 .. ")")
  ok, got = with(full, h25, home)
  lsp.report("20_java25.java_home_25", ok and got == h25, "JAVA_HOME=25 -> " .. tostring(got) .. " (want kept " .. h25 .. ")")
  ok, got = with(poor, p23, home)
  local msg = tostring(got)
  lsp.report("20_java25.no_25", not ok and msg:find("needs a JDK >= 25", 1, true) and msg:find("21.0.7", 1, true)
    and msg:find("23.0.2", 1, true) and msg:find("can stay 21/23", 1, true) and msg:find("sdk install java 25-amzn", 1, true) ~= nil,
    "only 21 and 23: " .. msg)
  -- health: ERROR naming the minimum (stubbed vim.health), and an ok line with the version when a 25 exists
  local function health(rootdir, jh)
    local out, saved = {}, {}
    for _, lv in ipairs({ "start", "ok", "warn", "error", "info" }) do
      saved[lv] = vim.health[lv]
      vim.health[lv] = function(m) out[#out + 1] = { lv, m } end
    end
    with(rootdir, jh, function() require("nv4j.health").check() end)
    for lv, f in pairs(saved) do vim.health[lv] = f end
    return out
  end
  local function line(out, lv) for _, e in ipairs(out) do if e[1] == lv and e[2]:find("jdt.ls needs a JDK", 1, true) then return e[2] end end end
  local bad = line(health(poor, p23), "error")
  local good = health(full, h23)
  local okline
  for _, e in ipairs(good) do if e[1] == "ok" and e[2]:find("Java for jdt.ls", 1, true) and e[2]:find(h26, 1, true) then okline = e[2] end end
  lsp.report("20_java25.health_error", bad ~= nil and bad:find(">= 25", 1, true) ~= nil and okline ~= nil,
    "error line: " .. tostring(bad) .. " | ok line: " .. tostring(okline))
  vim.fn.delete(root, "rf")
end

-- case 1
local fixture = vim.env.NV4J_FIXTURE
local buf1 = lsp.open(fixture .. "/src/main/java/demo/Modern.java")
check_case("20_java25", nil, fixture, 25, buf1)

-- JVM jdtls itself runs on: first word of its process command line.
local jvm
for _, l in ipairs(vim.fn.systemlist({ "ps", "-axo", "command=" })) do
  local exe = l:match("^(%S+/bin/java) ")
  if exe and l:find("org.eclipse.equinox.launcher", 1, true) and l:find(require("nv4j.paths").jdtls_data .. "/", 1, true) then
    jvm = exe
    break
  end
end
local expect = require("nv4j.jdk").server_home()
lsp.report("20_java25.server_jvm", jvm ~= nil and jvm == expect .. "/bin/java", "jdtls runs on " .. tostring(jvm) .. " (expected " .. expect .. ")")
-- The server JVM must come from nv4j.jdk, not from PATH: compare with the real PATH java home.
-- If they are legitimately the same JDK the test cannot tell the two apart: report SKIP, not PASS.
local path_java = vim.fn.exepath("java")
local path_real = path_java ~= "" and vim.uv.fs_realpath(path_java) or nil
local jvm_real = jvm and vim.uv.fs_realpath(jvm) or nil
if not path_real or not jvm_real then
  lsp.report("20_java25.server_not_path_java", jvm_real ~= nil, "no java on PATH (" .. tostring(path_java) .. "), server " .. tostring(jvm))
elseif path_real == jvm_real then
  print("SKIP 20_java25.server_not_path_java PATH java and server JVM are the same JDK (" .. path_real .. ")")
else
  lsp.report("20_java25.server_not_path_java", true, "server " .. jvm_real .. " != PATH java " .. path_real)
end

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
