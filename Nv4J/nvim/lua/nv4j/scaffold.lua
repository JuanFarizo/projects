-- Scaffolding (decision D22, specs/features/scaffolding.md, check 61_scaffold): new Java type, package
-- or the test class of the current class. The one template source: <leader>jn / <leader>jt
-- (config/keymaps.lua), neo-tree's `a` (plugins/neo-tree.lua file_added) and `:e Foo.java`
-- (config/autocmds.lua BufNewFile) all use M.lines.
--
-- The file is written to disk with its content BEFORE it is opened: nvim-jdtls writes every new Java
-- buffer whose file does not exist to disk on attach (jdtls/setup.lua `vim.cmd('w')`), which left an
-- empty file on disk with the old buffer template.
--
-- Templates follow IntelliJ's internal ones (no header comment): `package x;` (omitted in the default
-- package), a blank line, the declaration. Spring presets add their import and annotation. The package
-- comes from the directory under `src/<set>/java`; a dotted name (`foo.Bar`) creates the packages.
local M = {}

M.KINDS = { "class", "interface", "record", "enum", "annotation", "controller", "service", "repository", "entity",
  "package", "test" }

local TYPE_KINDS = { class = true, interface = true, record = true, enum = true, annotation = true, controller = true,
  service = true, repository = true, entity = true }

-- Spring stereotypes: a class with the import and annotation typed by hand on every one of them.
local PRESETS = {
  controller = { import = "org.springframework.web.bind.annotation.RestController", annotation = "@RestController" },
  service = { import = "org.springframework.stereotype.Service", annotation = "@Service" },
  repository = { import = "org.springframework.stereotype.Repository", annotation = "@Repository" },
  entity = { import = "jakarta.persistence.Entity", annotation = "@Entity" },
}

local KEYWORDS = {}
for w in ([[abstract assert boolean break byte case catch char class const continue default do double else enum
  extends final finally float for goto if implements import instanceof int interface long native new package private
  protected public return short static strictfp super switch synchronized this throw throws transient try void
  volatile while true false null _]]):gmatch("%S+") do
  KEYWORDS[w] = true
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.WARN, { title = "Nv4J scaffold" })
end

--- A Java identifier (ASCII letters, digits, _ and $; not a keyword or literal).
function M.valid_identifier(s)
  return type(s) == "string" and s:match("^[%a_$][%w_$]*$") ~= nil and not KEYWORDS[s]
end

--- Splits `a.b.C` into its segments when every one is a valid identifier; nil, reason otherwise.
local function segments(name)
  if type(name) ~= "string" or name == "" then return nil, "empty name" end
  local parts = vim.split(name, ".", { plain = true })
  for _, p in ipairs(parts) do
    if not M.valid_identifier(p) then
      return nil, ("'%s' is not a valid Java name (part '%s')"):format(name, p)
    end
  end
  return parts
end

--- Source root and package of a directory: `<...>/src/<set>/java[/a/b]` -> root, "a.b" ("" = default package).
--- nil when the directory is not inside a `src/<set>/java` source root.
---@return string? root, string? package, string? set
function M.source_root(dir)
  dir = vim.fs.normalize(dir):gsub("/+$", "")
  local root, set, rest = dir:match("^(.*/src/([^/]+)/java)(.*)$")
  if not root or (rest ~= "" and rest:sub(1, 1) ~= "/") then return nil end
  local pkg = rest:gsub("^/", ""):gsub("/", ".")
  return root, pkg, set
end

--- Class name and package of a *.java path (package nil outside a source root, "" never returned).
---@return string class_name, string? package
function M.derive(path)
  local class_name = vim.fn.fnamemodify(path, ":t:r")
  local _, pkg = M.source_root(vim.fn.fnamemodify(path, ":h"))
  return class_name, (pkg ~= nil and pkg ~= "") and pkg or nil
end

--- JUnit flavour from the project build file: 5 unless the build names only JUnit 4.
local function junit(path)
  local root = require("nv4j.root").project(path)
  for _, f in ipairs({ "pom.xml", "build.gradle", "build.gradle.kts" }) do
    local fh = io.open(root .. "/" .. f, "r")
    if fh then
      local s = fh:read("*a")
      fh:close()
      if s:find("junit%-jupiter") or s:find("spring%-boot%-starter%-test") or s:find("org%.junit%.jupiter") then return 5 end
      if s:find("<artifactId>junit</artifactId>") or s:find("junit:junit") then return 4 end
    end
  end
  return 5
end

--- Template lines for a type. kind: a TYPE_KINDS kind or "test" (opts.junit 4|5).
---@return string[] lines, integer cursor_line (1-based), integer cursor_col (0-based), boolean insert_at_end
function M.lines(class_name, package_name, kind, opts)
  opts = opts or {}
  local lines = {}
  if package_name and package_name ~= "" then
    lines[#lines + 1] = "package " .. package_name .. ";"
    lines[#lines + 1] = ""
  end
  local preset = PRESETS[kind]
  if kind == "test" then
    local j4 = opts.junit == 4
    lines[#lines + 1] = "import " .. (j4 and "org.junit.Test" or "org.junit.jupiter.api.Test") .. ";"
    lines[#lines + 1] = ""
    lines[#lines + 1] = (j4 and "public class " or "class ") .. class_name .. " {"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "    @Test"
    lines[#lines + 1] = (j4 and "    public void " or "    void ") .. "test() {"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "    }"
    lines[#lines + 1] = "}"
    return lines, #lines - 2, 0, true
  end
  if preset then
    lines[#lines + 1] = "import " .. preset.import .. ";"
    lines[#lines + 1] = ""
    lines[#lines + 1] = preset.annotation
  end
  if kind == "record" then
    local decl = ("public record %s() {"):format(class_name)
    lines[#lines + 1] = decl
    lines[#lines + 1] = "}"
    return lines, #lines - 1, (decl:find("()", 1, true)), false
  end
  local word = (preset and "class") or (kind == "annotation" and "@interface") or kind
  lines[#lines + 1] = ("public %s %s {"):format(word, class_name)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "}"
  return lines, #lines - 1, 0, true
end

--- Directory the user is "in": neo-tree's node under the cursor, else the current file's directory, else cwd.
local function context_dir()
  if vim.bo.filetype == "neo-tree" then
    local ok, node = pcall(function()
      return require("neo-tree.sources.manager").get_state("filesystem").tree:get_node()
    end)
    if ok and node and node.path then
      return node.type == "directory" and node.path or vim.fs.dirname(node.path)
    end
  end
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" and vim.bo.buftype == "" and not name:match("^%a[%w+.-]*://") then return vim.fs.dirname(name) end
  return vim.fn.getcwd()
end

--- Leaves special windows (neo-tree, quickfix, terminal) so the file opens in an editing window.
local function editing_window()
  if vim.bo.buftype == "" and vim.bo.filetype ~= "neo-tree" then return end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].buftype == "" and vim.bo[b].filetype ~= "neo-tree" and vim.api.nvim_win_get_config(w).relative == "" then
      vim.api.nvim_set_current_win(w)
      return
    end
  end
  vim.cmd("botright vnew")
end

-- Insert mode only with a UI: a headless caller (the checks) must not get a queued `S` in its typeahead.
local function has_ui()
  return #vim.api.nvim_list_uis() > 0
end

local function open(path, cursor, insert)
  if not has_ui() then insert = nil end
  editing_window()
  vim.cmd.edit(vim.fn.fnameescape(path))
  if cursor then
    pcall(vim.api.nvim_win_set_cursor, 0, { cursor[1], cursor[2] })
    if insert == "line" then
      vim.api.nvim_feedkeys("S", "n", false) -- `S` on the empty body line: insert with the indent
    elseif insert == "here" then
      vim.cmd.startinsert()
    end
  end
end

local function write_new(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local fd = vim.uv.fs_open(path, "wx", 420) -- 0644; "x": never overwrite (a file made since the check)
  if not fd then return false end
  vim.uv.fs_write(fd, table.concat(lines, "\n") .. "\n")
  vim.uv.fs_close(fd)
  return true
end

--- Creates and opens a type file. Returns the path, or nil and the reason (also notified).
local function new_type(kind, name, dir, insert)
  local parts, why = segments(name)
  if not parts then return nil, why end
  local root, base_pkg = M.source_root(dir)
  local loose = false
  if not root then
    -- a loose-file directory (no build file above it): default package, as jdt.ls treats it
    local _, has_marker = require("nv4j.root").project(dir .. "/x.java")
    if has_marker then
      return nil, ("%s is not in a Java source root (src/<set>/java)"):format(dir)
    end
    loose = true
  end
  local class_name = table.remove(parts)
  local pkg_parts = {}
  if not loose and base_pkg ~= "" then pkg_parts = vim.split(base_pkg, ".", { plain = true }) end
  vim.list_extend(pkg_parts, parts)
  local target_dir = vim.fs.normalize(dir) .. (#parts > 0 and ("/" .. table.concat(parts, "/")) or "")
  local path = target_dir .. "/" .. class_name .. ".java"
  if vim.uv.fs_stat(path) then
    open(path)
    return nil, ("%s already exists (not overwritten, opened)"):format(vim.fn.fnamemodify(path, ":~:."))
  end
  local lines, cl, cc, at_end = M.lines(class_name, table.concat(pkg_parts, "."), kind,
    kind == "test" and { junit = junit(path) } or nil)
  if not write_new(path, lines) then return nil, "could not write " .. path end
  open(path, { cl, cc }, insert and (at_end and "line" or "here") or nil)
  return path
end

local function new_package(name, dir)
  local parts, why = segments(name)
  if not parts then return nil, why end
  if not M.source_root(dir) then return nil, ("%s is not in a Java source root (src/<set>/java)"):format(dir) end
  local path = vim.fs.normalize(dir) .. "/" .. table.concat(parts, "/")
  if vim.fn.isdirectory(path) == 1 then return nil, ("package directory %s already exists"):format(path) end
  vim.fn.mkdir(path, "p")
  notify("Package created: " .. vim.fn.fnamemodify(path, ":~:."), vim.log.levels.INFO)
  return path
end

--- Test class path for a class file: same package under src/test/java, <Name>Test.java.
---@return string? test_path, string? reason
function M.test_path(class_path, name)
  local root, pkg, set = M.source_root(vim.fs.dirname(class_path or ""))
  if not root or not class_path:match("%.java$") then return nil, "not a Java class in a source root (src/<set>/java)" end
  if set == "test" then return nil, "already in the test sources" end
  local test_root = root:gsub("/src/[^/]+/java$", "/src/test/java")
  local dir = test_root .. (pkg ~= "" and ("/" .. pkg:gsub("%.", "/")) or "")
  return dir .. "/" .. (name or (vim.fn.fnamemodify(class_path, ":t:r") .. "Test")) .. ".java"
end

local function new_test(opts)
  local class_path = opts.class or vim.api.nvim_buf_get_name(0)
  local path, why = M.test_path(class_path, opts.name)
  if not path then return nil, why end
  if opts.name and not M.valid_identifier(opts.name) then return nil, ("'%s' is not a valid Java name"):format(opts.name) end
  return new_type("test", vim.fn.fnamemodify(path, ":t:r"), vim.fs.dirname(path), opts.insert)
end

--- Creates and opens a new Java file or package.
--- opts.kind: one of M.KINDS (asked with vim.ui.select when missing); opts.name: type name, dotted
--- names create packages (asked with vim.ui.input when missing; for "test" defaults to <Class>Test);
--- opts.dir: directory (default: neo-tree node, current file's directory, cwd); opts.insert: start
--- insert mode in the body (the keys do); opts.class: for "test", the class file (default current buffer).
--- Returns the path created (nil and the reason when refused; the reason is notified).
function M.new(opts)
  opts = opts or {}
  if not opts.kind then
    return vim.ui.select(M.KINDS, { prompt = "New Java:" }, function(kind)
      if kind then M.new(vim.tbl_extend("force", opts, { kind = kind })) end
    end)
  end
  local kind = opts.kind
  if not (TYPE_KINDS[kind] or kind == "package" or kind == "test") then
    notify("unknown kind: " .. tostring(kind), vim.log.levels.ERROR)
    return nil, "unknown kind"
  end
  local res, why
  if kind == "test" then
    res, why = new_test(opts)
  else
    local dir = opts.dir or context_dir()
    if not opts.name then
      local _, pkg = M.source_root(dir)
      local where = pkg and (pkg ~= "" and pkg or "default package") or dir
      return vim.ui.input({ prompt = ("New %s in %s: "):format(kind, where) }, function(name)
        if name and name ~= "" then M.new(vim.tbl_extend("force", opts, { name = vim.trim(name), dir = dir })) end
      end)
    end
    if kind == "package" then
      res, why = new_package(opts.name, dir)
    else
      res, why = new_type(kind, opts.name, dir, opts.insert)
    end
  end
  if not res then notify(why) end
  return res, why
end

--- <leader>jt: open the test class of the current class, create it when missing.
function M.test_for_current()
  local path, why = M.test_path(vim.api.nvim_buf_get_name(0))
  if not path then return notify(why) end
  if vim.uv.fs_stat(path) then return open(path) end
  return M.new({ kind = "test", insert = true })
end

local function pick_kind(class_name, cb)
  local kinds = vim.tbl_filter(function(k) return TYPE_KINDS[k] end, M.KINDS)
  vim.ui.select(kinds, { prompt = "Scaffold " .. class_name .. " as:" }, function(kind)
    if kind then cb(kind) end
  end)
end

--- `:e Foo.java` (BufNewFile): asks the kind, fills the buffer and writes it, so the file on disk is
--- not the empty one nvim-jdtls writes on attach.
function M.fill_buf(bufnr, path)
  local class_name, pkg = M.derive(path)
  pick_kind(class_name, function(kind)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    local lines, cl, cc, at_end = M.lines(class_name, pkg, kind)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent write!") end)
    if vim.api.nvim_get_current_buf() == bufnr and has_ui() then
      vim.api.nvim_win_set_cursor(0, { cl, cc })
      if at_end then vim.api.nvim_feedkeys("S", "n", false) else vim.cmd.startinsert() end
    end
  end)
end

--- neo-tree `a` (file_added): neo-tree made an empty file; ask the kind and write the template into it.
function M.fill_file(path)
  local st = vim.uv.fs_stat(path)
  if st and st.size > 0 then return end
  local class_name, pkg = M.derive(path)
  pick_kind(class_name, function(kind)
    vim.fn.writefile((M.lines(class_name, pkg, kind)), path)
    local b = vim.fn.bufnr(path)
    if b ~= -1 and vim.api.nvim_buf_is_loaded(b) and not vim.bo[b].modified then
      vim.api.nvim_buf_call(b, function() vim.cmd("silent checktime") end)
    end
  end)
end

return M
