-- <F2> / <leader>cr / <leader>rn on a class name (nvim/lua/nv4j/refactor.lua rename_symbol, specs/features/refactors.md "Plain
-- rename keys"). Bug (user report, codecrafters-redis-java, classes in the DEFAULT package): plain vim.lsp.buf.rename renamed
-- the file but left every dependent buffer modified and UNSAVED, so disk and `mvn compile` still named the old class and nothing
-- said so. NV4J_99_UNIT=1 runs only the pure cases (tests/lib/control_99.sh); the live one starts a jdt.ls on a small
-- default-package Maven project it writes to /tmp/nv4j/d99-<pid> (offline import; nothing in tests/fixtures is touched).
--  keys          : <F2> and <leader>rn call refactor.rename_symbol; a Java buffer gets a buffer-local <leader>cr that does too.
--  routing       : stubbed: a type name (declaration or use) -> rename_class; a method, a constant (CRLF), a variable and a
--                  `package` line -> vim.lsp.buf.rename (the plain LSP rename stays for them).
-- Live (default package: Handler used by Loop and Main, Loop and Main open):
--  live_rename   : rename_symbol on `Handler` -> Dispatcher.java on disk, Handler.java gone, Loop/Main on disk name Dispatcher
--                  and no `Handler` token, no buffer left modified, no jdt.ls error.
--  live_undo     : undo_last puts the file name and every reference back (disk), no `Dispatcher` left.
--  live_method   : on a method name the plain LSP rename still runs (the file keeps its name).
local lsp = require("lsp")
local P = "99_rename_symbol."
local function rep(name, ok, detail) lsp.report(P .. name, ok and true or false, detail) end
local unit_only = vim.env.NV4J_99_UNIT == "1"
pcall(require, "lazyvim.config.keymaps")
pcall(require, "config.keymaps")
local R = require("nv4j.refactor")

-- keys
do
  local orig, asked = R.rename_symbol, 0
  R.rename_symbol = function() asked = asked + 1 end
  local bad = {}
  for _, lhs in ipairs({ "<F2>", "<leader>rn" }) do
    local m = vim.fn.maparg(lhs, "n", false, true)
    local before = asked
    if type(m) ~= "table" or not m.callback then bad[#bad + 1] = lhs .. " unmapped" else
      pcall(m.callback)
      if asked ~= before + 1 then bad[#bad + 1] = lhs .. " does not call rename_symbol" end
    end
  end
  local b = vim.api.nvim_create_buf(false, true)
  R.bind(b)
  local found
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(b, "n")) do
    if m.lhs == (vim.g.mapleader or " ") .. "cr" or m.lhs == "<Space>cr" then found = m end
  end
  local before = asked
  if not found or not found.callback then bad[#bad + 1] = "<leader>cr not bound in the buffer" else
    pcall(found.callback)
    if asked ~= before + 1 then bad[#bad + 1] = "<leader>cr does not call rename_symbol" end
  end
  R.rename_symbol = orig
  rep("keys", #bad == 0, #bad > 0 and table.concat(bad, "; ") or "<F2>, <leader>rn, buffer <leader>cr -> rename_symbol")
end

-- routing (stubs): a java buffer with an attached fake jdtls
do
  local buf = vim.api.nvim_create_buf(true, false)
  local path = "/tmp/nv4j/d99-route/Handler.java"
  vim.fn.mkdir("/tmp/nv4j/d99-route", "p")
  vim.api.nvim_buf_set_name(buf, path)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "package demo;", "public class Handler {", "  static final String CRLF = \"x\";", "  void handle(int count) {", "    new Handler().handle(count);", "  }", "}",
  })
  local ei = vim.o.eventignore
  vim.o.eventignore = "FileType" -- no real jdt.ls for the stub buffer
  vim.bo[buf].filetype = "java"
  vim.o.eventignore = ei
  vim.api.nvim_set_current_buf(buf)
  local o_class, o_plain, o_clients = R.rename_class, vim.lsp.buf.rename, vim.lsp.get_clients
  local class_calls, plain_calls = 0, 0
  R.rename_class = function() class_calls = class_calls + 1 end
  vim.lsp.buf.rename = function() plain_calls = plain_calls + 1 end
  vim.lsp.get_clients = function() return { { name = "jdtls", config = { root_dir = vim.fs.dirname(vim.api.nvim_buf_get_name(buf)) }, id = 1 } } end
  local function at(l, c)
    class_calls, plain_calls = 0, 0
    vim.api.nvim_win_set_cursor(0, { l, c })
    pcall(R.rename_symbol, {})
    return class_calls, plain_calls
  end
  local got = {}
  got.decl = { at(2, 15) }   -- on `Handler` of `public class Handler`
  got.use = { at(5, 10) }    -- on `Handler` of `new Handler()`
  got.method = { at(4, 8) }  -- on `handle`
  got.const = { at(3, 25) }  -- on `CRLF`
  got.var = { at(4, 20) }    -- on `count`
  got.pkg = { at(1, 12) }    -- on `demo` of the package line
  R.rename_class, vim.lsp.buf.rename, vim.lsp.get_clients = o_class, o_plain, o_clients
  local ok = got.decl[1] == 1 and got.decl[2] == 0 and got.use[1] == 1 and got.use[2] == 0
    and got.method[1] == 0 and got.method[2] == 1 and got.const[1] == 0 and got.const[2] == 1
    and got.var[1] == 0 and got.var[2] == 1 and got.pkg[1] == 0 and got.pkg[2] == 1
  rep("routing", ok, vim.inspect(got))
  vim.api.nvim_buf_delete(buf, { force = true })
end

if not unit_only then
  local root = "/tmp/nv4j/d99-" .. vim.fn.getpid()
  vim.fn.delete(root, "rf")
  local function w(rel, s) vim.fn.mkdir(vim.fs.dirname(root .. "/" .. rel), "p"); local f = io.open(root .. "/" .. rel, "w"); f:write(s); f:close() end
  local function r(p) local f = io.open(p); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
  w("pom.xml", [[<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>
<groupId>demo</groupId><artifactId>d99</artifactId><version>1</version>
<properties><maven.compiler.release>21</maven.compiler.release><project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>
</project>
]])
  local J = root .. "/src/main/java/"
  local SRC = {
    ["Handler.java"] = "public class Handler {\n  static final String CRLF = \"\\r\\n\";\n\n  public static void handle(String s) {\n    System.out.println(s + CRLF);\n  }\n}\n",
    ["Loop.java"] = "public class Loop {\n  public static void run() {\n    Handler.handle(\"x\");\n  }\n}\n",
    ["Main.java"] = "public class Main {\n  public static void main(String[] args) {\n    Loop.run();\n    Handler.handle(\"y\");\n  }\n}\n",
  }
  for n, s in pairs(SRC) do w("src/main/java/" .. n, s) end
  local wsname = vim.fs.basename(root) .. "-" .. vim.fn.sha256(root):sub(1, 8)
  vim.fn.delete(require("nv4j.paths").jdtls_data .. "/" .. wsname, "rf")
  local orig_start = vim.lsp.start
  vim.lsp.start = function(config, opts)
    if config and config.name == "jdtls" then
      config.settings = vim.tbl_deep_extend("force", config.settings or {}, { java = { import = { maven = { offline = { enabled = true } } } } })
    end
    return orig_start(config, opts)
  end
  local buf = lsp.open(J .. "Handler.java")
  local client, why = lsp.wait_ready(buf, 240000)
  if not client then
    rep("live_ready", false, tostring(why))
  else
    vim.cmd("cd " .. vim.fn.fnameescape(root))
    for _, n in ipairs({ "Loop.java", "Main.java" }) do
      local b = vim.fn.bufadd(J .. n); vim.fn.bufload(b); vim.bo[b].buflisted = true
      vim.bo[b].filetype = "java"
      vim.api.nvim_exec_autocmds("FileType", { buffer = b, modeline = false })
    end
    vim.wait(8000, function() return #vim.lsp.get_buffers_by_client_id(client.id) >= 3 end, 100)
    vim.api.nvim_set_current_buf(buf)
    -- live_rename: cursor on `Handler` of the declaration
    vim.api.nvim_win_set_cursor(0, { 1, 15 })
    local done
    R.rename_symbol({ name = "Dispatcher", on_done = function(ok) done = ok == nil and true or ok end })
    vim.wait(30000, function() return done ~= nil or r(J .. "Dispatcher.java") ~= nil end, 100)
    vim.wait(4000, function() return false end, 100) -- plain rename: let the edit land
    local disp, loop, main = r(J .. "Dispatcher.java"), r(J .. "Loop.java"), r(J .. "Main.java")
    local mods = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted and vim.bo[b].modified then mods[#mods + 1] = vim.fs.basename(vim.api.nvim_buf_get_name(b)) end
    end
    local function nohandler(s) return s ~= nil and not s:find("%f[%w_]Handler%f[^%w_]") end
    local errs = 0
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) then
        for _, d in ipairs(vim.diagnostic.get(b)) do if d.severity == vim.diagnostic.severity.ERROR then errs = errs + 1 end end
      end
    end
    rep("live_rename", disp ~= nil and r(J .. "Handler.java") == nil and nohandler(disp) and nohandler(loop) and nohandler(main)
      and loop:find("Dispatcher.handle", 1, true) ~= nil and main:find("Dispatcher.handle", 1, true) ~= nil and #mods == 0 and errs == 0,
      ("Dispatcher.java=%s Handler.java gone=%s loop=%q main=%q modified buffers=%s errors=%d"):format(tostring(disp ~= nil),
        tostring(r(J .. "Handler.java") == nil), tostring(loop):sub(1, 90), tostring(main):sub(1, 110), table.concat(mods, ","), errs))
    -- live_undo
    local undone
    R.undo_last({ on_done = function(ok) undone = ok end })
    vim.wait(30000, function() return undone ~= nil end, 100)
    local same = true
    for n, s in pairs(SRC) do if r(J .. n) ~= s then same = false end end
    rep("live_undo", undone == true and same and r(J .. "Dispatcher.java") == nil, ("undone=%s files back=%s"):format(tostring(undone), tostring(same)))
    -- live_method: `handle` in Handler.java: plain LSP rename, the file keeps its name
    local hb = vim.fn.bufnr(J .. "Handler.java")
    if hb ~= -1 and vim.api.nvim_buf_is_loaded(hb) then
      vim.api.nvim_set_current_buf(hb)
      vim.api.nvim_win_set_cursor(0, { 4, 22 })
      local o_class, class_calls = R.rename_class, 0
      R.rename_class = function(...) class_calls = class_calls + 1; return o_class(...) end
      R.rename_symbol({ name = "process" })
      vim.wait(5000, function() return false end, 100)
      R.rename_class = o_class
      local hs = table.concat(vim.api.nvim_buf_get_lines(hb, 0, -1, false), "\n")
      rep("live_method", class_calls == 0 and hs:find("void process", 1, true) ~= nil and r(J .. "Handler.java") ~= nil,
        ("class_calls=%d process in buffer=%s"):format(class_calls, tostring(hs:find("void process", 1, true) ~= nil)))
    else
      rep("live_method", false, "Handler.java buffer missing after the undo")
    end
  end
  vim.lsp.start = orig_start
end

lsp.finish()
