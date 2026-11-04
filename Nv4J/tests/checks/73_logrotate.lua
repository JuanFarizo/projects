-- Log housekeeping at start (nv4j/logrotate.lua, called from nvim/init.lua). Run via tests/run.sh. No jdt.ls, no timing.
-- Everything runs in a temp dir /tmp/nv4j/d73-<pid> (the directory is a parameter of run(); the real /tmp/nv4j/logs is never
-- touched). File ages are set with fs_utime against a fixed `now`, caps are tiny (max_mb = 1/1024 is 1024 bytes).
--  rotate_over   : lsp.log, spring-route.log, spring-boot-ls.log over the cap are renamed to <name>.1 with their content, the
--                  name is gone (the next write starts a fresh file); other .log files are not rotated.
--  keep_under    : files at or under the cap stay, no .1.
--  one_old_copy  : an existing .1 is replaced (new content), no .2 or other copy appears; a second rotation replaces it again.
--  old_deleted   : test-*.log and lsp-capture-*.bin older than 14 days are deleted; 13 days old stay; other names that are
--                  old (flaky-*.log, notes.txt, test-x.txt, spring-boot-ls.log.2026-11-02.0.gz, lsp.log.1) stay.
--  fresh_kept    : fresh test logs and captures keep their content and mtime.
--  only_files    : an old directory named test-dir.log and an old symlink test-link.log (to a file outside the dir) are left;
--                  the link target is not deleted.
--  missing_dir   : a directory that does not exist: no error, nothing done.
--  unreadable    : a chmod 000 directory: no error; a chmod 000 oversize lsp.log is still rotated; a .1 that is a non-empty
--                  directory (rename fails) gives no error and leaves the log.
--  options       : vim.g.nv4j_log_max_mb and vim.g.nv4j_log_keep_days are read (default 20 MB / 14 days: a 1 MB log stays,
--                  a 20 day old test log goes); max_mb = 0 never rotates; keep_days = 0 never deletes.
--  twice         : run twice in a row: the second changes nothing and does not touch the .1.
--  wired         : nvim/init.lua requires nv4j.logrotate and runs it before the LSP log filename is set.
local lsp = require("lsp")
local P = "73_logrotate."
local TMP = "/tmp/nv4j/d73-" .. vim.fn.getpid()
local uv = vim.uv
local NOW = 2000000000
local DAY = 86400

local function write(path, text)
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
local function exists(path) return uv.fs_lstat(path) ~= nil end
local function fresh_dir(name)
  local d = TMP .. "/" .. name
  vim.fn.delete(d, "rf")
  vim.fn.mkdir(d, "p")
  return d
end
local function age(path, days) uv.fs_utime(path, NOW - days * DAY, NOW - days * DAY) end
local BIG = ("x"):rep(2000)

local ok_mod, L = pcall(require, "nv4j.logrotate")
lsp.report(P .. "api", ok_mod and type(L) == "table" and type(L.run) == "function",
  ok_mod and "run" or tostring(L):gsub("\n.*", ""))
local cases = { "rotate_over", "keep_under", "one_old_copy", "old_deleted", "fresh_kept", "only_files", "missing_dir",
  "unreadable", "options", "twice", "wired" }
if not ok_mod then
  for _, c in ipairs(cases) do lsp.report(P .. c, false, "nv4j.logrotate not loadable") end
  return lsp.finish()
end

local function case(name, fn)
  local ok, err = pcall(fn)
  if not ok then lsp.report(P .. name, false, "error: " .. tostring(err):gsub("\n.*", "")) end
end
local opts = { max_mb = 1 / 1024, keep_days = 14, now = NOW }

case("rotate_over", function()
  local d = fresh_dir("rotate")
  for _, n in ipairs({ "lsp.log", "spring-route.log", "spring-boot-ls.log", "edit-trace.log" }) do write(d .. "/" .. n, BIG .. n) end
  local done = L.run(d, opts)
  local ok = #done.rotated == 3
  for _, n in ipairs({ "lsp.log", "spring-route.log", "spring-boot-ls.log" }) do
    ok = ok and not exists(d .. "/" .. n) and read(d .. "/" .. n .. ".1") == BIG .. n
  end
  ok = ok and exists(d .. "/edit-trace.log") and not exists(d .. "/edit-trace.log.1")
  lsp.report(P .. "rotate_over", ok, ("rotated %d: %s"):format(#done.rotated, table.concat(done.rotated, ",")))
end)

case("keep_under", function()
  local d = fresh_dir("under")
  write(d .. "/lsp.log", ("y"):rep(1024)) -- exactly the cap (1024 bytes)
  write(d .. "/spring-route.log", "small")
  local done = L.run(d, opts)
  local ok = #done.rotated == 0 and read(d .. "/lsp.log") == ("y"):rep(1024) and not exists(d .. "/lsp.log.1")
    and read(d .. "/spring-route.log") == "small" and not exists(d .. "/spring-route.log.1")
  lsp.report(P .. "keep_under", ok, ("rotated %d, lsp.log.1 %s"):format(#done.rotated, tostring(exists(d .. "/lsp.log.1"))))
end)

case("one_old_copy", function()
  local d = fresh_dir("one")
  write(d .. "/lsp.log.1", "OLD")
  write(d .. "/lsp.log", BIG .. "first")
  L.run(d, opts)
  local ok1 = read(d .. "/lsp.log.1") == BIG .. "first"
  write(d .. "/lsp.log", BIG .. "second") -- the "fresh" file grew past the cap again
  L.run(d, opts)
  local names = vim.fn.readdir(d)
  table.sort(names)
  local ok = ok1 and read(d .. "/lsp.log.1") == BIG .. "second" and table.concat(names, ",") == "lsp.log.1"
  lsp.report(P .. "one_old_copy", ok, "files: " .. table.concat(names, ",") .. "; .1 first=" .. tostring(ok1))
end)

case("old_deleted", function()
  local d = fresh_dir("old")
  local gone = { "test-20261001-000000.log", "lsp-capture-jdtls-20261001-000000.bin", "lsp-capture-jdtls-20261001-000000-exit-1.bin" }
  local stay = { "flaky-1-spring-route.log", "notes.txt", "test-x.txt", "spring-boot-ls.log.2026-11-02.0.gz", "lsp.log.1",
    "control-69-off-155356.log", "test-13d.log", "lsp-capture-13d.bin" }
  for _, n in ipairs(gone) do write(d .. "/" .. n, "g"); age(d .. "/" .. n, 15) end
  for _, n in ipairs(stay) do write(d .. "/" .. n, "s"); age(d .. "/" .. n, n:match("13d") and 13 or 400) end
  local done = L.run(d, { max_mb = 1 / 1024, keep_days = 14, now = NOW })
  local ok = #done.deleted == #gone
  for _, n in ipairs(gone) do ok = ok and not exists(d .. "/" .. n) end
  for _, n in ipairs(stay) do ok = ok and read(d .. "/" .. n) == "s" end
  lsp.report(P .. "old_deleted", ok, ("deleted %d: %s"):format(#done.deleted, table.concat(done.deleted, ",")))
end)

case("fresh_kept", function()
  local d = fresh_dir("fresh")
  local names = { "test-20261104-100000.log", "lsp-capture-jdtls-20261104-100000.bin" }
  local mt = {}
  for _, n in ipairs(names) do write(d .. "/" .. n, "keep" .. n); age(d .. "/" .. n, 1); mt[n] = uv.fs_stat(d .. "/" .. n).mtime.sec end
  local done = L.run(d, opts)
  local ok = #done.deleted == 0
  for _, n in ipairs(names) do ok = ok and read(d .. "/" .. n) == "keep" .. n and uv.fs_stat(d .. "/" .. n).mtime.sec == mt[n] end
  lsp.report(P .. "fresh_kept", ok, "deleted " .. #done.deleted)
end)

case("only_files", function()
  local d = fresh_dir("kinds")
  local outside = fresh_dir("outside") .. "/target.log"
  write(outside, "outside")
  age(outside, 400)
  vim.fn.mkdir(d .. "/test-dir.log", "p")
  uv.fs_utime(d .. "/test-dir.log", NOW - 400 * DAY, NOW - 400 * DAY)
  uv.fs_symlink(outside, d .. "/test-link.log")
  uv.fs_utime(d .. "/test-link.log", NOW - 400 * DAY, NOW - 400 * DAY) -- follows the link: the target is old either way
  local done = L.run(d, opts)
  local ok = #done.deleted == 0 and vim.fn.isdirectory(d .. "/test-dir.log") == 1 and exists(d .. "/test-link.log")
    and read(outside) == "outside"
  lsp.report(P .. "only_files", ok, "deleted " .. #done.deleted)
end)

case("missing_dir", function()
  local ok_call, done = pcall(L.run, TMP .. "/does-not-exist", opts)
  local ok = ok_call and type(done) == "table" and #done.rotated == 0 and #done.deleted == 0 and not exists(TMP .. "/does-not-exist")
  lsp.report(P .. "missing_dir", ok, ok_call and "no error, nothing done" or tostring(done))
end)

case("unreadable", function()
  local d = fresh_dir("unreadable")
  vim.fn.mkdir(d .. "/locked", "p")
  uv.fs_chmod(d .. "/locked", 0)
  local ok_a, err_a = pcall(L.run, d .. "/locked", opts)
  uv.fs_chmod(d .. "/locked", tonumber("755", 8))
  write(d .. "/lsp.log", BIG)
  uv.fs_chmod(d .. "/lsp.log", 0)
  local ok_b, done_b = pcall(L.run, d, opts)
  local rot_b = ok_b and #done_b.rotated == 1 and exists(d .. "/lsp.log.1") and not exists(d .. "/lsp.log")
  local d2 = fresh_dir("blocked")
  write(d2 .. "/lsp.log", BIG)
  vim.fn.mkdir(d2 .. "/lsp.log.1/sub", "p") -- rename onto a non-empty directory fails
  local ok_c, done_c = pcall(L.run, d2, opts)
  local ok = ok_a and rot_b and ok_c and #done_c.rotated == 0 and read(d2 .. "/lsp.log") == BIG
  lsp.report(P .. "unreadable", ok, ("locked dir %s, 000 file rotated %s, failed rename %s"):format(
    tostring(ok_a or err_a), tostring(rot_b), ok_c and "silent, log kept" or tostring(done_c)))
  uv.fs_chmod(d .. "/lsp.log.1", tonumber("644", 8))
end)

case("options", function()
  local d = fresh_dir("opts")
  write(d .. "/lsp.log", BIG)                  -- 2 KB
  write(d .. "/test-old.log", "x"); age(d .. "/test-old.log", 20)
  local old_max, old_keep = vim.g.nv4j_log_max_mb, vim.g.nv4j_log_keep_days
  -- defaults: 20 MB and 14 days
  vim.g.nv4j_log_max_mb, vim.g.nv4j_log_keep_days = nil, nil
  local d1 = L.run(d, { now = NOW })
  local ok_def = #d1.rotated == 0 and exists(d .. "/lsp.log") and #d1.deleted == 1 and not exists(d .. "/test-old.log")
  -- options: 1 KB cap rotates the 2 KB file
  vim.g.nv4j_log_max_mb = 1 / 1024
  local d2 = L.run(d, { now = NOW })
  local ok_max = #d2.rotated == 1 and exists(d .. "/lsp.log.1")
  -- keep_days from the option: 30 keeps a 20 day old log, 10 deletes it
  write(d .. "/test-20d.log", "x"); age(d .. "/test-20d.log", 20)
  vim.g.nv4j_log_keep_days = 30
  local k30 = #L.run(d, { now = NOW }).deleted == 0 and exists(d .. "/test-20d.log")
  vim.g.nv4j_log_keep_days = 10
  local k10 = #L.run(d, { now = NOW }).deleted == 1 and not exists(d .. "/test-20d.log")
  -- 0 disables each part
  write(d .. "/lsp.log", BIG)
  write(d .. "/test-20d.log", "x"); age(d .. "/test-20d.log", 20)
  vim.g.nv4j_log_max_mb, vim.g.nv4j_log_keep_days = 0, 0
  local off = L.run(d, { now = NOW })
  local ok_off = #off.rotated == 0 and #off.deleted == 0 and exists(d .. "/lsp.log") and exists(d .. "/test-20d.log")
  vim.g.nv4j_log_max_mb, vim.g.nv4j_log_keep_days = old_max, old_keep
  lsp.report(P .. "options", ok_def and ok_max and k30 and k10 and ok_off,
    ("defaults %s, max_mb %s, keep 30 %s, keep 10 %s, both 0 %s"):format(tostring(ok_def), tostring(ok_max), tostring(k30),
      tostring(k10), tostring(ok_off)))
end)

case("twice", function()
  local d = fresh_dir("twice")
  write(d .. "/lsp.log", BIG .. "t")
  write(d .. "/test-old.log", "x"); age(d .. "/test-old.log", 30)
  local a = L.run(d, opts)
  local m1 = uv.fs_stat(d .. "/lsp.log.1").mtime.sec
  local b = L.run(d, opts)
  local ok = #a.rotated == 1 and #a.deleted == 1 and #b.rotated == 0 and #b.deleted == 0 and read(d .. "/lsp.log.1") == BIG .. "t"
    and uv.fs_stat(d .. "/lsp.log.1").mtime.sec == m1 and not exists(d .. "/lsp.log")
  lsp.report(P .. "twice", ok, ("first %d+%d, second %d+%d"):format(#a.rotated, #a.deleted, #b.rotated, #b.deleted))
end)

case("wired", function()
  local init = read(vim.fn.stdpath("config") .. "/init.lua") or ""
  local a = init:find('require("nv4j.logrotate")', 1, true)
  local b = init:find("_set_filename", 1, true)
  lsp.report(P .. "wired", a ~= nil and b ~= nil and a < b, ("logrotate at %s, _set_filename at %s"):format(tostring(a), tostring(b)))
end)

pcall(vim.fn.delete, TMP, "rf")
return lsp.finish()
