-- :checkhealth nv4j / :Nv4JHealth (specs/features/health.md): pure + headless, no jdt.ls, nothing downloaded, no real file touched
-- (the CFR jar path, the logs dir and the ~/.m2/settings.xml path are stubbed to a temp tree /tmp/nv4j/d96-<pid>; PATH is
-- emptied inside pcall and restored).
--  zero_cost_startup : nv4j.health is not loaded when the config has started.
--  tools_ok / tools_missing : with the real PATH java, mvn, rg, fd, git are ok (an error otherwise, reported as the detail);
--                      with PATH emptied every one of the five is an ERROR and fzf is only info.
--  bundles           : jdt.ls, java-debug, java-test, Spring LS and the JDK of jdt.ls each get a line (ok/warn/error), no crash.
--  cfr_absent        : jar missing = WARN naming :Nv4JInstallCfr, no error.
--  cfr_sha_ok / cfr_sha_bad : a stub jar whose SHA-256 equals / differs from the pinned one = ok / error.
--  logs_dir          : absent = info (on demand), writable dir = ok.
--  m2_settings       : present and absent = info only; a secret in the file never appears in any output line.
--  root_marker       : .nv4j above the current buffer = ok with the root; none = info.
--  no_side_effects   : no process spawned (vim.system / jobstart untouched), the temp tree is unchanged after the report.
--  commands          : :Nv4JHealth exists, and both it and :checkhealth nv4j produce a buffer with every section title.
local lsp = require("lsp")
local P = "96_health."
local function rep(name, ok, detail) lsp.report(P .. name, ok and true or false, detail) end
local TMP = "/tmp/nv4j/d96-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")

rep("zero_cost_startup", package.loaded["nv4j.health"] == nil, "loaded at startup: " .. tostring(package.loaded["nv4j.health"] ~= nil))

local H = require("nv4j.health")
local D = require("nv4j.decompile")

local spawned, in_run = 0, false
--- Runs M.check() with vim.health stubbed; returns { {level, msg}, ... }.
local function run()
  local out, saved = {}, {}
  for _, lv in ipairs({ "start", "ok", "warn", "error", "info" }) do
    saved[lv] = vim.health[lv]
    vim.health[lv] = function(msg) out[#out + 1] = { lv, msg } end
  end
  in_run = true
  local ok, err = pcall(H.check)
  in_run = false
  for lv, f in pairs(saved) do vim.health[lv] = f end
  assert(ok, err)
  return out
end
local function find(out, lv, pat)
  for _, e in ipairs(out) do if e[1] == lv and e[2]:find(pat, 1, true) then return e[2] end end
end
local function count(out, lv, pat) local n = 0 for _, e in ipairs(out) do if e[1] == lv and e[2]:find(pat, 1, true) then n = n + 1 end end return n end

-- Process spawns during the report only (none allowed; gitsigns spawns git while the root_marker case opens buffers).
local sys, jobstart = vim.system, vim.fn.jobstart
vim.system = function(...) if in_run then spawned = spawned + 1 end; return sys(...) end
vim.fn.jobstart = function(...) if in_run then spawned = spawned + 1 end; return jobstart(...) end

local real = run()
do
  local missing = {}
  for _, t in ipairs({ "java", "mvn", "rg", "fd", "git" }) do
    if not find(real, "ok", t .. ": ") then missing[#missing + 1] = t end
  end
  rep("tools_ok", #missing == 0, #missing == 0 and "all five found" or ("not found on this machine: " .. table.concat(missing, ",")))
end

do
  local path = vim.env.PATH
  vim.env.PATH = TMP -- an empty dir
  local ok, out = pcall(run)
  vim.env.PATH = path
  local errs = ok and (count(out, "error", "java not found") + count(out, "error", "mvn not found") + count(out, "error", "rg not found")
    + count(out, "error", "fd not found") + count(out, "error", "git not found")) or -1
  rep("tools_missing", ok and errs == 5 and find(out, "info", "fzf (optional)") ~= nil, "errors " .. errs)
end

do
  local n = 0
  for _, k in ipairs({ "jdt.ls", "java-debug", "java-test", "Spring Boot LS", "Java for jdt.ls" }) do
    for _, lv in ipairs({ "ok", "warn", "error", "info" }) do
      if find(real, lv, k) then n = n + 1; break end
    end
  end
  rep("bundles", n == 5, n .. "/5 lines")
end

local jar_path = D.jar_path
local sha = D.CFR.sha256
local function with_jar(path, f) D.jar_path = function() return path end; local ok, e = pcall(f); D.jar_path = jar_path; D.CFR.sha256 = sha; assert(ok, e) end

with_jar(TMP .. "/none.jar", function()
  local out = run()
  local w = find(out, "warn", "Nv4JInstallCfr")
  rep("cfr_absent", w ~= nil and not find(out, "error", "none.jar"), w or "no warning")
end)

local stub = TMP .. "/cfr.jar"
do local f = assert(io.open(stub, "wb")); f:write("not a jar"); f:close() end
with_jar(stub, function()
  D.CFR.sha256 = vim.fn.sha256("not a jar")
  local ok = find(run(), "ok", "SHA-256 matches")
  D.CFR.sha256 = sha
  local bad = find(run(), "error", "expected " .. sha)
  rep("cfr_sha_ok", ok ~= nil, ok or "no ok line")
  rep("cfr_sha_bad", bad ~= nil, bad or "no error line")
end)

do
  local old = H.LOG_DIR
  H.LOG_DIR = TMP .. "/nologs"
  local a = find(run(), "info", "created on demand")
  vim.fn.mkdir(TMP .. "/logs", "p")
  H.LOG_DIR = TMP .. "/logs"
  local b = find(run(), "ok", "writable")
  H.LOG_DIR = old
  rep("logs_dir", a ~= nil and b ~= nil, ("absent->info %s, present->ok %s"):format(tostring(a ~= nil), tostring(b ~= nil)))
end

do
  local old = H.m2_settings
  local f = assert(io.open(TMP .. "/settings.xml", "wb")); f:write("<password>SECRET-TOKEN-123</password>"); f:close()
  H.m2_settings = function() return TMP .. "/settings.xml" end
  local pres = run()
  H.m2_settings = function() return TMP .. "/nope.xml" end
  local abs = run()
  H.m2_settings = old
  local leak = false
  for _, e in ipairs(pres) do if e[2]:find("SECRET", 1, true) or e[2]:find("password", 1, true) then leak = true end end
  rep("m2_settings", find(pres, "info", "present") ~= nil and find(abs, "info", "absent") ~= nil and not leak
    and not find(pres, "warn", "settings.xml") and not find(pres, "error", "settings.xml"), "leak " .. tostring(leak))
end

do
  vim.fn.mkdir(TMP .. "/proj/src", "p")
  vim.fn.mkdir(TMP .. "/proj/.nv4j", "p")
  vim.fn.mkdir(TMP .. "/bare", "p")
  local function buf(path) vim.cmd("silent edit " .. vim.fn.fnameescape(path)) end
  local f = assert(io.open(TMP .. "/proj/src/A.txt", "wb")); f:write("x"); f:close()
  f = assert(io.open(TMP .. "/bare/B.txt", "wb")); f:write("x"); f:close()
  buf(TMP .. "/proj/src/A.txt")
  local rp = vim.uv.fs_realpath(TMP)
  local a = find(run(), "ok", ".nv4j project root: " .. rp .. "/proj")
  buf(TMP .. "/bare/B.txt")
  -- /tmp/nv4j/... has no .nv4j above it unless the machine has one; accept only an info line when none is found
  local out = run()
  local b = find(out, "info", "no .nv4j marker") or find(out, "ok", ".nv4j project root")
  rep("root_marker", a ~= nil and b ~= nil and not find(out, "ok", rp .. "/proj"), tostring(a) .. " | " .. tostring(b))
  vim.cmd("silent! enew")
end

do
  local before = vim.fn.glob(TMP .. "/**", false, true)
  run()
  local after = vim.fn.glob(TMP .. "/**", false, true)
  rep("no_side_effects", spawned == 0 and #before == #after, ("spawned %d, files %d -> %d"):format(spawned, #before, #after))
end
vim.system, vim.fn.jobstart = sys, jobstart

do
  local cmds = vim.api.nvim_get_commands({})
  if not cmds.Nv4JHealth then pcall(require, "config.keymaps") end
  local function titles(cmd)
    vim.cmd("silent! enew")
    local ok, err = pcall(vim.cmd, cmd)
    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    local all = true
    for _, t in ipairs({ "tools on PATH", "Mason packages and JDK", "CFR decompiler", "logs, Maven settings, project" }) do
      if not text:find(t, 1, true) then all = false end
    end
    return ok and all, ok and #text or err
  end
  local a, an = titles("Nv4JHealth")
  local b, bn = titles("checkhealth nv4j")
  rep("commands", vim.api.nvim_get_commands({}).Nv4JHealth ~= nil and a and b, ("Nv4JHealth %s (%s), checkhealth nv4j %s (%s)"):format(tostring(a), tostring(an), tostring(b), tostring(bn)))
  vim.cmd("silent! enew")
end

vim.fn.delete(TMP, "rf")
return lsp.finish()
