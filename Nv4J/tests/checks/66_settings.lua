-- Saved run defaults in `.nv4j` (empty file stays a marker). Run via tests/run.sh.
-- Spec: specs/features/run-defaults.md. Code: nvim/lua/nv4j/settings.lua, nv4j/run.lua.
-- No jdt.ls: the run cases use the build-tool fallback (stub mvnw).
--  api            : require("nv4j.settings") exposes load, apply, mark.
--  empty          : empty `.nv4j` is still a project marker; apply returns no profile/env/vm_args.
--  missing        : no file: apply returns empty, no warning.
--  json           : run.profile / run.env / run.vm_args fill apply() when opts omit them.
--  opts_win       : apply({ profile, env }) keeps the caller's profile and env keys; other file env stays.
--  bad_json       : one WARN (title Nv4J), apply empty, file still a marker.
--  mark           : mark(dir) writes an empty `.nv4j`; project() uses that dir.
--  mark_cwd       : mark() with no dir writes at cwd (the folder Neovim was opened at), not the
--                   current file's folder (loose files have no project root yet; that is why you mark).
--  mark_exists    : existing `.nv4j` is not overwritten.
--  command        : :Nv4jMark exists after keymaps load.
--  no_write       : apply never writes the file.
--  run_default    : spring_boot{} (no opts) uses the file's profile, env and vm_args (build-tool path).
--  run_opts_win   : spring_boot{ profile = "prod" } uses prod, file unchanged.
local lsp = require("lsp")
local P = "66_settings."
local TMP = "/tmp/nv4j/d66-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
TMP = vim.uv.fs_realpath(TMP)

local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(text or "")
  f:close()
end
local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

pcall(require, "config.keymaps")

local notes = {}
local orig_notify = vim.notify
vim.notify = function(msg, level, o)
  notes[#notes + 1] = { msg = tostring(msg), level = level or vim.log.levels.INFO, title = o and o.title }
end

local ok_mod, S = pcall(require, "nv4j.settings")
lsp.report(P .. "api", ok_mod and type(S) == "table" and type(S.load) == "function"
    and type(S.apply) == "function" and type(S.mark) == "function",
  ok_mod and "load/apply/mark" or tostring(S):gsub("\n.*", ""))
if not ok_mod then
  for _, c in ipairs({ "empty", "missing", "json", "opts_win", "bad_json", "mark", "mark_cwd",
    "mark_exists", "command", "no_write", "run_default", "run_opts_win" }) do
    lsp.report(P .. c, false, "nv4j.settings not loadable")
  end
  vim.notify = orig_notify
  vim.fn.delete(TMP, "rf")
  return lsp.finish()
end

local root = require("nv4j.root")

-- empty `.nv4j`: marker unchanged, no run defaults
local E = TMP .. "/empty"
write(E .. "/.nv4j", "")
write(E .. "/x.java", "class X {}")
local er, _, ek = root.project(E .. "/x.java")
local empty = S.apply({}, E)
lsp.report(P .. "empty", er == E and ek == "nv4j" and empty.profile == nil
    and vim.tbl_isempty(empty.env or {}) and (not empty.vm_args or #empty.vm_args == 0),
  ("root %s kind %s; profile %s env %s vm_args %s"):format(er, tostring(ek), tostring(empty.profile),
    vim.inspect(empty.env), vim.inspect(empty.vm_args)))

-- no file
local Mdir = TMP .. "/missing"
write(Mdir .. "/x.java", "class X {}")
local n0 = #notes
local miss = S.apply({}, Mdir)
lsp.report(P .. "missing", miss.profile == nil and vim.tbl_isempty(miss.env or {}) and #notes == n0,
  ("profile %s; warnings %d (want 0)"):format(tostring(miss.profile), #notes - n0))

-- JSON defaults
local J = TMP .. "/json"
write(J .. "/.nv4j", [[{
  "run": {
    "profile": "dev",
    "env": { "FOO": "bar", "KEEP": "file" },
    "vm_args": ["-Xmx512m"]
  }
}]])
local got = S.apply({}, J)
lsp.report(P .. "json", got.profile == "dev" and (got.env or {}).FOO == "bar"
    and (got.env or {}).KEEP == "file" and vim.deep_equal(got.vm_args, { "-Xmx512m" }),
  vim.inspect(got):gsub("\n%s*", " "))

local win = S.apply({ profile = "prod", env = { FOO = "caller" } }, J)
lsp.report(P .. "opts_win", win.profile == "prod" and win.env.FOO == "caller" and win.env.KEEP == "file"
    and vim.deep_equal(win.vm_args, { "-Xmx512m" }),
  vim.inspect(win):gsub("\n%s*", " "))

-- bad JSON: warn once, still a marker, apply empty
local B = TMP .. "/bad"
write(B .. "/.nv4j", "{ nope")
write(B .. "/x.java", "class X {}")
local n1 = #notes
local bad = S.apply({}, B)
local br, _, bk = root.project(B .. "/x.java")
local warn
for i = n1 + 1, #notes do
  local n = notes[i]
  if n.level == vim.log.levels.WARN and n.title == "Nv4J" then warn = n.msg end
end
S.apply({}, B) -- second apply: still only the one warning from the first, or at most one more? once per root
local extra = 0
for i = n1 + 1, #notes do
  if notes[i].level == vim.log.levels.WARN and notes[i].title == "Nv4J" then extra = extra + 1 end
end
lsp.report(P .. "bad_json", br == B and bk == "nv4j" and bad.profile == nil and warn ~= nil and extra == 1,
  ("kind %s; profile %s; warn %s; warn count %d"):format(tostring(bk), tostring(bad.profile), tostring(warn), extra))

-- mark
local K = TMP .. "/mark"
vim.fn.mkdir(K .. "/src", "p")
local path, err = S.mark(K)
local kr, _, kk = root.project(K .. "/src/X.java")
local body = read(K .. "/.nv4j")
lsp.report(P .. "mark", err == nil and path == K .. "/.nv4j" and body == "" and kr == K and kk == "nv4j",
  ("path %s err %s body %q root %s kind %s"):format(tostring(path), tostring(err), tostring(body), tostring(kr), tostring(kk)))

-- mark() with no dir: cwd, not the open file's folder (D25 loose root is that folder)
local TOP = TMP .. "/this"
write(TOP .. "/isanexample/x.java", "class X {}")
vim.cmd("lcd " .. vim.fn.fnameescape(TOP))
vim.cmd("edit " .. vim.fn.fnameescape(TOP .. "/isanexample/x.java"))
local cwd_path, cwd_err = S.mark()
lsp.report(P .. "mark_cwd", cwd_err == nil and cwd_path == TOP .. "/.nv4j"
    and read(TOP .. "/.nv4j") == "" and read(TOP .. "/isanexample/.nv4j") == nil,
  ("path %s err %s; isanexample has file %s; cwd %s"):format(tostring(cwd_path), tostring(cwd_err),
    tostring(read(TOP .. "/isanexample/.nv4j") ~= nil), vim.fn.getcwd()))

write(K .. "/.nv4j", "keep")
local p2, e2 = S.mark(K)
lsp.report(P .. "mark_exists", e2 ~= nil and read(K .. "/.nv4j") == "keep" and p2 == K .. "/.nv4j",
  ("err %s body %q"):format(tostring(e2), tostring(read(K .. "/.nv4j"))))

local cmds = vim.api.nvim_get_commands({})
lsp.report(P .. "command", cmds.Nv4jMark ~= nil, cmds.Nv4jMark and "Nv4jMark" or "missing")

-- apply does not write
local before = read(J .. "/.nv4j")
S.apply({ profile = "other" }, J)
lsp.report(P .. "no_write", read(J .. "/.nv4j") == before, "unchanged")

-- run: build-tool path, no jdt.ls, stub mvnw
local ok_run, R = pcall(require, "nv4j.run")
if not ok_run then
  lsp.report(P .. "run_default", false, "nv4j.run not loadable: " .. tostring(R):gsub("\n.*", ""))
  lsp.report(P .. "run_opts_win", false, "nv4j.run not loadable")
else
  local D = TMP .. "/run"
  write(D .. "/pom.xml", "<project><parent>\n<groupId>org.springframework.boot</groupId>\n<artifactId>spring-boot-starter-parent</artifactId></parent></project>")
  write(D .. "/mvnw", "#!/bin/sh\n")
  vim.fn.setfperm(D .. "/mvnw", "rwxr-xr-x")
  write(D .. "/.nv4j", '{"run":{"profile":"dev","env":{"NV4J_66":"from-file"},"vm_args":["-Xmx64m"]}}\n')
  vim.cmd("edit " .. vim.fn.fnameescape(D .. "/pom.xml"))
  local ns = #R.sessions
  local file_before = read(D .. "/.nv4j")
  R.spring_boot({})
  local s = R.sessions[ns + 1]
  local cmd = s and table.concat(s.cmd, " ") or ""
  local has_prof = cmd:find("-Dspring-boot.run.profiles=dev", 1, true)
  local has_vm = cmd:find("-Dspring-boot.run.jvmArguments=-Xmx64m", 1, true)
  local has_env = s and s.env and s.env.NV4J_66 == "from-file"
  lsp.report(P .. "run_default", s ~= nil and has_prof and has_vm and has_env,
    ("session %s; cmd %s; env NV4J_66=%s"):format(tostring(s ~= nil), cmd, tostring(s and s.env and s.env.NV4J_66)))
  if s and s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    pcall(function() R.close(s) end)
    pcall(vim.api.nvim_buf_delete, s.buf, { force = true })
  end

  local ns2 = #R.sessions
  R.spring_boot({ profile = "prod" })
  local s2 = R.sessions[ns2 + 1]
  local cmd2 = s2 and table.concat(s2.cmd, " ") or ""
  local unchanged = read(D .. "/.nv4j") == file_before
  lsp.report(P .. "run_opts_win", s2 ~= nil and cmd2:find("-Dspring-boot.run.profiles=prod", 1, true)
      and not cmd2:find("-Dspring-boot.run.profiles=dev", 1, true) and unchanged,
    ("cmd %s; file unchanged %s"):format(cmd2, tostring(unchanged)))
  if s2 and s2.buf and vim.api.nvim_buf_is_valid(s2.buf) then
    pcall(function() R.close(s2) end)
    pcall(vim.api.nvim_buf_delete, s2.buf, { force = true })
  end
end

vim.notify = orig_notify
vim.fn.delete(TMP, "rf")
lsp.finish()
