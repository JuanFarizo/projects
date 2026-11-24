-- JDK discovery in more places (SDKMAN env vars, mise, asdf, jabba, Gradle toolchains, /usr/lib/jvm), pure.
-- Spec: specs/features/jdk-java25.md "More JDK locations". Code: nvim/lua/nv4j/jdk.lua. Reference: IntelliJ
-- JavaHomeFinderBasic (findSdkManCandidatesDir, findMiseInstallsDir, findAsdfInstallsDir, findJavaInstalledByJabba/Gradle).
-- Fake JDK homes (a `bin/java` stub and a `release` file) and a fake HOME/environment under /tmp/nv4j/d111-<pid>; nothing real is read
-- except the fixed /Library and /usr/lib/jvm roots, so every case looks only at homes under the temp dir.
--  worktree_config      : the config under test is the checkout this file lives in (not ~/.config/nv4j's target).
--  zero_cost_startup    : nv4j.jdk not loaded at startup; roots() builds strings only (no stat/dir calls).
--  sdkman_candidates_dir: SDKMAN_CANDIDATES_DIR wins over SDKMAN_DIR and ~/.sdkman.
--  sdkman_dir / sdkman_home : SDKMAN_DIR/candidates, then ~/.sdkman/candidates.
--  mise_data_dir / mise_xdg / mise_home : MISE_DATA_DIR/installs/java, XDG_DATA_HOME/mise/installs/java, ~/.local/share/mise/installs/java.
--  asdf_data_dir / asdf_home : ASDF_DATA_DIR/installs/java, ~/.asdf/installs/java.
--  jabba                : ~/.jabba/jdk.   gradle: ~/.gradle/jdks (home one level down).   usr_lib_jvm: listed as the last root.
--  dedupe               : a mise `21` link to `21.0.1` and a sdkman copy of the same real path is ONE entry.
--  order                : newest first across all managers (unchanged rule).
--  jre_last             : a home without bin/javac (a headless JRE) sorts after a full JDK, even when its version is newer.
--  selection            : `.sdkmanrc` java=17 picks the JDK 17 that only jabba has as default runtime (user's version choice kept).
local lsp = require("lsp")
local P = "111_jdk_roots."
local rep = function(n, ok, d) lsp.report(P .. n, ok, d) end

-- 1. the config under test is this worktree
local here = debug.getinfo(1, "S").source:gsub("^@", "")
local nvim_dir = vim.fs.normalize(vim.fn.fnamemodify(here, ":p:h:h:h") .. "/nvim")
local mod = package.searchpath("nv4j.organize", vim.o.rtp:gsub(",", "/lua/?.lua;") .. ";" .. package.path)
local mod_real = mod and vim.uv.fs_realpath(mod) or ""
rep("worktree_config", mod_real:sub(1, #nvim_dir) == vim.uv.fs_realpath(nvim_dir),
  ("config module %s, expected under %s"):format(mod_real, nvim_dir))

local loaded_at_start = package.loaded["nv4j.jdk"] ~= nil
local jdk = require("nv4j.jdk")

local TMP = "/tmp/nv4j/d111-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
TMP = vim.uv.fs_realpath(TMP)
local function jdkhome(dir, ver)
  vim.fn.mkdir(dir .. "/bin", "p")
  vim.fn.writefile({ "#!/bin/sh" }, dir .. "/bin/java")
  vim.fn.writefile({ 'JAVA_VERSION="' .. ver .. '"' }, dir .. "/release")
  return dir
end

-- a full JDK 31.0.0 and a newer JRE-only 31.0.2 (no bin/javac) in the same manager
jdkhome(TMP .. "/home/.jabba/jdk/full31", "31.0.0")
vim.fn.writefile({ "#!/bin/sh" }, TMP .. "/home/.jabba/jdk/full31/bin/javac")
jdkhome(TMP .. "/home/.jabba/jdk/jre31", "31.0.2")

-- fake HOME and managers
local H = TMP .. "/home"
jdkhome(H .. "/.sdkman/candidates/java/25.0.2-fake", "25.0.2")
jdkhome(H .. "/.local/share/mise/installs/java/temurin-23.0.1", "23.0.1")
jdkhome(H .. "/.asdf/installs/java/zulu-22.0.1", "22.0.1")
jdkhome(H .. "/.jabba/jdk/adopt@17", "17.0.9")
jdkhome(H .. "/.gradle/jdks/eclipse_adoptium-20-amd64-linux.2/jdk-20.0.2+9", "20.0.2")
-- env-var locations
jdkhome(TMP .. "/cand/java/26.0.1-cand", "26.0.1")
jdkhome(TMP .. "/sdkdir/candidates/java/27.0.1-sdk", "27.0.1")
jdkhome(TMP .. "/misedata/installs/java/temurin-28.0.1", "28.0.1")
jdkhome(TMP .. "/xdg/mise/installs/java/temurin-29.0.1", "29.0.1")
jdkhome(TMP .. "/asdfdata/installs/java/zulu-30.0.1", "30.0.1")

local VARS = { "NV4J_JDK_ROOT", "SDKMAN_CANDIDATES_DIR", "SDKMAN_DIR", "MISE_DATA_DIR", "XDG_DATA_HOME", "ASDF_DATA_DIR", "JAVA_HOME", "HOME" }
local function with_env(env, fn)
  local saved = {}
  for _, k in ipairs(VARS) do saved[k] = vim.env[k]; vim.env[k] = env[k] end
  local ok, a, b = pcall(fn)
  for _, k in ipairs(VARS) do vim.env[k] = saved[k] end
  if not ok then error(a, 0) end
  return a, b
end
local function found(env)
  return with_env(env, function()
    local set, list = {}, {}
    for _, d in ipairs(jdk.discover()) do
      if d.home:sub(1, #TMP) == TMP then set[d.version] = d.home; list[#list + 1] = d end
    end
    return set, list
  end)
end
local function has(set, ver) return set[ver] ~= nil end

-- zero cost: nothing loaded at startup, roots() does no filesystem call
local calls = 0
local o_stat, o_dir = vim.uv.fs_stat, vim.fs.dir
vim.uv.fs_stat = function(...) calls = calls + 1; return o_stat(...) end
vim.fs.dir = function(...) calls = calls + 1; return o_dir(...) end
local roots = with_env({ HOME = H }, function() return jdk.roots() end)
vim.uv.fs_stat, vim.fs.dir = o_stat, o_dir
rep("zero_cost_startup", not loaded_at_start and calls == 0 and #roots >= 7,
  ("loaded at startup: %s; fs calls in roots(): %d; roots: %d"):format(tostring(loaded_at_start), calls, #roots))

-- SDKMAN
local s = found({ HOME = H, SDKMAN_CANDIDATES_DIR = TMP .. "/cand", SDKMAN_DIR = TMP .. "/sdkdir" })
rep("sdkman_candidates_dir", has(s, "26.0.1") and not has(s, "27.0.1") and not has(s, "25.0.2"),
  vim.inspect(vim.tbl_keys(s)))
s = found({ HOME = H, SDKMAN_DIR = TMP .. "/sdkdir" })
rep("sdkman_dir", has(s, "27.0.1") and not has(s, "25.0.2") and not has(s, "26.0.1"), vim.inspect(vim.tbl_keys(s)))
s = found({ HOME = H })
rep("sdkman_home", has(s, "25.0.2"), vim.inspect(vim.tbl_keys(s)))

-- mise
s = found({ HOME = H, MISE_DATA_DIR = TMP .. "/misedata", XDG_DATA_HOME = TMP .. "/xdg" })
rep("mise_data_dir", has(s, "28.0.1") and not has(s, "29.0.1") and not has(s, "23.0.1"), vim.inspect(vim.tbl_keys(s)))
s = found({ HOME = H, XDG_DATA_HOME = TMP .. "/xdg" })
rep("mise_xdg", has(s, "29.0.1") and not has(s, "23.0.1"), vim.inspect(vim.tbl_keys(s)))
s = found({ HOME = H })
rep("mise_home", has(s, "23.0.1"), vim.inspect(vim.tbl_keys(s)))

-- asdf
s = found({ HOME = H, ASDF_DATA_DIR = TMP .. "/asdfdata" })
rep("asdf_data_dir", has(s, "30.0.1") and not has(s, "22.0.1"), vim.inspect(vim.tbl_keys(s)))
rep("asdf_home", has(found({ HOME = H }), "22.0.1"), "22.0.1 from ~/.asdf")

-- jabba, gradle (nested), /usr/lib/jvm
s = found({ HOME = H })
rep("jabba", has(s, "17.0.9"), vim.inspect(vim.tbl_keys(s)))
rep("gradle", has(s, "20.0.2"), vim.inspect(vim.tbl_keys(s)))
rep("usr_lib_jvm", roots[#roots] == "/usr/lib/jvm", roots[#roots])

-- dedupe: a link to the same home in two managers is one entry
vim.uv.fs_symlink(H .. "/.sdkman/candidates/java/25.0.2-fake", H .. "/.local/share/mise/installs/java/25", { dir = true })
vim.uv.fs_symlink(H .. "/.sdkman/candidates/java/25.0.2-fake", H .. "/.asdf/installs/java/25-link", { dir = true })
local _, list = found({ HOME = H })
local n25 = 0
for _, d in ipairs(list) do if d.version == "25.0.2" then n25 = n25 + 1 end end
rep("dedupe", n25 == 1, "25.0.2 entries: " .. n25)

-- order: newest first
local ok_order = true
for i = 2, #list do if list[i - 1].major < list[i].major then ok_order = false end end
rep("order", ok_order and #list >= 5, table.concat(vim.tbl_map(function(d) return d.version end, list), " "))

-- jre_last
local i_full, i_jre
for i, d in ipairs(list) do
  if d.version == "31.0.0" then i_full = i elseif d.version == "31.0.2" then i_jre = i end
end
rep("jre_last", i_full and i_jre and i_full < i_jre, ("full at %s, jre at %s"):format(tostring(i_full), tostring(i_jre)))

-- selection: .sdkmanrc java=17 picks the jabba JDK as default runtime
local proj = TMP .. "/proj"
vim.fn.mkdir(proj, "p")
vim.fn.writefile({ "java=17.0.9-fake" }, proj .. "/.sdkmanrc")
local rts = with_env({ HOME = H }, function() return (jdk.runtimes(proj)) end)
local def
for _, r in ipairs(rts) do if r.default then def = r end end
rep("selection", def ~= nil and def.name == "JavaSE-17" and def.path:find("adopt@17", 1, true) ~= nil,
  def and (def.name .. " " .. def.path) or "no default")

vim.fn.delete(TMP, "rf")
lsp.finish()
