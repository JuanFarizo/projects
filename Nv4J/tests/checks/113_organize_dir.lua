-- Organize imports for a folder / the project (nv4j/organize.lua, jdt.ls command java.edit.organizeImports). Run via tests/run.sh
-- (live jdt.ls on a temp Maven project under /tmp/nv4j/d113-<pid>). Spec: specs/features/organize-imports-dir.md.
--  attached        : jdt.ls ready on the temp project.
--  keys            : `<leader>cI` is mapped (desc says folder/project); the neo-tree config maps `O` to a command that exists.
--  dir_scope       : run(<package folder a>) changes exactly its 2 messy files (unused import gone, rest sorted), files outside it
--                    (b, c/d) stay byte for byte; reply says 2 files; both saved to disk.
--  message         : the notification says "Organized imports in 2 files under <dir>".
--  project_scope   : run(<project root>) now changes the remaining 3 messy files (b/Messy, c/d/Deep, and the dirty one below).
--  dirty_not_saved : a buffer with unsaved edits is organized in the buffer but NOT written; the message says so (1 not saved).
--  again_zero      : a second project run changes nothing: "already organized", 0 files.
--  no_client       : a folder outside every jdt.ls project: WARN, no crash, files = 0, err set.
local lsp = require("lsp")
local P = "113_organize_dir."
local rep = function(n, ok, d) lsp.report(P .. n, ok, d) end
vim.o.confirm = false

local DIR = "/tmp/nv4j/d113-" .. vim.fn.getpid()
vim.fn.delete(DIR, "rf")
local SRC = DIR .. "/src/main/java"
local function write(rel, lines)
  vim.fn.mkdir(vim.fs.dirname(SRC .. "/" .. rel), "p")
  vim.fn.writefile(lines, SRC .. "/" .. rel)
end
local function messy(pkg, cls)
  return {
    "package " .. pkg .. ";",
    "",
    "import java.util.Map;",
    "import java.util.List;", -- unused
    "import java.io.File;",
    "import java.util.ArrayList;",
    "",
    "public class " .. cls .. " {",
    "    ArrayList<String> a = new ArrayList<>();",
    "    Map<String, String> m;",
    "    File f;",
    "}",
  }
end
vim.fn.writefile({
  '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>',
  "<groupId>d113</groupId><artifactId>d113</artifactId><version>1</version>",
  "<properties><maven.compiler.release>21</maven.compiler.release>",
  "<project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties></project>",
}, (function() vim.fn.mkdir(DIR, "p"); return DIR .. "/pom.xml" end)())
write("a/One.java", messy("a", "One"))
write("a/Two.java", messy("a", "Two"))
write("b/Messy.java", messy("b", "Messy"))
write("b/Dirty.java", messy("b", "Dirty"))
write("b/Clean.java", { "package b;", "", "public class Clean {}" })
write("c/d/Deep.java", messy("c.d", "Deep"))
vim.fn.mkdir(DIR .. "/outside", "p")

local function read(rel) return table.concat(vim.fn.readfile(SRC .. "/" .. rel), "\n") end
local before = {}
for _, f in ipairs({ "a/One.java", "a/Two.java", "b/Messy.java", "b/Dirty.java", "b/Clean.java", "c/d/Deep.java" }) do before[f] = read(f) end

local buf = lsp.open(SRC .. "/b/Clean.java")
local client, why = lsp.wait_ready(buf, 180000)
rep("attached", client ~= nil, client and "jdtls ready" or why)
if not client then return lsp.finish() end

pcall(require, "config.keymaps")
local map = vim.fn.maparg("<leader>cI", "n", false, true)
local spec = require("plugins.neo-tree")
local o = spec.opts
rep("keys", (map.desc or ""):find("folder/project", 1, true) ~= nil and o.window.mappings.O == "nv4j_organize_imports"
  and type(o.commands.nv4j_organize_imports) == "function",
  ("<leader>cI desc=%s; neo-tree O=%s"):format(tostring(map.desc), tostring(o.window.mappings.O)))

local notes = {}
local orig_notify = vim.notify
vim.notify = function(msg, level, opts) notes[#notes + 1] = { msg = tostring(msg), level = level, title = opts and opts.title } end

local function run(dir)
  local res
  require("nv4j.organize").run(dir, function(r) res = r end)
  vim.wait(60000, function() return res ~= nil end, 50)
  return res
end
local function organized(text)
  return not text:find("import java.util.List;", 1, true)
    and text:find("import java.io.File;\nimport java.util.ArrayList;\nimport java.util.Map;", 1, true) ~= nil
end

-- the dirty one: open it and change something harmless without saving (jdt.ls gets the unsaved text)
local dbuf = vim.fn.bufadd(SRC .. "/b/Dirty.java")
vim.fn.bufload(dbuf)
vim.bo[dbuf].filetype = "java"
vim.api.nvim_buf_set_lines(dbuf, -1, -1, false, { "// unsaved edit" })
vim.wait(1500, function() return false end, 100)

local r1 = run(SRC .. "/a")
local msg1 = notes[#notes] and notes[#notes].msg or ""
local ok_dir = r1.files == 2 and organized(read("a/One.java")) and organized(read("a/Two.java"))
  and read("b/Messy.java") == before["b/Messy.java"] and read("c/d/Deep.java") == before["c/d/Deep.java"]
  and read("b/Dirty.java") == before["b/Dirty.java"] and r1.saved == 2
rep("dir_scope", ok_dir, ("files=%s saved=%s; b/Messy untouched=%s; err=%s"):format(tostring(r1.files), tostring(r1.saved),
  tostring(read("b/Messy.java") == before["b/Messy.java"]), tostring(r1.err)))
rep("message", msg1:find("Organized imports in 2 files under", 1, true) ~= nil, msg1)

local r2 = run(DIR)
local msg2 = notes[#notes] and notes[#notes].msg or ""
rep("project_scope", r2.files == 3 and organized(read("b/Messy.java")) and organized(read("c/d/Deep.java")),
  ("files=%s saved=%s %s"):format(tostring(r2.files), tostring(r2.saved), msg2))
local dtext = table.concat(vim.api.nvim_buf_get_lines(dbuf, 0, -1, false), "\n")
rep("dirty_not_saved", organized(dtext) and read("b/Dirty.java") == before["b/Dirty.java"] and r2.saved == 2
  and msg2:find("1 not saved", 1, true) ~= nil, ("saved=%s; buffer organized=%s; disk unchanged=%s; %s"):format(tostring(r2.saved),
  tostring(organized(dtext)), tostring(read("b/Dirty.java") == before["b/Dirty.java"]), msg2))

local r3 = run(DIR)
local msg3 = notes[#notes] and notes[#notes].msg or ""
rep("again_zero", r3.files == 0 and msg3:find("already organized", 1, true) ~= nil, ("files=%s %s"):format(tostring(r3.files), msg3))

notes = {}
local r4 = run("/tmp/nv4j/d113-nowhere-" .. vim.fn.getpid())
rep("no_client", r4.files == 0 and r4.err ~= nil and notes[1] and notes[1].level == vim.log.levels.WARN, vim.inspect(r4) .. " " .. vim.inspect(notes))

vim.notify = orig_notify
vim.fn.delete(DIR, "rf")
lsp.finish()
