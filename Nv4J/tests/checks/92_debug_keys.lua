-- IntelliJ debugger keys (nv4j/debugkeys.lua, specs/features/debug-run.md "IntelliJ keys"). Run via tests/run.sh.
-- HEAVY: real jdt.ls + a debuggee. The Maven fixture is COPIED to /tmp/nv4j (src + pom.xml) and a KeysRunner<N> planted in
-- the copy BEFORE jdt.ls starts (as check 40 does with LateRunner). Keys are sent as real notation through nvim_feedkeys
-- ("<F8>"), so the mapping is what is tested; every assertion reads the DAP stopped frame (name / line) or an evaluate result.
--  before_session  : no session: F8 / S-F8 are the diagnostic maps (maparg), F7/F9/A-F9/A-F8/S-F7 are not mapped, <D-F8>|<C-F8> (platform key) toggles a breakpoint (maparg).
--  session_maps    : at the first stop F7, F8, S-F8, F9, A-F9, A-F8 (n and x), S-F7 are the debug maps (desc "Debug:").
--  step_over       : F8 moves the stopped frame from line 1 to line 2 of run().
--  step_into       : F7 on the line that calls helper() stops in helper().
--  step_out        : S-F8 is back in run(), line >= the call line.
--  resume          : F9 runs on to the next breakpoint.
--  run_to_cursor   : A-F9 with the cursor on a later line stops exactly there.
--  evaluate        : A-F8 on a word (normal) and on a selection (visual) returns the expression value (text of the evaluate result).
--  smart_step_into : S-F7 does not error and the session stays alive (the Java adapter has no stepInTargets: plain step into).
--  restore         : after dap.terminate F8 / S-F8 are the diagnostic maps again (same rhs as before) and the debug maps are gone.
--  second_session  : a second launch installs the maps again and F8 steps; they are restored again after it.
--  no_orphan       : the marked JVM is alive before the last terminate and gone <= 10 s after.
-- Controls (NV4J_92_CONTROL env is not used; tests/lib/control_92.sh patches nv4j/debugkeys.lua): nomaps, noremove, f8into.
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
-- keymaps load on VeryLazy, after -c commands: load them now (as check 65 does)
pcall(require, "lazyvim.config.keymaps")
pcall(require, "config.keymaps")
local P = "92_debug_keys."
local BREAK_BUDGET_MS, STEP_BUDGET_MS, ORPHAN_WAIT_MS = 20000, 15000, 10000
local MARKER = "nv4j.check=92_debug_keys"

local fixture = vim.env.NV4J_FIXTURE
local TMP = "/tmp/nv4j/keys92-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
for _, name in ipairs({ "src", "pom.xml" }) do vim.fn.system({ "cp", "-R", fixture .. "/" .. name, TMP .. "/" }) end
TMP = vim.uv.fs_realpath(TMP)
local function cleanup()
  vim.fn.system({ "pkill", "-f", MARKER })
  vim.fn.delete(TMP, "rf")
end
vim.fn.system({ "pkill", "-f", MARKER })

local src = TMP .. "/src/main/java/demo/"
local runner = "KeysRunner" .. os.time()
-- line numbers are found by pattern below
vim.fn.writefile({
  "package demo;",
  "",
  "import org.springframework.boot.ApplicationArguments;",
  "import org.springframework.boot.ApplicationRunner;",
  "import org.springframework.stereotype.Component;",
  "",
  "@Component",
  "public class " .. runner .. " implements ApplicationRunner {",
  "    @Override",
  "    public void run(ApplicationArguments args) {",
  "        int a = 2;",
  "        int b = helper(a) + 3;",
  "        int c = helper(b);",
  "        int d = c * 2;",
  "        System.out.println(d);",
  "        int e = d + 1;",
  "        System.out.println(e + d);",
  "        System.out.println(\"done\");",
  "    }",
  "",
  "    int helper(int x) {",
  "        int y = x + 1;",
  "        return y * 2;",
  "    }",
  "}",
}, src .. runner .. ".java")

local errs = {}
local function wait_until(ms, pred)
  local deadline = E.now() + ms
  while E.now() < deadline do
    local ok, r = pcall(pred)
    if ok and r then return true end
    if not ok then errs[#errs + 1] = tostring(r):gsub("\n.*", "") end
    vim.wait(50)
  end
  local ok, r = pcall(pred)
  return ok and r or false
end

local starts = {}
local orig_start = vim.lsp.start
vim.lsp.start = function(config, ...)
  if config and config.name == "jdtls" then starts[#starts + 1] = tostring(config.root_dir) end
  return orig_start(config, ...)
end

local buf = lsp.open(src .. "DemoApplication.java")
local client, why = lsp.wait_ready(buf, 180000)
lsp.report(P .. "attached", client ~= nil and vim.uv.fs_realpath(client.config.root_dir or "") == TMP,
  client and ("jdtls ready, root %s (want %s)"):format(tostring(client.config.root_dir), TMP) or tostring(why))
if not client then
  cleanup()
  return lsp.finish()
end

local dap = require("dap")
dap.listeners.on_config["nv4j_92"] = function(c)
  c = vim.deepcopy(c)
  if c.type == "java" then c.vmArgs = ((c.vmArgs and (c.vmArgs .. " ")) or "") .. "-D" .. MARKER end
  return c
end
local function alive() return vim.fn.system({ "pgrep", "-f", MARKER }) ~= "" end

local function dap_req(cmd, args)
  local session = dap.session()
  if not session then return nil end
  local res
  session:request(cmd, args, function(e, r) res = e and false or r end)
  wait_until(5000, function() return res ~= nil end)
  return res or nil
end

local stops, last_stop = 0, nil
dap.listeners.after.event_stopped["nv4j_92"] = function(_, body) stops = stops + 1; last_stop = body end

local function frame()
  local s = dap.session()
  if not s or not last_stop then return nil end
  local st = dap_req("stackTrace", { threadId = last_stop.threadId, levels = 1 })
  return st and st.stackFrames and st.stackFrames[1]
end
local function at(f) return f and ("%s line %s"):format(f.name, tostring(f.line)) or "no frame" end

-- Presses a key as real notation and waits for the next `stopped` event; returns the top frame (nil: no stop in time).
local function press(key)
  local n = stops
  vim.api.nvim_feedkeys(vim.keycode(key), "mx", false)
  if not wait_until(STEP_BUDGET_MS, function() return stops > n end) then return nil, "no stop within " .. STEP_BUDGET_MS .. " ms after " .. key end
  return frame()
end

local function map(lhs, mode)
  local m = vim.fn.maparg(lhs, mode or "n", false, true)
  return (m and m.lhs) and m or nil
end
local function is_debug(lhs, mode)
  local m = map(lhs, mode)
  return m ~= nil and (m.desc or ""):find("^Debug:") ~= nil
end
local function is_diag(lhs, want_rhs)
  local m = map(lhs)
  return m ~= nil and m.rhs == want_rhs and (m.desc or ""):find("diagnostic") ~= nil
end

local DEBUG_KEYS = { "<F7>", "<F8>", "<S-F8>", "<F9>", "<A-F9>", "<A-F8>", "<S-F7>" }

local ok_all, err = pcall(function()
  local configs
  wait_until(120000, function()
    configs = nil
    require("jdtls.dap").fetch_main_configs({}, function(c) configs = c or false end)
    wait_until(20000, function() return configs ~= nil end)
    for _, c in ipairs(configs or {}) do if c.mainClass == "demo.DemoApplication" then return true end end
    return false
  end)
  local cfg
  for _, c in ipairs(configs or {}) do if c.mainClass == "demo.DemoApplication" then cfg = vim.deepcopy(c) end end
  if not cfg then
    lsp.report(P .. "configs", false, "no launch config for demo.DemoApplication")
    return
  end
  cfg.args = "--server.port=0"

  local rbuf = lsp.open(src .. runner .. ".java")
  local L = function(pat) return E.line_of(rbuf, pat) + 1 end
  local l_a, l_b, l_call, l_d, l_print_d, l_e, l_print_ed =
    L("int a = 2;"), L("int b = helper%(a%) %+ 3;"), L("int c = helper%(b%);"), L("int d = c %* 2;"),
    L("System%.out%.println%(d%);"), L("int e = d %+ 1;"), L("System%.out%.println%(e %+ d%);")
  local l_done = L('System%.out%.println%("done"%);')
  local bps = require("dap.breakpoints")

  -- before_session (the diagnostic keys exist, debug ones are not mapped)
  local pre_f8, pre_sf8 = map("<F8>"), map("<S-F8>")
  local appkey = require("nv4j.debugkeys").bpkey()
  local bp_map = map(appkey)
  local none = true
  for _, k in ipairs({ "<F7>", "<F9>", "<A-F9>", "<A-F8>", "<S-F7>" }) do if map(k) then none = false end end
  lsp.report(P .. "before_session", is_diag("<F8>", "]d") and is_diag("<S-F8>", "[d") and none and bp_map ~= nil
      and (bp_map.desc or ""):find("breakpoint") ~= nil,
    ("F8 -> %s (%s), S-F8 -> %s, other debug keys unmapped %s, %s -> %s"):format(tostring(pre_f8 and pre_f8.rhs), tostring(pre_f8 and pre_f8.desc),
      tostring(pre_sf8 and pre_sf8.rhs), tostring(none), appkey, tostring(bp_map and bp_map.desc)))

  -- Breakpoints: line 1 of run() (set by the platform breakpoint key, proves that map), and print(d) (for F9).
  vim.api.nvim_set_current_buf(rbuf)
  vim.api.nvim_win_set_cursor(0, { l_a, 0 })
  vim.api.nvim_feedkeys(vim.keycode(appkey), "mx", false)
  local placed = false
  for _, b in ipairs((bps.get(rbuf) or {})[rbuf] or {}) do if b.line == l_a then placed = true end end
  bps.set({}, rbuf, l_print_d)
  vim.api.nvim_set_current_buf(buf)

  -- 1. session 1
  local n0 = stops
  dap.run(cfg)
  local started = wait_until(BREAK_BUDGET_MS + 20000, function() return stops > n0 end)
  local f = started and frame() or nil
  lsp.report(P .. "breakpoint_hit", placed and f ~= nil and f.line == l_a and f.name:find(runner, 1, true) ~= nil,
    ("breakpoint set by %s: %s; stopped at %s (want %s line %d)"):format(appkey, tostring(placed), at(f), runner, l_a))
  if not f then return end

  local okmaps = true
  local bad = {}
  for _, k in ipairs(DEBUG_KEYS) do if not is_debug(k) then okmaps = false; bad[#bad + 1] = k end end
  if not is_debug("<A-F8>", "x") then okmaps = false; bad[#bad + 1] = "x:<A-F8>" end
  lsp.report(P .. "session_maps", okmaps, okmaps and "7 debug maps installed (n; A-F8 also x)" or ("not debug maps: " .. table.concat(bad, " ")))

  vim.api.nvim_set_current_buf(rbuf)
  local f2, e2 = press("<F8>")
  lsp.report(P .. "step_over", f2 ~= nil and f2.line == l_b and f2.name:find(runner, 1, true) ~= nil,
    f2 and ("F8: %s (want line %d)"):format(at(f2), l_b) or e2)
  local f3, e3 = press("<F8>")
  lsp.report(P .. "step_over_call_line", f3 ~= nil and f3.line == l_call, f3 and ("second F8: %s (want line %d)"):format(at(f3), l_call) or e3)
  local f4, e4 = press("<F7>")
  lsp.report(P .. "step_into", f4 ~= nil and f4.name:find("helper", 1, true) ~= nil,
    f4 and ("F7 on the call line: %s (want helper)"):format(at(f4)) or e4)
  local f5, e5 = press("<S-F8>")
  lsp.report(P .. "step_out", f5 ~= nil and f5.name:find("run", 1, true) ~= nil and f5.name:find("helper", 1, true) == nil
      and f5.line >= l_call and f5.line <= l_d,
    f5 and ("S-F8: %s (want run, line %d..%d)"):format(at(f5), l_call, l_d) or e5)
  local f6, e6 = press("<F9>")
  lsp.report(P .. "resume", f6 ~= nil and f6.line == l_print_d and f6.name:find(runner, 1, true) ~= nil,
    f6 and ("F9: %s (want line %d, the next breakpoint)"):format(at(f6), l_print_d) or e6)
  vim.api.nvim_set_current_buf(rbuf)
  vim.api.nvim_win_set_cursor(0, { l_print_ed, 0 })
  local f7, e7 = press("<A-F9>")
  lsp.report(P .. "run_to_cursor", f7 ~= nil and f7.line == l_print_ed, f7 and ("A-F9 with the cursor on line %d: %s"):format(l_print_ed, at(f7)) or e7)

  -- evaluate: normal mode (word under the cursor `d` = 40), then a visual selection `e + d` (= 81)
  local line = vim.api.nvim_buf_get_lines(rbuf, l_print_ed - 1, l_print_ed, false)[1]
  local col_e = line:find("e + d", 1, true)
  local ev = require("nv4j.debugkeys")
  ev.last_eval = nil
  vim.api.nvim_win_set_cursor(0, { l_print_ed, col_e + 3 }) -- on `d`
  vim.api.nvim_feedkeys(vim.keycode("<A-F8>"), "mx", false)
  wait_until(5000, function() return ev.last_eval ~= nil end)
  local n_eval = ev.last_eval
  pcall(function() vim.cmd("silent! only") end)
  ev.last_eval = nil
  vim.api.nvim_set_current_buf(rbuf)
  vim.api.nvim_win_set_cursor(0, { l_print_ed, col_e - 1 })
  vim.api.nvim_feedkeys(vim.keycode("v4l<A-F8>"), "mx", false) -- v + 4 right = "e + d"
  wait_until(5000, function() return ev.last_eval ~= nil end)
  local v_eval = ev.last_eval
  lsp.report(P .. "evaluate", n_eval ~= nil and n_eval.expr == "d" and n_eval.result == "40"
      and v_eval ~= nil and v_eval.expr == "e + d" and v_eval.result == "81",
    ("normal: %s; visual: %s (want d = 40, e + d = 81)"):format(vim.inspect(n_eval, { newline = " ", indent = "" }), vim.inspect(v_eval, { newline = " ", indent = "" })))

  -- smart step into: Java has no stepInTargets; plain step in; the session must survive. Cursor line 7 has no call to enter, so a step.
  vim.api.nvim_set_current_buf(rbuf)
  local f8, e8 = press("<S-F7>")
  lsp.report(P .. "smart_step_into", f8 ~= nil and dap.session() ~= nil, f8 and ("S-F7: %s, session alive"):format(at(f8)) or e8)

  -- no_orphan needs the JVM seen alive now
  local was_alive = alive()
  dap.terminate()
  wait_until(ORPHAN_WAIT_MS, function() return dap.session() == nil end)
  wait_until(2000, function() return not map("<F7>") end)
  local restored = is_diag("<F8>", "]d") and is_diag("<S-F8>", "[d") and is_diag("<F20>", "[d")
  local gone_maps = true
  for _, k in ipairs({ "<F7>", "<F9>", "<A-F9>", "<A-F8>", "<S-F7>" }) do if map(k) then gone_maps = false end end
  if map("<A-F8>", "x") then gone_maps = false end
  lsp.report(P .. "restore", restored and gone_maps,
    ("after terminate: F8 -> %s (%s), S-F8 -> %s, other debug maps gone %s"):format(tostring(map("<F8>") and map("<F8>").rhs), tostring(map("<F8>") and map("<F8>").desc),
      tostring(map("<S-F8>") and map("<S-F8>").rhs), tostring(gone_maps)))
  wait_until(ORPHAN_WAIT_MS, function() return not alive() end)

  -- 2. second session
  bps.clear()
  bps.set({}, rbuf, l_a)
  local n1 = stops
  dap.run(cfg)
  local again = wait_until(BREAK_BUDGET_MS + 20000, function() return stops > n1 end)
  local g = again and frame() or nil
  vim.api.nvim_set_current_buf(rbuf)
  local g2, ge = nil, nil
  if g then g2, ge = press("<F8>") end
  -- terminfo names of the shifted/alt keys (what a terminal without the kitty protocol, and tmux, sends): F20 = S-F8, F57 = A-F9, F56 = A-F8, F19 = S-F7
  local alias_ok = true
  for _, k in ipairs({ "<F20>", "<F57>", "<F56>", "<F19>" }) do if not is_debug(k) then alias_ok = false end end
  local g3, g4, ge2
  if g2 then
    g3, ge2 = press("<F8>") -- line 13, the call
    if g3 then g4 = press("<F7>") end -- into helper
  end
  local g5 = g4 and press("<F20>") or nil -- S-F8 by its terminfo name: out of helper
  local aliased = g5 ~= nil and g5.name:find("helper", 1, true) == nil and g5.name:find(runner, 1, true) ~= nil
  local maps2 = is_debug("<F8>") and is_debug("<F7>") and alias_ok and aliased
  lsp.report(P .. "second_session", g ~= nil and g.line == l_a and g2 ~= nil and g2.line == l_b and maps2,
    ("second launch stopped %s, F8 -> %s, debug maps %s, terminfo aliases F19/F20/F56/F57 debug maps %s, F20 (S-F8) left helper: %s%s"):format(at(g), at(g2), tostring(maps2), tostring(alias_ok), at(g5), ge and (" (" .. ge .. ")") or ""))

  local alive2 = alive()
  dap.terminate()
  wait_until(ORPHAN_WAIT_MS, function() return dap.session() == nil end)
  local gone = wait_until(ORPHAN_WAIT_MS, function() return not alive() end)
  lsp.report(P .. "restore_again", is_diag("<F8>", "]d") and is_diag("<S-F8>", "[d") and is_diag("<F20>", "[d") and not map("<F7>") and not map("<F56>"),
    ("after the second terminate: F8 -> %s, F7 mapped %s"):format(tostring(map("<F8>") and map("<F8>").desc), tostring(map("<F7>") ~= nil)))
  lsp.report(P .. "no_orphan", was_alive and alive2 and gone,
    ("JVM alive in session 1 %s, in session 2 %s, gone after the last terminate %s"):format(tostring(was_alive), tostring(alive2), tostring(gone)))
  local other = vim.tbl_filter(function(x) return vim.uv.fs_realpath(x) ~= TMP end, starts)
  lsp.report(P .. "one_jdtls", #starts > 0 and #other == 0, ("%d jdtls starts, %d with another root"):format(#starts, #other))
end)
if not ok_all then lsp.report(P .. "error", false, tostring(err)) end
if #errs > 0 then io.stdout:write("\nnote: errors raised while waiting: " .. table.concat(errs, " | "):sub(1, 400) .. "\n") end
pcall(function() dap.terminate() end)
cleanup()
lsp.finish()
