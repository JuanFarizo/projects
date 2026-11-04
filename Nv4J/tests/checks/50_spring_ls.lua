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
--  off_at_start: a child nvim started with g:nv4j_spring = false loads no plugin; an unnamed java buffer
--                (not Boot) also does not load it (only a Boot file does). Control: lazy.load still loads
--                it when the flag is on, not when the flag is off.
--  want_install : Mason ensure_installed only when cwd is a Spring Boot project (and the flag is on).
--  should_load  : spring-boot.nvim loads only for a Boot Java/yml/properties file, not a plain pom or unnamed buffer.
--  wired        : nv4j.spring start() patches spring_boot.jdtls (the test does not call route_jdtls itself).
--  jdtls_route  : two jdt.ls clients: the one whose root owns the file / projectUri, not clients[1].
--  route_paths  : symlinked projectUri, case folding only where the FS is case-insensitive, current-buffer
--                 fallback only when no root contains the path (+ spring-route.log line), plain jdt.ls never the fallback.
--  route_wrapped: stub jdt.ls clients through spring_boot.jdtls.execute_command / get_jdtls_client: B's projectUri
--                 reaches only B (and its answer returns), a plain owner is still the owner, unmatched -> current buffer.
--  classpath_all: addClasspathListener on every Boot jdt.ls (answering one waits, others async: a silent one does not
--                 block), never on a plain one; the answer is the Boot jdt.ls's.
--  classpath_attach: late-starting Boot jdt.ls (LspAttach) registered once however many buffers attach, none for
--                 plain or already registered; removeClasspathListener reaches every Boot jdt.ls and clears the state.
--  classpath_retry: a Boot jdt.ls that rejects addClasspathListener (error reply) is retried on a timer (capped; not
--                 after remove/stop/success); route_paths also covers the single-slash file:/ projectUri the Spring LS sends.
--  two_boot_shared: real second Boot project: second jdt.ls, ONE Spring LS process and client on both, listener on the
--                 second jdt.ls through the real LspAttach path.
--  two_boot_index: the same Spring LS (workspace folder = project A only) answers for what exists only in B: B's request
--                 mapping and bean (workspace/symbol) and B's configuration property key (completion in B's
--                 application.properties), A's own still there. No workspace folder is needed: B arrives by jdt.ls classpath events.
--  route_log_nomatch / route_log_nobuf / route_log_rejected: the three spring-route.log lines of nv4j/spring.lua (M.route_log),
--                 each written in its situation (unmatched projectUri; current buffer without a jdt.ls; addClasspathListener
--                 rejected, 1 + 4 retries) and not otherwise (matched, buffer in a root, accepted, rejected after remove).
--                 Controls n50a (route_log a no-op) and n50b (lines written always).
--  ensure_package_installing: Mason registry stubbed; while the package is_installing ensure_package never calls install()
--                 (polls every 2 s), once it stops installing it calls it exactly once. Control n50b (guard removed).
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
end)
if not ok3 then lsp.report(P .. "detect", false, "error: " .. tostring(err3)) end

local ok4, err4 = pcall(function()
  -- Mason install and plugin load only for Boot (cwd / Boot file).
  local S = require("nv4j.spring")
  local here = vim.fn.getcwd()
  local noboot = "/tmp/nv4j/50_need"
  vim.fn.delete(noboot, "rf")
  vim.fn.mkdir(noboot, "p")
  vim.fn.writefile({ "<project><groupId>x</groupId></project>" }, noboot .. "/pom.xml")
  vim.cmd("lcd " .. vim.fn.fnameescape(noboot))
  local want_plain = S.want_install()
  vim.cmd("lcd " .. vim.fn.fnameescape(fixture))
  local want_boot = S.want_install()
  local prev_flag = vim.g.nv4j_spring
  vim.g.nv4j_spring = false
  local want_off = S.want_install()
  vim.g.nv4j_spring = prev_flag
  vim.cmd("lcd " .. vim.fn.fnameescape(here))
  lsp.report(P .. "want_install", want_plain == false and want_boot == true and want_off == false,
    ("cwd plain pom %s (want false); cwd Boot fixture %s (want true); flag off on fixture %s (want false)")
      :format(tostring(want_plain), tostring(want_boot), tostring(want_off)))

  local boot_java = fixture .. "/src/main/java/demo/DemoApplication.java"
  local boot_yml = fixture .. "/src/main/resources/application.properties"
  local plain_java = "/tmp/nv4j/plain21/src/main/java/p21/Plain.java"
  lsp.report(P .. "should_load", S.should_load(boot_java) == true and S.should_load(boot_yml) == true
      and S.should_load(plain_java) == false and S.should_load("") == false,
    ("Boot java %s, Boot properties %s, plain java %s, unnamed %s")
      :format(tostring(S.should_load(boot_java)), tostring(S.should_load(boot_yml)),
        tostring(S.should_load(plain_java)), tostring(S.should_load(""))))

  -- Flag off: plugin stays unloaded. Unnamed java is not Boot: plugin stays unloaded (no ft=java).
  -- Control: lazy.load still loads it when the flag is on.
  local probe_line = [[lua local n=0 for k in pairs(vim.lsp.commands) do if tostring(k):find('spring%-boot') or tostring(k):find('^sts') then n=n+1 end end ]]
    .. [[io.stdout:write(('PROBE cmd=%d lsp_cmds=%d loaded=%s\n'):format(vim.fn.exists(':SpringBoot'), n, tostring(package.loaded['spring_boot'] ~= nil)))]]
  vim.fn.writefile({ "enew", "setfiletype java", "lua vim.wait(1500)", probe_line }, "/tmp/nv4j/50_probe.vim")
  vim.fn.writefile({
    "lua require('lazy').load({ plugins = { 'spring-boot.nvim' } })",
    "lua vim.wait(1500)",
    probe_line,
  }, "/tmp/nv4j/50_probe_load.vim")
  local function child(flag, script)
    local args = { "nvim", "--headless" }
    if flag then vim.list_extend(args, { "--cmd", "let g:nv4j_spring = v:false" }) end
    vim.list_extend(args, { "-S", script, "+qa!" })
    local out = vim.fn.system(args)
    return out:match("PROBE[^\n]*") or ("no probe line: " .. out:sub(-200):gsub("%s+", " "))
  end
  local off, unnamed = child(true, "/tmp/nv4j/50_probe.vim"), child(false, "/tmp/nv4j/50_probe.vim")
  local load_on, load_off = child(false, "/tmp/nv4j/50_probe_load.vim"), child(true, "/tmp/nv4j/50_probe_load.vim")
  lsp.report(P .. "off_at_start", off:find("cmd=0 lsp_cmds=0 loaded=false", 1, true) ~= nil
      and unnamed:find("loaded=false", 1, true) ~= nil
      and load_on:find("loaded=true", 1, true) ~= nil
      and load_off:find("loaded=false", 1, true) ~= nil,
    ("flag off unnamed: %s | default unnamed (must not load): %s | lazy.load default: %s | lazy.load flag off: %s")
      :format(off, unnamed, load_on, load_off))
end)
if not ok4 then lsp.report(P .. "want_install", false, "error: " .. tostring(err4)) end

-- Two Boot projects, one Spring LS (nv4j/spring.lua route_jdtls). Stub jdt.ls clients under /tmp/nv4j/50_route
-- (A, B Boot; C plain Maven; D Boot) drive the wrapper through the plugin's own entry point
-- (spring_boot.jdtls.execute_command), vim.lsp.get_clients / get_client_by_id patched for one call and restored in a
-- finally, the classpath state restored too.
local ROUTE = "/tmp/nv4j/50_route"
local function route_setup()
  vim.fn.delete(ROUTE, "rf")
  local boot_pom = {
    "<project><modelVersion>4.0.0</modelVersion><parent><groupId>org.springframework.boot</groupId>",
    "<artifactId>spring-boot-starter-parent</artifactId><version>3.5.13</version></parent>",
    "<groupId>r</groupId><artifactId>%s</artifactId><version>1</version></project>",
  }
  for _, n in ipairs({ "A", "B", "D" }) do
    vim.fn.mkdir(ROUTE .. "/" .. n .. "/src", "p")
    local l = vim.deepcopy(boot_pom)
    l[3] = l[3]:format(n)
    vim.fn.writefile(l, ROUTE .. "/" .. n .. "/pom.xml")
  end
  vim.fn.mkdir(ROUTE .. "/C/src", "p")
  vim.fn.writefile({ "<project><groupId>r</groupId><artifactId>C</artifactId></project>" }, ROUTE .. "/C/pom.xml")
  vim.uv.fs_symlink(ROUTE .. "/B", ROUTE .. "/linkB")
end
local function seen_for(seen, who)
  local out = {}
  for _, r in ipairs(seen) do if r.who == who then out[#out + 1] = r end end
  return out
end
local function mk_stub(seen, label, id, root, opts)
  opts = opts or {}
  return {
    id = id, name = "jdtls", label = label, config = { root_dir = root },
    is_stopped = function() return false end,
    request = function(_, _, params, cb)
      seen[#seen + 1] = { who = label, cmd = params and params.command, args = params and params.arguments }
      if opts.fail and cb and (opts.fail == true or #seen_for(seen, label) <= opts.fail) then
        cb({ code = -32603, message = "stub: command rejected" }) -- error reply (opts.fail = number of leading errors, true = always)
      elseif not opts.silent and cb then
        cb(nil, opts.answer or vim.NIL)
      end
      return true
    end,
  }
end
local function count(seen, who, cmd)
  local n = 0
  for _, r in ipairs(seen) do if r.who == who and (not cmd or r.cmd == cmd) then n = n + 1 end end
  return n
end
--- fn() with stub clients behind vim.lsp.get_clients / get_client_by_id and the current buffer named `buf_name`.
local function with_stubs(list, buf_name, fn)
  local S = require("nv4j.spring")
  local o_get, o_by_id, o_args = vim.lsp.get_clients, vim.lsp.get_client_by_id, S._state.classpath_args
  local o_buf = vim.api.nvim_get_current_buf()
  vim.lsp.get_clients = function(f)
    if f and f.name == "jdtls" then return list end
    return o_get(f)
  end
  vim.lsp.get_client_by_id = function(id)
    for _, c in ipairs(list) do if c.id == id then return c end end
    return o_by_id(id)
  end
  local sb = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(sb)
  vim.api.nvim_buf_set_name(sb, buf_name)
  local ok, err = pcall(fn)
  vim.lsp.get_clients, vim.lsp.get_client_by_id = o_get, o_by_id
  S._state.classpath_args = o_args
  vim.api.nvim_set_current_buf(o_buf)
  pcall(vim.api.nvim_buf_delete, sb, { force = true })
  if not ok then error(err, 0) end
end
local function route_log_size()
  local st = vim.uv.fs_stat(require("nv4j.paths").logs .. "/spring-route.log")
  return st and st.size or 0
end
local function route_log_tail(from)
  local f = io.open(require("nv4j.paths").logs .. "/spring-route.log", "r")
  if not f then return "" end
  f:seek("set", from)
  local t = f:read("*a")
  f:close()
  return t
end

local ok5, err5 = pcall(function()
  local S = require("nv4j.spring")
  local seenp = {}
  route_setup()
  local sA = mk_stub(seenp, "A", 101, ROUTE .. "/A", { answer = { from = "A" } })
  local sB = mk_stub(seenp, "B", 102, ROUTE .. "/B", { answer = { from = "B" } })
  local sC = mk_stub(seenp, "C", 103, ROUTE .. "/C")
  local all = { sA, sB, sC }

  -- start() really wires the routing (the test does not call route_jdtls itself).
  local jm = require("spring_boot.jdtls")
  lsp.report(P .. "wired", jm._nv4j_routed == true,
    ("spring_boot.jdtls patched by nv4j.spring start(): %s"):format(tostring(jm._nv4j_routed)))

  -- jdtls_route: pure matching, no stubs of the LSP API.
  local rA = S.jdtls_for(ROUTE .. "/A/src/Foo.java", all)
  local rB = S.jdtls_for(ROUTE .. "/B/src/Bar.java", all)
  local rUri = S.jdtls_for("file://" .. ROUTE .. "/B/src/Bar.java", all)
  local rNone = S.jdtls_for("/tmp/nv4j/other/x.java", all)
  lsp.report(P .. "jdtls_route", rA == sA and rB == sB and rUri == sB and rNone == nil,
    ("A file -> %s, B file -> %s, B projectUri -> %s, other -> %s (want A, B, B, nil)")
      :format(rA and rA.label, rB and rB.label, rUri and rUri.label, tostring(rNone)))

  -- route_paths: symlinked projectUri, case folding, and the fallback only when no root contains the path.
  local bad = {}
  with_stubs(all, ROUTE .. "/A/src/Cur.java", function()
    local link = S.route_client({ projectUri = "file://" .. ROUTE .. "/linkB/src/X.java" }, all)
    if link ~= sB then bad[#bad + 1] = "symlink projectUri -> " .. tostring(link and link.label) .. " (want B)" end
    -- the Spring LS writes projectUri as "file:/path" (one slash, Java File.toURI()): must match like "file:///path"
    local one = S.route_client({ projectUri = "file:" .. ROUTE .. "/B" }, all)
    if one ~= sB then bad[#bad + 1] = "single-slash file:/ projectUri -> " .. tostring(one and one.label) .. " (want B, not the current buffer's A)" end
    local pre = route_log_size()
    local un = S.route_client({ projectUri = "file:///nowhere/Z/x.java" }, all)
    local logged = route_log_tail(pre)
    if un ~= sA then bad[#bad + 1] = "unmatched projectUri -> " .. tostring(un and un.label) .. " (want current buffer A)" end
    if not logged:find("/nowhere/Z/x.java", 1, true) then bad[#bad + 1] = "no spring-route.log line for the fallback" end
    local swapped = ROUTE .. "/b/src/X.java" -- case-different root
    local swapped_exists = vim.uv.fs_stat(ROUTE .. "/b") ~= nil -- case-insensitive FS: realpath alone resolves it
    vim.g.nv4j_case_fold = true
    local folded = S.route_client({ projectUri = swapped }, all)
    vim.g.nv4j_case_fold = false
    local unfolded = S.route_client({ projectUri = swapped }, all)
    vim.g.nv4j_case_fold = nil
    if folded ~= sB then bad[#bad + 1] = "case folded -> " .. tostring(folded and folded.label) .. " (want B)" end
    if not swapped_exists and unfolded == sB then bad[#bad + 1] = "case-sensitive FS, fold off, still matched B" end
  end)
  with_stubs({ sC, sA, sB }, "/tmp/nv4j/elsewhere/n.txt", function()
    local f = S.route_client(nil, { sC, sA, sB })
    if f ~= sA then bad[#bad + 1] = "no buffer project -> " .. tostring(f and f.label) .. " (want first Boot jdt.ls A, never plain C)" end
  end)
  lsp.report(P .. "route_paths", #bad == 0, #bad == 0 and "symlink, case fold (FS-dependent), fallback + log line, first Boot not plain: all right" or table.concat(bad, "; "))

  -- route_wrapped: through the plugin's execute_command / get_jdtls_client.
  local bad2 = {}
  with_stubs(all, ROUTE .. "/A/src/Cur.java", function()
    for i = #seenp, 1, -1 do seenp[i] = nil end
    local rb = jm.execute_command("sts.project.gav", { projectUri = "file://" .. ROUTE .. "/B/src/Bar.java" }, 300)
    if count(seenp, "B", "sts.project.gav") ~= 1 or #seenp ~= 1 then bad2[#bad2 + 1] = "B projectUri hit " .. vim.inspect(seenp) end
    if type(rb) ~= "table" or rb.from ~= "B" then bad2[#bad2 + 1] = "B answer " .. vim.inspect(rb) end
    for i = #seenp, 1, -1 do seenp[i] = nil end
    local rc = jm.execute_command("sts.project.gav", { projectUri = "file://" .. ROUTE .. "/C/x" }, 300)
    if count(seenp, "C") ~= 1 or #seenp ~= 1 or rc ~= vim.NIL then bad2[#bad2 + 1] = "plain C owner: " .. vim.inspect(seenp) end
    for i = #seenp, 1, -1 do seenp[i] = nil end
    jm.execute_command("sts.project.gav", { projectUri = "file:///nowhere/Z" }, 300)
    if count(seenp, "A") ~= 1 or #seenp ~= 1 then bad2[#bad2 + 1] = "unmatched hit " .. vim.inspect(seenp) end
    if jm.get_jdtls_client({ projectUri = "file://" .. ROUTE .. "/B/q" }) ~= sB then bad2[#bad2 + 1] = "get_jdtls_client(B) wrong" end
  end)
  lsp.report(P .. "route_wrapped", #bad2 == 0, #bad2 == 0 and "projectUri B -> B only (answer from B), plain C owner -> C, unmatched -> current buffer A" or table.concat(bad2, "; "))

  -- classpath_all: Boot jdt.ls only, async for all but the answering one (B never answers: a blocking fan-out
  -- would take the whole 300 ms timeout), the answer is A's, never a NIL from a non-Boot jdt.ls.
  local bad3 = {}
  local seen2 = {}
  local a2 = mk_stub(seen2, "A", 111, ROUTE .. "/A", { answer = { from = "A" } })
  local b2 = mk_stub(seen2, "B", 112, ROUTE .. "/B", { silent = true })
  local c2 = mk_stub(seen2, "C", 113, ROUTE .. "/C") -- answers NIL, last in the list
  with_stubs({ a2, b2, c2 }, ROUTE .. "/A/src/Cur.java", function()
    local t0 = vim.uv.hrtime()
    local r = jm.execute_command("sts.java.addClasspathListener", { "cb1" }, 300)
    local ms = (vim.uv.hrtime() - t0) / 1e6
    if count(seen2, "A", "sts.java.addClasspathListener") ~= 1 or count(seen2, "B", "sts.java.addClasspathListener") ~= 1 then
      bad3[#bad3 + 1] = "A/B not once each: " .. vim.inspect(seen2)
    end
    if count(seen2, "C") ~= 0 then bad3[#bad3 + 1] = "non-Boot C got the command" end
    if type(r) ~= "table" or r.from ~= "A" then bad3[#bad3 + 1] = "answer " .. vim.inspect(r) end
    if ms > 150 then bad3[#bad3 + 1] = ("blocked %.0f ms (silent B, timeout 300)"):format(ms) end
    seen2.ms = ms
  end)
  lsp.report(P .. "classpath_all", #bad3 == 0,
    #bad3 == 0 and ("addClasspathListener: A (answers) and B (async, silent) once, plain C none, return %.0f ms of 300"):format(seen2.ms or -1)
      or table.concat(bad3, "; "))

  -- classpath_attach: late starter (LspAttach, once per client however many buffers) and removeClasspathListener.
  local bad4 = {}
  local seen3 = {}
  local d3 = mk_stub(seen3, "D", 121, ROUTE .. "/D")
  local c3 = mk_stub(seen3, "C", 122, ROUTE .. "/C")
  local a3 = mk_stub(seen3, "A", 123, ROUTE .. "/A", { answer = { from = "A" } })
  local function attach(c, n)
    for _ = 1, n do
      vim.api.nvim_exec_autocmds("LspAttach", { group = "nv4j_spring_route", data = { client_id = c.id } })
    end
  end
  with_stubs({ a3 }, ROUTE .. "/A/src/Cur.java", function()
    jm.execute_command("sts.java.addClasspathListener", { "cb2" }, 300) -- fan-out registered A
    attach(a3, 3)
    if count(seen3, "A", "sts.java.addClasspathListener") ~= 1 then bad4[#bad4 + 1] = "A registered by the fan-out got " .. count(seen3, "A") .. " (want 1)" end
  end)
  with_stubs({ a3, d3, c3 }, ROUTE .. "/A/src/Cur.java", function()
    S._state.classpath_args = { "cb2" }
    attach(d3, 3)
    attach(c3, 2)
    local nd, nc = count(seen3, "D", "sts.java.addClasspathListener"), count(seen3, "C")
    if nd ~= 1 then bad4[#bad4 + 1] = "late Boot D registered " .. nd .. " times (want 1 for 3 attaches)" end
    if nc ~= 0 then bad4[#bad4 + 1] = "plain C registered " .. nc end
    if not vim.deep_equal(seen3[#seen3] and seen3[#seen3].args, { "cb2" }) then bad4[#bad4 + 1] = "args " .. vim.inspect(seen3[#seen3]) end
    -- removeClasspathListener: every Boot jdt.ls, state cleared, a later starter gets nothing.
    jm.execute_command("sts.java.removeClasspathListener", { "cb2" }, 300)
    local rem = { count(seen3, "A", "sts.java.removeClasspathListener"), count(seen3, "D", "sts.java.removeClasspathListener"), count(seen3, "C", "sts.java.removeClasspathListener") }
    if rem[1] ~= 1 or rem[2] ~= 1 or rem[3] ~= 0 then bad4[#bad4 + 1] = ("remove A,D,C = %s (want 1,1,0)"):format(table.concat(rem, ",")) end
    if S._state.classpath_args ~= nil or S._state.registered[d3] ~= nil then bad4[#bad4 + 1] = "state not cleared by remove" end
    local before = #seen3
    attach(d3, 2)
    if #seen3 ~= before then bad4[#bad4 + 1] = "attach after remove still sent" end
  end)
  lsp.report(P .. "classpath_attach", #bad4 == 0,
    #bad4 == 0 and "late Boot starter: 3 attaches -> 1 registration; fan-out-registered A: 0 extra; plain C: 0; remove: A and D, state cleared, no later send"
      or table.concat(bad4, "; "))

  -- classpath_retry: a Boot jdt.ls that REJECTS addClasspathListener (error reply) would never send its classpath to
  -- the Spring LS; the registration is retried on a timer (state.retry_ms shortened here), stops after the limit, stops
  -- when the listener is removed, never retries a stopped client, never sends twice while one is accepted.
  local bad5 = {}
  local seen5 = {}
  local e5 = mk_stub(seen5, "E", 131, ROUTE .. "/D", { fail = 2 }) -- two errors, then accepts
  local f5 = mk_stub(seen5, "F", 132, ROUTE .. "/B", { fail = true }) -- always rejects
  local g5 = mk_stub(seen5, "G", 133, ROUTE .. "/A", { fail = true }) -- rejects, then removed
  local h5 = mk_stub(seen5, "H", 134, ROUTE .. "/D", { fail = true }) -- rejects, then stopped
  local o_retry = S._state.retry_ms
  S._state.retry_ms = 20
  local function attach5(c) vim.api.nvim_exec_autocmds("LspAttach", { group = "nv4j_spring_route", data = { client_id = c.id } }) end
  with_stubs({ e5, f5, g5, h5 }, ROUTE .. "/A/src/Cur.java", function()
    S._state.classpath_args = { "cb5" }
    attach5(e5)
    vim.wait(3000, function() return count(seen5, "E", "sts.java.addClasspathListener") >= 3 end, 10)
    vim.wait(300) -- no fourth send once accepted
    local ne = count(seen5, "E", "sts.java.addClasspathListener")
    if ne ~= 3 then bad5[#bad5 + 1] = "E (2 errors then ok) sent " .. ne .. " times (want 3)" end
    if S._state.registered[e5] ~= "cb5" then bad5[#bad5 + 1] = "E not registered after the retries: " .. tostring(S._state.registered[e5]) end
    attach5(e5)
    if count(seen5, "E", "sts.java.addClasspathListener") ~= 3 then bad5[#bad5 + 1] = "attach after success sent again" end
    attach5(f5)
    vim.wait(3000, function() return count(seen5, "F", "sts.java.addClasspathListener") >= 5 end, 10)
    vim.wait(600)
    local nf = count(seen5, "F", "sts.java.addClasspathListener")
    if nf ~= 5 then bad5[#bad5 + 1] = "F (always rejects) sent " .. nf .. " times (want 1 + 4 retries)" end
    attach5(g5)
    S._state.classpath_args = nil -- removeClasspathListener
    vim.wait(300)
    local ng = count(seen5, "G", "sts.java.addClasspathListener")
    if ng ~= 1 then bad5[#bad5 + 1] = "G retried after the listener was removed (" .. ng .. " sends)" end
    S._state.classpath_args = { "cb5" }
    attach5(h5)
    h5.is_stopped = function() return true end
    vim.wait(300)
    local nh = count(seen5, "H", "sts.java.addClasspathListener")
    if nh ~= 1 then bad5[#bad5 + 1] = "H retried after it stopped (" .. nh .. " sends)" end
  end)
  S._state.retry_ms = o_retry
  lsp.report(P .. "classpath_retry", #bad5 == 0,
    #bad5 == 0 and "rejected addClasspathListener: retried until accepted (2 errors -> 3 sends), capped at 1+4, none after remove or stop, none after success"
      or table.concat(bad5, "; "))

  -- route_log_*: the three spring-route.log lines (nv4j/spring.lua route_log), each written in its own situation and
  -- not otherwise. The file is <logs>/spring-route.log (nv4j.paths.logs); every probe reads only what the probe appended.
  local function logged(fn)
    local pre = route_log_size()
    fn()
    return route_log_tail(pre)
  end
  local function lines_of(t) return vim.split(vim.trim(t), "\n", { plain = true, trimempty = true }) end
  -- (1) no jdt.ls root contains the projectUri path
  local bad6 = {}
  with_stubs(all, ROUTE .. "/A/src/Cur.java", function()
    local hit = logged(function() S.route_client({ projectUri = "file://" .. ROUTE .. "/B/src/X.java" }, all) end)
    if hit ~= "" then bad6[#bad6 + 1] = "matched projectUri wrote: " .. hit end
    local nopath = logged(function() S.route_client(nil, all) end)
    if nopath:find("no jdt.ls root contains", 1, true) then bad6[#bad6 + 1] = "no projectUri wrote a no-root line: " .. nopath end
    local miss = logged(function() S.route_client({ projectUri = "file:///nowhere/Z1/x.java" }, all) end)
    local l = lines_of(miss)
    if #l ~= 1 or not l[1]:find("^%d%d:%d%d:%d%d no jdt%.ls root contains /nowhere/Z1/x%.java: current buffer's jdt%.ls$") then
      bad6[#bad6 + 1] = "unmatched projectUri line: " .. vim.inspect(miss)
    end
  end)
  lsp.report(P .. "route_log_nomatch", #bad6 == 0, #bad6 == 0
    and "unmatched projectUri: exactly one 'no jdt.ls root contains <path>' line; matched projectUri and no projectUri: none (spring-route.log)"
    or table.concat(bad6, "; "))
  -- (2) the current buffer has no jdt.ls: first Boot jdt.ls
  local bad7 = {}
  local elsewhere = "/tmp/nv4j/elsewhere/n.txt"
  with_stubs({ sC, sA, sB }, elsewhere, function()
    local t = logged(function() assert(S.route_client(nil, { sC, sA, sB }) == sA) end)
    local l = lines_of(t)
    if #l ~= 1 or not l[1]:find("current buffer '" .. elsewhere .. "' has no jdt.ls: first Boot jdt.ls (root " .. ROUTE .. "/A)", 1, true) then
      bad7[#bad7 + 1] = "buffer without jdt.ls line: " .. vim.inspect(t)
    end
    local both = logged(function() S.route_client({ projectUri = "file:///nowhere/Z2/x.java" }, { sC, sA, sB }) end)
    if #lines_of(both) ~= 2 or not both:find("Z2/x.java", 1, true) or not both:find("first Boot jdt.ls", 1, true) then
      bad7[#bad7 + 1] = "unmatched uri + foreign buffer: want both lines, got " .. vim.inspect(both)
    end
    local byuri = logged(function() S.route_client({ projectUri = "file://" .. ROUTE .. "/B/src/X.java" }, { sC, sA, sB }) end)
    if byuri ~= "" then bad7[#bad7 + 1] = "projectUri owner found, line written: " .. byuri end
    local only_plain = logged(function() assert(S.route_client(nil, { sC }) == nil) end)
    if only_plain ~= "" then bad7[#bad7 + 1] = "no Boot jdt.ls at all, line written: " .. only_plain end
  end)
  with_stubs({ sC, sA, sB }, ROUTE .. "/B/src/Cur.java", function()
    local own = logged(function() assert(S.route_client(nil, { sC, sA, sB }) == sB) end)
    if own ~= "" then bad7[#bad7 + 1] = "buffer inside B's root, line written: " .. own end
  end)
  lsp.report(P .. "route_log_nobuf", #bad7 == 0, #bad7 == 0
    and "buffer without a jdt.ls: one 'current buffer ... has no jdt.ls: first Boot jdt.ls (root ...)' line; buffer in B's root, projectUri owner, no Boot jdt.ls: none (spring-route.log)"
    or table.concat(bad7, "; "))
  -- (3) addClasspathListener rejected by a jdt.ls
  local bad8 = {}
  local seen8 = {}
  local ok8 = mk_stub(seen8, "OK", 141, ROUTE .. "/A")
  local rej8 = mk_stub(seen8, "REJ", 142, ROUTE .. "/B", { fail = true })
  local rm8 = mk_stub(seen8, "RM", 143, ROUTE .. "/D", { silent = true })
  local late8 -- rm8's reply callback: answered with an error only after the listener was removed
  rm8.request = function(_, _, params, cb) seen8[#seen8 + 1] = { who = "RM", cmd = params and params.command }; late8 = cb; return true end
  local o_retry8 = S._state.retry_ms
  S._state.retry_ms = 20
  local function attach8(c) vim.api.nvim_exec_autocmds("LspAttach", { group = "nv4j_spring_route", data = { client_id = c.id } }) end
  with_stubs({ ok8, rej8, rm8 }, ROUTE .. "/A/src/Cur.java", function()
    S._state.classpath_args = { "cb8" }
    local fine = logged(function() attach8(ok8); vim.wait(200) end)
    if fine ~= "" then bad8[#bad8 + 1] = "accepted registration wrote: " .. fine end
    local t = logged(function()
      attach8(rej8)
      vim.wait(3000, function() return count(seen8, "REJ", "sts.java.addClasspathListener") >= 5 end, 10)
      vim.wait(400)
    end)
    local l = lines_of(t)
    local want = "addClasspathListener rejected by jdt.ls 142 (root " .. ROUTE .. "/B): "
    local n_ok = 0
    for _, ln in ipairs(l) do if ln:find(want, 1, true) and ln:find("stub: command rejected", 1, true) then n_ok = n_ok + 1 end end
    if #l ~= 5 or n_ok ~= 5 then bad8[#bad8 + 1] = ("always-rejecting jdt.ls: want 5 lines (1 + 4 retries), got %d (%d right): %s"):format(#l, n_ok, vim.inspect(t):sub(1, 200)) end
    -- a rejection that arrives after the listener was removed is not an event worth a line
    local gone = logged(function()
      attach8(rm8)
      S._state.classpath_args = nil
      S._state.registered[rm8] = nil -- what removeClasspathListener does
      if late8 then late8({ code = -32603, message = "stub: late rejection" }) end
      vim.wait(300)
    end)
    if not late8 or gone:find("jdt.ls 143", 1, true) then bad8[#bad8 + 1] = "rejection after remove wrote: " .. gone end
  end)
  S._state.retry_ms = o_retry8
  lsp.report(P .. "route_log_rejected", #bad8 == 0, #bad8 == 0
    and "rejected addClasspathListener: one line per rejection (1 + 4 retries = 5, with client id and root); accepted, or rejected after remove: none (spring-route.log)"
    or table.concat(bad8, "; "))
end)
if not ok5 then lsp.report(P .. "jdtls_route", false, "error: " .. tostring(err5)) end

-- ensure_package_installing: the Mason `is_installing` guard in nv4j.spring ensure_package. ensure_installed (want_install)
-- may already be installing the package: a second install() would run in parallel, so ensure_package waits (polls every 2 s)
-- and installs only once the package is no longer installing. Registry stubbed through package.loaded["mason-registry"].
do
  local S = require("nv4j.spring")
  local o_jar, o_reg, o_notify = S.ls_jar, package.loaded["mason-registry"], vim.notify
  local notes_m, installs, gets, closed_cb = {}, 0, 0, nil
  local installing_now = true
  local pkg = {
    is_installed = function() return false end,
    is_installing = function() return installing_now end,
    install = function()
      installs = installs + 1
      return { once = function(_, _, cb) closed_cb = cb end }
    end,
  }
  S.ls_jar = function() return nil end
  package.loaded["mason-registry"] = { refresh = function(cb) cb() end, get_package = function() gets = gets + 1; return pkg end }
  vim.notify = function(msg, level) notes_m[#notes_m + 1] = tostring(msg) end
  local okm, errm = pcall(function()
    S.ensure_package()
    vim.wait(4300, function() return installs > 0 end, 20) -- two polls (2 s apart) while 'installing'
    local waited_installs, waited_gets = installs, gets
    S.ensure_package() -- a second caller while the first waits: ignored
    installing_now = false
    vim.wait(3500, function() return installs > 0 end, 20) -- the next poll installs
    vim.wait(300)
    local bad = {}
    if waited_installs ~= 0 then bad[#bad + 1] = ("install() ran %d time(s) while the package was installing"):format(waited_installs) end
    if waited_gets < 3 then bad[#bad + 1] = ("polled %d time(s) in 4.3 s (want >= 3: first call + 2 retries)"):format(waited_gets) end
    if installs ~= 1 then bad[#bad + 1] = ("install() ran %d time(s) after it finished installing elsewhere (want 1)"):format(installs) end
    if closed_cb then closed_cb(); vim.wait(300) end -- the install closes without a jar: the WARN, `installing` reset
    local warned = false
    for _, m in ipairs(notes_m) do if m:find("Spring Boot LS not installed", 1, true) then warned = true end end
    if not warned then bad[#bad + 1] = "no 'not installed' warning after the install closed" end
    lsp.report(P .. "ensure_package_installing", #bad == 0, #bad == 0
      and ("while Mason reports the package installing: 0 install() calls over 4.3 s (%d registry polls); once it stops: exactly 1"):format(waited_gets)
      or table.concat(bad, "; "))
  end)
  S.ls_jar, package.loaded["mason-registry"], vim.notify = o_jar, o_reg, o_notify
  if not okm then lsp.report(P .. "ensure_package_installing", false, "error: " .. tostring(errm)) end
end
-- Two real Boot projects: a second jdt.ls (root B), the SAME Spring LS process attached to B's files, the
-- classpath listener registered on B's jdt.ls by the real LspAttach path, sts/* routed to each project's jdt.ls.
local ok6, err6 = pcall(function()
  local S = require("nv4j.spring")
  local dir = "/tmp/nv4j/50_two/B"
  local route_path = require("nv4j.paths").logs .. "/spring-route.log"
  local route_from = (vim.uv.fs_stat(route_path) or { size = 0 }).size -- two_boot_index quotes what this case appended
  vim.fn.delete("/tmp/nv4j/50_two", "rf")
  vim.fn.mkdir(dir .. "/src/main/java/twob", "p")
  vim.fn.mkdir(dir .. "/src/main/resources", "p")
  vim.fn.writefile({
    '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>',
    "<parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId>",
    "<version>3.5.13</version><relativePath/></parent>",
    "<groupId>twob</groupId><artifactId>twob</artifactId><version>1</version>",
    "<properties><maven.compiler.release>21</maven.compiler.release></properties>",
    -- web starter: B's controller/bean annotations resolve; the configuration processor writes B's own
    -- target/classes/META-INF/spring-configuration-metadata.json (the Spring LS reads property keys from there).
    "<dependencies><dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>",
    "<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-configuration-processor</artifactId><optional>true</optional></dependency></dependencies></project>",
  }, dir .. "/pom.xml")
  vim.fn.writefile({ "package twob;", "class App { int x; }" }, dir .. "/src/main/java/twob/App.java")
  -- Things that exist ONLY in B (case two_boot_index): a request mapping, a bean, a configuration property.
  vim.fn.writefile({
    "package twob;",
    "import org.springframework.web.bind.annotation.GetMapping;",
    "import org.springframework.web.bind.annotation.RestController;",
    "@RestController public class TwoBOnlyController {",
    '  @GetMapping("/twob-only-path") public String hi() { return "b"; }',
    "}",
  }, dir .. "/src/main/java/twob/TwoBOnlyController.java")
  vim.fn.writefile({
    "package twob;",
    "import org.springframework.boot.context.properties.ConfigurationProperties;",
    '@ConfigurationProperties(prefix = "twob.cfg") public class TwoBProps {',
    "  private int limit; public int getLimit() { return limit; } public void setLimit(int l) { limit = l; }",
    "}",
  }, dir .. "/src/main/java/twob/TwoBProps.java")
  vim.fn.writefile({ "server.port=9091" }, dir .. "/src/main/resources/application.properties")
  local jh = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.exepath("java")), ":h:h") -- the JDK 21 on PATH; release 21
  local mvn_out = vim.fn.system({ "env", "JAVA_HOME=" .. jh, "mvn", "-q", "-f", dir .. "/pom.xml", "compile" })
  local mvn_rc = vim.v.shell_error
  local bbuf = lsp.open(dir .. "/src/main/java/twob/App.java")
  local bj = lsp.wait_ready(bbuf, 120000)
  local bsp = bj and wait_attach(bbuf, 20000)
  local spring_all = vim.lsp.get_clients({ name = NAME })
  local routed_b = bj and S.route_client({ projectUri = vim.uri_from_fname(dir .. "/src/main/java/twob/App.java") })
  local routed_a = S.route_client({ projectUri = vim.uri_from_fname(fixture .. "/src/main/java/demo/DemoApplication.java") })
  local st = S._state
  local want_id = st.classpath_args and st.classpath_args[1]
  local reg_b = bj and st.registered[bj]
  local folders = {}
  for _, f in ipairs(client.workspace_folders or {}) do folders[#folders + 1] = f.name end
  lsp.report(P .. "two_boot_shared", bj ~= nil and bj.id ~= jdtls.id and bsp ~= nil and bsp.id == client.id
      and #spring_all == 1 and #spring_pids() == 1 and routed_b == bj and routed_a == jdtls
      and want_id ~= nil and reg_b == want_id,
    ("second jdt.ls %s (own client: %s); spring-boot client on B's App.java %s (same client: %s); spring-boot clients %d, processes %d; "
      .. "route B -> %s, route A -> %s; listener on B's jdt.ls %s (want %s); Spring LS workspace folders: %s")
      :format(bj and "ready" or "NOT READY", tostring(bj and bj.id ~= jdtls.id), bsp and "attached" or "NONE",
        tostring(bsp and bsp.id == client.id), #spring_all, #spring_pids(),
        routed_b == bj and "B's jdt.ls" or "WRONG", routed_a == jdtls and "A's jdt.ls" or "WRONG",
        tostring(reg_b), tostring(want_id), table.concat(folders, ",")))

  -- two_boot_index: the ONE Spring LS (workspace folder = project A only, see the folders above) answers for what only
  -- B contains: B's request mapping and bean (workspace/symbol @/ and @+) and B's configuration property key
  -- (completion in B's application.properties). B reaches the LS through its jdt.ls classpath events (the listener
  -- registered on B's jdt.ls), not through a workspace folder. A's own mapping must still be there.
  local ok7, err7 = pcall(function()
    local function syms(q)
      local r = client:request_sync("workspace/symbol", { query = q }, 6000, bbuf)
      local out = {}
      for _, x in ipairs(r and r.result or {}) do out[#out + 1] = x.name .. " @ " .. (x.location and x.location.uri or "") end
      return out
    end
    local function any(list, pat)
      for _, n in ipairs(list) do
        if n:find(pat, 1, true) then return true end
      end
      return false
    end
    local pbufb
    vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/src/main/resources/application.properties"))
    pbufb = vim.api.nvim_get_current_buf()
    vim.wait(20000, function() return #vim.lsp.get_clients({ bufnr = pbufb, name = NAME }) > 0 end, 20)
    vim.api.nvim_buf_set_lines(pbufb, 0, -1, false, { "twob.cfg.li" })
    local function prop_items()
      local r = client:request_sync("textDocument/completion",
        { textDocument = { uri = vim.uri_from_bufnr(pbufb) }, position = { line = 0, character = 11 } }, 6000, pbufb)
      local res = r and r.result or {}
      local labels = {}
      for _, it in ipairs(res.items or res) do labels[#labels + 1] = it.label end
      return labels
    end
    local maps, beans, props = {}, {}, {}
    local t_b, t_ab
    local t0 = E.now()
    local deadline = vim.uv.now() + 60000 -- each request below is bounded (6 s), so is the loop
    repeat
      maps, beans, props = syms("@/"), syms("@+"), prop_items()
      local b_now = any(maps, "twob-only-path") and any(beans, "TwoBOnlyController") and vim.tbl_contains(props, "twob.cfg.limit")
      local a_now = any(maps, "@/hello") and any(beans, "GreetingController")
      -- A is re-read when B's classpath arrives: right after B appears A can be momentarily absent (seen once, run
      -- 2026-11-03 08:56). Both must be present together; the times show how long either was missing.
      if b_now and not t_b then t_b = E.now() - t0 end
      if b_now and a_now then t_ab = E.now() - t0; break end
      vim.wait(500)
    until vim.uv.now() > deadline
    local waited = E.now() - t0
    local m_ok, b_ok = any(maps, "twob-only-path"), any(beans, "TwoBOnlyController")
    local p_ok = vim.tbl_contains(props, "twob.cfg.limit")
    local a_ok = any(maps, "@/hello") and any(beans, "GreetingController")
    local only_a = #folders == 1 and (folders[1]):find("fixtures/demo", 1, true) ~= nil
    -- Evidence for a failure (flake: cause never captured): was the listener registered on B's jdt.ls at the end
    -- (state.registered), did jdt.ls reject it (spring-route.log lines appended by this case), which kinds of answer
    -- were empty. Nothing here is asserted; it only goes into the FAIL line.
    local ev = ""
    if not (m_ok and b_ok and p_ok and a_ok) then
      local rf = io.open(route_path, "r")
      local appended = {}
      if rf then
        rf:seek("set", route_from)
        for l in rf:lines() do appended[#appended + 1] = l end
        rf:close()
      end
      ev = ("; EVIDENCE listener on B's jdt.ls %s (want %s), B jdt.ls %s, %d spring-route.log line(s) during the case%s; symbols @/ %d, @+ %d"):format(
        tostring(bj and S._state.registered[bj]), tostring(S._state.classpath_args and S._state.classpath_args[1]),
        bj and (bj:is_stopped() and "STOPPED" or "alive") or "nil", #appended,
        #appended > 0 and (" (last: " .. appended[#appended]:sub(1, 160) .. ")") or "", #maps, #beans)
    end
    lsp.report(P .. "two_boot_index", mvn_rc == 0 and m_ok and b_ok and p_ok and a_ok and only_a,
      ("Spring LS (workspace folder only A: %s) answers for B after %.0f ms: request mapping /twob-only-path %s, bean TwoBOnlyController %s, "
        .. "property twob.cfg.limit %s (%d items); A's /hello and GreetingController still there: %s (B first seen at %s ms, A and B together at %s ms); B compile rc %d%s"):format(
        tostring(only_a), waited, tostring(m_ok), tostring(b_ok), tostring(p_ok), #props, tostring(a_ok), tostring(t_b and math.floor(t_b)), tostring(t_ab and math.floor(t_ab)), mvn_rc,
        mvn_rc ~= 0 and (" " .. mvn_out:sub(1, 200)) or "") .. ev)
  end)
  if not ok7 then lsp.report(P .. "two_boot_index", false, "error: " .. tostring(err7)) end
end)
if not ok6 then lsp.report(P .. "two_boot_shared", false, "error: " .. tostring(err6)) end
lsp.finish()
