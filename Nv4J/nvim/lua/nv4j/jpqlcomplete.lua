-- JPQL completion inside @Query strings of a Spring Data repository (specs/features/jpa.md, J8).
-- Buffer layer over the pure nv4j.jpql: finds the @Query literal under the cursor (string or text block, not nativeQuery),
-- reads the entities through nv4j.dataquery (jdt.ls + treesitter), answers LSP-style completion items.
--   M.query_at(buf, row, col)       { query =, offset =, method = node } | nil  (row 0-based, col byte offset)
--   M.complete(buf, row, col, cb)   cb(items|nil): nil = the cursor is not in a @Query string; {} = nothing to offer
local jpql = require("nv4j.jpql")
local dq = require("nv4j.dataquery")
local M = {}

local Kind = { Field = 5, Class = 7, Variable = 6, Keyword = 14 }
M.TIMEOUT_MS = 1500

local function txt(n, buf) return vim.treesitter.get_node_text(n, buf) end

--- Java string escapes to their characters (enough for queries).
local function unescape(s)
  return (s:gsub("\\(.)", { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["\n"] = "" }))
end

--- The annotation node when `lit` is the value of @Query, plus whether it is native.
local function query_annotation(lit, buf)
  local n = lit:parent()
  if n and n:type() == "element_value_pair" then
    if txt(n:field("key")[1], buf) ~= "value" then return nil end
    n = n:parent()
  end
  if not n or n:type() ~= "annotation_argument_list" then return nil end
  local ann = n:parent()
  if not ann or ann:type() ~= "annotation" or txt(ann:field("name")[1], buf) ~= "Query" then return nil end
  for c in n:iter_children() do
    if c:type() == "element_value_pair" and txt(c:field("key")[1], buf) == "nativeQuery"
      and txt(c:field("value")[1], buf) == "true" then
      return nil
    end
  end
  return ann
end

function M.query_at(buf, row, col)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "java")
  if not ok or not parser then return nil end
  parser:parse()
  local node = vim.treesitter.get_node({ bufnr = buf, pos = { row, math.max(col - 1, 0) } })
  while node and node:type() ~= "string_literal" do node = node:parent() end
  if not node then return nil end
  local ann = query_annotation(node, buf)
  if not ann then return nil end
  local sr, sc, er, ec = node:range()
  local lit = table.concat(vim.api.nvim_buf_get_text(buf, sr, sc, er, ec, {}), "\n")
  local open = lit:sub(1, 3) == '"""' and 3 or 1
  local off = #table.concat(vim.api.nvim_buf_get_text(buf, sr, sc, row, col, {}), "\n")
  if off < open or off > #lit - open then return nil end
  local content = lit:sub(open + 1, #lit - open)
  return {
    query = unescape(content),
    offset = #unescape(lit:sub(open + 1, off)),
    method = ann:parent() and ann:parent():parent(),
  }
end

--- Parameter names of the annotated method: @Param("x") value or the Java name.
local function params(method, buf)
  local out = {}
  local ps = method and method:type() == "method_declaration" and method:field("parameters")[1]
  if not ps then return out end
  for p in ps:iter_children() do
    if p:type() == "formal_parameter" then
      local name = txt(p:field("name")[1], buf)
      for c in p:iter_children() do
        if c:type() == "modifiers" then
          for a in c:iter_children() do
            if a:type() == "annotation" and txt(a:field("name")[1], buf) == "Param" then
              local v = txt(a, buf):match('"([^"]+)"')
              if v then name = v end
            end
          end
        end
      end
      out[#out + 1] = name
    end
  end
  return out
end

-- @Entity classes of the project: rg over *.java, cached per root for a while.
local ent_cache = {}
local ENT_TTL_MS = 30000
local function entity_names(buf, cb)
  local root = require("nv4j.root").project(vim.api.nvim_buf_get_name(buf))
  local c = ent_cache[root]
  if c and (vim.uv.now() - c.t) < ENT_TTL_MS then return cb(c.names) end
  if vim.fn.executable("rg") ~= 1 then return cb({}) end
  vim.system({ "rg", "-l", "--glob", "*.java", "@Entity\\b", root }, { text = true }, function(r)
    vim.schedule(function()
      local names = {}
      for f in (r.stdout or ""):gmatch("[^\n]+") do names[#names + 1] = vim.fn.fnamemodify(f, ":t:r") end
      table.sort(names)
      ent_cache[root] = { t = vim.uv.now(), names = names }
      cb(names)
    end)
  end)
end
function M.reset() ent_cache = {} end

local function item(label, kind, detail) return { label = label, kind = kind, detail = detail } end

--- Items for the analysis `a` of query `q`, or nil while a type is still being fetched.
local function attempt(buf, row, q, a, map, repo_key, repo_name)
  local props = dq.resolver_for(buf)
  local ctx = {
    entity_type = function(name)
      if name == repo_name then return repo_key end
      local k = dq.named_key(name)
      if not k then dq.load_named(buf, name) end
      return k
    end,
    props = props,
  }
  local items = {}
  if a.kind == "member" then
    local ms = jpql.members(a.path, map, ctx)
    if not ms then return nil end
    for _, m in ipairs(ms) do items[#items + 1] = item(m.name, Kind.Field, m.type and dq.label(m.type) or nil) end
  elseif a.kind == "alias" or a.kind == "expr" then
    for _, al in ipairs(jpql.alias_list(map, ctx)) do
      items[#items + 1] = item(al.name, Kind.Variable, al.type and dq.label(al.type) or nil)
    end
    if a.kind == "expr" then
      for _, k in ipairs(jpql.KEYWORDS) do items[#items + 1] = item(k, Kind.Keyword) end
    end
  elseif a.kind == "param" then
    for _, p in ipairs(params(q.method, buf)) do items[#items + 1] = item(p, Kind.Variable, "parameter") end
  end
  return items
end

function M.complete(buf, row, col, cb)
  local q = M.query_at(buf, row, col)
  if not q then return cb(nil) end
  local a = jpql.analyze(q.query, q.offset)
  if a.kind == "none" then return cb({}) end
  if a.kind == "entity" then
    return entity_names(buf, function(names)
      local items = {}
      for _, n in ipairs(names) do items[#items + 1] = item(n, Kind.Class, "entity") end
      cb(items)
    end)
  end
  local map = jpql.aliases(q.query)
  local repo_key, repo_name = dq.repository_at(buf, row)
  local done = false
  local function finish(items)
    if done then return end
    done = true
    cb(items or {})
  end
  local function try(left)
    if done then return end
    if not vim.api.nvim_buf_is_valid(buf) then return finish({}) end
    local items = attempt(buf, row, q, a, map, repo_key, repo_name)
    if items then return finish(items) end
    if left > 0 and dq.pending() then
      dq.on_arrival(function() try(left - 1) end)
    else
      finish({})
    end
  end
  vim.defer_fn(function() finish({}) end, M.TIMEOUT_MS)
  try(8)
end

return M
