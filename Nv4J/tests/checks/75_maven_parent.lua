-- Maven module under an aggregator: Nv4J follows IntelliJ (MavenProjectsTree.findAggregator links a module to its
-- aggregator only through an imported pom; nothing climbs from a submodule). The user marks where the project starts
-- with a `.nv4j` file (D25); the folder holding it is the root and the modules below it are its children.
-- Pure unit cases on temp trees under /tmp/nv4j/maven-parent-<pid>; root.project reads files only, no jdt.ls.
--  module_alone     backend/pom.xml lists app, no .nv4j: a file of app -> app (NOT backend), as IntelliJ opening that folder.
--  nv4j_parent      backend/.nv4j beside backend/pom.xml: files of app and core -> backend, kind nv4j.
--  nv4j_two_levels  .nv4j at the top aggregator: a module two levels down -> the top.
--  nv4j_no_pom      .nv4j in a folder with no pom beside it does not swallow a module's pom (D25 rule kept): -> the module.
--  git_root_pom     git root holding a pom wins over a nearer module pom (older rule kept).
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
local function case(name, file, want, want_kind)
  local r, m, k = root.project(TMP .. "/" .. file)
  lsp.report(P .. name, r == TMP .. "/" .. want and m and k == want_kind,
    ("%s -> %s, %s, %s (want TMP/%s, true, %s); log %s"):format(file, r:gsub(vim.pesc(TMP), "TMP"), tostring(m), k, want, want_kind, log))
end

write(TMP .. "/r1/backend/pom.xml", pom({ "app" }))
write(TMP .. "/r1/backend/app/pom.xml", "<project/>")
case("module_alone", "r1/backend/app/src/A.java", "r1/backend/app", "build")

write(TMP .. "/r2/backend/.nv4j", "")
write(TMP .. "/r2/backend/pom.xml", pom({ "app", "core" }))
write(TMP .. "/r2/backend/app/pom.xml", "<project/>")
write(TMP .. "/r2/backend/core/pom.xml", "<project/>")
case("nv4j_parent", "r2/backend/app/src/A.java", "r2/backend", "nv4j")
case("nv4j_parent_core", "r2/backend/core/src/C.java", "r2/backend", "nv4j")

write(TMP .. "/r3/.nv4j", "")
write(TMP .. "/r3/pom.xml", pom({ "services" }))
write(TMP .. "/r3/services/pom.xml", pom({ "orders" }))
write(TMP .. "/r3/services/orders/pom.xml", "<project/>")
case("nv4j_two_levels", "r3/services/orders/src/O.java", "r3", "nv4j")

write(TMP .. "/r4/.nv4j", "")
write(TMP .. "/r4/app/pom.xml", "<project/>")
case("nv4j_no_pom", "r4/app/src/A.java", "r4/app", "build")

write(TMP .. "/r5/.git/HEAD", "")
write(TMP .. "/r5/pom.xml", pom({ "app" }))
write(TMP .. "/r5/app/pom.xml", "<project/>")
case("git_root_pom", "r5/app/src/A.java", "r5", "build")

vim.fn.delete(TMP, "rf")
lsp.finish()
