-- Per-session LSP log name (nv4j/paths.lua lsp_log, init.lua): lsp-<project>-<pid>.log so :LspLog shows only this session.
--  named_by_marker   a file under a dir with pom.xml -> lsp-<dir>-<pid>.log in /tmp/nv4j/logs, nearest marker wins
--  named_by_git      .git root when there is no build file
--  named_dir         no marker: the dir's own name; a file path gives its dir
--  sanitized         spaces and odd characters in the project name become "_"
--  runner_fixed      the test runner keeps lsp.log (00_boot reads it)
--  two_projects      two different projects give two different file names (the point of the change)
--  cleanup           logrotate deletes an old lsp-<project>-<pid>.log, keeps a fresh one, lsp.log and lsp.log.1
local lsp = require("lsp")
local paths = require("nv4j.paths")
local P = "81_lsplog_name."
local TMP = "/tmp/nv4j/lsplog-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
local function touch(p) vim.fn.mkdir(vim.fs.dirname(p), "p"); io.open(p, "w"):close() end
touch(TMP .. "/appointments-backend/pom.xml")
touch(TMP .. "/appointments-backend/src/main/java/A.java")
touch(TMP .. "/learnx/.git/HEAD")
touch(TMP .. "/learnx/src/B.java")
touch(TMP .. "/plain/C.java")
touch(TMP .. "/my project (1)/pom.xml")
local pid = vim.uv.os_getpid()
local function name(p) return paths.lsp_log(p, false) end

local a = name(TMP .. "/appointments-backend/src/main/java/A.java")
lsp.report(P .. "named_by_marker", a == ("/tmp/nv4j/logs/lsp-appointments-backend-%d.log"):format(pid), a)
local b = name(TMP .. "/learnx/src/B.java")
lsp.report(P .. "named_by_git", b == ("/tmp/nv4j/logs/lsp-learnx-%d.log"):format(pid), b)
local c = name(TMP .. "/plain/C.java")
lsp.report(P .. "named_dir", c:match("lsp%-plain%-%d+%.log$") ~= nil or c:match("lsp%-lsplog%-%d+%-%d+%.log$") ~= nil, c)
local d = name(TMP .. "/my project (1)/pom.xml")
lsp.report(P .. "sanitized", d == ("/tmp/nv4j/logs/lsp-my_project__1_-%d.log"):format(pid), d)
lsp.report(P .. "runner_fixed", paths.lsp_log(TMP, true) == "/tmp/nv4j/logs/lsp.log", paths.lsp_log(TMP, true))
lsp.report(P .. "two_projects", a ~= b, a .. " vs " .. b)

local dir = TMP .. "/logs"
vim.fn.mkdir(dir, "p")
for _, n in ipairs({ "lsp-old-1.log", "lsp-new-2.log", "lsp.log", "lsp.log.1" }) do touch(dir .. "/" .. n) end
vim.uv.fs_utime(dir .. "/lsp-old-1.log", 1, 1)
require("nv4j.logrotate").run(dir, { keep_days = 14 })
local function ex(n) return vim.uv.fs_stat(dir .. "/" .. n) ~= nil end
lsp.report(P .. "cleanup", not ex("lsp-old-1.log") and ex("lsp-new-2.log") and ex("lsp.log") and ex("lsp.log.1"),
  ("old %s new %s lsp.log %s .1 %s"):format(tostring(ex("lsp-old-1.log")), tostring(ex("lsp-new-2.log")), tostring(ex("lsp.log")), tostring(ex("lsp.log.1"))))
vim.fn.delete(TMP, "rf")
lsp.finish()
