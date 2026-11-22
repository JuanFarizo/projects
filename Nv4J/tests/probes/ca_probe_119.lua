-- Probe (run by copying to tests/checks as 119_ca_probe.lua) (candidate d): which of text block, class to record, extract interface, extract field scopes does the
-- INSTALLED jdt.ls offer, with and without extractInterfaceSupport, and what do the actions carry. Writes
-- /tmp/nv4j/ca_probe.txt. Not an assertion check.
vim.o.confirm = false
local lsp = require("lsp")
local E = require("edit")
local P = "119_ca_probe."
if vim.env.NV4J_PROBE_IFACE == "1" then
  local orig = require
  require = function(n)
    local m = orig(n)
    if n == "jdtls.capabilities" then m.extractInterfaceSupport = true end
    return m
  end
end

local dir = vim.uv.fs_realpath("/tmp") .. "/nv4j/ca119"
vim.fn.delete(dir, "rf")
vim.fn.mkdir(dir .. "/src/main/java/ca", "p")
vim.fn.writefile({
  '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>',
  "<groupId>ca</groupId><artifactId>ca119</artifactId><version>1</version>",
  "<properties><maven.compiler.release>25</maven.compiler.release>",
  "<project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>",
  "</project>",
}, dir .. "/pom.xml")
local FILE = dir .. "/src/main/java/ca/Ca.java"
local SRC = {
  "package ca;", "",
  "public class Ca {",
  "    private int base = 1;",                                   -- 3
  "    public int total(int a) {",                               -- 4
  "        int local = a * 2;",                                  -- 5
  "        return local + base;",                                -- 6
  "    }",
  "    public String text() {",                                  -- 8
  '        String s = "line1\\n" + "line2\\n" + "line3\\n";',    -- 9
  "        return s;",
  "    }",
  "    public String text2() {",                                 -- 12
  '        return "a\\n" + "b\\n";',                              -- 13
  "    }",
  "    static final class P {",                                  -- 15
  "        private final int x;",
  "        private final String n;",
  "        P(int x, String n) { this.x = x; this.n = n; }",
  "        int x() { return x; }",
  "        String n() { return n; }",
  "    }",
  "    record R(int q) {}",
  "}",
}
vim.fn.writefile(SRC, FILE)
local buf = lsp.open(FILE)
local client = lsp.wait_ready(buf, 180000)
lsp.report(P .. "attached", client ~= nil, client and "ready" or "not ready")
if not client then return lsp.finish() end
vim.wait(3000)
local out = {}
local function ask(name, sl, sc, el, ec)
  local r = E.code_actions(client, buf, sl, sc, el, ec)
  out[#out + 1] = ("== %s (%d:%d-%d:%d) err=%s\n  %s"):format(name, sl, sc, el, ec, tostring(r.err), E.titles(r.actions))
  for _, a in ipairs(r.actions) do
    if a.title:find("[Ee]xtract") or a.title:find("[Rr]ecord") or a.title:find("[Tt]ext") or a.title:find("[Ii]nterface") then
      out[#out + 1] = "  -> " .. a.title .. " kind=" .. tostring(a.kind) .. " cmd=" .. vim.inspect(a.command or (a.data and "data") or "edit"):gsub("\n%s*", " "):sub(1, 700)
    end
  end
end
ask("text block, on literal", 9, 20, 9, 20)
ask("text block, on the =", 9, 17, 9, 17)
ask("text block, selection", 9, 19, 9, 52)
ask("text block, return", 13, 17, 13, 17)
ask("class to record, name", 15, 23, 15, 23)
ask("class to record, keyword", 15, 12, 15, 12)
ask("extract interface, name", 2, 14, 2, 14)
ask("extract interface, class kw", 2, 8, 2, 8)
ask("extract interface, selection of class", 2, 0, 22, 1)
ask("extract field, local", 5, 12, 5, 12)
ask("extract field, expr selection", 5, 20, 5, 25)
vim.fn.writefile(out, "/tmp/nv4j/ca_probe_" .. (vim.env.NV4J_PROBE_IFACE or "0") .. ".txt")
lsp.report(P .. "done", true, "written")
lsp.finish()
