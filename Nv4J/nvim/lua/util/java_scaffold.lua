-- Shared by config/autocmds.lua (BufNewFile, fills a buffer) and
-- plugins/neo-tree.lua (FILE_ADDED, writes to disk directly since neo-tree
-- creates files via libuv, not `:edit`).
local M = {}

-- Spring stereotypes: same "class" boilerplate plus the import + annotation
-- you'd otherwise type by hand on every controller/service/entity.
local PRESETS = {
  ["controller"] = { imports = { "org.springframework.web.bind.annotation.RestController" }, annotation = "@RestController" },
  ["service"] = { imports = { "org.springframework.stereotype.Service" }, annotation = "@Service" },
  ["repository"] = { imports = { "org.springframework.stereotype.Repository" }, annotation = "@Repository" },
  ["entity"] = { imports = { "jakarta.persistence.Entity" }, annotation = "@Entity" },
}
local KINDS = { "class", "interface", "record", "enum", "controller", "service", "repository", "entity" }

---Derive class name + package (Maven/Gradle `src/main/java` or
---`src/test/java` layout) from a *.java file path.
---@param path string
---@return string class_name
---@return string? package_name
function M.derive(path)
  local class_name = vim.fn.fnamemodify(path, ":t:r")
  local dir = vim.fn.fnamemodify(path, ":h")
  local after_root = dir:match("/src/main/java/(.+)$") or dir:match("/src/test/java/(.+)$")
  local package_name = after_root and after_root:gsub("/", ".") or nil
  return class_name, package_name
end

---@param class_name string
---@param package_name string?
---@param kind "class"|"interface"|"record"|"enum"|"controller"|"service"|"repository"|"entity"
---@return string[] lines
---@return integer cursor_line 1-indexed
---@return integer cursor_col 0-indexed
function M.lines(class_name, package_name, kind)
  local preset = PRESETS[kind]
  local lines = {}
  if package_name then
    table.insert(lines, "package " .. package_name .. ";")
    table.insert(lines, "")
  end

  if preset then
    for _, imp in ipairs(preset.imports) do
      table.insert(lines, "import " .. imp .. ";")
    end
    table.insert(lines, "")
  end

  kind = preset and "class" or kind

  if preset then
    table.insert(lines, preset.annotation)
  end

  local cursor_line, cursor_col
  if kind == "record" then
    local decl = string.format("public record %s() {", class_name)
    table.insert(lines, decl)
    table.insert(lines, "}")
    cursor_line = #lines - 1
    cursor_col = decl:find("()", 1, true) -- 0-indexed col right between the parens
  else
    table.insert(lines, string.format("public %s %s {", kind, class_name))
    table.insert(lines, "")
    table.insert(lines, "}")
    cursor_line = #lines - 1
    cursor_col = 0
  end
  return lines, cursor_line, cursor_col
end

---Prompt for class/interface/record/enum, then fill the given (empty) buffer.
---@param bufnr integer
---@param path string
function M.scaffold_buf(bufnr, path)
  local class_name, package_name = M.derive(path)
  vim.ui.select(KINDS, {
    prompt = "Scaffold " .. class_name .. " as:",
  }, function(kind)
    if not kind then
      return
    end
    local lines, cursor_line, cursor_col = M.lines(class_name, package_name, kind)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modified = true
    if vim.api.nvim_get_current_buf() == bufnr then
      vim.api.nvim_win_set_cursor(0, { cursor_line, cursor_col })
      vim.cmd(kind == "record" and "startinsert" or "startinsert!")
    end
  end)
end

---Prompt for class/interface/record/enum, then write straight to disk.
---For files created outside of a normal `:edit`-opened buffer (e.g.
---neo-tree's `a`), so there's nothing to fill in yet.
---@param path string
function M.scaffold_file(path)
  local class_name, package_name = M.derive(path)
  vim.ui.select(KINDS, {
    prompt = "Scaffold " .. class_name .. " as:",
  }, function(kind)
    if not kind then
      return
    end
    local lines = M.lines(class_name, package_name, kind)
    vim.fn.writefile(lines, path)
  end)
end

return M
