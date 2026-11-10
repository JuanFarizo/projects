-- :Nv4JLogs registry (nv4j/logs.lua), pure + headless, no jdt.ls. A temp tree /tmp/nv4j/d90-<pid> stands in for the log dirs; mtimes are set
-- with fs_utime against a fixed `now`.
--  order         : entries come newest first (mtime), across sources.
--  since         : "30m" / "2h" / "1d" / "7d" keep only files newer than the period; nil keeps all; junk is no filter.
--  rotated       : lsp-<project>-<pid>.log.1 and spring-route.log.1 are listed.
--  sources       : every source of the research list is found (lsp, spring-ls, route, jdt.ls per project, dap, capture, latency, profile).
--  tests_hidden  : test-*.log only with opts.tests (or opts.id = "test").
--  id_filter     : opts.id keeps one source.
--  extend        : a source registered at runtime shows up; same id replaces.
--  missing       : a dir that does not exist, and a source whose files() errors: no entry, no error.
--  fields        : size, mtime, age, label, path are right.
--  save_copies   : save() copies the bytes identically into <root>/<YYYYmmdd-HHMMSS>/, originals still there and unchanged; a second
--                  save in the same second makes a new folder; two files with one basename both survive.
--  save_command  : `:Nv4JLogs save <period>` path (logsui.command) saves everything in the period only.
--  command       : :Nv4JLogs exists after setup().
--  route_format  : spring-route.log lines are "YYYY-mm-dd HH:MM:SS [pid] message".
--  jdt_show      : show_jdt_logs opens the real LSP log (vim.lsp.log.get_filename), never stdpath("log")/lsp.log.
local lsp = require("lsp")
local L = require("nv4j.logs")
local P = "90_logs."
local TMP = "/tmp/nv4j/d90-" .. vim.fn.getpid()
local uv = vim.uv
local NOW = os.time()
vim.fn.delete(TMP, "rf")

local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "wb")); f:write(text); f:close()
end
local function read(path) local f = io.open(path, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
local function age(path, sec) uv.fs_utime(path, NOW - sec, NOW - sec) end
local function mk(rel, text, sec) local p = TMP .. "/" .. rel; write(p, text); age(p, sec); return p end

local dirs = { logs = TMP .. "/logs", state = TMP .. "/state", jdtls_data = TMP .. "/jdtls" }
mk("logs/lsp-appA-111.log", "a\n", 600)            -- 10m
mk("logs/lsp-appA-111.log.1", "a1\n", 3 * 3600)    -- 3h
mk("logs/lsp-projects-5.log", "p\n", 20 * 60)      -- 20m
mk("logs/spring-boot-ls.log", "s\n", 90 * 60)      -- 90m
mk("logs/spring-route.log", "r\n", 2 * 86400)      -- 2d
mk("logs/spring-route.log.1", "r1\n", 9 * 86400)   -- 9d
mk("jdtls/appA-12345678/.metadata/.log", "j\n", 30)
mk("jdtls/appB-87654321/.metadata/.log", "j2\n", 5 * 86400)
mk("state/dap.log", "d\n", 4 * 3600)
mk("state/completion-profile.jsonl", "{}\n", 1000)
mk("logs/lsp-capture-jdtls-1-20261110-000000.bin", "\0\1\2", 6 * 86400)
mk("logs/latency.jsonl", "{}\n", 7200)
mk("logs/test-20261110-000000.log", "t\n", 100)
write(TMP .. "/logs/notes.txt", "x")

local function ents(o) o = o or {}; o.dirs = dirs; o.now = NOW; return L.entries(o) end
local function ids(list) return vim.tbl_map(function(e) return e.id .. ":" .. vim.fs.basename(e.path) end, list) end
local function has(list, base) for _, e in ipairs(list) do if vim.fs.basename(e.path) == base then return true end end return false end
local function case(name, fn)
  local ok, err = pcall(fn)
  if not ok then lsp.report(P .. name, false, "error: " .. tostring(err)) end
end

case("order", function()
  local e = ents()
  local ok = #e > 5
  for i = 2, #e do if e[i - 1].mtime < e[i].mtime then ok = false end end
  lsp.report(P .. "order", ok and vim.fs.basename(e[1].path) == ".log" and vim.fs.basename(e[#e].path) == "spring-route.log.1",
    table.concat(vim.list_slice(ids(e), 1, 4), ", ") .. " ... " .. ids(e)[#e])
end)

case("since", function()
  local function n(s) return #ents({ since = s }) end
  local all, m30, h2, d1, d7 = n(nil), n("30m"), n("2h"), n("1d"), n("7d")
  local e30 = ents({ since = "30m" })
  local ok = all == 12 and m30 == 4 and h2 == 6 and d1 == 8 and d7 == 11 and n("junk") == all
    and has(e30, "lsp-appA-111.log") and not has(e30, "dap.log")
  lsp.report(P .. "since", ok, ("all %d, 30m %d (want 4), 2h %d (6), 1d %d (8), 7d %d (11)"):format(all, m30, h2, d1, d7))
end)

case("rotated", function()
  local e = ents()
  lsp.report(P .. "rotated", has(e, "lsp-appA-111.log.1") and has(e, "spring-route.log.1"), table.concat(ids(e), " "))
end)

case("sources", function()
  local e = ents()
  local got = {}
  for _, x in ipairs(e) do got[x.id] = (got[x.id] or 0) + 1 end
  local ok = got["lsp"] == 2 and got["lsp-projects"] == 1 and got["spring-ls"] == 1 and got["spring-route"] == 2 and got["jdtls"] == 2
    and got["dap"] == 1 and got["lsp-capture"] == 1 and got["latency"] == 1 and got["completion-profile"] == 1 and not has(e, "notes.txt")
  local jl = vim.tbl_filter(function(x) return x.id == "jdtls" end, e)
  ok = ok and jl[1].label:find("jdt.ls appA", 1, true) ~= nil
  lsp.report(P .. "sources", ok, vim.inspect(got))
end)

case("tests_hidden", function()
  local a, b, c = ents(), ents({ tests = true }), ents({ id = "test" })
  lsp.report(P .. "tests_hidden", not has(a, "test-20261110-000000.log") and has(b, "test-20261110-000000.log") and #c == 1,
    ("default %d, tests %d, id=test %d"):format(#a, #b, #c))
end)

case("id_filter", function()
  local e = ents({ id = "spring-route" })
  lsp.report(P .. "id_filter", #e == 2 and e[1].id == "spring-route", table.concat(ids(e), " "))
end)

case("extend", function()
  local made = mk("extra/my.log", "m\n", 5)
  L.register({ id = "mine", label = "mine", kind = "x", files = function() return { made } end })
  local e = ents({ id = "mine" })
  local first = #e == 1 and e[1].path == made and e[1].label == "mine my.log"
  L.register({ id = "mine", label = "mine2", kind = "x", files = function() return {} end })
  local replaced = #ents({ id = "mine" }) == 0
  for i, s in ipairs(L.SOURCES) do if s.id == "mine" then table.remove(L.SOURCES, i) break end end
  lsp.report(P .. "extend", first and replaced and not has(ents(), "my.log"), ("added %s, replaced %s"):format(tostring(first), tostring(replaced)))
end)

case("missing", function()
  local e = L.entries({ dirs = { logs = TMP .. "/nope", state = TMP .. "/nope2", jdtls_data = TMP .. "/nope3" }, now = NOW })
  L.register({ id = "boom", label = "b", kind = "x", files = function() error("boom") end })
  local ok, e2 = pcall(ents, { id = "boom" })
  for i, s in ipairs(L.SOURCES) do if s.id == "boom" then table.remove(L.SOURCES, i) break end end
  lsp.report(P .. "missing", #e == 0 and ok and #e2 == 0, ("missing dirs %d entries, failing source ok=%s"):format(#e, tostring(ok)))
end)

case("fields", function()
  local e = ents({ id = "dap" })[1]
  lsp.report(P .. "fields", e and e.size == 2 and e.mtime == NOW - 4 * 3600 and e.age == 4 * 3600 and e.path == TMP .. "/state/dap.log"
    and e.label == "nvim-dap dap.log" and L.age_str(e.age) == "4h", vim.inspect(e))
end)

case("save_copies", function()
  local root = TMP .. "/saved"
  local list = ents({ since = "1d" })
  local before = {}
  for _, e in ipairs(list) do before[e.path] = { read(e.path), uv.fs_stat(e.path).mtime.sec } end
  local d1, c1 = L.save(list, { dest_root = root, now = NOW })
  local same = #c1 == #list and #c1 > 0
  for i, e in ipairs(list) do
    same = same and c1[i] and read(c1[i]) == before[e.path][1]
    same = same and read(e.path) == before[e.path][1] and uv.fs_stat(e.path).mtime.sec == before[e.path][2]
  end
  local bin = ents({ id = "lsp-capture" })
  local dbin, cbin = L.save(bin, { dest_root = root, now = NOW })
  local d2 = L.save(list, { dest_root = root, now = NOW })
  local a, b = mk("x/dup.log", "one", 1), mk("y/dup.log", "two", 1)
  local d3, c3 = L.save({ a, b }, { dest_root = root, now = NOW + 5 })
  local dup = #c3 == 2 and read(c3[1]) == "one" and read(c3[2]) == "two"
  local _, none = L.save({}, { dest_root = root, now = NOW })
  lsp.report(P .. "save_copies", same and d1:match("/saved/%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d$") ~= nil and read(cbin[1]) == "\0\1\2"
    and d2 ~= d1 and d2 ~= dbin and dup and #none == 0,
    ("%d copied to %s, bytes same %s, second %s, dup %s"):format(#c1, d1, tostring(same), d2, tostring(dup)))
end)

case("command", function()
  L.setup()
  lsp.report(P .. "command", vim.fn.exists(":Nv4JLogs") == 2, "exists=" .. vim.fn.exists(":Nv4JLogs"))
end)

case("save_command", function()
  local ui = require("nv4j.logsui")
  local root = TMP .. "/savedcmd"
  local o_save, o_dirs, o_notify = L.save, L.dirs, vim.notify
  L.dirs = function() return dirs end
  L.save = function(items, opts) return o_save(items, { dest_root = root, now = os.time() }) end
  vim.notify = function() end
  ui.command({ "save", "30m" })
  L.save, L.dirs, vim.notify = o_save, o_dirs, o_notify
  local folders = vim.fn.glob(root .. "/*", true, true)
  local names = {}
  for _, f in ipairs(folders[1] and vim.fn.readdir(folders[1]) or {}) do names[#names + 1] = f end
  table.sort(names)
  lsp.report(P .. "save_command", #folders == 1 and table.concat(names, " ") == "completion-profile.jsonl jdt.ls_appA-12345678.log lsp-appA-111.log lsp-projects-5.log",
    ("%d folder(s): %s"):format(#folders, table.concat(names, " ")))
end)

case("route_format", function()
  local S = require("nv4j.spring")
  local path = require("nv4j.paths").logs .. "/spring-route.log"
  S.route_log("check 90 format probe")
  local last
  for l in io.lines(path) do last = l end
  lsp.report(P .. "route_format", last ~= nil and last:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d %[" .. uv.os_getpid() .. "%] check 90 format probe$") ~= nil, tostring(last))
end)

case("jdt_show", function()
  local real = vim.lsp.log.get_filename()
  vim.cmd("only")
  L.show_jdt_logs()
  local names = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do names[#names + 1] = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)) end
  local stale = vim.fn.stdpath("log") .. "/lsp.log"
  local has_real, has_stale = false, false
  for _, n in ipairs(names) do
    if n ~= "" and uv.fs_realpath(n) == uv.fs_realpath(real) then has_real = true end
    if n == stale then has_stale = true end
  end
  lsp.report(P .. "jdt_show", has_real and not has_stale and real ~= stale, "real " .. real .. ", windows " .. table.concat(names, " | "))
  vim.cmd("only")
end)

pcall(vim.fn.delete, TMP, "rf")
return lsp.finish()
