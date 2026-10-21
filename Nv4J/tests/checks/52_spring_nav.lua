-- P2/P4 Spring navigation. Run via tests/run.sh. Spec: specs/features/spring-language-server.md
-- ("Completion and navigation (Task 4)").
--  attached     : prerequisite, the `spring-boot` client initialized on application.properties (+1.0 s pin).
--  hover_yml    : hover on `level` under `logging:` in application-dev.yml returns docs naming logging.level and its
--                 description, <= 500 ms, sent 1.0 s after the yml is opened (the 1.0 s pin of D13 / 50_spring_ls).
--  hover_yml_port: then `port` under `server:`: names server.port, <= 1000 ms (a regression limit, not the 500 ms
--                 budget: the server's first YAML hover of server.port costs 200-520 ms, trials c5-c7, Known limitations).
--  hover_props  : hover on spring.jpa.open-in-view in application.properties returns its docs, <= 500 ms.
--  definition   : `@Value("${server.port}")` in GreetingController: vim.lsp.buf.definition (every client of the
--                 buffer, what gd asks) lists application.properties at the `server.port=8080` line (and
--                 application-dev.yml); <= 500 ms.
--  mappings     : workspace/symbol `@/` on the Spring client lists the request mappings with their full paths
--                 and methods: /customers GET+POST, /customers/{id} GET+PUT (class prefix + method path), /hello.
--  beans        : workspace/symbol `@+` lists the beans: greetingController, customerController, devBanner (a @Bean
--                 with @Profile), customerRepository.
--  key          : <leader>sp is mapped (desc "Spring symbols"), and LazyVim's <leader>ss (Goto Symbol) is untouched.
--  picker       : <leader>sp in a Java buffer opens a Telescope picker with the beans and request mappings
--                 (17 entries on the fixture: 12 beans + 5 mappings), <= 1 s.
--  picker_jump  : typing `/hello` in that picker and <CR> opens GreetingController.java at the @GetMapping("/hello")
--                 line.
--  no_client    : <leader>sp in a buffer of a non-Boot project warns ("no Spring Boot language server") and opens
--                 no picker.
--  no_answer    : the Spring server never answers workspace/symbol (stubbed, timeout lowered to 300 ms): <leader>sp shows a
--                 WARN ("no answer from the Spring Boot LS"), no picker.
-- Timings: /tmp/nv4j/logs/latency.jsonl (spring_hover_yml, spring_definition, spring_picker).
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local P = "52_spring_nav."
local NAME = "spring-boot"
local HOVER_MS, PICKER_MS = 500, 1000
local PORT_HOVER_LIMIT_MS = 1000 -- server.port's first yml hover is 200-520 ms server side (trial c5): a regression limit

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

local jbuf = lsp.open(src .. "DemoApplication.java")
local jdtls = lsp.wait_ready(jbuf, 120000)
vim.cmd("edit " .. vim.fn.fnameescape(res .. "application.properties"))
local pbuf = vim.api.nvim_get_current_buf()
local client = jdtls and wait_spring(pbuf, 30000)
local t_client = E.now()
lsp.report(P .. "attached", client ~= nil, client and ("client %d initialized"):format(client.id)
  or ("no initialized '%s' client (jdt.ls %s)"):format(NAME, jdtls and "ready" or "NOT ready"))
if not client then return lsp.finish() end
vim.wait(2000, function() return E.now() >= t_client + 1000 end, 5)

local function hover_text(buf, line, col)
  local t0 = E.now()
  local r = client:request_sync("textDocument/hover",
    { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = line, character = col } }, 10000, buf)
  local ms = E.now() - t0
  local c = r and r.result and r.result.contents
  local text = type(c) == "table" and (c.value or table.concat(vim.tbl_map(function(x) return type(x) == "table" and x.value or x end, c), "\n")) or c or ""
  return text, ms, r and r.err
end
local function oneline(s) return (s:gsub("%s+", " ")):sub(1, 140) end

local ok_all, err = pcall(function()
  -- Hover
  local t_open = E.now()
  vim.cmd("edit " .. vim.fn.fnameescape(res .. "application-dev.yml"))
  local ybuf = vim.api.nvim_get_current_buf()
  if not wait_spring(ybuf, 5000) then error("no spring-boot client on application-dev.yml") end
  -- Sent 1.0 s after the yml is opened (the user moves to the key first).
  vim.wait(2000, function() return E.now() >= t_open + 1000 end, 5)
  local yl = E.line_of(ybuf, "^  level:")
  local text, ms = hover_text(ybuf, yl, 3)
  E.log("spring_hover_yml", ms, 1)
  lsp.report(P .. "hover_yml", text:find("logging.level", 1, true) ~= nil and text:find("Log levels", 1, true) ~= nil and ms <= HOVER_MS,
    ("%.0f ms (budget %d): %s"):format(ms, HOVER_MS, oneline(text)))
  local ptext, pms = hover_text(ybuf, E.line_of(ybuf, "^  port:"), 3)
  E.log("spring_hover_yml_port", pms, 1)
  lsp.report(P .. "hover_yml_port", ptext:find("server.port", 1, true) ~= nil and pms <= PORT_HOVER_LIMIT_MS,
    ("first yml hover of server.port %.0f ms (regression limit %d; the 500 ms budget is on logging.level above, Known limitations): %s"):format(
      pms, PORT_HOVER_LIMIT_MS, oneline(ptext)))
  local pl = E.line_of(pbuf, "^spring%.jpa%.open%-in%-view")
  text, ms = hover_text(pbuf, pl, 12)
  lsp.report(P .. "hover_props", text:find("spring.jpa.open-in-view", 1, true) ~= nil and #text > 40 and ms <= HOVER_MS,
    ("%.0f ms (budget %d): %s"):format(ms, HOVER_MS, oneline(text)))

  -- Go to definition from @Value through Neovim's own request to every client of the buffer.
  local gbuf = lsp.open(src .. "GreetingController.java")
  if not wait_spring(gbuf, 10000) then error("no spring-boot client on GreetingController.java") end
  local orig = vim.api.nvim_buf_get_lines(gbuf, 0, -1, false)
  local vl = E.line_of(gbuf, "@Value%(")
  vim.api.nvim_buf_set_lines(gbuf, vl, vl + 1, false, { '    @Value("${server.port}")' })
  vim.wait(1000) -- the server reconciles after a 500 ms debounce
  vim.api.nvim_set_current_buf(gbuf)
  vim.api.nvim_win_set_cursor(0, { vl + 1, 18 })
  local items
  local t0 = E.now()
  vim.lsp.buf.definition({ on_list = function(o) items = o.items end })
  vim.wait(5000, function() return items ~= nil end, 2)
  local dms = E.now() - t0
  E.restore(gbuf, orig)
  E.log("spring_definition", dms, 1)
  local props_line = E.line_of(pbuf, "^server%.port=") -- 0-based
  local hit_props, hit_yml = false, false
  local where = {}
  for _, it in ipairs(items or {}) do
    where[#where + 1] = ("%s:%d"):format(vim.fs.basename(it.filename), it.lnum)
    if vim.endswith(it.filename, "/src/main/resources/application.properties") and it.lnum == props_line + 1 then hit_props = true end
    if vim.endswith(it.filename, "/src/main/resources/application-dev.yml") then hit_yml = true end
  end
  lsp.report(P .. "definition", hit_props and hit_yml and dms <= HOVER_MS,
    ("%.0f ms (budget %d), %d locations: %s (want application.properties:%d and application-dev.yml)"):format(dms, HOVER_MS,
      #(items or {}), table.concat(where, ", "), props_line + 1))

  -- workspace/symbol on the Spring client
  local function symbols(q)
    local r = client:request_sync("workspace/symbol", { query = q }, 10000, gbuf)
    return r and r.result or {}
  end
  local maps = symbols("@/")
  local names = vim.tbl_map(function(s) return s.name end, maps)
  local want = { "@/customers -- GET", "@/customers -- POST", "@/customers/{id} -- GET", "@/customers/{id} -- PUT", "@/hello -- GET" }
  local missing = vim.tbl_filter(function(w) return not vim.tbl_contains(names, w) end, want)
  lsp.report(P .. "mappings", #missing == 0, ("%d mappings: %s; missing: %s"):format(#maps, table.concat(names, " | "),
    #missing == 0 and "none" or table.concat(missing, ", ")))
  local beans = symbols("@+")
  local bnames = table.concat(vim.tbl_map(function(s) return s.name end, beans), " | ")
  local bmissing = vim.tbl_filter(function(b) return not bnames:find("'" .. b .. "'", 1, true) end,
    { "greetingController", "customerController", "devBanner", "customerRepository" })
  lsp.report(P .. "beans", #bmissing == 0, ("%d beans; missing: %s; %s"):format(#beans,
    #bmissing == 0 and "none" or table.concat(bmissing, ", "), bnames:sub(1, 160)))

  -- <leader>sp (config/keymaps.lua loads on VeryLazy, after -c commands: load it now, idempotent, as 31/41 do)
  pcall(require, "config.keymaps")
  local m =vim.fn.maparg("<leader>sp", "n", false, true)
  local ss = vim.fn.maparg("<leader>ss", "n", false, true)
  lsp.report(P .. "key", m.desc ~= nil and m.desc:find("Spring") ~= nil and (ss.desc or ""):find("Spring") == nil,
    ("<leader>sp: %s; <leader>ss: %s"):format(m.desc or "UNMAPPED", ss.desc or tostring(ss.rhs or "unmapped")))

  local function prompt_buf()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(w)
      if vim.bo[b].filetype == "TelescopePrompt" then return b end
    end
  end
  local function press()
    local mm = vim.fn.maparg("<leader>sp", "n", false, true)
    if mm.callback then mm.callback() elseif mm.rhs then vim.cmd(mm.rhs:gsub("^<[Cc]md>", ""):gsub("<[Cc][Rr]>$", "")) else error("<leader>sp unmapped") end
  end
  vim.api.nvim_set_current_buf(gbuf)
  local tp = E.now()
  local pok, perr = pcall(press)
  local pb
  vim.wait(PICKER_MS * 3, function() pb = prompt_buf(); return pb ~= nil end, 5)
  local picker = pb and require("telescope.actions.state").get_current_picker(pb)
  local n = 0
  if picker then
    vim.wait(PICKER_MS * 3, function() n = picker.manager and picker.manager:num_results() or 0; return n >= 17 end, 5)
  end
  local pms = E.now() - tp
  E.log("spring_picker", pms, 1)
  lsp.report(P .. "picker", picker ~= nil and n >= 17 and pms <= PICKER_MS,
    not pok and ("error: " .. tostring(perr)) or ("%s, %d entries (want >= 17), %.0f ms (budget %d)"):format(
      picker and ("picker '" .. tostring(picker.prompt_title) .. "'") or "NO picker", n, pms, PICKER_MS))
  if picker then
    picker:set_prompt("/hello")
    vim.wait(2000, function() return picker.manager:num_results() >= 1 and picker.manager:num_results() < n end, 10)
    vim.wait(200)
    require("telescope.actions").select_default(pb)
    vim.wait(2000, function() return vim.api.nvim_buf_get_name(0):find("GreetingController.java", 1, true) ~= nil and prompt_buf() == nil end, 10)
    local at = vim.api.nvim_win_get_cursor(0)[1] - 1
    local want_line = E.line_of(vim.api.nvim_get_current_buf(), '@GetMapping%("/hello"%)')
    local name = vim.fs.basename(vim.api.nvim_buf_get_name(0))
    lsp.report(P .. "picker_jump", name == "GreetingController.java" and want_line ~= nil and math.abs(at - want_line) <= 1,
      ("after `/hello` <CR>: %s line %d (@GetMapping(\"/hello\") at %s)"):format(name, at + 1, tostring(want_line and want_line + 1)))
  else
    lsp.report(P .. "picker_jump", false, "no picker (see picker)")
  end
  local stray = prompt_buf()
  if stray then pcall(require("telescope.actions").close, stray) end

  -- No Spring client: a warning, no picker.
  local dir = "/tmp/nv4j/52_plain"
  vim.fn.delete(dir, "rf")
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({ "class Plain { }" }, dir .. "/Plain.java")
  vim.cmd("edit " .. dir .. "/Plain.java")
  local notes = E.capture_notify()
  pcall(press)
  vim.wait(500)
  local warned = false
  for _, nn in ipairs(notes) do if nn.msg:find("no Spring Boot language server", 1, true) then warned = true end end
  lsp.report(P .. "no_client", warned and prompt_buf() == nil,
    ("warning %s, picker %s"):format(warned and "shown" or "MISSING", prompt_buf() and "OPENED" or "none"))

  -- A Spring server that never answers workspace/symbol: a visible warning after the timeout, no picker.
  local nav = require("nv4j.spring_nav")
  local real, real_to = client.request, nav.TIMEOUT_MS
  client.request = function(self, method, params, handler, bufnr)
    if method == "workspace/symbol" then return true, 999998 end -- swallowed: no answer ever
    return real(self, method, params, handler, bufnr)
  end
  nav.TIMEOUT_MS = 300
  vim.api.nvim_set_current_buf(gbuf)
  local notes2 = E.capture_notify()
  local t_na = E.now()
  pcall(press)
  local hung
  vim.wait(2000, function()
    for _, nn in ipairs(notes2) do if nn.msg:find("no answer from the Spring Boot LS", 1, true) and nn.level == vim.log.levels.WARN then hung = E.now() - t_na return true end end
    return false
  end, 10)
  client.request, nav.TIMEOUT_MS = real, real_to
  lsp.report(P .. "no_answer", hung ~= nil and prompt_buf() == nil,
    ("server swallows workspace/symbol: warning %s, picker %s"):format(hung and ("after %.0f ms (timeout 300)"):format(hung) or "MISSING",
      prompt_buf() and "OPENED" or "none"))
end)
if not ok_all then lsp.report(P .. "cases", false, "error: " .. tostring(err)) end
lsp.finish()
