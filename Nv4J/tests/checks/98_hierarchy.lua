-- Type / call hierarchy picker (nvim/lua/nv4j/hierarchy.lua, specs/features/hierarchy.md). NV4J_98_UNIT=1 runs only the pure
-- cases (tests/lib/control_98.sh uses it); the live case needs jdt.ls and starts one on a tiny Maven project it writes to
-- /tmp/nv4j/d98-<pid> (nothing in tests/fixtures is touched, offline import).
-- Pure cases:
--  zero_cost_startup : nv4j.hierarchy not loaded when the config has started (the keys require it on first use).
--  keys              : <leader>cS/cP/ci/cO are mapped to functions of nv4j.hierarchy (no vim.lsp.buf.* any more).
--  type_row          : TypeHierarchyItem -> name first, package = detail, path relative to the root, jump = selectionRange.
--  call_row          : CallHierarchyItem -> `Class#method` (parameters dropped), package of the container, x N call sites.
--  call_target       : incoming: jump = FIRST call site (sorted, not the order sent); outgoing: the declaration.
--  sort              : by name (case-insensitive), then package, then path.
--  display           : text starts with the icon and the NAME; package and path come after; highlights dim the tail.
--  entry             : entry_maker fills filename/lnum/col/text (preview and <C-q>) and an ordinal with name+pkg+path.
--  library_path      : a jdt:// URI shows `jar/package/Class.java`, no entry filename.
--  no_client         : run() without a language server warns and sends nothing.
--  stub_flow         : stub client: prepare then ONE request per prepared item, rows sorted, "No subtypes" on [] , stale run dropped.
-- Live (one jdt.ls):
--  live_subtypes     : subtypes of the interface = the 3 implementors, rows start with the name, the jump lands on the class line.
--  live_calls        : incoming calls of a method: callers as `Class#method`, jump = the call site line.
local lsp = require("lsp")
local P = "98_hierarchy."
local function rep(name, ok, detail) lsp.report(P .. name, ok and true or false, detail) end
local unit_only = vim.env.NV4J_98_UNIT == "1"

rep("zero_cost_startup", package.loaded["nv4j.hierarchy"] == nil, "loaded at startup: " .. tostring(package.loaded["nv4j.hierarchy"] ~= nil))
pcall(require, "lazyvim.config.keymaps")
pcall(require, "config.keymaps")

-- keys: call each mapping with the hierarchy module's run stubbed and see which kind it asks for
do
  local H = require("nv4j.hierarchy")
  local orig, asked = H.run, {}
  H.run = function(kind) asked[#asked + 1] = kind end
  local want = { ["<leader>cS"] = "subtypes", ["<leader>cP"] = "supertypes", ["<leader>ci"] = "incoming", ["<leader>cO"] = "outgoing" }
  local ok, bad = true, {}
  local leader = vim.g.mapleader or " "
  for lhs, kind in pairs(want) do
    local m = vim.fn.maparg(lhs, "n", false, true)
    if type(m) ~= "table" or not m.callback then ok = false; bad[#bad + 1] = lhs .. " unmapped"
    else
      asked = {}
      pcall(m.callback)
      if asked[1] ~= kind then ok = false; bad[#bad + 1] = ("%s asked %s want %s"):format(lhs, tostring(asked[1]), kind) end
    end
  end
  H.run = orig
  rep("keys", ok, #bad > 0 and table.concat(bad, "; ") or "4 keys -> nv4j.hierarchy.run(subtypes|supertypes|incoming|outgoing)")
end

local H = require("nv4j.hierarchy")
local function rng(l1, c1, l2, c2) return { start = { line = l1, character = c1 }, ["end"] = { line = l2, character = c2 } } end
local ROOT = "/tmp/nv4j/r98"
local U = function(rel) return vim.uri_from_fname(ROOT .. "/" .. rel) end

-- type_row
local circle = H.row({ name = "Circle", kind = 5, detail = "demo.shapes", uri = U("src/main/java/demo/shapes/Circle.java"),
  range = rng(2, 0, 5, 1), selectionRange = rng(2, 13, 2, 19) }, { root = ROOT })
rep("type_row", circle.name == "Circle" and circle.pkg == "demo.shapes" and circle.path == "src/main/java/demo/shapes/Circle.java"
  and circle.target.range.start.line == 2 and circle.target.range.start.character == 13 and circle.target.uri == U("src/main/java/demo/shapes/Circle.java"),
  vim.inspect({ circle.name, circle.pkg, circle.path, circle.target.range.start }))

-- call_row / call_target
local caller_item = { name = "run(int)", kind = 6, detail = "demo.app.Report", uri = U("src/main/java/demo/app/Report.java"),
  range = rng(10, 4, 14, 5), selectionRange = rng(10, 16, 10, 19) }
local sites = { rng(30, 8, 30, 14), rng(12, 20, 12, 26), rng(40, 1, 40, 5) } -- not in order on purpose
local inc = H.row(caller_item, { calls = true, root = ROOT, ranges = sites, sites_in_item = true })
rep("call_row", inc.name == "Report#run" and inc.pkg == "demo.app" and inc.sites == 3, vim.inspect({ inc.name, inc.pkg, inc.sites }))
local out = H.row(caller_item, { calls = true, root = ROOT, ranges = sites, sites_in_item = false })
rep("call_target", inc.target.range.start.line == 12 and out.target.range.start.line == 10 and out.target.range.start.character == 16,
  ("incoming line %d (want 12), outgoing line %d col %d (want declaration 10/16)"):format(inc.target.range.start.line, out.target.range.start.line, out.target.range.start.character))

-- sort
do
  local function r(name, pkg, path) return { name = name, pkg = pkg, path = path, target = { range = rng(0, 0, 0, 0) }, sites = 0 } end
  local rows = { r("beta", "z", "a"), r("Alpha", "b", "x"), r("alpha", "a", "y"), r("Alpha", "a", "b"), r("Zed", "", "") }
  H.sort(rows)
  local got = vim.tbl_map(function(x) return x.name .. "/" .. x.pkg .. "/" .. x.path end, rows)
  rep("sort", table.concat(got, ",") == "Alpha/a/b,alpha/a/y,Alpha/b/x,beta/z/a,Zed//", table.concat(got, ","))
end

-- display
do
  local text, hl = H.display(circle)
  local icon = H.icon(circle.kind)
  local name_at, pkg_at, path_at = text:find("Circle", 1, true), text:find("demo.shapes", 1, true), text:find("src/main", 1, true)
  rep("display", name_at == #icon + 1 and pkg_at and pkg_at > name_at and path_at and path_at > pkg_at and text:find(":3", 1, true)
    and hl[2][2] == "TelescopeResultsComment" and hl[2][1][1] == #icon + #"Circle", text)
end

-- entry
do
  local e = H.entry_maker(circle)
  rep("entry", e.filename == ROOT .. "/src/main/java/demo/shapes/Circle.java" and e.lnum == 3 and e.col == 14
    and e.ordinal:find("Circle", 1, true) == 1 and e.ordinal:find("demo.shapes", 1, true) and e.text:find("^Circle"),
    vim.inspect({ e.filename, e.lnum, e.col, e.ordinal, e.text }))
end

-- library_path
do
  local lib = H.row({ name = "Object", kind = 5, detail = "java.lang", uri = "jdt://contents/java.base/java.lang/Object.class?=x",
    range = rng(0, 0, 0, 0), selectionRange = rng(0, 0, 0, 0) }, { root = ROOT })
  local e = H.entry_maker(lib)
  rep("library_path", lib.path == "java.base/java.lang/Object.class" and e.filename == lib.uri, vim.inspect({ lib.path, e.filename }))
end

-- entry_safe (regression, user report E5108 "path: expected string, got table"): telescope's from_entry.path must give a string
-- (or nil) for file, library (jdt://) and URI-less rows, never the row table; no error for validate true/false.
do
  local from_entry = require("telescope.from_entry")
  local lib = H.row({ name = "println(String)", kind = 6, detail = "java.io.PrintStream", uri = "jdt://contents/java.base/java.io/PrintStream.class?=x",
    range = rng(0, 0, 0, 1), selectionRange = rng(0, 0, 0, 1) }, { calls = true, root = ROOT })
  local nouri = H.row({ name = "X", kind = 5, detail = "p", range = rng(0, 0, 0, 1) }, { root = ROOT })
  local bad = {}
  for label, row in pairs({ file = circle, lib = lib, nouri = nouri }) do
    local e = H.entry_maker(row)
    for _, validate in ipairs({ true, false }) do
      local ok, p = pcall(from_entry.path, e, validate, false)
      if not ok or (p ~= nil and type(p) ~= "string") then bad[#bad + 1] = ("%s validate=%s -> %s"):format(label, tostring(validate), ok and type(p) or tostring(p)) end
    end
    if type(e.path) ~= "string" or type(e.filename) ~= "string" then bad[#bad + 1] = label .. " path/filename not strings" end
  end
  rep("entry_safe", #bad == 0, #bad == 0 and "file, library and URI-less rows: path is a string for from_entry.path (validate true/false)" or table.concat(bad, "; "))
end

-- no_client: an empty scratch buffer has no server
do
  local notes, orig = {}, vim.notify
  vim.notify = function(m, l) notes[#notes + 1] = m end
  vim.cmd("enew")
  H.run("subtypes")
  vim.notify = orig
  rep("no_client", #notes == 1 and notes[1]:find("no language server", 1, true) ~= nil, vim.inspect(notes))
end

-- stub_flow: a fake client; counts requests
do
  local b = vim.api.nvim_get_current_buf()
  local reqs, answers = {}, {}
  local fake = { offset_encoding = "utf-16", name = "stub" }
  function fake:cancel_request() end
  function fake:request(method, params, cb)
    reqs[#reqs + 1] = method
    local n = #reqs
    answers[n] = function(res) cb(nil, res) end
    return true, n
  end
  local orig_get, orig_pos = vim.lsp.get_clients, vim.lsp.util.make_position_params
  vim.lsp.get_clients = function() return { fake } end
  vim.lsp.util.make_position_params = function() return { textDocument = { uri = "file:///x" }, position = { line = 0, character = 0 } } end
  local got
  H.invalidate()
  local function items(names) local t = {}; for _, n in ipairs(names) do t[#t + 1] = { name = n, kind = 5, detail = "p", uri = U("A.java"), range = rng(0, 0, 0, 1), selectionRange = rng(0, 0, 0, 1) } end return t end
  H.run("subtypes", { on_rows = function(rows) got = rows end })
  answers[1](items({ "Shape" }))
  answers[2](items({ "Zed", "alpha", "Beta" }))
  local ok1 = #reqs == 2 and reqs[1] == "textDocument/prepareTypeHierarchy" and reqs[2] == "typeHierarchy/subtypes"
    and got and #got == 3 and got[1].name == "alpha" and got[3].name == "Zed"
  -- empty
  local notes, orig = {}, vim.notify
  vim.notify = function(m) notes[#notes + 1] = m end
  reqs, answers, got = {}, {}, nil
  H.invalidate()
  H.run("subtypes", { on_rows = function(rows) got = rows end })
  answers[1](items({ "Shape" }))
  answers[2]({})
  local ok2 = got == nil and notes[1] == "No subtypes of Shape"
  -- stale: a second run supersedes the first; the first answer is dropped
  notes, reqs, answers, got = {}, {}, {}, nil
  local rows1, rows2
  H.invalidate()
  H.run("supertypes", { on_rows = function(rows) rows1 = rows end })
  local first = answers[1]
  H.run("supertypes", { on_rows = function(rows) rows2 = rows end })
  H.invalidate()
  first(items({ "Old" })) -- superseded run: dropped, no hierarchy request sent
  local sent_after_stale = #reqs
  answers[2](items({ "New" }))
  answers[3](items({ "Parent" }))
  local ok3 = rows1 == nil and sent_after_stale == 2 and #reqs == 3 and rows2 and #rows2 == 1 and rows2[1].name == "Parent"
  vim.notify = orig
  vim.lsp.get_clients, vim.lsp.util.make_position_params = orig_get, orig_pos
  rep("stub_flow", ok1 and ok2 and ok3, ("ok1=%s ok2=%s ok3=%s reqs=%s notes=%s"):format(tostring(ok1), tostring(ok2), tostring(ok3), vim.inspect(reqs), vim.inspect(notes)))
end

-- level-1 cache (stub client): a repeat press sends nothing; invalidated by didChange / didSave / didChangeWatchedFiles /
-- LspProgress end; an answer that was in flight across an invalidation, an error and a failed request are not stored; LRU bound.
do
  local reqs, answers, pos = {}, {}, { line = 0, character = 0 }
  local fake = { offset_encoding = "utf-16", name = "stub", id = 7 }
  function fake:cancel_request() end
  function fake:request(method, params, cb)
    reqs[#reqs + 1] = method
    local n = #reqs
    answers[n] = function(res, err) cb(err, res) end
    return true, n
  end
  local orig_get, orig_pos = vim.lsp.get_clients, vim.lsp.util.make_position_params
  vim.lsp.get_clients = function() return { fake } end
  vim.lsp.util.make_position_params = function() return { textDocument = { uri = "file:///x" }, position = vim.deepcopy(pos) } end
  local function items(names) local t = {}; for _, n in ipairs(names) do t[#t + 1] = { name = n, kind = 5, detail = "p", uri = U(n .. ".java"), range = rng(0, 0, 0, 1), selectionRange = rng(0, 0, 0, 1) } end return t end
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(b)
  local notes, orig_notify = {}, vim.notify
  vim.notify = function(m) notes[#notes + 1] = m end
  local function press(kind)
    local got
    reqs, answers = {}, {}
    H.run(kind or "subtypes", { on_rows = function(rows) got = rows end })
    return got
  end
  local function names_of(rows) return table.concat(vim.tbl_map(function(r) return r.name end, rows or {}), ",") end
  local function press_full(prep, subs) -- a press that must ask everything (cache emptied first)
    local got
    H.invalidate()
    reqs, answers = {}, {}
    H.run("subtypes", { on_rows = function(rows) got = rows end })
    answers[1](items(prep))
    answers[2](items(subs))
    return got
  end

  -- cache_hit: second press -> nothing sent, rows at once (before this function returns), same rows
  H.invalidate()
  local first = press_full({ "Shape" }, { "Zed", "alpha" })
  local first_reqs = #reqs
  local second = press()
  local ok_hit = first_reqs == 2 and #reqs == 0 and second ~= nil and names_of(second) == "alpha,Zed" and names_of(first) == "alpha,Zed" and H.cache_size() == 2
  rep("cache_hit", ok_hit, ("first press %d requests, repeat press %d requests, rows %s, cache size %d"):format(first_reqs, #reqs, names_of(second), H.cache_size()))

  -- cache_other_kind: supertypes of the same item is another method: only its own request is sent (the prepare answer of
  -- the same cursor and buffer state is shared), never the subtypes entry
  press("supertypes")
  rep("cache_other_kind", #reqs == 1 and reqs[1] == "typeHierarchy/supertypes", ("supertypes after subtypes sent %s"):format(vim.inspect(reqs)))
  answers[1](items({ "Base" }))

  -- cache_invalidate: each workspace-change event empties the cache; the next press asks again
  local bad = {}
  local events = {
    { "LspNotify", { method = "textDocument/didChange" } },
    { "LspNotify", { method = "textDocument/didSave" } },
    { "LspNotify", { method = "workspace/didChangeWatchedFiles" } },
    { "LspProgress", { params = { value = { kind = "end", title = "Building workspace" } } } },
  }
  for _, e in ipairs(events) do
    press_full({ "Shape" }, { "A" })
    local size = H.cache_size()
    vim.api.nvim_exec_autocmds(e[1], { data = e[2], modeline = false })
    local after = H.cache_size()
    local again = press()
    if not (size > 0 and after == 0 and #reqs == 1) then bad[#bad + 1] = ("%s %s: size %d -> %d, repeat sent %d"):format(e[1], (vim.inspect(e[2]):gsub("%s+", " ")), size, after, #reqs) end
  end
  -- not these: didOpen, progress begin, report
  press_full({ "Shape" }, { "A" })
  vim.api.nvim_exec_autocmds("LspNotify", { data = { method = "textDocument/didOpen" }, modeline = false })
  vim.api.nvim_exec_autocmds("LspProgress", { data = { params = { value = { kind = "begin", title = "Building workspace" } } }, modeline = false })
  vim.api.nvim_exec_autocmds("LspProgress", { data = { params = { value = { kind = "end", title = "Validate documents" } } }, modeline = false })
  local kept = H.cache_size()
  if kept ~= 2 then bad[#bad + 1] = "didOpen/progress begin emptied the cache (" .. kept .. ")" end
  rep("cache_invalidate", #bad == 0, #bad == 0 and "didChange, didSave, didChangeWatchedFiles, progress end each empty the cache; didOpen, progress begin and the end of Validate documents do not" or table.concat(bad, "; "))

  -- cache_inflight: an event between request and answer -> the answer is shown but not stored
  H.invalidate()
  local g = press()
  answers[1](items({ "Shape" }))
  vim.api.nvim_exec_autocmds("LspNotify", { data = { method = "textDocument/didChange" }, modeline = false })
  answers[2](items({ "A" }))
  local stored = H.cache_size()
  rep("cache_inflight", stored == 0, "entries after an answer that crossed an invalidation: " .. stored .. " (want 0; the prepare answer arrived before the event and was dropped by it)")

  -- cache_error: an LSP error is not cached (the retry asks again)
  H.invalidate()
  press()
  answers[1](items({ "Shape" }))
  answers[2](nil, { message = "boom" })
  local size_err = H.cache_size()
  press()
  rep("cache_error", size_err == 1 and #reqs == 1 and reqs[1] == "typeHierarchy/subtypes", ("entries after an error %d (only the prepare), retry sent %s"):format(size_err, vim.inspect(reqs)))

  -- cache_lru: bounded, least recently used out first
  H.invalidate()
  local max = H.CACHE_MAX
  H.CACHE_MAX = 4 -- 2 prepare + 2 level-1 entries
  for i, n in ipairs({ "One", "Two", "Three" }) do
    pos = { line = i, character = 0 }
    press() -- no invalidate: the entries of the three presses pile up
    answers[1](items({ n })); answers[2](items({ "X" .. n }))
  end
  local size_lru = H.cache_size()
  pos = { line = 3, character = 0 }
  press()
  local newest_hit = #reqs == 0
  pos = { line = 1, character = 0 }
  press()
  local oldest_miss = #reqs >= 1
  H.CACHE_MAX = max
  pos = { line = 0, character = 0 }
  rep("cache_lru", size_lru == 4 and newest_hit and oldest_miss, ("size %d (want 4), newest repeat sent nothing=%s, oldest asked again=%s"):format(size_lru, tostring(newest_hit), tostring(oldest_miss)))

  vim.notify = orig_notify
  vim.lsp.get_clients, vim.lsp.util.make_position_params = orig_get, orig_pos
  H.invalidate()
end

if not unit_only then
  local root = "/tmp/nv4j/d98-" .. vim.fn.getpid()
  vim.fn.delete(root, "rf")
  local function w(rel, s) vim.fn.mkdir(vim.fs.dirname(root .. "/" .. rel), "p"); local f = io.open(root .. "/" .. rel, "w"); f:write(s); f:close() end
  w("pom.xml", [[<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion>
<groupId>demo</groupId><artifactId>h98</artifactId><version>1</version>
<properties><maven.compiler.release>21</maven.compiler.release><project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>
</project>
]])
  w("src/main/java/demo/shapes/Shape.java", "package demo.shapes;\n\npublic interface Shape {\n  double area();\n}\n")
  w("src/main/java/demo/shapes/Square.java", "package demo.shapes;\n\npublic class Square implements Shape {\n  public double area() { return 4; }\n}\n")
  w("src/main/java/demo/shapes/Circle.java", "package demo.shapes;\n\n// a comment line\npublic class Circle implements Shape {\n  public double area() { return 3; }\n}\n")
  w("src/main/java/demo/other/Zeta.java", "package demo.other;\n\npublic class Zeta implements demo.shapes.Shape {\n  public double area() { return 1; }\n}\n")
  w("src/main/java/demo/app/Report.java", "package demo.app;\n\nimport demo.shapes.Shape;\n\npublic class Report {\n  public double total(Shape s) {\n    double a = 1;\n    return s.area() + a;\n  }\n  public double run(Shape s) {\n    return total(s);\n  }\n}\n")
  w("src/main/java/demo/app/Main.java", "package demo.app;\n\npublic class Main {\n  void go(demo.shapes.Shape s) {\n    new Report().total(s);\n  }\n}\n")
  w("src/main/java/demo/app/Out.java", "package demo.app;\n\npublic class Out {\n  public void hi(demo.shapes.Shape s) {\n    System.out.println(s.area());\n    java.util.List.of(1);\n  }\n}\n")
  local wsname = vim.fs.basename(root) .. "-" .. vim.fn.sha256(root):sub(1, 8)
  vim.fn.delete(require("nv4j.paths").jdtls_data .. "/" .. wsname, "rf")
  local orig_start = vim.lsp.start
  vim.lsp.start = function(config, opts)
    if config and config.name == "jdtls" then
      config.settings = vim.tbl_deep_extend("force", config.settings or {}, { java = { import = { maven = { offline = { enabled = true } } } } })
    end
    return orig_start(config, opts)
  end
  local buf = lsp.open(root .. "/src/main/java/demo/shapes/Shape.java")
  local client, why = lsp.wait_ready(buf, 240000)
  if not client then
    rep("live_ready", false, tostring(why))
  else
    vim.cmd("cd " .. vim.fn.fnameescape(root))
    local function collect(kind, line, col)
      vim.api.nvim_win_set_cursor(0, { line, col })
      local got, t0 = nil, vim.uv.hrtime()
      H.run(kind, { on_rows = function(rows, title) got = { rows = rows, title = title } end })
      vim.wait(30000, function() return got ~= nil end, 50)
      return got, (vim.uv.hrtime() - t0) / 1e6
    end
    -- live_subtypes: cursor on `Shape` of `public interface Shape` (line 3)
    local g, ms = collect("subtypes", 3, 20)
    local names, texts = {}, {}
    for _, r in ipairs(g and g.rows or {}) do names[#names + 1] = r.name; texts[#texts + 1] = (H.display(r)) end
    local name_first = #texts > 0
    for _, t in ipairs(texts) do
      local a, p = t:find("%u%l+"), t:find("/", 1, true)
      if not (a and p and a < p) then name_first = false end
    end
    -- jump: the Circle row opens Circle.java on the declaration line
    local jumped, jline
    for _, r in ipairs(g and g.rows or {}) do
      if r.name == "Circle" then
        H.jump(r, client.offset_encoding)
        jumped = vim.api.nvim_buf_get_name(0)
        jline = vim.api.nvim_win_get_cursor(0)[1]
      end
    end
    rep("live_subtypes", g ~= nil and table.concat(names, ",") == "Circle,Square,Zeta" and name_first
      and jumped and vim.uv.fs_realpath(jumped) == vim.uv.fs_realpath(root) .. "/src/main/java/demo/shapes/Circle.java" and jline == 4,
      ("rows=%s (%.0f ms) first row %q; jumped to %s line %s (want Circle.java:4); title %s"):format(table.concat(names, ","), ms, texts[1] or "", tostring(jumped), tostring(jline), g and g.title or "nil"))
    vim.cmd("edit " .. vim.fn.fnameescape(root .. "/src/main/java/demo/app/Report.java"))
    -- live_calls: cursor on `total` (line 6) -> callers Report#run and Main#go
    local c = collect("incoming", 6, 18)
    local cn = {}
    for _, r in ipairs(c and c.rows or {}) do cn[#cn + 1] = ("%s@%d"):format(r.name, r.target.range.start.line + 1) end
    local jl
    if c and c.rows[1] then H.jump(c.rows[1], client.offset_encoding); jl = vim.api.nvim_buf_get_name(0):match("[^/]+$") .. ":" .. vim.api.nvim_win_get_cursor(0)[1] end
    rep("live_calls", c ~= nil and table.concat(cn, ",") == "Main#go@5,Report#run@11" and jl == "Main.java:5", ("rows=%s jump=%s"):format(table.concat(cn, ","), tostring(jl)))

    -- live_cache: the repeat press of the same key sends nothing (rows at once, same rows); an edit (didChange) empties the cache
    -- and the next press asks jdt.ls again.
    vim.cmd("edit " .. vim.fn.fnameescape(root .. "/src/main/java/demo/shapes/Shape.java"))
    local sent, orig_req = 0, client.request
    client.request = function(self, method, ...)
      if method:find("^typeHierarchy/") or method:find("prepareTypeHierarchy", 1, true) then sent = sent + 1 end
      return orig_req(self, method, ...)
    end
    H.invalidate("test")
    local c1, ms1 = collect("subtypes", 3, 20)
    local s1, n1 = sent, H.cache_size()
    sent = 0
    local c2, ms2 = collect("subtypes", 3, 20)
    local s2, why2 = sent, H.last_reason
    local function nm(g) local t = {}; for _, r in ipairs(g and g.rows or {}) do t[#t + 1] = r.name end return table.concat(t, ",") end
    local same = c1 and c2 and nm(c1) == nm(c2) and nm(c1) == "Circle,Square,Zeta"
    vim.api.nvim_buf_set_lines(0, 4, 4, false, { "// edited" })
    local cleared = vim.wait(5000, function() return H.cache_size() == 0 end, 50)
    local why3 = H.last_reason
    sent = 0
    local c3, ms3 = collect("subtypes", 3, 20)
    local s3 = sent
    vim.cmd("silent! undo")
    client.request = orig_req
    rep("live_cache", same and s1 == 2 and n1 == 2 and s2 == 0 and cleared and s3 == 2 and c3 ~= nil and nm(c3) == "Circle,Square,Zeta",
      ("first press: %d requests, %d entries, %.0f ms; repeat: %d requests, %.0f ms, same rows=%s (last invalidation: %s); after an edit cache emptied=%s (%s), next press: %d requests, %.0f ms"):format(
        s1, n1, ms1, s2, ms2, tostring(same), tostring(why2), tostring(cleared), tostring(why3), s3, ms3))
  end

  if client then
    -- live_outgoing_library (regression for the E5108 crash): outgoing calls of Out#hi hold JDK methods (jdt:// targets). The REAL
    -- picker opens and the selection moves over every row; no error may be raised (v:errmsg, :messages), every row's preview ran.
    vim.cmd("edit " .. vim.fn.fnameescape(root .. "/src/main/java/demo/app/Out.java"))
    vim.api.nvim_win_set_cursor(0, { 4, 16 })
    vim.v.errmsg = ""
    vim.cmd("messages clear")
    H.run("outgoing")
    local picker
    local state = require("telescope.actions.state")
    vim.wait(30000, function()
      picker = state.get_current_picker(vim.api.nvim_get_current_buf())
      return picker ~= nil and picker.manager ~= nil and picker.manager:num_results() > 0
    end, 50)
    local n, libs, errs = 0, 0, {}
    if picker then
      n = picker.manager:num_results()
      for i = 1, n do
        local e = picker:get_selection()
        if e and type(e.path) == "string" and e.path:sub(1, 6) == "jdt://" then libs = libs + 1 end
        local ok, err = pcall(picker.refresh_previewer, picker)
        if not ok then errs[#errs + 1] = tostring(err) end
        vim.wait(150)
        vim.api.nvim_feedkeys(vim.keycode("<C-n>"), "x", false)
        vim.wait(150)
      end
    end
    local msgs = vim.api.nvim_exec2("messages", { output = true }).output
    local bad = vim.v.errmsg ~= "" or msgs:find("E5108", 1, true) or msgs:find("expected string", 1, true) or #errs > 0
    pcall(function() require("telescope.actions").close(picker.prompt_bufnr) end)
    rep("live_outgoing_library", picker ~= nil and n >= 2 and libs >= 1 and not bad,
      ("rows=%d library rows=%d errmsg=%q errs=%s messages=%q"):format(n, libs, vim.v.errmsg, vim.inspect(errs), msgs:sub(1, 200)))

    -- live_enter_library: <CR> on a library (jdt://) row opens the class in the current window with its content (jdt.ls
    -- decompiled or JDK source) and the cursor on the method's line; no error.
    do
      vim.cmd("edit " .. vim.fn.fnameescape(root .. "/src/main/java/demo/app/Out.java"))
      vim.api.nvim_win_set_cursor(0, { 4, 16 })
      vim.v.errmsg = ""
      H.run("outgoing")
      local pk
      vim.wait(30000, function()
        pk = state.get_current_picker(vim.api.nvim_get_current_buf())
        return pk ~= nil and pk.manager ~= nil and pk.manager:num_results() > 0
      end, 50)
      local want_line, picked
      if pk then
        for _ = 1, pk.manager:num_results() do
          local e = pk:get_selection()
          if e and type(e.path) == "string" and e.path:sub(1, 6) == "jdt://" then picked = e; want_line = e.lnum; break end
          vim.api.nvim_feedkeys(vim.keycode("<C-n>"), "x", false)
          vim.wait(100)
        end
      end
      local t0 = vim.uv.hrtime()
      if picked then vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false) end
      local landed = vim.wait(30000, function() return vim.api.nvim_buf_get_name(0):sub(1, 6) == "jdt://" and vim.api.nvim_buf_line_count(0) > 5 end, 100)
      local ms = (vim.uv.hrtime() - t0) / 1e6
      local lb = vim.api.nvim_get_current_buf()
      local cur = vim.api.nvim_win_get_cursor(0)[1]
      local picker_closed = state.get_current_picker(vim.api.nvim_get_current_buf()) == nil
      rep("live_enter_library", picked ~= nil and landed and cur == want_line and picker_closed and (vim.v.errmsg == "" or vim.v.errmsg:find("java_spotbugs_post", 1, true)) and not vim.bo[lb].modifiable,
        ("picked %s; landed=%s in %.0f ms: %s, %d lines, cursor %d (want %s), picker closed=%s, errmsg=%q"):format(picked and picked.text or "none", tostring(landed),
          ms, vim.api.nvim_buf_get_name(0):sub(1, 60), vim.api.nvim_buf_line_count(0), cur, tostring(want_line), tostring(picker_closed), vim.v.errmsg))
    end
  end
  vim.lsp.start = orig_start
end

lsp.finish()
