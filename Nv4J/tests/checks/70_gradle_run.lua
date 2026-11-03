-- P4 T5 (G4, D32): <leader>rS on Gradle. Run via tests/run.sh (gated like 67: SKIP when the Gradle fixture cannot resolve,
-- although no case needs Gradle). Spec: specs/006-p4-gradle.md G4, specs/001-architecture.md D32. Code: nvim/lua/nv4j/run.lua
-- (build_tool_command + the build-tool branch of spring_boot). Throwaway projects in /tmp/nv4j/gradle-run-<pid>; the terminal
-- starter (nv4j.run.start_terminal) is stubbed, so no Gradle and no JVM run. The real fixture run of rS stays in 67 run_bootrun.
--  vm_env          : vm_args {-Dfoo=1, "-Dbar=a b"} reach the terminal env as JAVA_TOOL_OPTIONS (`-Dfoo=1 "-Dbar=a b"`);
--                    the command is `<wrapper> bootRun` (no vm flag on the command line).
--  no_vm           : no vm_args: no JAVA_TOOL_OPTIONS in the env, and Neovim's own value is not copied in.
--  merge_nvim_env  : Neovim's JAVA_TOOL_OPTIONS=-Dpre=1 + vm_args: env value is `-Dpre=1 -Dfoo=1` (kept, extended) and one
--                    notification names JAVA_TOOL_OPTIONS (never silent).
--  settings_vm     : `.nv4j` run.vm_args alone (D27) reach the env; run.env other keys still apply.
--  merge_settings  : `.nv4j` run.env.JAVA_TOOL_OPTIONS=-Dset=1 + run.vm_args: `-Dset=1 -Dfile=2`; the other env key stays.
--  nonexec         : gradlew without the exec bit: the command is `sh <gradlew> bootRun`, not bare gradle; the session name says gradlew.
--  nonexec_parent  : multi-project: the non-exec wrapper sits at the top, the Boot module below: same `sh <top>/gradlew`.
--  nonexec_runs    : that command really runs (a stub gradlew script prints a marker and its args, exit 0).
--  exec_wins       : an executable wrapper is used directly (no sh), even when a non-exec one is higher up.
--  path_gradle     : no wrapper, `gradle` executable on PATH: `gradle bootRun`.
--  no_gradle       : no wrapper and no `gradle`: nothing is started; one WARN names gradlew and the SDKMAN function cause.
--  maven_unchanged : the Maven command with profile, vm_args and args is exactly as before, and has no JAVA_TOOL_OPTIONS.
-- Controls (log paths in the report): vm_args dropped, merge overwrites, non-exec skipped, no_gradle check removed, Maven flag changed.
vim.o.confirm = false
local lsp = require("lsp")
local P = "70_gradle_run."
local TMP = "/tmp/nv4j/gradle-run-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
TMP = vim.uv.fs_realpath(TMP)

local function write(path, text, perm)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(text or "")
  f:close()
  if perm then vim.fn.setfperm(path, perm) end
end

pcall(require, "config.keymaps")
local R = require("nv4j.run")
local notes = {}
local orig_notify = vim.notify
vim.notify = function(msg, level, o) notes[#notes + 1] = { msg = tostring(msg), level = level or vim.log.levels.INFO } end
local orig_start = R.start_terminal
local orig_path, orig_jto = vim.env.PATH, vim.env.JAVA_TOOL_OPTIONS
local started

local BOOT = "plugins { id 'org.springframework.boot' version '3.5.0' }\n"
local function mkproj(name, o)
  o = o or {}
  local d = TMP .. "/" .. name
  write(d .. "/build.gradle", BOOT)
  write(d .. "/settings.gradle", "rootProject.name = '" .. name .. "'\n")
  if o.wrapper then write(d .. "/gradlew", "#!/bin/sh\necho gradlew-ran \"$@\"\n", o.wrapper) end
  if o.nv4j then write(d .. "/.nv4j", o.nv4j) end
  return d
end
--- spring_boot(opts) on the project's build.gradle with the terminal starter stubbed; returns the starter's arg (or nil)
local function run_in(dir, opts, file)
  started, notes = nil, {}
  R.start_terminal = function(o) started = o; return { cmd = o.cmd } end
  vim.cmd("edit " .. vim.fn.fnameescape(file or (dir .. "/build.gradle")))
  R.spring_boot(opts or {})
  R.start_terminal = orig_start
  return started
end
local function jto(o) return o and o.env and o.env.JAVA_TOOL_OPTIONS end
local function note_has(s)
  for _, n in ipairs(notes) do if n.msg:find(s, 1, true) then return n end end
end

local ok_all, err = pcall(function()
  vim.env.JAVA_TOOL_OPTIONS = nil
  -- an empty dir first on PATH so a stray `gradle` of the machine cannot satisfy the cases that expect none
  local empty = TMP .. "/emptybin"
  vim.fn.mkdir(empty, "p")
  vim.env.PATH = empty .. ":" .. (orig_path or "")

  local d = mkproj("vm", { wrapper = "rwxr-xr-x" })
  local o = run_in(d, { vm_args = { "-Dfoo=1", "-Dbar=a b" } })
  lsp.report(P .. "vm_env", o ~= nil and o.cmd[1] == d .. "/gradlew" and o.cmd[2] == "bootRun" and #o.cmd == 2
      and jto(o) == '-Dfoo=1 "-Dbar=a b"',
    ("cmd %s; JAVA_TOOL_OPTIONS=%s; notes: %s"):format(o and table.concat(o.cmd, " ") or "none", tostring(jto(o)), vim.inspect(notes):gsub("%s+", " "):sub(1, 200)))

  d = mkproj("novm", { wrapper = "rwxr-xr-x" })
  vim.env.JAVA_TOOL_OPTIONS = "-Dambient=1"
  o = run_in(d, {})
  lsp.report(P .. "no_vm", o ~= nil and jto(o) == nil, ("cmd %s; JAVA_TOOL_OPTIONS=%s"):format(o and table.concat(o.cmd, " ") or "none", tostring(jto(o))))

  d = mkproj("merge", { wrapper = "rwxr-xr-x" })
  vim.env.JAVA_TOOL_OPTIONS = "-Dpre=1"
  o = run_in(d, { vm_args = { "-Dfoo=1" } })
  lsp.report(P .. "merge_nvim_env", jto(o) == "-Dpre=1 -Dfoo=1" and note_has("JAVA_TOOL_OPTIONS") ~= nil,
    ("JAVA_TOOL_OPTIONS=%s; notified %s"):format(tostring(jto(o)), tostring(note_has("JAVA_TOOL_OPTIONS") ~= nil)))
  vim.env.JAVA_TOOL_OPTIONS = nil

  d = mkproj("settings", { wrapper = "rwxr-xr-x", nv4j = '{"run":{"env":{"NV4J_70":"x"},"vm_args":["-Dfile=2"]}}\n' })
  o = run_in(d, {})
  lsp.report(P .. "settings_vm", jto(o) == "-Dfile=2" and o.env.NV4J_70 == "x",
    ("JAVA_TOOL_OPTIONS=%s; NV4J_70=%s"):format(tostring(jto(o)), tostring(o and o.env and o.env.NV4J_70)))

  d = mkproj("settings2", { wrapper = "rwxr-xr-x",
    nv4j = '{"run":{"env":{"NV4J_70":"x","JAVA_TOOL_OPTIONS":"-Dset=1"},"vm_args":["-Dfile=2"]}}\n' })
  vim.env.JAVA_TOOL_OPTIONS = "-Dambient=1"
  o = run_in(d, {})
  lsp.report(P .. "merge_settings", jto(o) == "-Dset=1 -Dfile=2" and o.env.NV4J_70 == "x",
    ("JAVA_TOOL_OPTIONS=%s; NV4J_70=%s"):format(tostring(jto(o)), tostring(o and o.env and o.env.NV4J_70)))
  vim.env.JAVA_TOOL_OPTIONS = nil

  d = mkproj("nonexec", { wrapper = "rw-r--r--" })
  o = run_in(d, {})
  lsp.report(P .. "nonexec", o ~= nil and o.cmd[1] == "sh" and o.cmd[2] == d .. "/gradlew" and o.cmd[3] == "bootRun"
      and (o.name or ""):find("gradlew", 1, true) ~= nil,
    ("cmd %s; name %s"):format(o and table.concat(o.cmd, " ") or "none", tostring(o and o.name)))

  -- multi-project: wrapper (not executable) at the top, Boot module below
  local top = TMP .. "/multi"
  write(top .. "/settings.gradle", "include 'app'\n")
  write(top .. "/build.gradle", "")
  write(top .. "/gradlew", "#!/bin/sh\necho gradlew-ran \"$@\"\n", "rw-r--r--")
  write(top .. "/app/build.gradle", BOOT)
  write(top .. "/app/src/main/java/App.java", "class App {}\n")
  o = run_in(top, {}, top .. "/app/build.gradle")
  lsp.report(P .. "nonexec_parent", o ~= nil and o.cmd[1] == "sh" and o.cmd[2] == top .. "/gradlew" and o.cmd[3] == "bootRun"
      and vim.uv.fs_realpath(o.cwd) == top .. "/app",
    ("cmd %s; cwd %s"):format(o and table.concat(o.cmd, " ") or "none", tostring(o and o.cwd)))

  -- the sh command really runs without the exec bit
  local out = o and vim.system(o.cmd, { text = true }):wait() or { stdout = "", code = -1 }
  lsp.report(P .. "nonexec_runs", out.code == 0 and (out.stdout or ""):find("gradlew-ran bootRun", 1, true) ~= nil,
    ("exit %s; stdout %s"):format(tostring(out.code), (out.stdout or ""):gsub("%s+", " ")))

  -- an executable wrapper in the module wins over a non-exec one above
  write(top .. "/app/gradlew", "#!/bin/sh\necho module\n", "rwxr-xr-x")
  o = run_in(top, {}, top .. "/app/build.gradle")
  lsp.report(P .. "exec_wins", o ~= nil and o.cmd[1] == top .. "/app/gradlew" and o.cmd[2] == "bootRun",
    ("cmd %s"):format(o and table.concat(o.cmd, " ") or "none"))

  -- no wrapper: gradle from PATH only when executable
  local gbin = TMP .. "/gbin"
  write(gbin .. "/gradle", "#!/bin/sh\n", "rwxr-xr-x")
  d = mkproj("pathgradle")
  vim.env.PATH = gbin .. ":" .. empty .. ":" .. (orig_path or "")
  o = run_in(d, { vm_args = { "-Dp=1" } })
  lsp.report(P .. "path_gradle", o ~= nil and o.cmd[1] == "gradle" and o.cmd[2] == "bootRun" and jto(o) == "-Dp=1",
    ("cmd %s; JAVA_TOOL_OPTIONS=%s"):format(o and table.concat(o.cmd, " ") or "none", tostring(jto(o))))

  vim.env.PATH = empty .. ":" .. (orig_path or "")
  d = mkproj("nogradle")
  if vim.fn.executable("gradle") == 1 then
    lsp.report(P .. "no_gradle", true, "SKIPPED-IN-ENV: the machine has gradle in a system dir on PATH (" .. vim.fn.exepath("gradle") .. ")")
  else
    o = run_in(d, {})
    local n = note_has("gradlew")
    lsp.report(P .. "no_gradle", o == nil and n ~= nil and n.level == vim.log.levels.WARN and n.msg:find("SDKMAN", 1, true) ~= nil,
      ("started %s; note: %s"):format(tostring(o ~= nil), n and n.msg or vim.inspect(notes):gsub("%s+", " "):sub(1, 200)))
  end

  -- Maven stays as it was
  local m = TMP .. "/mvn"
  write(m .. "/pom.xml", "<project><parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId></parent></project>")
  write(m .. "/mvnw", "#!/bin/sh\n", "rwxr-xr-x")
  o = run_in(m, { profile = "dev", vm_args = { "-Dx=1", "-Dy=2" }, args = { "--a=b" } }, m .. "/pom.xml")
  local want = { m .. "/mvnw", "spring-boot:run", "-Dspring-boot.run.profiles=dev", "-Dspring-boot.run.jvmArguments=-Dx=1 -Dy=2",
    "-Dspring-boot.run.arguments=--a=b" }
  lsp.report(P .. "maven_unchanged", o ~= nil and vim.deep_equal(o.cmd, want) and jto(o) == nil,
    ("cmd %s; JAVA_TOOL_OPTIONS=%s"):format(o and table.concat(o.cmd, " ") or "none", tostring(jto(o))))
end)
R.start_terminal = orig_start
vim.env.PATH = orig_path
vim.env.JAVA_TOOL_OPTIONS = orig_jto
vim.notify = orig_notify
if not ok_all then lsp.report(P .. "error", false, tostring(err)) end
vim.fn.delete(TMP, "rf")
lsp.finish()
