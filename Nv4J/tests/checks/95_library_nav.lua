-- Library navigation (specs/features/library-navigation.md): go to definition into a jar with sources (real source), without
-- (jdt.ls's bundled Fernflower), and into a class Fernflower cannot decompile (CFR backup, nv4j/decompile.lua).
-- Fixture tests/fixtures/libnav copied to /tmp/nv4j/95_libnav (plain Maven, offline: java.import.maven.offline.enabled forced);
-- its three dependencies must already be in ~/.m2 (commons-logging 1.2 WITH -sources.jar, commons-codec 1.20.0 and
-- kotlin-stdlib 2.4.10 WITHOUT): nothing is downloaded by this check, missing jars make the live cases SKIP (reported as PASS
-- with "SKIP" in the detail). NV4J_95_UNIT=1 runs only the pure cases (tests/lib/run1.sh 95_library_nav; controls use it).
-- Cases (live, in order):
--  zero_cost_startup : nv4j.decompile is not loaded at startup.
--  settings          : effective jdt.ls settings: java.eclipse.downloadSources = true (lazy, on navigation) and
--                      java.maven.downloadSources = vim.g.nv4j_maven_download_sources == true (eager at import, off by default).
--  zero_cost_open    : after the Java file is ready: module still not loaded, no CFR process.
--  sources_jar       : LogFactory -> Apache licence header, > 1000 lines (the -sources.jar).
--  fernflower        : Hex -> FernFlower header on line 1, `public class Hex`, > 100 lines, and the buffer is NOT replaced.
--  fernflower_failed_live : SequencesKt.sortedBy -> jdt.ls's content has `// $FF: Couldn't be decompiled` (real failure);
--                      the buffer ends up as CFR output: line 1 `// Decompiled with CFR 0.152 (Fernflower failed)`, no marker.
--  cfr_live          : decompile(jar, class) on commons-codec's Hex: `class Hex`, CFR header line 1 (lines_of).
--  cfr_manual        : :Nv4JDecompile cfr on the Hex buffer -> "(on demand)" header; :Nv4JDecompile fernflower -> back.
-- Cases (pure, stubbed spawn): uri_parse, cmd_line, trigger_empty, trigger_marker, trigger_normal_kept, timeout, cache_hit,
--  missing_jar, install_verify, after_open_stubbed.
-- Controls: tests/lib/control_95.sh.
local lsp = require("lsp")
local P = "95_library_nav."
local function rep(name, ok, detail) lsp.report(P .. name, ok and true or false, detail) end
local function sleep(ms) local d = vim.uv.hrtime() + ms * 1e6; while vim.uv.hrtime() < d do vim.wait(math.min(200, ms)) end end
-- Deadline loop with a real sleep per round (never vim.wait with an instant sync request: Neovim 0.12 spin, see lsp.lua).
local function until_(ms, step, f)
  local d = vim.uv.hrtime() + ms * 1e6
  while vim.uv.hrtime() < d do
    local v = f()
    if v then return v end
    sleep(step)
  end
  return f()
end

local unit_only = vim.env.NV4J_95_UNIT == "1"
local HOME = vim.env.HOME
local M2 = HOME .. "/.m2/repository"
local JARS = {
  logging = M2 .. "/commons-logging/commons-logging/1.2/commons-logging-1.2.jar",
  logging_src = M2 .. "/commons-logging/commons-logging/1.2/commons-logging-1.2-sources.jar",
  codec = M2 .. "/commons-codec/commons-codec/1.20.0/commons-codec-1.20.0.jar",
  codec_src = M2 .. "/commons-codec/commons-codec/1.20.0/commons-codec-1.20.0-sources.jar",
  kotlin = M2 .. "/org/jetbrains/kotlin/kotlin-stdlib/2.4.10/kotlin-stdlib-2.4.10.jar",
  kotlin_src = M2 .. "/org/jetbrains/kotlin/kotlin-stdlib/2.4.10/kotlin-stdlib-2.4.10-sources.jar",
  annotations = M2 .. "/org/jetbrains/annotations/13.0/annotations-13.0.jar",
}
local function exists(p) return vim.uv.fs_stat(p) ~= nil end
local HEX_URI = "jdt://contents/commons-codec-1.20.0.jar/org.apache.commons.codec.binary/Hex.java?=decomp/%5C/Users%5C/juan.farizo%5C/.m2%5C/repository%5C/commons-codec%5C/commons-codec%5C/1.20.0%5C/commons-codec-1.20.0.jar=/maven.pomderived=/true=/=/maven.groupId=/commons-codec=/=/maven.artifactId=/commons-codec=/=/maven.version=/1.20.0=/=/maven.scope=/compile=/=/maven.pomderived=/true=/%3Corg.apache.commons.codec.binary%28Hex.class"

-- zero_cost_startup (before anything requires the module)
rep("zero_cost_startup", package.loaded["nv4j.decompile"] == nil, "package.loaded['nv4j.decompile'] = " .. tostring(package.loaded["nv4j.decompile"]))
-- keymaps (the :Nv4JDecompile / :Nv4JInstallCfr definitions) load on VeryLazy, after -c commands: load them now (as check 92 does).
-- zero_cost_open below proves that defining the commands loads nothing.
pcall(require, "lazyvim.config.keymaps")
pcall(require, "config.keymaps")

local client, buf, lines
local live_skip
if not unit_only then
  local missing = {}
  for _, k in ipairs({ "logging", "logging_src", "codec", "kotlin", "annotations" }) do if not exists(JARS[k]) then missing[#missing + 1] = JARS[k] end end
  for _, k in ipairs({ "codec_src", "kotlin_src" }) do if exists(JARS[k]) then missing[#missing + 1] = JARS[k] .. " (must NOT exist)" end end
  if #missing > 0 then
    live_skip = "~/.m2 does not match the fixture (no download is made by this check): " .. table.concat(missing, ", ")
  else
    -- Fresh copy of the fixture and a fresh jdt.ls workspace (the lazy source request cache lives in jdt.ls's memory, the
    -- workspace keeps the classpath): the project root is always the same path so the workspace name is stable.
    local root = "/tmp/nv4j/95_libnav"
    vim.fn.delete(root, "rf")
    vim.fn.mkdir(root, "p")
    vim.fn.system({ "cp", "-R", vim.env.NV4J_FIXTURE:gsub("/demo$", "") .. "/libnav/.", root })
    local wsname = vim.fs.basename(root) .. "-" .. vim.fn.sha256(root):sub(1, 8)
    vim.fn.delete(require("nv4j.paths").jdtls_data .. "/" .. wsname, "rf")
    local orig_start = vim.lsp.start
    vim.lsp.start = function(config, opts)
      if config and config.name == "jdtls" then
        config.settings = vim.tbl_deep_extend("force", config.settings or {}, { java = { import = { maven = { offline = { enabled = true } } } } })
      end
      return orig_start(config, opts)
    end
    buf = lsp.open(root .. "/src/main/java/demo/App.java")
    local why
    client, why = lsp.wait_ready(buf, 240000)
    if not client then live_skip = nil; rep("ready", false, tostring(why)) end
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
end

local function def_uri(word)
  for i, l in ipairs(lines) do
    local s = l:find(word, 1, true)
    if s and not l:find("^import") and not l:find("^//") then
      local res, done
      client:request("textDocument/definition", { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = i - 1, character = s } },
        function(err, r) res = err and { err = err } or r; done = true end, buf)
      until_(60000, 200, function() return done end)
      local loc = res and (res[1] or res)
      return loc and (loc.uri or loc.targetUri), res
    end
  end
end

local function open_uri(uri)
  if not uri then return false, "no definition uri", nil, -1 end
  local t0 = vim.uv.hrtime()
  local ok, e = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(uri))
  local b = vim.api.nvim_get_current_buf()
  return ok, e, b, (vim.uv.hrtime() - t0) / 1e6
end

if client then
  -- settings
  local s = client.config.settings or {}
  local ecl, mvn = vim.tbl_get(s, "java", "eclipse", "downloadSources"), vim.tbl_get(s, "java", "maven", "downloadSources")
  local want_mvn = vim.g.nv4j_maven_download_sources == true
  rep("settings", ecl == true and mvn == want_mvn,
    ("java.eclipse.downloadSources=%s (want true) java.maven.downloadSources=%s (want %s: vim.g.nv4j_maven_download_sources)"):format(tostring(ecl), tostring(mvn), tostring(want_mvn)))

  -- zero_cost_open
  local pg = vim.system({ "pgrep", "-f", "cfr-" .. "0.152.jar" }, { text = true }):wait()
  rep("zero_cost_open", package.loaded["nv4j.decompile"] == nil and vim.trim(pg.stdout or "") == "",
    ("module loaded=%s, cfr processes: '%s'"):format(tostring(package.loaded["nv4j.decompile"] ~= nil), vim.trim(pg.stdout or "")))

  -- sources_jar
  do
    local uri = def_uri("LogFactory.")
    local ok, e, b, ms = open_uri(uri)
    local ls = ok and vim.api.nvim_buf_get_lines(b, 0, -1, false) or {}
    local text = table.concat(ls, "\n")
    rep("sources_jar", ok and #ls > 1000 and text:find("Licensed to the Apache Software Foundation", 1, true) ~= nil,
      ("uri=%s open=%s %s lines=%d %.0f ms line1=%s"):format(tostring(uri), tostring(ok), ok and "" or tostring(e), #ls, ms or -1, tostring(ls[1])))
    if ok then vim.cmd("buffer " .. buf) end
  end

  -- fernflower
  local hex_buf
  do
    local uri = def_uri("Hex.")
    local ok, e, b, ms = open_uri(uri)
    sleep(1500) -- a wrongly triggered fallback would land by now (CFR on Hex takes about 400 ms)
    local ls = ok and vim.api.nvim_buf_get_lines(b, 0, -1, false) or {}
    local text = table.concat(ls, "\n")
    local D = package.loaded["nv4j.decompile"]
    rep("fernflower", ok and ls[1] == (D and D.FERNFLOWER_HEADER or "// Source code is decompiled from a .class file using FernFlower decompiler (from Intellij IDEA).")
      and text:find("public class Hex", 1, true) ~= nil and #ls > 100 and D ~= nil and not text:find("Decompiled with CFR", 1, true),
      ("uri=%s open=%s %s lines=%d %.0f ms line1=%s module loaded after open=%s"):format(tostring(uri), tostring(ok), ok and "" or tostring(e), #ls, ms or -1, tostring(ls[1]), tostring(D ~= nil)))
    hex_buf = ok and b or nil
    if ok then vim.cmd("buffer " .. buf) end
  end

  -- A jdt:// URI for another class of the same jar as `uri` (same classpath entry handle, other package fragment and class).
  local function sibling_uri(uri, pkg, name)
    local jarname = uri:match("^jdt://contents/([^/]+)/")
    local handle = uri:match("%?=(.*)$"):gsub("=/%%3C[^=]*$", "")
    return ("jdt://contents/%s/%s/%s.class?=%s=/%%3C%s%%28%s.class"):format(jarname, pkg, name, handle, pkg, name)
  end
  local function wait_cfr(b, ms)
    return until_(ms, 500, function()
      local l = vim.api.nvim_buf_get_lines(b, 0, -1, false)
      return l[1] and l[1]:find("Decompiled with CFR", 1, true) and l or nil
    end)
  end

  -- fernflower_failed_live: the class jdt.ls's own Fernflower (its options differ from the console defaults) gives up on.
  -- Candidates in kotlin-stdlib 2.4.10 found with the same Fernflower jar and jdt.ls's options (docs/RESEARCH-decompiler.md);
  -- the first whose jdt.ls content carries the marker is opened. The definition of sortedBy gives the jar's handle.
  do
    local kuri = def_uri("sortedBy(")
    local tried, pick, raw_len = {}, nil, 0
    if kuri then
      for _, c in ipairs({ { "kotlin", "SynchronizedLazyImpl" }, { "kotlin.coroutines.jvm.internal", "RunSuspend" }, { "kotlin", "StandardKt__SynchronizedKt" },
        { "kotlin.collections", "CollectionsKt___CollectionsKt" }, { "kotlin.sequences", "SequencesKt___SequencesKt" } }) do
        local u = sibling_uri(kuri, c[1], c[2])
        local jd = client:request_sync("java/classFileContents", { uri = u }, 30000, buf)
        local raw = jd and type(jd.result) == "string" and jd.result or ""
        local has = raw:find("// $FF: Couldn't be decompiled", 1, true) ~= nil
        tried[#tried + 1] = ("%s.%s=%s(%d)"):format(c[1], c[2], has and "MARKER" or "ok", #raw)
        if has then pick, raw_len = u, #raw; break end
      end
    end
    if not pick then
      rep("fernflower_failed_live", false, "no real Fernflower failure under jdt.ls's options (see fallback_live_empty for the chain): " .. table.concat(tried, ", "))
    else
      local ok, e, b, ms = open_uri(pick)
      local t0 = vim.uv.hrtime()
      local ls = ok and wait_cfr(b, 40000) or {}
      local cfr_ms = (vim.uv.hrtime() - t0) / 1e6
      if ok and #ls == 0 then ls = vim.api.nvim_buf_get_lines(b, 0, -1, false) end
      local text = table.concat(ls, "\n")
      local name = pick:match("%%28([%w_$]+)%.class$")
      rep("fernflower_failed_live", ok and ls[1] == "// Decompiled with CFR 0.152 (Fernflower failed)" and text:find("class " .. name, 1, true) ~= nil
        and not text:find("$FF: Couldn't be decompiled", 1, true) and not vim.bo[b].modifiable,
        ("%s: jdt.ls content %d chars with the marker; open=%s %s %.0f ms, CFR replaced after %.0f ms, lines=%d line1=%s modifiable=%s; tried %s"):format(
          name, raw_len, tostring(ok), ok and "" or tostring(e), ms or -1, cfr_ms, #ls, tostring(ls[1]), ok and tostring(vim.bo[b].modifiable) or "-", table.concat(tried, ", ")))
      if ok then vim.cmd("buffer " .. buf) end
    end
  end

  -- fallback_live_empty: jdt.ls answers "" for one class (the client's request is wrapped for that URI only); the real chain
  -- (nvim-jdtls BufReadCmd -> wrapped open_classfile -> after_open -> CFR process) fills the buffer.
  do
    local D = require("nv4j.decompile")
    local uri = hex_buf and sibling_uri(vim.api.nvim_buf_get_name(hex_buf), "org.apache.commons.codec.binary", "Base64")
    local ok, e, b, ms, ls = false, "no Hex buffer", nil, -1, {}
    if uri and exists(D.jar_path()) then
      local orig_request = client.request
      client.request = function(self, method, params, handler, bufnr)
        if method == "java/classFileContents" and type(params) == "table" and params.uri == uri then
          vim.schedule(function() handler(nil, "") end)
          return true, 0
        end
        return orig_request(self, method, params, handler, bufnr)
      end
      ok, e, b, ms = open_uri(uri)
      ls = ok and wait_cfr(b, 40000) or {}
      client.request = orig_request
      if ok and #ls == 0 then ls = vim.api.nvim_buf_get_lines(b, 0, -1, false) end
    elseif uri then
      ok, e = true, "SKIP: CFR jar not installed"
      ls = { "// Decompiled with CFR 0.152 (Fernflower failed)", "class Base64" }
    end
    local text = table.concat(ls, "\n")
    rep("fallback_live_empty", ok and ls[1] == "// Decompiled with CFR 0.152 (Fernflower failed)" and text:find("class Base64", 1, true) ~= nil,
      ("open=%s %s %.0f ms lines=%d line1=%s"):format(tostring(ok), tostring(e or ""), ms or -1, #ls, tostring(ls[1])))
    if ok and b then vim.cmd("buffer " .. buf) end
  end

  -- cfr_live
  do
    local D = require("nv4j.decompile")
    local skip = not exists(D.jar_path()) and ("SKIP: CFR jar not installed at " .. D.jar_path() .. " (download not possible here)") or nil
    if skip then
      rep("cfr_live", true, skip)
      rep("cfr_manual", true, skip)
    else
      local text, err, how
      local t0 = vim.uv.hrtime()
      D.decompile(JARS.codec, "org.apache.commons.codec.binary.Hex", function(t, e, h) text, err, how = t, e, h end)
      until_(30000, 200, function() return text ~= nil or err ~= nil end)
      local out = text and D.lines_of(text, "on demand") or {}
      rep("cfr_live", text ~= nil and out[1] == "// Decompiled with CFR 0.152 (on demand)" and text:find("class Hex", 1, true) ~= nil and (how or ""):find("^run"),
        ("how=%s err=%s lines=%d %.0f ms line1=%s line2=%s"):format(tostring(how), tostring(err), #out, (vim.uv.hrtime() - t0) / 1e6, tostring(out[1]), tostring(out[2])))

      -- cfr_manual
      if hex_buf then
        vim.api.nvim_set_current_buf(hex_buf)
        vim.cmd("Nv4JDecompile cfr")
        local l1 = until_(30000, 200, function()
          local l = vim.api.nvim_buf_get_lines(hex_buf, 0, 1, false)[1]
          return l and l:find("Decompiled with CFR", 1, true) and l or nil
        end)
        local cfr_text = table.concat(vim.api.nvim_buf_get_lines(hex_buf, 0, -1, false), "\n")
        vim.cmd("Nv4JDecompile fernflower")
        local l2 = until_(30000, 200, function()
          local l = vim.api.nvim_buf_get_lines(hex_buf, 0, 1, false)[1]
          return l and l:find("FernFlower", 1, true) and l or nil
        end)
        rep("cfr_manual", vim.fn.exists(":Nv4JDecompile") == 2 and l1 == "// Decompiled with CFR 0.152 (on demand)" and cfr_text:find("class Hex", 1, true) ~= nil
          and l2 == D.FERNFLOWER_HEADER and not vim.bo[hex_buf].modifiable,
          ("command exists=%s; after cfr line1=%s; after fernflower line1=%s"):format(tostring(vim.fn.exists(":Nv4JDecompile") == 2), tostring(l1), tostring(l2)))
        vim.cmd("buffer " .. buf)
      else
        rep("cfr_manual", false, "no Hex buffer")
      end
    end
  end
elseif live_skip then
  for _, c in ipairs({ "settings", "zero_cost_open", "sources_jar", "fernflower", "fernflower_failed_live", "cfr_live", "cfr_manual" }) do
    rep(c, true, "SKIP: " .. live_skip)
  end
end

-- ---------------------------------------------------------------- pure cases (stubbed spawn, no process, no network)
local D = require("nv4j.decompile")
local real_spawn, real_notify, real_install, real_jar, real_tools = D.spawn, D.notify, D.install, D.jar_path, D.tools_dir
local function restore() D.spawn, D.notify, D.install, D.jar_path, D.tools_dir = real_spawn, real_notify, real_install, real_jar, real_tools; D.reset_for_tests() end
local notes = {}
D.notify = function(msg, level) notes[#notes + 1] = { msg = msg, level = level } end

-- uri_parse
do
  local t = D.parse_uri(HEX_URI)
  local jdk = D.parse_uri("jdt://contents/java.base/java.lang/String.class?=decomp/%5C/Users%5C/me%5C/jdk%5C/lib%5C/jrt-fs.jar%60java.base=/javadoc_location=/x=/%3Cjava.lang%28String.class")
  local bad = D.parse_uri("file:///x/y.java")
  rep("uri_parse", t and t.jar == JARS.codec and t.class == "org.apache.commons.codec.binary.Hex" and t.name == "Hex" and bad == nil
    and (jdk == nil or jdk.jar:find("jrt%-fs%.jar$")),
    ("jar=%s class=%s; jrt -> %s; file -> %s"):format(t and t.jar or "-", t and t.class or "-", vim.inspect(jdk), tostring(bad)))
end

-- cmd_line
do
  local c = D.command("/jdk/bin/java", "/lib/a.jar", "p.q.Outer$Inner")
  rep("cmd_line", c[1] == "/jdk/bin/java" and c[2] == "-jar" and c[3] == D.jar_path() and c[4] == "/lib/a.jar" and c[5] == "--jarfilter"
    and c[6] == "^p\\.q\\.Outer\\$Inner(\\$.*)?$" and c[7] == "--silent" and c[8] == "true", table.concat(c, " "))
end

-- trigger_empty / trigger_marker / trigger_normal_kept
do
  local e1, w1 = D.needs_fallback({})
  local e2, w2 = D.needs_fallback({ "", "  " })
  rep("trigger_empty", e1 == true and e2 == true and w1 == w2 and w1:find("no content"), tostring(w1))
  local m, wm = D.needs_fallback({ D.FERNFLOWER_HEADER, "class X {", "  void f() {", "    // $FF: Couldn't be decompiled", "  }", "}" })
  rep("trigger_marker", m == true and wm:find("could not decompile"), tostring(wm))
  local n = D.needs_fallback({ D.FERNFLOWER_HEADER, "package x;", "public class Hex {", "}" })
  local src = D.needs_fallback({ "/*", " * Licensed to the Apache Software Foundation", " */", "package x;" })
  rep("trigger_normal_kept", n == false and src == false, ("fernflower=%s sources=%s"):format(tostring(n), tostring(src)))
end

-- timeout
do
  D.reset_for_tests()
  local seen_opts
  D.spawn = function(cmd, opts, on_exit) seen_opts = opts; on_exit({ code = 124, signal = 15, stdout = "", stderr = "" }) end
  local err
  D.decompile(JARS.codec, "a.B", function(_, e) err = e end)
  until_(2000, 50, function() return err ~= nil end)
  rep("timeout", seen_opts and seen_opts.timeout == 20000 and err and err:find("timed out after 20 s"), ("opts.timeout=%s err=%s"):format(tostring(seen_opts and seen_opts.timeout), tostring(err)))
end

-- cache_hit
do
  D.reset_for_tests()
  local spawns = 0
  D.spawn = function(cmd, opts, on_exit) spawns = spawns + 1; on_exit({ code = 0, stdout = "/*\n * Decompiled with CFR 0.152.\n */\nclass B {}\n", stderr = "" }) end
  local t1, h1, t2, h2
  D.decompile(JARS.codec, "a.B", function(t, _, h) t1, h1 = t, h end)
  until_(2000, 50, function() return t1 ~= nil end)
  D.decompile(JARS.codec, "a.B", function(t, _, h) t2, h2 = t, h end)
  rep("cache_hit", spawns == 1 and t1 == t2 and (h1 or ""):find("^run") and h2 == "cache", ("spawns=%d how1=%s how2=%s"):format(spawns, tostring(h1), tostring(h2)))
end

-- missing_jar
do
  D.reset_for_tests()
  notes = {}
  local spawns, installs = 0, 0
  D.spawn = function() spawns = spawns + 1 end
  D.install = function() installs = installs + 1 end
  D.jar_path = function() return "/tmp/nv4j/95_libnav/no-such-cfr.jar" end
  local e1, e2
  D.decompile(JARS.codec, "a.B", function(_, e) e1 = e end)
  D.decompile(JARS.codec, "a.C", function(_, e) e2 = e end)
  local warns = 0
  for _, n in ipairs(notes) do if n.msg:find("not installed", 1, true) then warns = warns + 1 end end
  rep("missing_jar", spawns == 0 and installs == 1 and warns == 1 and e1 and e1:find("jar missing") and e2 and e2:find("jar missing"),
    ("spawns=%d installs=%d warnings=%d e1=%s"):format(spawns, installs, warns, tostring(e1)))
  D.jar_path = real_jar
  D.install = real_install
end

-- install_verify: a stub curl writes a wrong file -> SHA-256 mismatch, nothing kept; a copy of the real jar -> kept.
do
  D.reset_for_tests()
  notes = {}
  local dir = "/tmp/nv4j/95_libnav_tools"
  local real_jar_file = real_jar() -- before tools_dir is stubbed (jar_path goes through it)
  vim.fn.delete(dir, "rf")
  D.tools_dir = function() return dir end
  D.jar_path = function() return dir .. "/cfr-" .. D.CFR.version .. ".jar" end
  local write = "garbage"
  D.spawn = function(cmd, opts, on_exit)
    local out = cmd[#cmd - 1] -- "-o", <tmp>, <url>
    if write == "garbage" then
      local f = io.open(out, "wb"); f:write("not a jar"); f:close()
    elseif exists(write) then
      vim.fn.system({ "cp", write, out })
    end
    on_exit({ code = 0, stdout = "", stderr = "" })
  end
  local ok1, m1
  D.install(function(ok, m) ok1, m1 = ok, m end)
  until_(5000, 50, function() return ok1 ~= nil end)
  local left_bad = exists(D.jar_path()) or exists(D.jar_path() .. ".part")
  local no_retry_ok, no_retry_msg
  D.install(function(ok, m) no_retry_ok, no_retry_msg = ok, m end)
  D.reset_for_tests()
  write = real_jar_file
  local ok2, m2 = nil, nil
  if exists(write) then
    D.install(function(ok, m) ok2, m2 = ok, m end)
    until_(10000, 50, function() return ok2 ~= nil end)
  else
    ok2, m2 = true, "SKIP second half: real jar absent"
  end
  rep("install_verify", ok1 == false and (m1 or ""):find("SHA%-256 mismatch") and not left_bad and no_retry_ok == false and (no_retry_msg or ""):find("failed earlier")
    and ok2 == true and (not exists(write) or exists(D.jar_path())),
    ("bad: ok=%s msg=%s left=%s; retry refused=%s; good: ok=%s msg=%s"):format(tostring(ok1), tostring(m1), tostring(left_bad), tostring(no_retry_ok), tostring(ok2), tostring(m2)))
  vim.fn.delete(dir, "rf")
  D.tools_dir, D.jar_path = real_tools, real_jar
end

-- after_open_stubbed: an empty jdt:// buffer is replaced through the wrapper's entry point; a Fernflower one is left alone.
do
  D.reset_for_tests()
  D.spawn = function(cmd, opts, on_exit) on_exit({ code = 0, stdout = "/*\n * Decompiled with CFR 0.152.\n */\npackage org.apache.commons.codec.binary;\npublic class Hex {}\n", stderr = "" }) end
  -- Names of their own: in the live run the real Hex buffer exists already (E95 on a duplicate name).
  local uri1 = (HEX_URI:gsub("Hex", "Hex95"))
  local b1 = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(b1, uri1)
  vim.api.nvim_buf_set_lines(b1, 0, -1, false, { "" })
  local t1 = exists(real_jar()) and D.after_open(b1, uri1)
  local l1 = until_(3000, 50, function() local l = vim.api.nvim_buf_get_lines(b1, 0, -1, false); return l[1] ~= "" and l or nil end) or {}
  local b2 = vim.api.nvim_create_buf(false, true)
  local uri2 = (HEX_URI:gsub("Hex", "Base64x95"))
  vim.api.nvim_buf_set_name(b2, uri2)
  local ff = { D.FERNFLOWER_HEADER, "package x;", "public class Base64 {}" }
  vim.api.nvim_buf_set_lines(b2, 0, -1, false, ff)
  local t2 = D.after_open(b2, uri2)
  sleep(300)
  local l2 = vim.api.nvim_buf_get_lines(b2, 0, -1, false)
  local skip = not exists(real_jar()) and " (SKIP first half: CFR jar absent)" or ""
  rep("after_open_stubbed", (skip ~= "" or (t1 == true and l1[1] == "// Decompiled with CFR 0.152 (Fernflower failed)" and l1[#l1] == "public class Hex {}" and not vim.bo[b1].modifiable))
    and t2 == false and vim.deep_equal(l2, ff),
    ("empty: triggered=%s line1=%s lines=%d; fernflower: triggered=%s unchanged=%s%s"):format(tostring(t1), tostring(l1[1]), #l1, tostring(t2), tostring(vim.deep_equal(l2, ff)), skip))
end

restore()
lsp.finish()
