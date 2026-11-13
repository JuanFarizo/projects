-- Java formatter profiles + :Nv4JFormatter (specs/features/formatter.md). Everything runs in a temp tree /tmp/nv4j/d97-<pid>:
-- the formatter module's data dir and state file are stubbed there (the real ones are never touched), nothing is downloaded
-- (the spawn is stubbed). NV4J_97_UNIT=1 runs only the pure cases (tests/lib/control_97.sh uses it).
-- Pure cases:
--  zero_cost_startup : nv4j.formatter not loaded when the config has started.
--  xml               : the intellij table becomes XML with lineSplit 120, tabulation.char space, size 4, a named profile.
--  xml_written       : ensure_intellij writes the file once (rewrite only when it differs); the URL is a file:// URL.
--  precedence        : .nv4j > saved > vim.g > default, each one alone and in the chain.
--  path_resolution   : absolute kept, relative joined to the project root; missing file -> nil + reason.
--  persistence       : save() then saved() in the temp state dir; garbage in the file -> nil.
--  settings_of       : eclipse = no url; intellij/google/path = url (+ profile name for the first two).
--  google_install    : stubbed curl: bad SHA refused (no file kept), good SHA kept at the pinned path.
--  command_switch    : :Nv4JFormatter eclipse saves the choice; with .nv4j set the effective source stays .nv4j.
-- (intellij keeps 2 blank lines, jdt.ls built-in 1; both wrap at 120, google at 100)
-- Live (one jdt.ls on a messy fixture, formatted over LSP with tabSize 4 / insertSpaces):
--  live_intellij / live_eclipse / live_switch_no_restart / live_back / live_google : results differ per profile, same client id.
local lsp = require("lsp")
local P = "97_formatter."
local function rep(name, ok, detail) lsp.report(P .. name, ok and true or false, detail) end
local unit_only = vim.env.NV4J_97_UNIT == "1"
local TMP = "/tmp/nv4j/d97-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP .. "/data", "p")
vim.fn.mkdir(TMP .. "/state", "p")

rep("zero_cost_startup", package.loaded["nv4j.formatter"] == nil, "loaded at startup: " .. tostring(package.loaded["nv4j.formatter"] ~= nil))
pcall(require, "lazyvim.config.keymaps")
pcall(require, "config.keymaps")

local F = require("nv4j.formatter")
local REAL_GOOGLE = F.google_path()
F.data_dir = function() return TMP .. "/data" end
F.state_file = function() return TMP .. "/state/formatter.json" end
local notes = {}
F.notify = function(msg) notes[#notes + 1] = msg end
local function nv4j_file(dir, tbl)
  vim.fn.mkdir(dir, "p")
  local f = io.open(dir .. "/.nv4j", "w"); f:write(tbl and vim.json.encode(tbl) or ""); f:close()
end
local function clear_saved() vim.fn.delete(F.state_file()) end

-- xml
do
  local x = F.xml()
  rep("xml", x:find('lineSplit" value="120"', 1, true) and x:find('tabulation.char" value="space"', 1, true)
    and x:find('tabulation.size" value="4"', 1, true) and x:find('name="Nv4J-IntelliJ"', 1, true) and not x:find("tab\"%s*/>"),
    "xml bytes: " .. #x)
end

-- xml_written
do
  local p = F.ensure_intellij()
  local st1 = vim.uv.fs_stat(p)
  vim.wait(1100)
  F.ensure_intellij()
  local st2 = vim.uv.fs_stat(p)
  local url = F.settings_of("intellij").url
  rep("xml_written", st1 and st2 and st1.mtime.sec == st2.mtime.sec and st1.mtime.nsec == st2.mtime.nsec and url:find("^file://") ~= nil
    and p:find(TMP, 1, true) == 1, "mtime unchanged on second call; url " .. tostring(url))
end

-- precedence
do
  local root = TMP .. "/proj"
  nv4j_file(root, nil)
  clear_saved(); vim.g.nv4j_format_profile = nil
  local a = { F.resolve(root) }
  vim.g.nv4j_format_profile = "eclipse"
  local b = { F.resolve(root) }
  F.save("google")
  local c = { F.resolve(root) }
  nv4j_file(root, { format_profile = "custom.xml" })
  local d = { F.resolve(root) }
  nv4j_file(root, { format_profile = 5 }) -- wrong type: ignored
  local e = { F.resolve(root) }
  nv4j_file(root, nil)
  vim.g.nv4j_format_profile = nil
  clear_saved()
  rep("precedence", a[1] == "intellij" and a[2] == "default" and b[1] == "eclipse" and b[2]:find("vim.g", 1, true)
    and c[1] == "google" and c[2] == "saved" and d[1] == "custom.xml" and d[2] == ".nv4j" and e[1] == "google" and e[2] == "saved",
    vim.inspect({ a, b, c, d, e }):gsub("%s+", " "))
end

-- path_resolution
do
  local root = TMP .. "/proj"
  vim.fn.mkdir(root .. "/cfg", "p")
  local f = io.open(root .. "/cfg/my.xml", "w"); f:write("<profiles/>"); f:close()
  local rel = F.settings_of("cfg/my.xml", root)
  local abs = F.settings_of(root .. "/cfg/my.xml", "/elsewhere")
  local miss, why = F.settings_of("nope.xml", root)
  rep("path_resolution", rel and rel.url == vim.uri_from_fname(root .. "/cfg/my.xml") and abs and abs.url == rel.url and miss == nil
    and why:find("not found", 1, true) ~= nil, ("rel=%s miss=%s"):format(tostring(rel and rel.url), tostring(why)))
end

-- persistence
do
  clear_saved()
  local none = F.saved()
  F.save("cfg/my.xml")
  local got = F.saved()
  local f = io.open(F.state_file(), "w"); f:write("{not json"); f:close()
  local bad = F.saved()
  clear_saved()
  rep("persistence", none == nil and got == "cfg/my.xml" and bad == nil, ("none=%s got=%s bad=%s"):format(tostring(none), tostring(got), tostring(bad)))
end

-- settings_of
do
  local e, i = F.settings_of("eclipse"), F.settings_of("intellij")
  local g0 = F.settings_of("google")
  local f = io.open(F.google_path(), "w"); f:write("x"); f:close()
  local g1 = F.settings_of("google")
  vim.fn.delete(F.google_path())
  rep("settings_of", e and e.url == nil and e.profile == nil and i.url and i.profile == "Nv4J-IntelliJ" and g0 == nil
    and g1 and g1.url and g1.profile == "GoogleStyle", "eclipse/intellij/google ok")
end

-- google_install (stubbed curl)
do
  F.reset_for_tests()
  local payload
  F.spawn = function(cmd, _, on_exit)
    local out = cmd[#cmd - 1]
    local f = io.open(out, "w"); f:write(payload); f:close()
    on_exit({ code = 0, stdout = "", stderr = "" })
  end
  local r1, r2
  payload = "not the google file"
  F.install(function(ok, msg) r1 = { ok, msg } end)
  vim.wait(2000, function() return r1 ~= nil end, 20)
  local kept_bad = vim.uv.fs_stat(F.google_path()) ~= nil
  -- the real file, copied only if present locally (no download)
  local real = io.open(REAL_GOOGLE, "rb")
  if real then
    payload = real:read("*a"); real:close()
    F.reset_for_tests()
    F.install(function(ok, msg) r2 = { ok, msg } end)
    vim.wait(2000, function() return r2 ~= nil end, 20)
  end
  local ok_good = (not real) or (r2 and r2[1] and vim.uv.fs_stat(F.google_path()) ~= nil)
  vim.fn.delete(F.google_path())
  F.spawn = function(...) error("unexpected spawn") end
  rep("google_install", r1 and r1[1] == false and tostring(r1[2]):find("SHA%-256 mismatch") and not kept_bad and ok_good,
    ("bad: %s kept=%s; good: %s%s"):format(vim.inspect(r1):gsub("%s+", " "), tostring(kept_bad), tostring(ok_good), real and "" or " (SKIP: real file not on this machine)"))
end

-- command_switch
do
  local root = TMP .. "/proj2"
  nv4j_file(root, { format_profile = "google" })
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(b, root .. "/A.java")
  vim.api.nvim_set_current_buf(b)
  clear_saved(); notes = {}
  vim.cmd("Nv4JFormatter eclipse")
  local saved = F.saved()
  local msg = notes[#notes] or ""
  vim.cmd("Nv4JFormatter nope/missing.xml")
  local saved2 = F.saved()
  nv4j_file(root, nil)
  clear_saved()
  vim.api.nvim_buf_delete(b, { force = true })
  rep("command_switch", saved == "eclipse" and msg:find("from .nv4j", 1, true) and msg:find("Effective here: google", 1, true)
    and saved2 == "eclipse" and (notes[#notes] or ""):find("not found", 1, true), msg)
end

if not unit_only then
  local root = TMP .. "/live"
  vim.fn.mkdir(root .. "/src/main/java/demo", "p")
  local pom = io.open(root .. "/pom.xml", "w")
  pom:write([[<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>
<groupId>demo</groupId><artifactId>fmt</artifactId><version>1</version>
<properties><maven.compiler.release>21</maven.compiler.release><project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>
</project>
]]); pom:close()
  local src = [[
package demo;
import java.util.*;
public class Messy {
  private final Map<String,List<String>> index = new HashMap<>();



  public String describe(String firstArgument, String secondArgument, String thirdArgument) {
    String result = String.join(",", firstArgument, secondArgument, thirdArgument, firstArgument, "tail");
    if(result.length()>3){return result.toUpperCase().trim().substring(0, 2).concat(secondArgument).concat(thirdArgument);}
    return result;
  }
}
]]
  local fpath = root .. "/src/main/java/demo/Messy.java"
  local f = io.open(fpath, "w"); f:write(src); f:close()
  -- fixed workspace name, fresh jdt.ls data, offline import (same as check 95)
  local wsname = vim.fs.basename(root) .. "-" .. vim.fn.sha256(root):sub(1, 8)
  vim.fn.delete(require("nv4j.paths").jdtls_data .. "/" .. wsname, "rf")
  local orig_start = vim.lsp.start
  vim.lsp.start = function(config, opts)
    if config and config.name == "jdtls" then
      config.settings = vim.tbl_deep_extend("force", config.settings or {}, { java = { import = { maven = { offline = { enabled = true } } } } })
    end
    return orig_start(config, opts)
  end
  F.google_path = function() return REAL_GOOGLE end
  clear_saved(); vim.g.nv4j_format_profile = nil
  local buf = lsp.open(fpath)
  local client, why = lsp.wait_ready(buf, 240000)
  if not client then
    rep("live_ready", false, tostring(why))
  else
    local id0 = client.id
    local function fmt()
      local res, done
      client:request("textDocument/formatting", { textDocument = { uri = vim.uri_from_bufnr(buf) },
        options = { tabSize = 4, insertSpaces = true } }, function(err, r) res = err and { err = err } or (r or {}); done = true end, buf)
      vim.wait(30000, function() return done end, 50)
      if not res or res.err then return nil, vim.inspect(res) end
      -- apply to a scratch copy of the text
      local sb = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(sb, 0, -1, false, vim.split(src, "\n", { plain = true }))
      vim.lsp.util.apply_text_edits(res, sb, "utf-16")
      local out = table.concat(vim.api.nvim_buf_get_lines(sb, 0, -1, false), "\n")
      vim.api.nvim_buf_delete(sb, { force = true })
      return out
    end
    local function longest(t) local m = 0 for l in t:gmatch("[^\n]+") do m = math.max(m, #l) end return m end
    local function settle() vim.wait(800) end

    local A = fmt()
    rep("live_intellij", A ~= nil and A:find("\n    private final", 1, true) ~= nil and not A:find("\n\n\n\n", 1, true) and longest(A) <= 120,
      ("longest line %s; url %s"):format(A and longest(A) or "?", vim.inspect(vim.tbl_get(client.config.settings, "java", "format", "settings", "url"))))
    vim.fn.writefile(vim.split(A or "", "\n"), TMP .. "/live_intellij.txt")

    F.save("eclipse")
    local n = F.apply(); settle()
    local B = fmt()
    vim.fn.writefile(vim.split(B or "", "\n"), TMP .. "/live_eclipse.txt")
    rep("live_eclipse", B ~= nil and A ~= nil and B ~= A and n >= 1 and A:find("\n\n\n    public", 1, true) ~= nil and not B:find("\n\n\n", 1, true), ("applied to %d client(s); intellij %d lines, eclipse %d lines"):format(n, #vim.split(A or "", "\n"), #vim.split(B or "", "\n")))
    rep("live_switch_no_restart", vim.lsp.get_client_by_id(id0) ~= nil and not client:is_stopped() and #vim.lsp.get_clients({ name = "jdtls" }) == 1,
      "same jdtls client id " .. id0)

    F.save("intellij")
    F.apply(); settle()
    local A2 = fmt()
    rep("live_back", A2 == A, "intellij again equals the first intellij result: " .. tostring(A2 == A))

    if vim.uv.fs_stat(REAL_GOOGLE) then
      F.save("google")
      F.apply(); settle()
      local G = fmt()
      rep("live_google", G ~= nil and G ~= A and G ~= B, ("google differs from both; longest %s"):format(G and longest(G) or "?"))
    else
      rep("live_google", true, "SKIP: google XML not downloaded on this machine (:Nv4JFormatter google)")
    end
  end
  vim.lsp.start = orig_start
  vim.g.nv4j_format_profile = nil
end

vim.fn.delete(TMP .. "/data", "rf")
lsp.finish()
