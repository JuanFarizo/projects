-- :checkhealth nv4j / :Nv4JHealth: a read-only report of what Nv4J needs on this machine. Loaded only when one of the two
-- is run (the command in config/keymaps.lua and Neovim's own `:checkhealth` lookup of lua/nv4j/health.lua), never at startup.
-- Cheap: stat calls, `executable()`, one SHA-256 of the CFR jar (2 MB). No network, no process, no LSP request or restart.
-- NEVER prints the content of ~/.m2/settings.xml (it may hold credentials): only whether the file exists.
-- Spec: specs/features/health.md. Check: tests/checks/96_health.lua.
local M = {}

local h = vim.health

-- Replaceable in tests.
M.LOG_DIR = "/tmp/nv4j/logs"
M.m2_settings = function() return vim.fs.joinpath(vim.uv.os_homedir(), ".m2", "settings.xml") end

local function stat(p) return vim.uv.fs_stat(p) end

local function tools()
  h.start("Nv4J: tools on PATH")
  for _, t in ipairs({ "java", "mvn", "rg", "fd", "git" }) do
    local p = vim.fn.exepath(t)
    if p ~= "" then h.ok(("%s: %s"):format(t, p)) else h.error(t .. " not found on PATH") end
  end
  local fzf = vim.fn.exepath("fzf")
  h.info(fzf ~= "" and ("fzf (optional): " .. fzf) or "fzf (optional): not found")
end

local function mason_bundles()
  h.start("Nv4J: Mason packages and JDK")
  local mason = vim.fn.stdpath("data") .. "/mason"
  local jd = mason .. "/packages/jdtls"
  local launcher = vim.fn.glob(jd .. "/plugins/org.eclipse.equinox.launcher_*.jar", false, true)[1]
  if launcher then h.ok("jdt.ls: " .. jd) else h.error("jdt.ls not installed (" .. jd .. "): :MasonInstall jdtls") end

  local dbg = vim.fn.glob(mason .. "/share/java-debug-adapter/com.microsoft.java.debug.plugin-*.jar", false, true)
  if #dbg > 0 then h.ok("java-debug bundle: " .. dbg[1]) else h.error("java-debug bundle missing: :MasonInstall java-debug-adapter") end

  local jt = vim.fn.glob(mason .. "/share/java-test/*.jar", false, true)
  if #jt > 0 then h.ok(("java-test bundle: %d jars in %s/share/java-test"):format(#jt, mason)) else h.error("java-test bundle missing: :MasonInstall java-test") end

  local okS, spring = pcall(require, "nv4j.spring")
  if not okS then
    h.warn("nv4j.spring did not load: " .. tostring(spring))
  elseif not spring.enabled() then
    h.info("Spring Boot LS: off (vim.g.nv4j_spring = false)")
  elseif spring.ls_jar() then
    h.ok(("Spring Boot LS: %s (%d jdt.ls extension jars)"):format(spring.ls_jar(), #spring.jars()))
  else
    h.warn("Spring Boot LS not installed (vscode-spring-boot-tools): installed when you open a Spring Boot project")
  end

  local okJ, home = pcall(function() return require("nv4j.jdk").server_home() end)
  if okJ then h.ok("Java for jdt.ls (nv4j.jdk.server_home): " .. home) else h.error(tostring(home)) end
end

local function cfr()
  h.start("Nv4J: CFR decompiler (optional backup)")
  local d = require("nv4j.decompile")
  local jar = d.jar_path()
  if not stat(jar) then
    return h.warn(jar .. " absent: optional, run :Nv4JInstallCfr (library classes still open with Fernflower)")
  end
  local f = io.open(jar, "rb")
  local data = f and f:read("*a")
  if f then f:close() end
  local got = data and vim.fn.sha256(data)
  if got == d.CFR.sha256 then h.ok(("%s (SHA-256 matches the pinned %s)"):format(jar, d.CFR.version))
  else h.error(("%s: SHA-256 %s, expected %s: delete it and run :Nv4JInstallCfr"):format(jar, tostring(got), d.CFR.sha256)) end
end

local function files_and_root()
  h.start("Nv4J: logs, Maven settings, project")
  local ld = M.LOG_DIR
  local st = stat(ld)
  if not st then h.info(ld .. " absent: created on demand")
  elseif st.type == "directory" and vim.uv.fs_access(ld, "W") then h.ok(ld .. " exists and is writable")
  else h.warn(ld .. " exists but is not a writable directory") end

  h.info(stat(M.m2_settings())
    and "~/.m2/settings.xml present (jdt.ls reads only this file, not a project settings.xml; content not shown)"
    or "~/.m2/settings.xml absent (jdt.ls reads only this file, not a project settings.xml)")

  local name = vim.api.nvim_buf_get_name(0)
  local path = name ~= "" and name or vim.uv.cwd()
  local root = vim.fs.root(path, { require("nv4j.root").project_marker })
  if root then h.ok(".nv4j project root: " .. root) else h.info("no .nv4j marker above " .. path .. " (optional; build files decide the root)") end
end

function M.check()
  for _, f in ipairs({ tools, mason_bundles, cfr, files_and_root }) do
    local ok, err = pcall(f)
    if not ok then h.error("health section failed: " .. tostring(err)) end
  end
end

return M
