-- Organize imports for a whole directory or project (IntelliJ: Optimize Imports on a folder). jdt.ls handles the
-- command `java.edit.organizeImports` with a file, folder or project URI (OrganizeImportsCommand: organizeImportsInFile /
-- InDirectory / InProject). It applies the edit itself with workspace/applyEdit; we count the files in that edit, save the
-- buffers that were clean before, and say how many changed. Loaded on the first key press (zero startup cost).
-- Spec: specs/features/organize-imports-dir.md. Keys: `<leader>cI` (project, or the neo-tree node's folder), neo-tree `O`.
local M = {}

local TITLE = { title = "Organize imports" }
local COMMAND = "java.edit.organizeImports"

--- Files with at least one text edit in a WorkspaceEdit: list of uris.
function M.edited_uris(edit)
  local uris, seen = {}, {}
  local function add(uri) if uri and not seen[uri] then seen[uri] = true; uris[#uris + 1] = uri end end
  for uri, edits in pairs((edit or {}).changes or {}) do
    if #edits > 0 then add(uri) end
  end
  for _, dc in ipairs((edit or {}).documentChanges or {}) do
    if dc.textDocument and dc.edits and #dc.edits > 0 then add(dc.textDocument.uri) end
  end
  return uris
end

--- The folder to organize: the neo-tree node's folder (a file's folder) when the current window is neo-tree, else the
--- project root of the current file (nv4j.root), else the cwd.
function M.target(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype == "neo-tree" then
    local ok, node = pcall(function()
      return require("neo-tree.sources.manager").get_state("filesystem").tree:get_node()
    end)
    if ok and node and node.path then
      return node.type == "directory" and node.path or vim.fs.dirname(node.path), "folder"
    end
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name ~= "" and vim.bo[buf].buftype == "" then
    local root = require("nv4j.root").project(name)
    if root then return root, "project" end
  end
  return vim.fn.getcwd(), "project"
end

--- `.java` files under `dir` (no hidden, build or output folders).
local SKIP = { target = true, build = true, out = true, node_modules = true }
local function java_files(dir)
  local files = {}
  for name, kind in vim.fs.dir(dir, { depth = 40, skip = function(n) return n:sub(1, 1) == "." or SKIP[n] end }) do
    if kind == "file" and name:match("%.java$") then files[#files + 1] = dir .. "/" .. name end
  end
  table.sort(files)
  return files
end

--- Ask jdt.ls to organize imports under `dir`. done({ files = n, uris = {...}, saved = k, err = msg|nil }) once.
--- The project root is one request (jdt.ls: organizeImportsInProject). jdt.ls 1.63.0 answers an empty edit for a folder URI below
--- the project (OrganizeImportsCommand.organizeImports takes the workspace's getFileForLocation handle, which exists for any path two
--- or more segments deep, so a package folder is treated as a file), so a sub-folder is one request per `.java` file under it.
---@param dir string
---@param done fun(res: table)|nil
function M.run(dir, done)
  done = done or function() end
  dir = vim.fs.normalize(dir)
  local client = require("nv4j.root").client_for_path(dir)
  if not client then
    local msg = "no jdt.ls client for " .. dir .. " (open a Java file of the project first)"
    vim.notify(msg, vim.log.levels.WARN, TITLE)
    return done({ files = 0, uris = {}, saved = 0, err = msg })
  end
  local root = client.config and client.config.root_dir and vim.fs.normalize(client.config.root_dir)
  local targets = (root == dir) and { dir } or java_files(dir)
  local clean = {} -- uri -> true when its buffer was not modified before
  local counted, edits_seen = {}, {}
  local function note(uri, was_clean)
    if counted[uri] then return end
    counted[uri] = true
    edits_seen[#edits_seen + 1] = uri
    clean[uri] = was_clean
  end
  local had = rawget(client.handlers, "workspace/applyEdit")
  local orig = had or vim.lsp.handlers["workspace/applyEdit"]
  client.handlers["workspace/applyEdit"] = function(err, params, ctx, config)
    for _, uri in ipairs(M.edited_uris(params and params.edit)) do
      local b = vim.fn.bufnr(vim.uri_to_fname(uri))
      note(uri, b == -1 or not vim.bo[b].modified)
    end
    return orig(err, params, ctx, config)
  end
  local function finish(err)
    client.handlers["workspace/applyEdit"] = had
    local saved = 0
    for _, uri in ipairs(edits_seen) do
      local b = vim.fn.bufnr(vim.uri_to_fname(uri))
      if b ~= -1 and clean[uri] and vim.bo[b].modified then
        local ok = pcall(vim.api.nvim_buf_call, b, function() vim.cmd("silent noautocmd write") end)
        if ok then saved = saved + 1 end
      elseif b == -1 or (clean[uri] and not vim.bo[b].modified) then
        saved = saved + 1 -- written to disk by the server's edit already (no buffer) or nothing left unsaved
      end
    end
    local n = #edits_seen
    local where = vim.fn.fnamemodify(dir, ":~")
    local msg = n == 0 and ("Imports already organized under %s."):format(where)
      or ("Organized imports in %d file%s under %s%s."):format(n, n == 1 and "" or "s", where,
        saved < n and (" (%d not saved: they had unsaved changes)"):format(n - saved) or "")
    if err then
      msg = "Organize imports stopped: " .. err .. (n > 0 and (" (%d file(s) changed before that)"):format(n) or "")
      vim.notify(msg, vim.log.levels.ERROR, TITLE)
    else
      vim.notify(msg, vim.log.levels.INFO, TITLE)
    end
    done({ files = n, uris = edits_seen, saved = saved, err = err })
  end
  local i = 0
  local function step()
    i = i + 1
    local target = targets[i]
    if not target then return finish(nil) end
    client:request("workspace/executeCommand", { command = COMMAND, arguments = { vim.uri_from_fname(target) } }, function(err, res)
      if err then return finish(("jdt.ls refused %s: %s"):format(COMMAND, tostring(err.message or err))) end
      -- A server without applyEdit support returns the edit instead.
      if type(res) == "table" and (res.changes or res.documentChanges) then
        vim.lsp.util.apply_workspace_edit(res, client.offset_encoding)
        for _, uri in ipairs(M.edited_uris(res)) do note(uri, true) end
      end
      step()
    end)
  end
  step()
end

--- Key action: organize the target of the current window.
function M.here()
  M.run((M.target()))
end

return M
