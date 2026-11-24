-- <leader>cxv / cxc / cxm in a Java buffer (specs/features/code-actions.md, check 100).
-- LazyVim's jdtls extra maps these to nvim-jdtls (extract_variable_all / extract_constant / extract_method) and nvim-jdtls
-- is SILENT when nothing can be extracted: jdt.ls answers java/getRefactorEdit with null (selection not a whole
-- expression: `vi"` inside a string, `viw` on a word, `V` on a statement) and nothing happens at all. This wrapper keeps
-- those same functions and adds two things:
--   * `vi"` / `vi'` (selection strictly inside a pair of quotes) and a selection with edge blanks become the whole
--     literal / the trimmed expression before the request (extract variable and constant only);
--   * when jdt.ls has nothing to extract, one WARN notification says so and what to select (nvim-jdtls only prints
--     "No selection found..." for the cursor case, and nothing for the selection case).
-- The notification is raised by wrapping client:request for java/inferSelection and java/getRefactorEdit while a key is
-- "armed" (set by the key, dropped at the first answer or after ARM_MS).
--   * name suggestions: jdt.ls answers extract variable / constant and introduce parameter with an edit that names the new
--     thing `i` / `INT` and a `java.action.rename` command (offset of the new name); the answer carries NO alternative
--     names. After the edit is applied a vim.ui.select lists names derived from the expression and the type (M.suggest),
--     best first, jdt.ls's own name among them, "Rename..." last; Esc keeps jdt.ls's name. Also for the code action menu
--     (<leader>ca "Introduce Parameter"). vim.g.nv4j_extract_names = false switches it off.
local M = {}

M.ARM_MS = 120000
local LABEL = { variable = "variable", constant = "constant", method = "method" }
local FN = { variable = "extract_variable_all", constant = "extract_constant", method = "extract_method" }
local armed -- { kind = , t = }

local function warn(msg) vim.notify(msg, vim.log.levels.WARN, { title = "Extract" }) end

-- ---------------------------------------------------------------- name suggestions
local KEYWORDS = {}
for w in ([[abstract assert boolean break byte case catch char class const continue default do double else enum extends final
  finally float for goto if implements import instanceof int interface long native new package private protected public return
  short static strictfp super switch synchronized this throw throws transient try void volatile while var record yield true false null]]):gmatch("%a+") do KEYWORDS[w] = true end
local PRIM = { int = "i", long = "l", double = "d", float = "f", boolean = "b", char = "c", byte = "b", short = "s" }
local COLL = { List = 1, Set = 1, Collection = 1, Iterable = 1, Queue = 1, Deque = 1, ArrayList = 1, LinkedList = 1, HashSet = 1, TreeSet = 1, LinkedHashSet = 1, Stream = 1 }

local function decap(w) return (w:gsub("^%u+", function(u) return #u > 1 and (u:sub(1, #u - 1):lower() .. u:sub(-1)) or u:lower() end)) end
local function cap(w) return (w:gsub("^%l", string.upper)) end
local function plural(w)
  if w:match("[sxz]$") or w:match("[cs]h$") then return w .. "es" end
  if w:match("[^aeiou]y$") then return w:sub(1, -2) .. "ies" end
  return w .. "s"
end
local function snake(w) return (w:gsub("(%l)(%u)", "%1_%2"):gsub("(%u)(%u%l)", "%1_%2"):upper()) end
local function words_of(str) local t = {} for w in str:gmatch("%a[%w]*") do t[#t + 1] = w:lower() end return t end

--- `Map<K, V>` -> "Map", { "K", "V" } (top-level arguments); anything else -> text, {}.
local function split_type(t)
  t = (vim.trim(t or ""):gsub("^final%s+", ""))
  local base, args = t:match("^([%w_%.]+)%s*<(.*)>%s*$")
  if not base then return t, {} end
  local list, depth, cur = {}, 0, ""
  for ch in args:gmatch(".") do
    if ch == "<" then depth = depth + 1 elseif ch == ">" then depth = depth - 1 end
    if ch == "," and depth == 0 then list[#list + 1] = vim.trim(cur) cur = "" else cur = cur .. ch end
  end
  list[#list + 1] = vim.trim(cur)
  return base:match("([%w_]+)$"), list
end

--- Names for a new variable / parameter (camelCase) or constant (UPPER_SNAKE) holding `expr` of Java type `typ`, best
--- first, valid identifiers only. Rules (IntelliJ JavaNameSuggestionUtil, Eclipse StubUtility.getVariableNameSuggestions):
--- string literal -> its words; `new Foo(..)` -> foo; `x.getFooBar()` / `isFoo()` / `hasFoo()` / `findFoo()` -> fooBar / foo;
--- other call or field path -> its last name; then the type: collection or array -> plural of the element type,
--- `Foo<..>` -> foo, primitive -> i l d f b c s.
function M.suggest(expr, typ, kind)
  local out, seen = {}, {}
  local function add(n)
    if not n or not n:match("^[%a_][%w_]*$") or KEYWORDS[n] then return end
    if kind == "constant" then n = (snake(n):gsub("__+", "_")) else n = decap(n) end
    if #n > 40 or seen[n] then return end
    seen[n] = true; out[#out + 1] = n
  end
  expr = vim.trim(expr or "")
  local base, targs = split_type(typ)
  local str = expr:match('^"(.*)"$')
  if str then
    local w = words_of((str:gsub("\\.", " "))) -- escapes (\r \n \t) are not words
    if #w > 0 then
      local keep = vim.list_slice(w, 1, 4)
      add(kind == "constant" and table.concat(keep, "_") or (keep[1] .. table.concat(vim.tbl_map(cap, vim.list_slice(keep, 2)))))
    end
  end
  local ctor = expr:match("^new%s+([%w_%.]+)")
  if ctor then
    add(ctor:match("([%w_]+)$"))
  elseif not str then
    local call = expr:match("([%a_][%w_]*)%s*%b()%s*$")
    if call then
      local rest = call:match("^get(%u[%w_]*)$") or call:match("^is(%u[%w_]*)$") or call:match("^has(%u[%w_]*)$") or call:match("^find(%u[%w_]*)$")
      if rest then add(rest) elseif call ~= "of" and call ~= "valueOf" and call ~= "get" then add(call) end
    elseif expr:match("^[%a_][%w_%.]*$") then
      add(expr:match("([%w_]+)$"))
    end
  end
  local elem = base:match("^(.-)%[%]$")
  local el = elem and (split_type(elem)) or ((COLL[base] == 1 and targs[1]) and (split_type(targs[1])) or nil)
  if el and el:match("^[%a_]") then
    add(plural(PRIM[el] and el or decap(el)))
  elseif base == "Map" or base:match("Map$") then
    add("map")
  elseif PRIM[base] then
    if kind ~= "constant" then add(PRIM[base]) end -- a constant `I` says nothing; jdt.ls's INT stays
  elseif base:match("^[%a_][%w_]*$") then
    add(decap(base))
  end
  return out
end

--- Type text just before the name at byte `col` (0-based) of a declaration line: `int`, `String`, `Foo<A, B>`.
local function type_before(line, col)
  local s = line:sub(1, col):gsub("%s+$", "")
  local i, depth = #s, 0
  while i > 0 do
    local ch = s:sub(i, i)
    if ch == ">" then depth = depth + 1 elseif ch == "<" then depth = depth - 1 end
    if depth == 0 and ch:match("[%s(,]") then break end
    i = i - 1
  end
  return s:sub(i + 1)
end

--- Text under the request: the inferred selection (offset, length) of a java/getRefactorEdit, else the request range.
local function expr_text(buf, params)
  local ca = params.commandArguments and params.commandArguments[1]
  if ca and ca.offset and ca.length then
    local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, true), "\n")
    local a, b = vim.fn.byteidx(content, ca.offset), vim.fn.byteidx(content, ca.offset + ca.length)
    if a >= 0 and b >= a then return content:sub(a + 1, b) end
  end
  local r = params.range or (params.context and params.context.range)
  if not r then return "" end
  local ok, t = pcall(vim.api.nvim_buf_get_text, buf, r.start.line, r.start.character, r["end"].line, r["end"].character, {})
  return ok and table.concat(t, "\n") or ""
end

local last_expr = "" -- text of the last extract request / codeAction range (read before the edit is applied)

--- After a refactoring edit jdt.ls sends java.action.rename (offset of the new name; nvim-jdtls moves the cursor there).
--- A new local variable / constant / parameter gets the picker; fields, methods and anything else are left alone.
local function offer_at(buf, row, col) -- row 1-based, col 0-based byte of the new name
  if vim.g.nv4j_extract_names == false or vim.api.nvim_get_current_buf() ~= buf then return end
  local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, true), "\n")
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  local default = line:match("^[%w_]+", col + 1)
  if not default then return end
  local before, after = line:sub(1, col), line:sub(col + #default + 1)
  local kind = (before:match("static%s+final%s") and after:match("^%s*=")) and "constant"
    or (after:match("^%s*[,)]") and before:match("[(,]%s*[%w_<>%[%]%.,%?%s]*$")) and "parameter"
    or after:match("^%s*=[^=]") and "variable"
  if not kind then return end
  local items = {}
  for _, n in ipairs(M.suggest(last_expr, type_before(line, col), kind)) do
    local used = n ~= default and select(2, content:gsub("%f[%w_]" .. n .. "%f[^%w_]", "")) > 0 -- already a name in the file
    if not used then items[#items + 1] = n end
    if #items == 5 then break end
  end
  if not vim.tbl_contains(items, default) then items[#items + 1] = default end
  if #items == 1 then return end
  items[#items + 1] = "Rename..."
  M.last_items = items
  local label = kind == "constant" and "Constant name" or kind == "parameter" and "Parameter name" or "Variable name"
  vim.schedule(function()
    if vim.api.nvim_get_current_buf() ~= buf then return end
    vim.ui.select(items, { prompt = label .. " (Esc keeps " .. default .. ")" }, function(choice)
      if not choice or choice == default then return end
      vim.lsp.buf.rename(choice ~= "Rename..." and choice or nil, { name = "jdtls" })
    end)
  end)
end

--- java.action.rename (offset of the new name): extract variable / constant.
local function offer(ctx, rename)
  local buf = ctx and ctx.bufnr
  local arg = rename and rename.arguments and rename.arguments[1]
  if not (buf and arg and arg.offset) then return end
  local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, true), "\n")
  local b = vim.fn.byteidx(content, arg.offset)
  if b < 0 then return end
  local row = vim.fn.byte2line(b + 1)
  offer_at(buf, row, b - vim.fn.line2byte(row) + 1)
end

--- Introduce Parameter answers codeAction/resolve with an edit and NO rename command: the new parameter is the edit that
--- inserts `Type name` (a pure insertion) into the current file; put the cursor on the name and offer.
local function offer_param(buf, action)
  local uri = vim.uri_from_bufnr(buf)
  local edits = action.edit and (action.edit.changes and action.edit.changes[uri])
  for _, dc in ipairs(action.edit and action.edit.documentChanges or {}) do
    if dc.textDocument and dc.textDocument.uri == uri then edits = dc.edits end
  end
  for _, e in ipairs(edits or {}) do
    -- jdt.ls answers one edit from after the `(` / last parameter to the replaced expression:
    -- "int parseInt) {\n        return parseInt" or ", int i) {...": the name stands before the first `)`.
    local first = (e.newText or ""):match("^[^\n]*")
    local s, _, name = first:find("%s([%a_][%w_]*)%s*%)")
    if s then
      local row, col = e.range.start.line + 1, e.range.start.character + s
      vim.api.nvim_win_set_cursor(0, { row, col })
      return offer_at(buf, row, col)
    end
  end
end

--- Wrap nvim-jdtls's java.action.rename command once (called by its refactor handler and by code action commands).
local function wrap_rename()
  local ok, jdtls = pcall(require, "jdtls")
  local orig = ok and jdtls.commands and jdtls.commands["java.action.rename"]
  if not orig or M.rename_wrapped == orig then return end
  local new = function(command, ctx)
    local r = orig(command, ctx)
    pcall(offer, ctx, command)
    return r
  end
  M.rename_wrapped = new
  jdtls.commands["java.action.rename"] = new
end

local function live() return armed and (vim.uv.now() - armed.t) < M.ARM_MS end

--- Wrap client:request once per client (a raw field shadows the metatable method).
local function wrap(client)
  wrap_rename()
  if rawget(client, "nv4j_extract_wrapped") then return end
  client.nv4j_extract_wrapped = true
  local orig = client.request
  client.request = function(self, method, params, handler, bufnr)
    if type(params) == "table" and (method == "java/getRefactorEdit" or method == "textDocument/codeAction") then
      local t = expr_text(vim.api.nvim_get_current_buf(), params)
      if t ~= "" or method == "java/getRefactorEdit" then last_expr = t end
    end
    if method == "codeAction/resolve" and handler and type(params) == "table" and (params.kind or ""):find("introduce.parameter", 1, true) then
      local buf0, inner0 = vim.api.nvim_get_current_buf(), handler
      handler = function(err, res, ctx)
        local r = inner0(err, res, ctx)
        if not err and res then pcall(offer_param, buf0, res) end
        return r
      end
    end
    if live() and (method == "java/getRefactorEdit" or method == "java/inferSelection") and handler then
      local kind = armed.kind
      local inner = handler
      handler = function(err, result, ctx)
        if method == "java/inferSelection" then
          if not err and (not result or #result == 0) then
            armed = nil
            warn(("Extract %s: nothing under the cursor. Select an expression."):format(LABEL[kind]))
            return -- nvim-jdtls would only print the same text
          end
        elseif not err then
          armed = nil
          if not result or (not result.edit and not result.command) then
            warn(("Extract %s: the selection is not a whole expression. Include a string's quotes."):format(LABEL[kind]))
          end
        else
          armed = nil
        end
        return inner(err, result, ctx)
      end
    end
    return orig(self, method, params, handler, bufnr)
  end
end

--- Visual selection (marks `<` `>`, charwise, one line): trim blanks, and widen a selection that sits strictly inside
--- a pair of quotes to the quotes. Returns true when the marks changed.
function M.normalize(buf)
  if vim.fn.visualmode() ~= "v" then return false end
  local s, e = vim.api.nvim_buf_get_mark(buf, "<"), vim.api.nvim_buf_get_mark(buf, ">")
  if s[1] ~= e[1] then return false end
  local line = vim.api.nvim_buf_get_lines(buf, s[1] - 1, s[1], false)[1] or ""
  local a, b = s[2] + 1, math.min(e[2] + 1, #line) -- 1-based inclusive bytes
  while a < b and line:sub(a, a):match("%s") do a = a + 1 end
  while b > a and line:sub(b, b):match("%s") do b = b - 1 end
  local q = line:sub(a - 1, a - 1)
  if (q == '"' or q == "'") and line:sub(b + 1, b + 1) == q and not line:sub(a, b):find(q, 1, true) then
    a, b = a - 1, b + 1
  end
  if a == s[2] + 1 and b == e[2] + 1 then return false end
  vim.api.nvim_buf_set_mark(buf, "<", s[1], a - 1, {})
  vim.api.nvim_buf_set_mark(buf, ">", e[1], b - 1, {})
  return true
end

--- kind: "variable" | "constant" | "method"; visual: from the x-mode map (marks already set by the <Esc> before it).
function M.run(kind, visual)
  local buf = vim.api.nvim_get_current_buf()
  local client = vim.lsp.get_clients({ bufnr = buf, name = "jdtls" })[1]
  if not client then return warn("Extract: no jdt.ls attached to this buffer.") end
  wrap(client)
  if visual and kind ~= "method" then M.normalize(buf) end
  armed = { kind = kind, t = vim.uv.now() }
  require("jdtls")[FN[kind]](visual and true or nil)
end

function M.armed() return live() and armed.kind or nil end

--- Buffer-local maps, set from on_attach (after LazyVim's which-key ones, so they win).
function M.bind(buf)
  local client = vim.lsp.get_clients({ bufnr = buf, name = "jdtls" })[1]
  if client then wrap(client) end -- name suggestions also for <leader>ca "Introduce Parameter"
  local function n(lhs, kind, desc) vim.keymap.set("n", lhs, function() M.run(kind) end, { buffer = buf, desc = desc }) end
  local function x(lhs, kind, desc)
    vim.keymap.set("x", lhs, "<Esc><Cmd>lua require('nv4j.extract').run('" .. kind .. "', true)<CR>", { buffer = buf, desc = desc, silent = true })
  end
  n("<leader>cxv", "variable", "Extract Variable")
  n("<leader>cxc", "constant", "Extract Constant")
  x("<leader>cxv", "variable", "Extract Variable")
  x("<leader>cxc", "constant", "Extract Constant")
  x("<leader>cxm", "method", "Extract Method")
end

return M
