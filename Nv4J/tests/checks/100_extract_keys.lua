-- Extract / inline keys pressed for real (nv4j/extract.lua, specs/features/code-actions.md "Pressed keys"). Check 91 applies the
-- same jdt.ls actions from Lua (code action request, require("jdtls").extract_constant(true) with marks set from Lua) and only asks
-- that the mapping exists; this one starts ONE real nvim (NVIM_APPNAME=nv4j) in a private tmux server (`tmux -L xc100-<pid>`), with ONE
-- jdt.ls on a tiny Maven project it writes to /tmp/nv4j/d100-<pid>, sends the keystrokes with `tmux send-keys` and reads the
-- BUFFER text (nvim --server ... --remote-expr) and the screen (capture-pane). Pure check: this headless nvim has no jdt.ls
-- (tests/lib/run1.sh 100_extract_keys). Nothing in tests/fixtures or the user's projects is touched; no process is killed by name.
-- Cases (package demo.xc and the default package; text compared exactly unless the name says a pattern):
--  cxc_normal_pick       : <leader>cxc, cursor on the `2` of `2 * 3`: the "Choices" picker appears, Down + Enter = `2 * 3`,
--                          private static final int INT = 2 * 3; both uses replaced.
--  cxc_visual            : `v4l` on `2 * 3`, <leader>cxc: same result, no picker.
--  cxc_visual_quotes     : `vi"` INSIDE the string (what users press), <leader>cxc: the selection widens to the quotes,
--                          STRING = "\r\n", both uses replaced (before extract.lua: nothing happened, no message).
--  cxc_ca_menu           : <leader>ca, filter "to constant", Enter on the literal 42: `_42` declared, the first use replaced
--                          (jdt.ls replaces only the selected occurrence of a lone number literal; strings and `2 * 3` replace all).
--  cxc_default_package   : the same <leader>cxc on a string in a default-package class.
--  cxc_nothing_cursor    : cursor on whitespace: one WARN on screen "nothing under the cursor", buffer unchanged.
--  cxc_nothing_selection : `viw` on one backslash: WARN "not a whole expression", buffer unchanged.
--  cxv_normal / cxv_visual / cxm_visual / ji_inline / co_organize / ca_lambda : the other basics, by key.
local lsp = require("lsp")
local P = "100_extract_keys."
local function rep(name, ok, detail) lsp.report(P .. name, ok and true or false, detail) end

local PID = vim.fn.getpid()
local ROOT = "/tmp/nv4j/d100-" .. PID
local SOCK = "/tmp/nv4j/d100-" .. PID .. ".sock"
local TM = "xc100-" .. PID
local function w(rel, s) vim.fn.mkdir(vim.fs.dirname(ROOT .. "/" .. rel), "p"); local f = io.open(ROOT .. "/" .. rel, "w"); f:write(s); f:close() end

-- No tmux = nothing to press keys in: SKIP (reported as PASS with the reason, like checks 21/95/97); the keys are exercised only where tmux exists.
if vim.fn.executable("tmux") ~= 1 then rep("tmux", true, "SKIP: tmux not installed, the pressed-keys cases need a private tmux server") lsp.finish() return end

vim.fn.delete(ROOT, "rf")
w("pom.xml", [[<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>
<groupId>demo</groupId><artifactId>d100</artifactId><version>1</version>
<properties><maven.compiler.release>21</maven.compiler.release><project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>
</project>
]])
local CALC = [[package demo.xc;

import java.util.List;
import java.util.Map;

public class Calc {
    int f() {
        int a = 2 * 3;
        int b = 2 * 3 + 1;
        return a + b;
    }

    String g() {
        String s = "\r\n";
        return s + "\r\n";
    }

    int h() {
        int x = 42;
        return x + 42;
    }

    int v(int x) {
        int y = x * 2 + 1;
        return y + 3;
    }

    int m(int x) {
        int t = x + 1;
        int u = t * 2;
        return u;
    }

    int inl(int a) {
        int b = a + 1;
        return b * 2;
    }

    Runnable r() {
        Runnable r = new Runnable() {
            public void run() {
                System.out.println("hi");
            }
        };
        return r;
    }
}
]]
local DP = [[public class Dp {
    String g() {
        String s = "\r\n";
        return s + "\r\n";
    }
}
]]
w("src/main/java/demo/xc/Calc.java", CALC)
w("src/main/java/Dp.java", DP)
local wsname = vim.fs.basename(ROOT) .. "-" .. vim.fn.sha256(ROOT):sub(1, 8)
vim.fn.delete(require("nv4j.paths").jdtls_data .. "/" .. wsname, "rf")

-- ── helpers ───────────────────────────────────────────────────────────────────────────────────────────────────
local function tmux(...) return vim.system({ "tmux", "-L", TM, ... }, { text = true }):wait() end
local function key(...) tmux("send-keys", "-t", "x", ...) end                -- named keys: Escape Enter Space Down
local function lit(s) tmux("send-keys", "-t", "x", "-l", s) end              -- literal text
local function screen() return tmux("capture-pane", "-p", "-t", "x").stdout or "" end
local function expr(e) -- evaluated in the nested nvim (its own socket), nothing is typed
  local r = vim.system({ "nvim", "--server", SOCK, "--remote-expr", e }, { text = true }):wait()
  return r.code == 0 and (r.stdout or ""):gsub("\n$", "") or nil
end
local function text()
  local j = expr("json_encode(getline(1,'$'))")
  local ok, t = pcall(vim.json.decode, j or "")
  return ok and type(t) == "table" and table.concat(t, "\n") .. "\n" or nil
end
local function wait(ms, pred)
  local ok = vim.wait(ms, function() local o, v = pcall(pred); return o and v end, 300)
  return ok
end
local function cmd(c) lit(c); key("Enter") end

local function cleanup()
  pcall(function() tmux("send-keys", "-t", "x", "Escape"); tmux("send-keys", "-t", "x", "-l", ":qa!"); tmux("send-keys", "-t", "x", "Enter") end)
  vim.wait(1500)
  tmux("kill-server")
  vim.fn.delete(SOCK)
  vim.fn.delete(ROOT, "rf")
  vim.fn.delete(require("nv4j.paths").jdtls_data .. "/" .. wsname, "rf")
end

tmux("kill-server")
vim.fn.delete(SOCK)
local sh = ("cd %s && env -u JAVA_HOME NVIM_APPNAME=nv4j nvim --listen %s src/main/java/demo/xc/Calc.java"):format(ROOT, SOCK)
local st = tmux("new-session", "-d", "-s", "x", "-x", "200", "-y", "50", sh)
if st.code ~= 0 then rep("start", false, "tmux new-session: " .. tostring(st.stderr)) cleanup() lsp.finish() return end

-- ready: jdt.ls attached, the buffer analysed (the unused imports are reported) and the extract maps are the Nv4J ones
local ready = wait(240000, function()
  return expr("luaeval(\"#vim.lsp.get_clients({name='jdtls',bufnr=0})\")") == "1" and tonumber(expr("luaeval('#vim.diagnostic.get(0)')") or "0") > 0
end)
if not ready then rep("ready", false, "jdt.ls not attached / no diagnostics in 240 s; screen:\n" .. screen()) cleanup() lsp.finish() return end
local m = expr("maparg(' cxc', 'n', 0, 1).desc")
rep("ready", true, "jdt.ls attached, buffer analysed; <leader>cxc desc: " .. tostring(m))

local function revert(want)
  -- <leader>ji (nv4j/refactor.lua) writes the file: put the original back on disk before reloading
  w("src/main/java/demo/xc/Calc.java", CALC); w("src/main/java/Dp.java", DP)
  key("Escape"); key("Escape"); cmd(":e!")
  return wait(8000, function() return text() == want end)
end
local function goto_(pat, nth, off) -- cursor on the nth match of a plain pattern (+ char offset)
  local t = text() or ""
  local n, l = 0, 0
  for line in (t .. "\n"):gmatch("(.-)\n") do
    l = l + 1
    local s = line:find(pat, 1, true)
    if s then n = n + 1; if n == (nth or 1) then cmd((":call cursor(%d,%d)"):format(l, s + (off or 0))) return true end end
  end
  return false
end
local function replace(t, a, b, count) -- plain replace of the first `count` (default all) occurrences
  local out, i, n = {}, 1, 0
  while true do
    local s, e = t:find(a, i, true)
    if not s or (count and n >= count) then break end
    out[#out + 1] = t:sub(i, s - 1) .. b; i = e + 1; n = n + 1
  end
  out[#out + 1] = t:sub(i)
  return table.concat(out)
end
local function after_class(t, decl) return replace(t, "public class Calc {\n", "public class Calc {\n    " .. decl .. "\n\n", 1) end

local function case(name, base, body)
  local ok, err = pcall(function()
    if not revert(base) then rep(name, false, "could not restore the buffer; screen:\n" .. screen()) return end
    body()
  end)
  if not ok then rep(name, false, "error: " .. tostring(err)) end
end
local function expect_text(name, want, shown, extra)
  local ok = wait(20000, function() return text() ~= nil and text() ~= extra end)
  vim.wait(1500)
  local got = text()
  rep(name, got == want, got == want and (shown or "text exact") or ("text differs. got:\n" .. tostring(got) .. "\n--- want:\n" .. want .. "\n--- screen:\n" .. screen()))
end
local function leader(...) key("Space"); for _, k in ipairs({ ... }) do lit(k) end end

-- ── cases ─────────────────────────────────────────────────────────────────────────────────────────────────────
local INT_ALL = replace(after_class(CALC, "private static final int INT = 2 * 3;"), "2 * 3;\n        int b", "INT;\n        int b")
INT_ALL = replace(INT_ALL, "int b = 2 * 3 + 1", "int b = INT + 1")
local STR_ALL = replace(replace(after_class(CALC, 'private static final String STRING = "\\r\\n";'), 'String s = "\\r\\n";', "String s = STRING;"), 'return s + "\\r\\n";', "return s + STRING;")

case("cxc_normal_pick", CALC, function()
  goto_("int a = 2 * 3;", 1, 8) -- the `2`
  leader("cxc")
  local pick = wait(20000, function() return screen():find("Choices", 1, true) ~= nil end)
  if not pick then rep("cxc_normal_pick", false, "no Choices picker; screen:\n" .. screen()) return end
  wait(10000, function() return screen():find("2 / 2", 1, true) ~= nil end); vim.wait(700) -- the list is drawn
  key("Down"); key("Enter")
  expect_text("cxc_normal_pick", INT_ALL, "picker shown, Down+Enter, INT = 2 * 3, both uses replaced", CALC)
end)

case("cxc_visual", CALC, function()
  goto_("int a = 2 * 3;", 1, 8)
  lit("v4l"); leader("cxc")
  expect_text("cxc_visual", INT_ALL, "v4l then <leader>cxc, INT = 2 * 3, both uses replaced", CALC)
end)

case("cxc_visual_quotes", CALC, function()
  goto_('String s = "', 1, 13) -- inside the quotes
  lit('vi"'); leader("cxc")
  expect_text("cxc_visual_quotes", STR_ALL, 'vi" widened to the quotes, STRING = "\\r\\n", both uses replaced', CALC)
end)

case("cxc_ca_menu", CALC, function()
  goto_("int x = 42;", 1, 8) -- the `4`
  leader("ca")
  if not wait(20000, function() return screen():find("Code actions", 1, true) ~= nil end) then rep("cxc_ca_menu", false, "no code action menu; screen:\n" .. screen()) return end
  lit("to constant"); vim.wait(800); key("Enter")
  local want = replace(after_class(CALC, "private static final int _42 = 42;"), "int x = 42;", "int x = _42;")
  expect_text("cxc_ca_menu", want, "menu, filter, Enter: _42 declared, first use replaced", CALC)
end)

case("cxc_nothing_cursor", CALC, function()
  goto_("int a = 2 * 3;", 1, 0) -- on the indentation
  leader("cxc")
  local shown = wait(20000, function() return screen():find("nothing under the cursor", 1, true) ~= nil end)
  vim.wait(500)
  rep("cxc_nothing_cursor", shown and text() == CALC, shown and "WARN on screen, buffer unchanged" or ("no message; screen:\n" .. screen()))
end)

case("cxc_nothing_selection", CALC, function()
  goto_('String s = "', 1, 13)
  lit("viw"); leader("cxc") -- one backslash: not an expression
  local shown = wait(20000, function() return screen():find("not a whole", 1, true) ~= nil end)
  vim.wait(500)
  rep("cxc_nothing_selection", shown and text() == CALC, shown and "WARN on screen, buffer unchanged" or ("no message; screen:\n" .. screen()))
end)

case("cxv_normal", CALC, function()
  goto_("return y + 3;", 1, 8) -- on `y`: picker y / y + 3
  leader("cxv")
  if not wait(20000, function() return screen():find("Choices", 1, true) ~= nil end) then rep("cxv_normal", false, "no Choices picker; screen:\n" .. screen()) return end
  wait(10000, function() return screen():find("2 / 2", 1, true) ~= nil end); vim.wait(700) -- the list is drawn
  key("Down"); key("Enter")
  expect_text("cxv_normal", replace(CALC, "return y + 3;", "int i = y + 3;\n        return i;"), "int i = y + 3; return i;", CALC)
end)

case("cxv_visual", CALC, function()
  goto_("int y = x * 2 + 1;", 1, 8)
  lit("v4l"); leader("cxv")
  expect_text("cxv_visual", replace(CALC, "int y = x * 2 + 1;", "int i = x * 2;\n        int y = i + 1;"), "int i = x * 2; int y = i + 1;", CALC)
end)

case("cxm_visual", CALC, function()
  goto_("int t = x + 1;", 1, 0)
  lit("Vj"); leader("cxm")
  local ok = wait(20000, function() local t = text(); return t and t:find("private int getU(int x) {", 1, true) ~= nil end)
  local t = text() or ""
  rep("cxm_visual", ok and t:find("int u = getU(x);", 1, true) ~= nil, ok and "extracted into getU(x)" or ("no method; screen:\n" .. screen()))
end)

case("ji_inline", CALC, function()
  goto_("int b = a + 1;", 1, 4) -- on `b`
  leader("ji")
  expect_text("ji_inline", replace(CALC, "int b = a + 1;\n        return b * 2;", "return (a + 1) * 2;"), "inlined: return (a + 1) * 2;", CALC)
end)

case("co_organize", CALC, function()
  cmd(":call cursor(1,1)")
  leader("co")
  expect_text("co_organize", replace(CALC, "import java.util.List;\nimport java.util.Map;\n\n", "", 1), "unused imports removed", CALC)
end)

case("ca_lambda", CALC, function()
  vim.wait(2000)
  local ok
  for _ = 1, 3 do -- jdt.ls may still be syncing the reloaded buffer: ask again
    goto_("Runnable r = new Runnable()", 1, 13) -- on `new`
    leader("ca")
    if not wait(20000, function() return screen():find("Code actions", 1, true) ~= nil end) then rep("ca_lambda", false, "no code action menu; screen:\n" .. screen()) return end
    lit("lambda"); vim.wait(800); key("Enter")
    ok = wait(8000, function() local t = text(); return t and t:find('Runnable r = () -> System.out.println("hi");', 1, true) ~= nil end)
    if ok then break end
    key("Escape"); key("Escape"); vim.wait(1500)
  end
  rep("ca_lambda", ok, ok and "converted to a lambda" or ("not converted; screen:\n" .. screen()))
end)

-- default package: open Dp.java in the same nvim (same jdt.ls)
do
  revert(CALC)
  cmd(":e src/main/java/Dp.java")
  local dp_ok = wait(30000, function() return text() == DP end)
  local want = replace(replace(replace(DP, "public class Dp {\n", 'public class Dp {\n    private static final String STRING = "\\r\\n";\n\n', 1), 'String s = "\\r\\n";', "String s = STRING;"), 'return s + "\\r\\n";', "return s + STRING;")
  if not dp_ok then rep("cxc_default_package", false, "Dp.java not open; screen:\n" .. screen())
  else
    -- jdt.ls needs the buffer analysed before it answers
    wait(30000, function() return tonumber(expr("luaeval('vim.api.nvim_buf_get_changedtick(0)')") or "0") > 0 and expr("luaeval(\"#vim.lsp.get_clients({name='jdtls',bufnr=0})\")") == "1" end)
    vim.wait(3000)
    goto_('String s = "', 1, 13)
    lit('vi"'); leader("cxc")
    expect_text("cxc_default_package", want, 'default package, vi" then <leader>cxc: STRING = "\\r\\n"', DP)
  end
end

cleanup()
lsp.finish()
