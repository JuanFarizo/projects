-- P2/P4 Spring completion through blink.cmp (what the menu shows: tests/lib/completion.lua M.menu runs blink's
-- own pipeline, every source of the buffer, transform_items, fuzzy, sorts). Run via tests/run.sh.
-- Spec: specs/features/spring-language-server.md ("Completion and navigation (Task 4)").
--  attached     : prerequisite, the `spring-boot` client initialized on application.properties; every request
--                 below is sent >= 1.0 s after that (the 50_spring_ls pin).
--  props_port   : application.properties `server.po` -> server.port in the menu's top 3.
--  props_ddl    : application.properties `spring.jpa.hibernate.ddl` -> spring.jpa.hibernate.ddl-auto top 3.
--  yml_port     : application-dev.yml, nested `server:` / `  po` -> port (server.port) top 3.
--  yml_dotted   : application-dev.yml, top-level `server.po` -> server.port top 3.
--  yml_first    : the first yml completion round trip (blink pipeline) <= 400 ms.
--  value_keys   : GreetingController `@Value("${}")` (cursor after `${`): the project's keys are listed
--                 (demo.greeting.text, demo.greeting.times, server.port), demo.greeting.text in the top 3.
--  value_project_late: the same list: zz.sample.flag (set only in the fixture's application.properties, sorts after
--                 every Boot key) in the top 3: project keys outside Boot's namespaces come first (trial c9).
--  value_prefix : `@Value("${server.po}")` -> server.port top 3.
--  value_first  : the first `@Value` completion round trip <= 400 ms, sent 1.0 s after GreetingController.java is
--                 opened (like the 1.0 s pins of D13 and 50_spring_ls; trial c4).
--  value_warm   : `@Value("${}")` warm p95 over 100 (the longest Spring list, about 1850 items) <= 150 ms.
--  yml_warm     : nested yml `po` warm p95 over 100 <= 150 ms.
--  profile      : GreetingConfig `@Profile("")` (mini.pairs closes the quote) -> dev (from application-dev.yml)
--                 top 3, sent 1.0 s after the file is opened (trial c8).
--  profile_clean: no snippet items inside that string literal (trim, trial c3).
--  snippets_kept: guard for that trim: `fo` in a method body still lists snippets.
--  yml_no_snippets: no snippet items in application*.yml with the Spring client (friendly-snippets' docker-compose
--                 `po` ranked above port; trim, trial c3); port rank 1.
--  broken_props : application.properties with syntax errors (key without value, value without key, bad
--                 escape, a line with only `=`); `server.po` on the next valid line -> server.port top 3,
--                 the client alive (same server process, not stopped).
--  broken_yml   : application-dev.yml with bad indentation and an unclosed flow sequence; `server.po` on the
--                 next valid line -> server.port top 3, client alive.
--  alive_after  : after both broken files, a properties completion still answers (the server did not crash).
--  at_regression: P1's spring_annotation_list with the Spring client on the same Java buffer: `@` lists
--                 RestController in the top 5; the detail counts the Spring items in the visible top 20.
-- Timings: /tmp/nv4j/logs/latency.jsonl (spring_yml_first, spring_value_first, spring_value_warm_p95,
-- spring_yml_warm_p95). Buffers are edited in memory only and restored.
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local C = require("completion")
local P = "51_spring_completion."
local NAME = "spring-boot"
local TOP, FIRST_MS, WARM_MS = 3, 400, 150

local fx = vim.env.NV4J_FIXTURE
local res = fx .. "/src/main/resources/"
local src = fx .. "/src/main/java/demo/"

local function spring(buf)
  local c = vim.lsp.get_clients({ bufnr = buf, name = NAME })[1]
  return c and c.initialized and not c:is_stopped() and c or nil
end
local function wait_spring(buf, ms)
  vim.wait(ms, function() return spring(buf) ~= nil end, 20)
  return spring(buf)
end
local function spring_pid()
  return vim.trim(vim.fn.system({ "pgrep", "-P", tostring(vim.fn.getpid()), "-f", "spring-boot-language-server|vscode-spring-boot-tools" })):match("^(%d+)")
end

local jbuf = lsp.open(src .. "DemoApplication.java")
local jdtls = lsp.wait_ready(jbuf, 120000)
vim.cmd("edit " .. vim.fn.fnameescape(res .. "application.properties"))
local pbuf = vim.api.nvim_get_current_buf()
local client = jdtls and wait_spring(pbuf, 30000)
local t_client = E.now()
lsp.report(P .. "attached", client ~= nil, client and ("client %d initialized, filetype %s"):format(client.id, vim.bo[pbuf].filetype)
  or ("no initialized '%s' client on application.properties (jdt.ls %s)"):format(NAME, jdtls and "ready" or "NOT ready"))
if not client then return lsp.finish() end
local fuzzy = C.blink()
if not fuzzy then
  lsp.report(P .. "blink", false, "blink.cmp not loaded")
  return lsp.finish()
end
local pid0 = spring_pid()
vim.wait(2000, function() return E.now() >= t_client + 1000 end, 5)

--- The visible menu for `lines` in buf, cursor at (lnum, col) (0-based; col defaults to the end of the line).
--- The buffer is shown in the current window (M.menu moves that window's cursor) and restored afterwards.
local function menu(buf, lines, lnum, col, settle_ms)
  vim.api.nvim_set_current_buf(buf)
  return C.scratch(buf, function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    if settle_ms then vim.wait(settle_ms) end
    col = col or #lines[lnum + 1]
    local m, why = C.menu(buf, lnum, col)
    if not m then return { items = {}, ms = 0, err = why } end
    return m
  end)
end
local function label_is(l) return function(it) return it.label == l end end
local function key_is(k) return function(it) return it.label == k or it.filterText == k end end
local function from_spring(it) return it.client_id == client.id end
--- PASS when pred's item is in the top `top`; detail names the rank and the first labels.
local function ranked(case, m, pred, want, top, extra)
  local r = C.rank(m.items, pred)
  local ok = not m.err and r ~= nil and r <= (top or TOP)
  lsp.report(P .. case, ok and (extra == nil or extra.ok),
    m.err and ("menu error: " .. m.err)
      or ("rank(%s)=%s (budget <= %d) of %d, %.0f ms%s shown=[%s]"):format(want, tostring(r), top or TOP, #m.items, m.ms,
        extra and (" " .. extra.detail) or "", C.labels(m.items, 5)))
end
local function lines_with(buf, pat, text)
  local l = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local at = C.find_line(buf, pat)
  l[at + 1] = text
  return l, at
end

local ok_all, err = pcall(function()
  -- application.properties
  ranked("props_port", menu(pbuf, { "server.po" }, 0), label_is("server.port"), "server.port")
  ranked("props_ddl", menu(pbuf, { "server.port=8080", "spring.jpa.hibernate.ddl" }, 1),
    label_is("spring.jpa.hibernate.ddl-auto"), "spring.jpa.hibernate.ddl-auto")

  -- application-dev.yml (Neovim's own filetype detection)
  vim.cmd("edit " .. vim.fn.fnameescape(res .. "application-dev.yml"))
  local ybuf = vim.api.nvim_get_current_buf()
  if not wait_spring(ybuf, 5000) then error("no spring-boot client on application-dev.yml") end
  local ynested = { "server:", "  po" }
  local yfirst = menu(ybuf, ynested, 1)
  E.log("spring_yml_first", yfirst.ms, 1)
  ranked("yml_port", yfirst, key_is("server.port"), "port (server.port)")
  lsp.report(P .. "yml_first", not yfirst.err and #yfirst.items > 0 and yfirst.ms <= FIRST_MS,
    ("%.0f ms (budget %d), %d items"):format(yfirst.ms, FIRST_MS, #yfirst.items))
  local ysnip = 0
  for _, it in ipairs(yfirst.items) do if it.source_id == "snippets" then ysnip = ysnip + 1 end end
  local yrank = C.rank(yfirst.items, key_is("server.port"))
  lsp.report(P .. "yml_no_snippets", not yfirst.err and ysnip == 0 and yrank == 1,
    ("%d snippet items in the yml menu (friendly-snippets' docker-compose `po` -> ports:), port rank %s"):format(ysnip, tostring(yrank)))
  ranked("yml_dotted", menu(ybuf, { "server.po" }, 0), label_is("server.port"), "server.port")

  -- @Value / @Profile in Java (the same client on the Java buffers)
  local t_open = E.now()
  local gbuf = lsp.open(src .. "GreetingController.java")
  if not wait_spring(gbuf, 10000) then error("no spring-boot client on GreetingController.java") end
  -- First request 1.0 s after the Java file is opened (trial c4): sent in the same millisecond as didOpen, the
  -- Spring LS answered in 506-557 ms in 2 of 3 runs (its own handling of the new file), 75-127 ms 1.5 s later.
  vim.wait(2000, function() return E.now() >= t_open + 1000 end, 5)
  local vlines, vat = lines_with(gbuf, "@Value%(", '    @Value("${}")')
  local vcol = #'    @Value("${'
  local vfirst = menu(gbuf, vlines, vat, vcol)
  E.log("spring_value_first", vfirst.ms, 1)
  local missing = {}
  for _, k in ipairs({ "demo.greeting.text", "demo.greeting.times", "server.port" }) do
    if not C.rank(vfirst.items, label_is(k)) then missing[#missing + 1] = k end
  end
  ranked("value_keys", vfirst, label_is("demo.greeting.text"), "demo.greeting.text", TOP,
    { ok = #missing == 0, detail = "project keys missing: " .. (#missing == 0 and "none" or table.concat(missing, ",")) })
  -- A project key that sorts after every Boot key (zz.sample.flag in application.properties): without the
  -- project-key boost it is item 1853 of the server's list and blink's max_items (200) cuts it (trial c9).
  ranked("value_project_late", vfirst, label_is("zz.sample.flag"), "zz.sample.flag")
  lsp.report(P .. "value_first", not vfirst.err and #vfirst.items > 0 and vfirst.ms <= FIRST_MS,
    ("%.0f ms (budget %d; sources answered in %.0f ms), %d items"):format(vfirst.ms, FIRST_MS, vfirst.lsp_ms or -1, #vfirst.items))
  local plines = lines_with(gbuf, "@Value%(", '    @Value("${server.po}")')
  ranked("value_prefix", menu(gbuf, plines, vat, #'    @Value("${server.po'), label_is("server.port"), "server.port")

  -- warm p95 over 100 (no I/O inside the loop)
  local function warm(buf, lines, lnum, col, pred)
    local samples, misses = {}, 0
    vim.api.nvim_set_current_buf(buf)
    C.scratch(buf, function()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      for _ = 1, 100 do
        local m = C.menu(buf, lnum, col)
        samples[#samples + 1] = m and m.ms or 1e9
        if not (m and C.rank(m.items, pred)) then misses = misses + 1 end
      end
    end)
    return C.pct(samples, 95), misses
  end
  local vp95, vmiss = warm(gbuf, vlines, vat, vcol, label_is("demo.greeting.text"))
  E.log("spring_value_warm_p95", vp95, 100)
  lsp.report(P .. "value_warm", vp95 <= WARM_MS and vmiss == 0,
    ("p95 %.1f ms (budget %d) over 100, demo.greeting.text missing in %d"):format(vp95, WARM_MS, vmiss))
  local yp95, ymiss = warm(ybuf, ynested, 1, 4, key_is("server.port"))
  E.log("spring_yml_warm_p95", yp95, 100)
  lsp.report(P .. "yml_warm", yp95 <= WARM_MS and ymiss == 0,
    ("p95 %.1f ms (budget %d) over 100, port missing in %d"):format(yp95, WARM_MS, ymiss))

  local t_copen = E.now()
  local cbuf = lsp.open(src .. "GreetingConfig.java")
  if not wait_spring(cbuf, 10000) then error("no spring-boot client on GreetingConfig.java") end
  -- Same 1.0 s pin after opening (trial c8: sent at once, the server answered `@Profile("")` with no items once in
  -- a full run).
  vim.wait(2000, function() return E.now() >= t_copen + 1000 end, 5)
  local prof, pat = lines_with(cbuf, "@Profile%(", '    @Profile("")')
  local pm = menu(cbuf, prof, pat, #'    @Profile("')
  ranked("profile", pm, function(it) return it.label == "dev" and from_spring(it) end, "dev")
  local psnip = #vim.tbl_filter(function(it) return it.source_id == "snippets" end, pm.items)
  lsp.report(P .. "profile_clean", not pm.err and psnip == 0 and #pm.items > 0,
    ("%d snippet items inside the string literal, %d items in all: [%s]"):format(psnip, #pm.items, C.labels(pm.items, 4)))
  -- Guard for the trim above: snippets still show in a Java statement position.
  local sl, sat = lines_with(cbuf, "return \"dev: \"", "        fo")
  local sm = menu(cbuf, sl, sat)
  local ssnip = #vim.tbl_filter(function(it) return it.source_id == "snippets" end, sm.items)
  lsp.report(P .. "snippets_kept", not sm.err and ssnip > 0,
    ("%d snippet items for `fo` in a method body (expected > 0): [%s]"):format(ssnip, C.labels(sm.items, 5)))

  -- Review Focus 3: broken files. The server parses after its 500 ms reconcile debounce: wait 1.5 s first.
  local broken_props = {
    "server.port=8080",
    "spring.jpa.open-in-view",
    "=value-without-key",
    "=",
    "demo.greeting.text=bad \\uZZZZ escape",
    "spring.main.banner-mode=: :: =",
    "server.po",
  }
  ranked("broken_props", menu(pbuf, broken_props, #broken_props - 1, nil, 1500), label_is("server.port"), "server.port", TOP,
    { ok = spring(pbuf) ~= nil and spring_pid() == pid0, detail = ("client alive %s, same process %s"):format(tostring(spring(pbuf) ~= nil), tostring(spring_pid() == pid0)) })
  local broken_yml = {
    "server:",
    "  port: 8081",
    " demo:",
    "      greeting:",
    "   text: [unclosed, flow",
    "logging:",
    "\tlevel: tab-indented",
    "server.po",
  }
  ranked("broken_yml", menu(ybuf, broken_yml, #broken_yml - 1, nil, 1500), label_is("server.port"), "server.port", TOP,
    { ok = spring(ybuf) ~= nil and spring_pid() == pid0, detail = ("client alive %s, same process %s"):format(tostring(spring(ybuf) ~= nil), tostring(spring_pid() == pid0)) })
  vim.wait(1500) -- let the server reconcile the restored files too
  local after = menu(pbuf, { "server.port=8080", "spring.jpa.hibernate.ddl" }, 1)
  local r = C.rank(after.items, label_is("spring.jpa.hibernate.ddl-auto"))
  lsp.report(P .. "alive_after", r ~= nil and spring(pbuf) ~= nil and spring_pid() == pid0,
    ("after the broken files: ddl-auto rank %s, client %s, server pid %s (was %s)"):format(tostring(r),
      spring(pbuf) and "alive" or "GONE", tostring(spring_pid()), tostring(pid0)))

  -- P1 regression: `@` with the Spring client on the same buffer.
  local abuf = C.open_ready(lsp, src .. "CustomerController.java", 120000)
  local on = abuf and wait_spring(abuf, 10000)
  if not on then
    lsp.report(P .. "at_regression", false, "no spring-boot client on CustomerController.java (the regression needs it)")
  else
    vim.api.nvim_set_current_buf(abuf)
    C.scratch(abuf, function()
      local at = C.find_line(abuf, "^@RequestMapping") + 1
      vim.api.nvim_buf_set_lines(abuf, at, at, false, { "@" })
      local m, why = C.menu(abuf, at, 1)
      if not m then return lsp.report(P .. "at_regression", false, "menu: " .. tostring(why)) end
      local rk = C.rank(m.items, label_is("RestController"))
      local n_spring, raw_spring = 0, 0
      for i = 1, math.min(20, #m.items) do if from_spring(m.items[i]) then n_spring = n_spring + 1 end end
      for _, it in ipairs(m.by_source.lsp or {}) do if from_spring(it) then raw_spring = raw_spring + 1 end end
      lsp.report(P .. "at_regression", rk ~= nil and rk <= 5,
        ("rank(RestController)=%s (budget <= 5) of %d, Spring items %d in the top 20 (%d from the server), shown=[%s]"):format(
          tostring(rk), #m.items, n_spring, raw_spring, C.labels(m.items, 6)))
    end)
  end
end)
if not ok_all then lsp.report(P .. "cases", false, "error: " .. tostring(err)) end
lsp.finish()
