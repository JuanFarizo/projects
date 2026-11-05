-- Maven module whose parent pom is not the git root: the aggregator that lists the module is the root.
-- Pure unit cases on temp trees under /tmp/nv4j/maven-parent-<pid>; root.project reads files only, no jdt.ls.
--  parent_listed   backend/pom.xml lists app and core, git root above has no pom: a file of app -> backend, kind build.
--  two_levels      backend -> services -> orders: the climb continues while each parent lists the child.
--  not_listed      a parent pom that does NOT list the module (a commented <module> does not count): the module stays its own root.
--  module_pom_path <module>app/pom.xml</module> and a trailing slash are read.
--  no_parent       a standalone module under a dir without pom: unchanged. Git root with a pom still wins (older rule).
-- Control: remove the `M.maven_parent_root(marker_root) or` call in root.project and parent_listed/two_levels/module_pom_path FAIL.
local lsp = require("lsp")
local P = "75_maven_parent."
local log = vim.env.NV4J_LOG or "(no NV4J_LOG)"
local TMP = "/tmp/nv4j/maven-parent-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
TMP = vim.uv.fs_realpath(TMP)
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(text or "")
  f:close()
end
local function pom(modules)
  local t = {}
  for _, m in ipairs(modules or {}) do t[#t + 1] = "<module>" .. m .. "</module>" end
  return "<project><modules>" .. table.concat(t) .. "</modules></project>"
end
local root = require("nv4j.root")
local function case(name, file, want)
  local r, m, k = root.project(TMP .. "/" .. file)
  lsp.report(P .. name, r == TMP .. "/" .. want and m and k == "build",
    ("%s -> %s, %s, %s (want TMP/%s, true, build); log %s"):format(file, r:gsub(vim.pesc(TMP), "TMP"), tostring(m), k, want, log))
end

write(TMP .. "/r1/.git/HEAD", "")
write(TMP .. "/r1/backend/pom.xml", pom({ "app", "core" }))
write(TMP .. "/r1/backend/app/pom.xml", "<project/>")
write(TMP .. "/r1/backend/core/pom.xml", "<project/>")
case("parent_listed", "r1/backend/app/src/A.java", "r1/backend")
case("parent_listed_core", "r1/backend/core/src/C.java", "r1/backend")

write(TMP .. "/r2/backend/pom.xml", pom({ "services" }))
write(TMP .. "/r2/backend/services/pom.xml", pom({ "orders" }))
write(TMP .. "/r2/backend/services/orders/pom.xml", "<project/>")
case("two_levels", "r2/backend/services/orders/src/O.java", "r2/backend")

write(TMP .. "/r3/pom.xml", pom({ "other" }) .. "<!-- <module>app</module> -->")
write(TMP .. "/r3/app/pom.xml", "<project/>")
case("not_listed", "r3/app/src/A.java", "r3/app")

write(TMP .. "/r4/pom.xml", pom({ "app/pom.xml", "lib/" }))
write(TMP .. "/r4/app/pom.xml", "<project/>")
write(TMP .. "/r4/lib/pom.xml", "<project/>")
case("module_pom_path", "r4/app/src/A.java", "r4")
case("module_trailing_slash", "r4/lib/src/L.java", "r4")

write(TMP .. "/r5/app/pom.xml", "<project/>")
case("no_parent", "r5/app/src/A.java", "r5/app")

vim.fn.delete(TMP, "rf")
lsp.finish()
