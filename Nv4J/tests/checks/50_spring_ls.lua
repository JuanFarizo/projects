-- P2 Spring Boot language server. Run via tests/run.sh. Spec: specs/features/spring-language-server.md.
--  attached    : an LSP client named `spring-boot` is attached to the fixture's application.properties
--                and initialized <= 10 s after jdt.ls is ready (budget in specs/001-architecture.md). The server
--                starts with the first Java buffer, so this overlaps jdt.ls's import: "initialized", not indexed.
--  props_first : the first completion on `server.po`, sent 1.0 s after the client is initialized (same
--                pin as P1's cold_first, D13: a request in the same millisecond finds the server's
--                property index still empty), lists `server.port`, round trip <= 400 ms.
--  props_warm  : warm completion p95 over 100 samples <= 150 ms, `server.port` in every list.
--  props_hover : hover on `server.port` returns text naming the key, <= 500 ms.
--  rss         : resident memory of the Spring LS process (a child of this nvim) <= 1.5 GB hard
--                limit; above the 1 GB budget it is printed in the detail.
--  yml_java_attached : the same client is on application-dev.yml (own filetype detection) and the Java buffer.
--  bundles     : jdt.ls was started with the five Spring LS extension jars plus the java-debug bundle,
--                and lists the command sts.java.addClasspathListener.
--  server_jvm  : the Spring LS JVM is nv4j.jdk's server JDK (>= 21), not the JDK 21 run.sh puts on PATH.
--  disabled    : with vim.g.nv4j_spring = false a newly opened Java buffer gets no client.
--  plain_maven : a plain Maven project (release 21, no Spring Boot, /tmp/nv4j/plain21) gets jdt.ls but no
--                spring-boot client (Java or application.properties), no Spring jars, no second process.
--  loose_file  : a loose .java file gets no spring-boot client and no process.
--  detect      : the shared Spring Boot rule (nv4j/root.lua): Gradle version catalog = Boot, a pom with only a
--                spring-boot.version property or Boot in a comment = not Boot, an aggregator whose module is Boot
--                = Boot project; nv4j.run and nv4j.spring agree.
--  off_at_start: a child nvim started with g:nv4j_spring = false loads no plugin: no :SpringBoot command, no
--                vscode-spring-boot / sts commands in vim.lsp.commands (positive control: same child without the flag).
-- Timings: /tmp/nv4j/logs/latency.jsonl (spring_ready, spring_props_first, spring_props_warm_p95,
-- spring_hover). The fixture file is only edited in memory and restored.
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local P = "50_spring_ls."
local READY_BUDGET_MS, FIRST_BUDGET_MS, WARM_BUDGET_MS, HOVER_BUDGET_MS = 10000, 400, 150, 500
local RSS_BUDGET_KB, RSS_HARD_KB = 1024 * 1024, 1536 * 1024
local NAME = "spring-boot"

local fixture = vim.env.NV4J_FIXTURE
local jbuf = lsp.open(fixture .. "/src/main/java/demo/DemoApplication.java")
local jdtls = lsp.wait_ready(jbuf, 120000)
local t_ready = E.now()
if not jdtls then
  lsp.report(P .. "attached", false, "jdtls not ready (prerequisite)")
  return lsp.finish()
end

-- The user opens application.properties: filetype comes from Neovim's own detection.
vim.cmd("edit " .. vim.fn.fnameescape(fixture .. "/src/main/resources/application.properties"))
local pbuf = vim.api.nvim_get_current_buf()
local orig = vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)
local function spring_client()
  local c = vim.lsp.get_clients({ bufnr = pbuf, name = NAME })[1]
  return c and c.initialized and not c:is_stopped() and c or nil
end
vim.wait(READY_BUDGET_MS + 20000, function() return spring_client() ~= nil end, 20)
local client = spring_client()
local ready_ms = E.now() - t_ready
E.log("spring_ready", client and ready_ms or -1, 1)
local names = table.concat(vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({ bufnr = pbuf })), ",")
lsp.report(P .. "attached", client ~= nil and ready_ms <= READY_BUDGET_MS,
  client and ("initialized %.0f ms after jdt.ls ready (budget %d), filetype %s"):format(ready_ms, READY_BUDGET_MS, vim.bo[pbuf].filetype)
    or ("no '%s' client on application.properties after %.0f ms (filetype %s, clients: %s)"):format(
      NAME, ready_ms, vim.bo[pbuf].filetype, names ~= "" and names or "none"))
if not client then
  for _, c in ipairs({ "props_first", "props_warm", "props_hover", "rss" }) do
    lsp.report(P .. c, false, "no '" .. NAME .. "' client (see attached)")
  end
  return lsp.finish()
end

local function complete()
  local t0 = E.now()
  local r = client:request_sync("textDocument/completion",
    { textDocument = { uri = vim.uri_from_bufnr(pbuf) }, position = { line = 0, character = 9 } }, 10000, pbuf)
  local ms = E.now() - t0
  if not r then return { items = {}, ms = ms, err = "timeout" } end
  if r.err then return { items = {}, ms = ms, err = vim.inspect(r.err) } end
  local res = r.result or {}
  return { items = res.items or res, ms = ms }
end
local function has_port(items)
  for i, it in ipairs(items) do
    if it.label == "server.port" then return i end
  end
end
local function labels(items, n)
  local t = {}
  for i = 1, math.min(n, #items) do t[#t + 1] = items[i].label end
  return table.concat(t, ", ")
end

local t_client = E.now()
local ok_all, err = pcall(function()
  E.set(pbuf, { "server.po" })
  vim.wait(10000, function() return E.now() >= t_client + 1000 end, 5)
  local first = complete()
  local rank = has_port(first.items)
  E.log("spring_props_first", first.ms, 1)
  lsp.report(P .. "props_first", not first.err and rank ~= nil and first.ms <= FIRST_BUDGET_MS,
    first.err and ("error: " .. first.err)
      or ("%.0f ms (budget %d), server.port rank %s of %d: %s"):format(first.ms, FIRST_BUDGET_MS, tostring(rank), #first.items, labels(first.items, 5)))

  local samples, missing, errs = {}, 0, 0
  for _ = 1, 100 do
    local r = complete()
    samples[#samples + 1] = r.ms
    if r.err then errs = errs + 1 elseif not has_port(r.items) then missing = missing + 1 end
  end
  table.sort(samples)
  local p95 = samples[95]
  E.log("spring_props_warm_p95", p95, 100)
  lsp.report(P .. "props_warm", errs == 0 and missing == 0 and p95 <= WARM_BUDGET_MS,
    ("p95 %.1f ms (budget %d) over 100, server.port missing in %d, errors %d"):format(p95, WARM_BUDGET_MS, missing, errs))

  E.restore(pbuf, orig)
  local at = E.line_of(pbuf, "^server%.port")
  local t0 = E.now()
  local h = at and client:request_sync("textDocument/hover",
    { textDocument = { uri = vim.uri_from_bufnr(pbuf) }, position = { line = at, character = 3 } }, 10000, pbuf)
  local ms = E.now() - t0
  local c = h and h.result and h.result.contents
  local text = type(c) == "table" and (c.value or table.concat(vim.tbl_map(function(x) return type(x) == "table" and x.value or x end, c), "\n")) or c or ""
  E.log("spring_hover", ms, 1)
  lsp.report(P .. "props_hover", text:find("server.port", 1, true) ~= nil and ms <= HOVER_BUDGET_MS,
    ("%.0f ms (budget %d): %s"):format(ms, HOVER_BUDGET_MS, (text ~= "" and text or vim.inspect(h and (h.err or h.result))):sub(1, 120):gsub("%s+", " ")))

  local pid = vim.trim(vim.fn.system({ "pgrep", "-P", tostring(vim.fn.getpid()), "-f", "spring-boot-language-server|vscode-spring-boot-tools" })):match("^(%d+)")
  local rss = pid and tonumber(vim.trim(vim.fn.system({ "ps", "-o", "rss=", "-p", pid }))) or nil
  lsp.report(P .. "rss", rss ~= nil and rss <= RSS_HARD_KB,
    rss and ("%.0f MB (budget %d MB, hard limit %d MB)%s"):format(rss / 1024, RSS_BUDGET_KB / 1024, RSS_HARD_KB / 1024,
      rss > RSS_BUDGET_KB and " OVER BUDGET" or "") or "Spring LS process (child of this nvim) not found")
end)
E.restore(pbuf, orig)
if not ok_all then lsp.report(P .. "props", false, "error: " .. tostring(err)) end

-- Where the client attaches, what jdt.ls loads, which JVM runs it, and where it must NOT run
-- (Review Focus 1 and 2, specs/features/spring-language-server.md "Gating and JDK cases").
local function spring_on(buf)
  return vim.lsp.get_clients({ bufnr = buf, name = NAME })[1]
end
local function spring_pids()
  local out = vim.fn.systemlist({ "pgrep", "-P", tostring(vim.fn.getpid()), "-f", "spring-boot-language-server|vscode-spring-boot-tools" })
  return vim.tbl_filter(function(l) return l:match("^%d+$") ~= nil end, out)
end
local function wait_attach(buf, ms)
  vim.wait(ms, function() return spring_on(buf) ~= nil end, 20)
  return spring_on(buf)
end
local ok2, err2 = pcall(function()
  -- yml with Neovim's own filetype detection, and the Java buffer opened first.
  vim.cmd("edit " .. vim.fn.fnameescape(fixture .. "/src/main/resources/application-dev.yml"))
  local ybuf = vim.api.nvim_get_current_buf()
  local yc = wait_attach(ybuf, 5000)
  local jc = spring_on(jbuf)
  lsp.report(P .. "yml_java_attached", yc ~= nil and yc.id == client.id and jc ~= nil and jc.id == client.id,
    ("application-dev.yml (filetype %s): %s; DemoApplication.java: %s (one client: %s)"):format(vim.bo[ybuf].filetype,
      yc and "attached" or "none", jc and "attached" or "none", tostring(yc and jc and yc.id == jc.id)))

  -- jdt.ls got the Spring LS bundles next to LazyVim's java-debug bundle, and exposes their commands.
  local bundles = (jdtls.config.init_options or {}).bundles or {}
  local want = { "io.projectreactor.reactor-core.jar", "org.reactivestreams.reactive-streams.jar", "jdt-ls-commons.jar",
    "jdt-ls-extension.jar", "sts-gradle-tooling.jar" }
  local missing, has_debug = {}, false
  for _, w in ipairs(want) do
    local found = false
    for _, b in ipairs(bundles) do if vim.endswith(b, "/" .. w) then found = true end end
    if not found then missing[#missing + 1] = w end
  end
  for _, b in ipairs(bundles) do if b:find("com.microsoft.java.debug.plugin", 1, true) then has_debug = true end end
  local cmds = vim.tbl_get(jdtls.server_capabilities or {}, "executeCommandProvider", "commands") or {}
  local sts = vim.tbl_contains(cmds, "sts.java.addClasspathListener")
  lsp.report(P .. "bundles", #missing == 0 and has_debug and sts,
    ("%d bundles, Spring jars missing: %s, java-debug kept: %s, jdt.ls command sts.java.addClasspathListener: %s"):format(
      #bundles, #missing == 0 and "none" or table.concat(missing, ","), tostring(has_debug), tostring(sts)))

  -- The server JVM is nv4j.jdk's server JDK (>= 21), not PATH's java (run.sh puts a JDK 21 first on PATH).
  local pids = spring_pids()
  local cmdline = pids[1] and vim.trim(vim.fn.system({ "ps", "-o", "command=", "-p", pids[1] })) or ""
  local exe = cmdline:match("^(%S+/bin/java)%s")
  local expect = require("nv4j.jdk").server_home() .. "/bin/java"
  local path_java = vim.fn.exepath("java")
  local path_real = path_java ~= "" and vim.uv.fs_realpath(path_java) or nil
  local exe_real = exe and vim.uv.fs_realpath(exe) or nil
  local major
  local rel = io.open(vim.fs.dirname(vim.fs.dirname(expect)) .. "/release", "r")
  if rel then major = tonumber(rel:read("*a"):match('JAVA_VERSION="(%d+)')); rel:close() end
  local same = path_real ~= nil and path_real == exe_real
  lsp.report(P .. "server_jvm", exe == expect and (major or 0) >= 21 and not same,
    ("Spring LS runs on %s (expected %s, major %s), PATH java %s%s"):format(tostring(exe), expect, tostring(major),
      tostring(path_real), same and " SAME JDK: cannot tell PATH apart" or ""))

  -- Turned off: a new Java buffer of the same Boot project gets no client.
  vim.g.nv4j_spring = false
  local obuf = lsp.open(fixture .. "/src/main/java/demo/GreetingController.java")
  local oc = wait_attach(obuf, 3000)
  vim.g.nv4j_spring = nil
  lsp.report(P .. "disabled", oc == nil and #spring_pids() == 1,
    ("vim.g.nv4j_spring = false: GreetingController.java %s, Spring LS processes %d"):format(oc and "ATTACHED" or "no client", #spring_pids()))

  -- A plain Maven project (no Spring Boot, release 21) and a loose .java file: jdt.ls yes, Spring LS no.
  local dir = "/tmp/nv4j/plain21"
  vim.fn.delete(dir, "rf")
  vim.fn.mkdir(dir .. "/src/main/java/p21", "p")
  vim.fn.mkdir(dir .. "/src/main/resources", "p")
  vim.fn.writefile({
    '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>',
    "<groupId>p21</groupId><artifactId>plain21</artifactId><version>1</version>",
    "<properties><maven.compiler.release>21</maven.compiler.release>",
    "<project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties></project>",
  }, dir .. "/pom.xml")
  vim.fn.writefile({ "package p21;", "class Plain { int x; }" }, dir .. "/src/main/java/p21/Plain.java")
  vim.fn.writefile({ "server.port=9090" }, dir .. "/src/main/resources/application.properties")
  local mbuf = lsp.open(dir .. "/src/main/java/p21/Plain.java")
  local mj = lsp.wait_ready(mbuf, 120000)
  vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/src/main/resources/application.properties"))
  local mpbuf = vim.api.nvim_get_current_buf()
  local mc = wait_attach(mbuf, 3000) or spring_on(mpbuf)
  local mbundles = mj and ((mj.config.init_options or {}).bundles or {}) or {}
  local mspring = #vim.tbl_filter(function(b) return b:find("jdt-ls-extension.jar", 1, true) ~= nil end, mbundles)
  lsp.report(P .. "plain_maven", mj ~= nil and mj.id ~= jdtls.id and mc == nil and mspring == 0 and #spring_pids() == 1,
    ("plain Maven project: jdt.ls %s, spring-boot client on .java/.properties %s, Spring jars in its jdt.ls %d, Spring LS processes %d"):format(
      mj and "ready (own client)" or "NOT READY", mc and "ATTACHED" or "none", mspring, #spring_pids()))

  local ldir = "/tmp/nv4j/loose"
  vim.fn.delete(ldir, "rf")
  vim.fn.mkdir(ldir, "p")
  vim.fn.writefile({ "class Loose { }" }, ldir .. "/Loose.java")
  local lbuf = lsp.open(ldir .. "/Loose.java")
  local lc = wait_attach(lbuf, 3000)
  lsp.report(P .. "loose_file", lc == nil and #spring_pids() == 1,
    ("loose Loose.java: spring-boot client %s, Spring LS processes %d"):format(lc and "ATTACHED" or "none", #spring_pids()))
end)
if not ok2 then lsp.report(P .. "gating", false, "error: " .. tostring(err2)) end

local ok3, err3 = pcall(function()
  local root = require("nv4j.root")
  local tmp = "/tmp/nv4j/50_detect"
  vim.fn.delete(tmp, "rf")
  local function project(name, files)
    local d = tmp .. "/" .. name
    for f, body in pairs(files) do
      vim.fn.mkdir(vim.fs.dirname(d .. "/" .. f), "p")
      vim.fn.writefile(vim.split(body, "\n"), d .. "/" .. f)
    end
    return d
  end
  local cases = {
    { "fixture", fixture, true },
    { "catalog", project("catalog", {
      ["settings.gradle.kts"] = 'rootProject.name = "c"',
      ["build.gradle.kts"] = "plugins {\n  java\n  alias(libs.plugins.spring.boot)\n}\ndependencies { implementation(libs.spring.boot.starter.web) }",
      ["gradle/libs.versions.toml"] = '[plugins]\nspring-boot = { id = "org.springframework.boot", version = "3.5.13" }',
    }), true },
    { "catalog_toml_only", project("catalog2", {
      ["build.gradle"] = "plugins { id 'java' }\ndependencies { implementation libs.web }",
      ["gradle/libs.versions.toml"] = '[libraries]\nweb = { module = "org.springframework.boot:spring-boot-starter-web" }',
    }), true },
    { "property_only", project("prop", { ["pom.xml"] = "<project><properties><spring-boot.version>3.5.13</spring-boot.version></properties><groupId>x</groupId></project>" }), false },
    { "comment_only", project("comment", { ["pom.xml"] = "<project><!-- <groupId>org.springframework.boot</groupId> --><groupId>x</groupId></project>" }), false },
    { "starter_artifact", project("starter", { ["pom.xml"] = "<project><dependencies><dependency><groupId>${boot.group}</groupId><artifactId>spring-boot-starter-web</artifactId></dependency></dependencies></project>" }), true },
  }
  local agg = project("agg", { ["pom.xml"] = "<project><groupId>x</groupId><modules><module>app</module></modules></project>",
    ["app/pom.xml"] = "<project><parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId></parent></project>" })
  local bad, got = {}, {}
  for _, c in ipairs(cases) do
    local r = root.boot_build(c[2]) == true
    local s_ = require("nv4j.spring").is_boot(c[2]) == true
    local run_ = require("nv4j.run").is_boot(c[2]) == true
    got[#got + 1] = ("%s=%s"):format(c[1], tostring(r))
    if r ~= c[3] or s_ ~= c[3] or run_ ~= c[3] then bad[#bad + 1] = ("%s (want %s: rule %s spring %s run %s)"):format(c[1], tostring(c[3]), tostring(r), tostring(s_), tostring(run_)) end
  end
  local agg_ok = root.boot_build(agg) == false and require("nv4j.spring").is_boot(agg) == true
  got[#got + 1] = "aggregator(module Boot)=" .. tostring(agg_ok)
  lsp.report(P .. "detect", #bad == 0 and agg_ok, table.concat(got, ", ") .. (#bad > 0 and ("; WRONG: " .. table.concat(bad, "; ")) or ""))

  -- The flag set before startup: the plugin is not loaded (lazy.nvim cond). Unnamed buffer with filetype java
  -- (lazy ft trigger; nv4j.debug starts no jdt.ls for it) and, flag off only, the fixture's application.properties.
  local probe = table.concat({
    "enew", "setfiletype java",
    -- the properties file only with the flag off (with it on it would start a Spring LS in the child)
    "if get(g:, 'nv4j_spring', 1) is v:false | edit " .. fixture .. "/src/main/resources/application.properties | endif",
    "lua vim.wait(1500)",
    [[lua local n=0 for k in pairs(vim.lsp.commands) do if tostring(k):find('spring%-boot') or tostring(k):find('^sts') then n=n+1 end end ]]
      .. [[io.stdout:write(('PROBE cmd=%d lsp_cmds=%d loaded=%s\n'):format(vim.fn.exists(':SpringBoot'), n, tostring(package.loaded['spring_boot'] ~= nil)))]],
  }, "\n")
  vim.fn.writefile(vim.split(probe, "\n"), "/tmp/nv4j/50_probe.vim")
  local function child(flag)
    local args = { "nvim", "--headless" }
    if flag then vim.list_extend(args, { "--cmd", "let g:nv4j_spring = v:false" }) end
    vim.list_extend(args, { "-S", "/tmp/nv4j/50_probe.vim", "+qa!" })
    local out = vim.fn.system(args)
    return out:match("PROBE[^\n]*") or ("no probe line: " .. out:sub(-200):gsub("%s+", " "))
  end
  local off, on = child(true), child(false)
  lsp.report(P .. "off_at_start", off:find("cmd=0 lsp_cmds=0 loaded=false", 1, true) ~= nil and on:find("cmd=2 lsp_cmds=[1-9]%d* loaded=true") ~= nil,
    ("g:nv4j_spring=false: %s | default (control): %s"):format(off, on))
end)
if not ok3 then lsp.report(P .. "detect", false, "error: " .. tostring(err3)) end
lsp.finish()
