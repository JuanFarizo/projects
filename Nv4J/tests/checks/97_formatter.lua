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
-- Live (one jdt.ls on a messy fixture, formatted over LSP with the options Neovim builds from the buffer, as <leader>cf does):
--  live_intellij / live_eclipse / live_switch_no_restart / live_back / live_google / live_path_project / live_project_eclipse : results differ per profile, same client id.
local lsp = require("lsp")
local P = "97_formatter."
local function rep(name, ok, detail) lsp.report(P .. name, ok and true or false, detail) end
local unit_only = vim.env.NV4J_97_UNIT == "1"
local TMP = "/tmp/nv4j/d97-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP .. "/data", "p")
vim.fn.mkdir(TMP .. "/state", "p")
TMP = vim.uv.fs_realpath(TMP)

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
local THREE = [[<?xml version="1.0"?><profiles version="21"><profile kind="CodeFormatterProfile" name="Three" version="21">]]
  .. [[<setting id="org.eclipse.jdt.core.formatter.tabulation.char" value="space"/>]]
  .. [[<setting id="org.eclipse.jdt.core.formatter.tabulation.size" value="3"/></profile></profiles>]]
local THREE0 = THREE

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
  local f = io.open(root .. "/cfg/my.xml", "w"); f:write(THREE0); f:close()
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

-- helpers for the scope / select / path cases
local sel_queue, sel_prompts = {}, {}
local real_select = vim.ui.select
vim.ui.select = function(items, opts, cb)
  sel_prompts[#sel_prompts + 1] = { items = items, prompt = opts.prompt }
  local want = table.remove(sel_queue, 1) -- a prefix of the item to pick, or false = cancel
  local pick
  if want then for _, it in ipairs(items) do if it:sub(1, #want) == want then pick = it break end end end
  cb(pick)
end
local function set_buf(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(b, path)
  vim.api.nvim_set_current_buf(b)
  return b
end
local function last() return notes[#notes] or "" end
local function slurp(p) local f = io.open(p, "rb"); if not f then return nil end local s = f:read("*a"); f:close(); return s end

-- path_forms: ~, quotes, '#' in a name, a directory, a file that is not an Eclipse XML, unknown name: each one a one-line message
do
  local root = TMP .. "/pf"
  vim.fn.mkdir(root .. "/dir.xml", "p")
  for _, n in ipairs({ "three.xml", "a#b.xml" }) do local f = io.open(root .. "/" .. n, "w"); f:write(THREE); f:close() end
  local f = io.open(root .. "/plain.txt", "w"); f:write("hello"); f:close()
  local home = vim.env.HOME
  vim.env.HOME = root
  local tilde = F.settings_of("~/three.xml", "/elsewhere")
  vim.env.HOME = home
  local quoted = F.settings_of('"' .. root .. '/three.xml"', "/elsewhere")
  local hash = F.settings_of("a#b.xml", root)
  local dir, dwhy = F.settings_of("dir.xml", root)
  local txt, twhy = F.settings_of("plain.txt", root)
  local b = set_buf(root .. "/A.java")
  clear_saved(); notes = {}
  vim.cmd("Nv4JFormatter goggle")
  local unk = last()
  vim.cmd("Nv4JFormatter dir.xml")
  local dmsg = last()
  vim.api.nvim_buf_delete(b, { force = true })
  rep("path_forms", tilde and tilde.url == vim.uri_from_fname(root .. "/three.xml") and tilde.profile == "Three"
    and tilde.indent and tilde.indent.size == 3 and tilde.indent.expandtab == true
    and quoted and quoted.url == tilde.url and hash and hash.url:find("a%%23b.xml") and dir == nil and dwhy:find("not a file", 1, true)
    and txt == nil and twhy:find("not an Eclipse formatter XML", 1, true) and unk:find("unknown profile 'goggle'", 1, true)
    and dmsg:find("not a file", 1, true) and F.saved() == nil,
    vim.inspect({ tilde and tilde.url, dwhy, twhy, unk, dmsg }):gsub("%s+", " "))
end

-- indent_sync: jdt.ls takes tabSize/insertSpaces from the client, so Java buffers follow the profile (google 2, intellij 4) and
-- eclipse puts the buffer's own values back (the live case proves the 2 spaces come out of jdt.ls)
do
  local b = vim.api.nvim_create_buf(true, false)
  vim.bo[b].shiftwidth, vim.bo[b].tabstop, vim.bo[b].expandtab = 8, 8, false
  local f = io.open(F.google_path(), "w"); f:write(slurp(REAL_GOOGLE) or '<profiles><profile name="GoogleStyle"><setting id="org.eclipse.jdt.core.formatter.tabulation.char" value="space"/><setting id="org.eclipse.jdt.core.formatter.tabulation.size" value="2"/></profile></profiles>'); f:close()
  local g = F.settings_of("google")
  F.sync_buffer(b, g)
  local sw_g, et_g = vim.bo[b].shiftwidth, vim.bo[b].expandtab
  F.sync_buffer(b, F.settings_of("intellij"))
  local sw_i = vim.bo[b].shiftwidth
  F.sync_buffer(b, F.settings_of("eclipse"))
  local back = { vim.bo[b].shiftwidth, vim.bo[b].tabstop, vim.bo[b].expandtab }
  vim.fn.delete(F.google_path())
  vim.api.nvim_buf_delete(b, { force = true })
  rep("indent_sync", g and g.indent and g.indent.size == 2 and sw_g == 2 and et_g == true and sw_i == 4 and back[1] == 8 and back[2] == 8 and back[3] == false,
    vim.inspect({ g and g.indent, sw_g, sw_i, back }):gsub("%s+", " "))
end

-- settings_set: .nv4j keeps the other fields; a non-JSON file is never overwritten; a missing file only with create
do
  local S = require("nv4j.settings")
  local root = TMP .. "/ss"
  vim.fn.mkdir(root, "p")
  local p = root .. "/.nv4j"
  local f = io.open(p, "w"); f:write('{"run":{"profile":"dev","env":{"A":"1"}},"spring_boot":"app"}'); f:close()
  local ok1 = S.set(root, "format_profile", "google")
  local d = vim.json.decode(slurp(p))
  f = io.open(p, "w"); f:write("{broken"); f:close()
  local p2, e2 = S.set(root, "format_profile", "google")
  local kept = slurp(p) == "{broken"
  f = io.open(p, "w"); f:write(""); f:close()
  S.set(root, "format_profile", "eclipse")
  local d3 = vim.json.decode(slurp(p))
  local p4, e4 = S.set(root .. "/none", "format_profile", "google")
  vim.fn.mkdir(root .. "/none", "p")
  local p5 = S.set(root .. "/none", "format_profile", "google", true)
  rep("settings_set", ok1 == p and d.format_profile == "google" and (d.run or {}).profile == "dev" and ((d.run or {}).env or {}).A == "1" and d.spring_boot == "app"
    and p2 == nil and e2:find("not a JSON object", 1, true) and kept and d3.format_profile == "eclipse"
    and p4 == nil and e4:find("does not exist", 1, true) and p5 and vim.uv.fs_stat(root .. "/none/.nv4j"), vim.inspect({ d, e2, d3, e4 }):gsub("%s+", " "))
end

-- project_scope: --project writes format_profile into .nv4j (other fields kept), asks before creating a missing file, says WHERE it
-- saved and what is effective; --global says the state file and warns when a .nv4j wins
do
  local root = TMP .. "/ps"
  local f
  vim.fn.mkdir(root, "p")
  f = io.open(root .. "/pom.xml", "w"); f:write("<project/>"); f:close()
  f = io.open(root .. "/three.xml", "w"); f:write(THREE); f:close()
  local b = set_buf(root .. "/src/A.java")
  f = io.open(root .. "/src/A.java", "w"); f:write("class A {}"); f:close()
  f = io.open(F.google_path(), "w"); f:write("<profiles><profile name=\"GoogleStyle\"/></profiles>"); f:close()
  clear_saved(); notes = {}; sel_queue, sel_prompts = {}, {}
  -- no .nv4j: declined -> nothing written
  sel_queue = { "No" }
  vim.cmd("Nv4JFormatter eclipse --project")
  local declined = vim.uv.fs_stat(root .. "/.nv4j") == nil and last():find("no .nv4j created", 1, true) ~= nil
    and sel_prompts[1] and sel_prompts[1].prompt:find("does not exist", 1, true) ~= nil
  -- accepted -> created, relative path kept as typed
  sel_queue = { "Yes" }
  vim.cmd("Nv4JFormatter three.xml --project")
  local created = vim.json.decode(slurp(root .. "/.nv4j") or "{}")
  local m1 = last()
  -- existing file with other fields: no prompt, fields kept
  f = io.open(root .. "/.nv4j", "w"); f:write('{"run":{"profile":"dev"}}'); f:close()
  sel_prompts = {}
  vim.cmd("Nv4JFormatter google --project")
  local d = vim.json.decode(slurp(root .. "/.nv4j"))
  local m2 = last()
  local noprompt = #sel_prompts == 0
  -- global while .nv4j wins
  vim.cmd("Nv4JFormatter eclipse")
  local m3 = last()
  vim.cmd("Nv4JFormatter")
  local status = notes[#notes - 0] or ""
  -- the real file was never created under the user's dirs, only the temp tree
  rep("project_scope", declined and created.format_profile == "three.xml" and m1:find(root .. "/.nv4j", 1, true) and m1:find("this project only", 1, true)
    and m1:find("Effective here: three.xml (from .nv4j", 1, true) and d.format_profile == "google" and d.run.profile == "dev" and noprompt
    and m2:find("saved to " .. root .. "/.nv4j", 1, true) and m3:find("saved globally in " .. F.state_file(), 1, true) and m3:find("NOTE: this project's .nv4j", 1, true)
    and m3:find("Effective here: google (from .nv4j", 1, true) and F.saved() == "eclipse" and status:find("from .nv4j: " .. root .. "/.nv4j", 1, true)
    and status:find("global choice eclipse in " .. F.state_file(), 1, true), vim.inspect({ m1, m2, m3, status }):gsub("%s+", " "))
  vim.fn.delete(F.google_path())
  vim.api.nvim_buf_delete(b, { force = true })
  clear_saved()
end

-- select_flow: no args = status line, then two steps (where, then which); `path` hands the typing to the native cmdline
-- (`:Nv4JFormatter --project `), not to vim.ui.input whose completion popup swallowed the first <CR>
do
  local root = TMP .. "/sf"
  vim.fn.mkdir(root, "p")
  local f = io.open(root .. "/pom.xml", "w"); f:write("<project/>"); f:close()
  f = io.open(root .. "/.nv4j", "w"); f:write("{}"); f:close()
  f = io.open(root .. "/my.xml", "w"); f:write(THREE); f:close()
  f = io.open(root .. "/A.java", "w"); f:write("class A {}"); f:close()
  local b = set_buf(root .. "/A.java")
  clear_saved(); notes = {}; sel_queue, sel_prompts = {}, {}
  local fed
  local real_feed = F.feed
  F.feed = function(t) fed = t end
  sel_queue = { "This project", "eclipse" }
  vim.cmd("Nv4JFormatter")
  local one = vim.json.decode(slurp(root .. "/.nv4j")).format_profile == "eclipse" and sel_prompts[1].items[1]:find(".nv4j", 1, true) and sel_prompts[1].items[2]:find("Global", 1, true)
    and sel_prompts[2].prompt:find("save: .nv4j", 1, true)
  sel_queue = { "Global", "path" }
  vim.cmd("Nv4JFormatter")
  vim.wait(500, function() return fed ~= nil end)
  local two = fed == "Nv4JFormatter --global "
  sel_queue = { "This project", "intellij" }
  vim.cmd("Nv4JFormatter")
  local three = vim.json.decode(slurp(root .. "/.nv4j")).format_profile == "intellij"
  sel_queue = { false } -- cancelled at step 1: nothing written
  local before = slurp(root .. "/.nv4j")
  vim.cmd("Nv4JFormatter")
  local four = slurp(root .. "/.nv4j") == before
  -- the command typed after `path`, with a relative file, global: saved absolute
  vim.cmd("Nv4JFormatter my.xml --global")
  local abs = F.saved() == root .. "/my.xml"
  F.feed = real_feed
  rep("select_flow", one and two and three and four and abs and notes[1]:find("^Java formatter: ") ~= nil,
    vim.inspect({ one, two, three, four, abs, fed, F.saved() }):gsub("%s+", " "))
  vim.api.nvim_buf_delete(b, { force = true })
  clear_saved()
end

-- failure_paths: every failure is one notification, never silent and never an error
do
  local root = TMP .. "/fp"
  vim.fn.mkdir(root, "p")
  local f = io.open(root .. "/pom.xml", "w"); f:write("<project/>"); f:close()
  f = io.open(root .. "/.nv4j", "w"); f:write("{bad"); f:close()
  f = io.open(root .. "/A.java", "w"); f:write("class A {}"); f:close()
  local b = set_buf(root .. "/A.java")
  clear_saved(); notes = {}
  local out = {}
  for _, cmd in ipairs({ "Nv4JFormatter eclipse --project", "Nv4JFormatter --bogus", "Nv4JFormatter nope.xml", "Nv4JFormatter intellij --project" }) do
    local n0 = #notes
    local ok, err = pcall(vim.cmd, cmd)
    out[#out + 1] = { ok, #notes - n0, last() }
  end
  local bad_kept = slurp(root .. "/.nv4j") == "{bad"
  vim.api.nvim_buf_delete(b, { force = true })
  clear_saved()
  local all = true
  for _, o in ipairs(out) do if not o[1] or o[2] < 1 then all = false end end
  rep("failure_paths", all and bad_kept and out[1][3]:find("not a JSON object", 1, true) and out[2][3]:find("unknown option", 1, true)
    and out[3][3]:find("not found", 1, true), vim.inspect(out):gsub("%s+", " "))
end
vim.ui.select = real_select

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
  vim.api.nvim_set_current_buf(buf)
  if not client then
    rep("live_ready", false, tostring(why))
  else
    local id0 = client.id
    local function fmt()
      local res, done
      client:request("textDocument/formatting", { textDocument = { uri = vim.uri_from_bufnr(buf) },
        options = vim.lsp.util.make_formatting_params().options }, function(err, r) res = err and { err = err } or (r or {}); done = true end, buf)
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
      vim.api.nvim_set_current_buf(buf)
      notes = {}
      vim.cmd("Nv4JFormatter google") -- the real command, no manual F.save/apply
      settle()
      local gmsg = notes[#notes] or ""
      local G = fmt()
      local sw = vim.bo[buf].shiftwidth
      -- Google's profile is 2 spaces / 100 columns. Before the indent sync jdt.ls got tabSize 4 from the buffer and printed 4 spaces.
      rep("live_google", G ~= nil and G ~= A and G ~= B and G:find("\n  private final", 1, true) ~= nil and not G:find("\n    private final", 1, true)
        and longest(G) <= 100 and sw == 2 and gmsg:find("1 jdt.ls updated", 1, true) ~= nil,
        ("google differs from both; indent 2 sw=%s; longest %s; %s"):format(sw, G and longest(G) or "?", gmsg))
      vim.fn.writefile(vim.split(G or "", "\n"), TMP .. "/live_google.txt")
    else
      rep("live_google", true, "SKIP: google XML not downloaded on this machine (:Nv4JFormatter google)")
    end

    -- a path (relative to the project root, written to .nv4j after the "create it?" prompt), 3 spaces / 60 columns
    local cfg = io.open(root .. "/cfg.xml", "w")
    cfg:write('<?xml version="1.0"?><profiles version="21"><profile kind="CodeFormatterProfile" name="Three" version="21">'
      .. '<setting id="org.eclipse.jdt.core.formatter.tabulation.char" value="space"/>'
      .. '<setting id="org.eclipse.jdt.core.formatter.tabulation.size" value="3"/>'
      .. '<setting id="org.eclipse.jdt.core.formatter.indentation.size" value="3"/>'
      .. '<setting id="org.eclipse.jdt.core.formatter.lineSplit" value="60"/></profile></profiles>')
    cfg:close()
    local real_select = vim.ui.select
    vim.ui.select = function(items, _, cb) cb(items[1]) end -- "Yes, create .../.nv4j"
    notes = {}
    vim.cmd("Nv4JFormatter cfg.xml --project")
    vim.ui.select = real_select
    settle()
    local pmsg = notes[#notes] or ""
    local Pm = fmt()
    local nv4j = io.open(root .. "/.nv4j", "r")
    local nv4j_txt = nv4j and nv4j:read("*a") or ""
    if nv4j then nv4j:close() end
    rep("live_path_project", Pm ~= nil and Pm:find("\n   private final", 1, true) ~= nil and not Pm:find("\n    private final", 1, true)
      and longest(Pm) <= 70 and nv4j_txt:find('"format_profile": "cfg.xml"', 1, true) ~= nil and pmsg:find(root .. "/.nv4j", 1, true) ~= nil
      and vim.bo[buf].shiftwidth == 3, ("longest %s; .nv4j %s; %s"):format(Pm and longest(Pm) or "?", nv4j_txt:gsub("%s+", " "), pmsg))
    vim.fn.writefile(vim.split(Pm or "", "\n"), TMP .. "/live_path.txt")

    -- back to eclipse for this project only (.nv4j), then the buffer keeps its own indent again
    vim.cmd("Nv4JFormatter eclipse --project")
    settle()
    local E2 = fmt()
    rep("live_project_eclipse", E2 == B and vim.bo[buf].shiftwidth == 4, "eclipse via .nv4j equals the earlier eclipse result: " .. tostring(E2 == B))
  end
  vim.lsp.start = orig_start
  vim.g.nv4j_format_profile = nil
end

vim.fn.delete(TMP .. "/data", "rf")
lsp.finish()
