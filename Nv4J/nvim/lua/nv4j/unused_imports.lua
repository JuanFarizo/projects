-- Unused-import warnings while the file has compile errors.
-- ECJ checks unused imports only when the compilation unit has no errors
-- (`if (!this.compilationResult.hasMandatoryErrors()) checkUnusedImports();`,
-- CompilationUnitDeclaration.java:664), and jdt.ls has no switch for it. IntelliJ keeps showing
-- them, and the user wants to decide when to clear them. This pass fills exactly that gap:
--  * it publishes only while jdt.ls reports at least one ERROR in the buffer (then jdt.ls reports
--    no unused import itself, so there is never a duplicate; without errors jdt.ls owns them);
--  * treesitter only (no LSP request): imports are parsed from the tree; a name is used if it is an
--    identifier/type_identifier anywhere after the imports (types, calls, annotations, scoped
--    references) or a javadoc reference ({@link X}, {@linkplain X}, {@value X}, @see X,
--    @throws X, @exception X), like JDT/IntelliJ which count javadoc references as uses;
--  * static imports are checked by member name; wildcard imports are skipped;
--  * runs on jdt.ls's DiagnosticChanged (each publish) and 400 ms after the last text change, never
--    in the completion or keystroke path. Measured cost: tests/checks/30_diagnostics.lua (unused_pass_perf).
-- Message and range as jdt.ls: "The import a.b.C is never used" on the qualified name, Warning,
-- Unnecessary tag (drawn faded). Own namespace "nv4j.unused_imports".
local M = {}

M.ns = vim.api.nvim_create_namespace("nv4j.unused_imports")
M.DEBOUNCE_MS = 400

local IDENT = { identifier = true, type_identifier = true }

local JAVADOC_TAGS = { link = true, linkplain = true, value = true, see = true, throws = true, exception = true }

--- Unused imports of `buf` as { { lnum, col, end_lnum, end_col, name = "a.b.C" } }, from the
--- syntax tree only. Returns nil when the buffer has no Java parser.
function M.scan(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "java")
  if not ok or not parser then return nil end
  local root = parser:parse()[1]:root()
  local imports, body_row = {}, 0
  for node in root:iter_children() do
    local t = node:type()
    if t == "import_declaration" then
      local text = vim.treesitter.get_node_text(node, buf)
      local wildcard, qname = false, nil
      for child in node:iter_children() do
        if child:type() == "asterisk" then wildcard = true end
        if child:type() == "scoped_identifier" or child:type() == "identifier" then qname = child end
      end
      if qname and not wildcard then
        local name_node = qname:field("name")[1] or qname
        local sr, sc, er, ec = qname:range()
        imports[#imports + 1] = {
          lnum = sr, col = sc, end_lnum = er, end_col = ec,
          name = vim.treesitter.get_node_text(qname, buf),
          simple = vim.treesitter.get_node_text(name_node, buf),
          static = text:find("^import%s+static%s") ~= nil,
        }
      end
      body_row = select(3, node:range()) + 1
    elseif t == "package_declaration" then
      body_row = math.max(body_row, select(3, node:range()) + 1)
    end
  end
  if #imports == 0 then return {} end
  local wanted = {}
  for _, imp in ipairs(imports) do wanted[imp.simple] = false end
  -- Text search for each imported name in the body (C string search, cheap), then ask the tree
  -- whether that occurrence is an identifier/type_identifier (not a string or comment). Most used
  -- names are found at their first occurrence; only unused ones scan the whole body.
  local lines = vim.api.nvim_buf_get_lines(buf, body_row, -1, false)
  local text = table.concat(lines, "\n")
  local starts, pos = { 1 }, 1
  for i = 1, #lines - 1 do
    pos = pos + #lines[i] + 1
    starts[i + 1] = pos
  end
  local function line_of(off)
    local lo, hi = 1, #starts
    while lo < hi do
      local mid = math.floor((lo + hi + 1) / 2)
      if starts[mid] <= off then lo = mid else hi = mid - 1 end
    end
    return lo
  end
  for name in pairs(wanted) do
    local init = 1
    while true do
      local s, e = text:find(name, init, true)
      if not s then break end
      local before, after = text:sub(s - 1, s - 1), text:sub(e + 1, e + 1)
      local whole = not before:find("[%w_$]") and not after:find("[%w_$]")
      local i = line_of(s)
      local row, col = body_row + i - 1, s - starts[i]
      local node = whole and root:named_descendant_for_range(row, col, row, col + #name) or nil
      if node and IDENT[node:type()] then
        wanted[name] = true
        break
      end
      -- javadoc reference ({@link X}, @see X, @throws X, ...): counts as a use, like JDT/IntelliJ
      if node and node:type() == "block_comment" then
        local tag = lines[i]:sub(1, col):match("@(%a+)%s+[%w_.#$]*$")
        if tag and JAVADOC_TAGS[tag] and vim.treesitter.get_node_text(node, buf):sub(1, 3) == "/**" then
          wanted[name] = true
          break
        end
      end
      init = e + 1
    end
  end
  local out = {}
  for _, imp in ipairs(imports) do
    if not wanted[imp.simple] then out[#out + 1] = imp end
  end
  return out
end

local function jdtls_state(buf)
  local errors, reported = 0, {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    local ns = vim.diagnostic.get_namespace(d.namespace)
    if ns and ns.name:find("jdtls", 1, true) then
      if d.severity == vim.diagnostic.severity.ERROR then errors = errors + 1 end
      reported[d.message] = true
    end
  end
  return errors, reported
end

local busy = {}
--- Recompute and publish (or clear) the warnings for `buf`.
function M.run(buf)
  if busy[buf] or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "java" then return end
  busy[buf] = true
  local ok, err = pcall(function()
    local errors, reported = jdtls_state(buf)
    local diags = {}
    if errors > 0 then
      for _, imp in ipairs(M.scan(buf) or {}) do
        local msg = ("The import %s is never used"):format(imp.name)
        if not reported[msg] then
          diags[#diags + 1] = {
            lnum = imp.lnum, col = imp.col, end_lnum = imp.end_lnum, end_col = imp.end_col,
            severity = vim.diagnostic.severity.WARN, message = msg, source = "nv4j",
            _tags = { unnecessary = true },
          }
        end
      end
    end
    vim.diagnostic.set(M.ns, buf, diags)
  end)
  busy[buf] = nil
  if not ok then vim.notify("nv4j.unused_imports: " .. tostring(err), vim.log.levels.DEBUG) end
end

local timers = {}
local function schedule(buf)
  local t = timers[buf]
  if not t then
    t = vim.uv.new_timer()
    timers[buf] = t
  end
  t:stop()
  t:start(M.DEBOUNCE_MS, 0, vim.schedule_wrap(function() M.run(buf) end))
end

function M.setup()
  local g = vim.api.nvim_create_augroup("nv4j_unused_imports", { clear = true })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = g,
    callback = function(args)
      if busy[args.buf] or vim.bo[args.buf].filetype ~= "java" then return end
      M.run(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = g,
    callback = function(args)
      if vim.bo[args.buf].filetype == "java" then schedule(args.buf) end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = g,
    callback = function(args)
      local t = timers[args.buf]
      if t then t:stop(); t:close(); timers[args.buf] = nil end
    end,
  })
end

return M
