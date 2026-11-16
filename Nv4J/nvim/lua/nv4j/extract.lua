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
local M = {}

M.ARM_MS = 120000
local LABEL = { variable = "variable", constant = "constant", method = "method" }
local FN = { variable = "extract_variable_all", constant = "extract_constant", method = "extract_method" }
local armed -- { kind = , t = }

local function warn(msg) vim.notify(msg, vim.log.levels.WARN, { title = "Extract" }) end

local function live() return armed and (vim.uv.now() - armed.t) < M.ARM_MS end

--- Wrap client:request once per client (a raw field shadows the metatable method).
local function wrap(client)
  if rawget(client, "nv4j_extract_wrapped") then return end
  client.nv4j_extract_wrapped = true
  local orig = client.request
  client.request = function(self, method, params, handler, bufnr)
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
