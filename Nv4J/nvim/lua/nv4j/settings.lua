-- Per-project settings in `.nv4j` (D25 marker). Empty file is still only a root marker.
-- Optional JSON: { "run": { "profile": "dev", "env": { "FOO": "bar" }, "vm_args": ["-Xmx512m"] } }
-- Also `"spring_boot": true` (or a module directory, e.g. "app"): marks the project as Spring Boot when detection cannot
-- see it (a plugin from a jar or repository), read by nv4j.root boot_override.
-- <leader>rs / <leader>rd read these; <leader>rp still asks and does not write the file.
-- M.set (used by `:Nv4JFormatter --project`) is the only writer besides mark(). Caller's opts win. Bad JSON: one warning, file stays a marker. Spec: specs/features/run-defaults.md.
local M = {}

local TITLE = { title = "Nv4J" }
local warned = {} -- path -> true, bad JSON once per file

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function marker_path(root)
  if not root or root == "" then return nil end
  return vim.fs.normalize(root) .. "/" .. require("nv4j.root").project_marker
end

--- Decode `.nv4j` at `root`. Empty or missing: {}. Bad JSON: {} and one WARN.
function M.load(root)
  local path = marker_path(root)
  if not path then return {} end
  local raw = read(path)
  if raw == nil then return {} end
  local trimmed = raw:match("^%s*(.-)%s*$") or ""
  if trimmed == "" then return {} end
  local ok, data = pcall(vim.json.decode, trimmed)
  if not ok or type(data) ~= "table" then
    if not warned[path] then
      warned[path] = true
      vim.notify(("Could not read %s (not JSON). Using it as a project marker only."):format(path),
        vim.log.levels.WARN, TITLE)
    end
    return {}
  end
  return data
end

--- Set one top-level key in `.nv4j` at `root`, keeping every other field (pretty JSON, keys sorted). A missing file is only
--- created when `create` is true (the caller asks the user first). A file that is not a JSON object is never overwritten.
---@return string|nil path, string|nil err one-line reason
function M.set(root, key, value, create)
  local path = marker_path(root)
  if not path then return nil, "no project root" end
  local raw = read(path)
  local data = {}
  if raw == nil then
    if not create then return nil, path .. " does not exist" end
  else
    local trimmed = raw:match("^%s*(.-)%s*$") or ""
    if trimmed ~= "" then
      local ok, d = pcall(vim.json.decode, trimmed)
      if not ok or type(d) ~= "table" or vim.islist(d) then return nil, path .. " is not a JSON object; not modified" end
      data = d
    end
  end
  data[key] = value
  local f, err = io.open(path, "w")
  if not f then return nil, "cannot write " .. path .. ": " .. tostring(err) end
  f:write(vim.json.encode(data, { indent = "  ", sort_keys = true }), "\n")
  f:close()
  return path, nil
end

--- Fill omitted run fields from `.nv4j`. `opts` keys win. Never writes the file.
---@param opts { profile: string|nil, env: table|nil, vm_args: string[]|nil }|nil
---@return { profile: string|nil, env: table, vm_args: string[]|nil }
function M.apply(opts, root)
  opts = vim.deepcopy(opts or {})
  local run = M.load(root).run
  if type(run) ~= "table" then run = {} end
  if (not opts.profile or opts.profile == "") and type(run.profile) == "string" and run.profile ~= "" then
    opts.profile = run.profile
  end
  local file_env = {}
  if type(run.env) == "table" then
    for k, v in pairs(run.env) do
      if type(k) == "string" and type(v) == "string" then file_env[k] = v end
    end
  end
  opts.env = vim.tbl_extend("force", file_env, opts.env or {})
  if opts.vm_args == nil and type(run.vm_args) == "table" then
    local vm = {}
    for _, a in ipairs(run.vm_args) do
      if type(a) == "string" and a ~= "" then vm[#vm + 1] = a end
    end
    if #vm > 0 then opts.vm_args = vm end
  end
  return opts
end

--- Write an empty `.nv4j` in `dir` (cwd if omitted: the folder Neovim was opened at). Does not overwrite.
---@return string|nil path, string|nil err
function M.mark(dir)
  if not dir or dir == "" then
    dir = vim.fn.getcwd()
  end
  dir = vim.fs.normalize(dir)
  local root = require("nv4j.root")
  if root.home_or_above(dir) then
    return nil, "refused: that folder is home or above"
  end
  local path = dir .. "/" .. root.project_marker
  if vim.uv.fs_stat(path) then return path, "already exists" end
  vim.fn.mkdir(dir, "p")
  local f, err = io.open(path, "w")
  if not f then return nil, err end
  f:write("")
  f:close()
  return path, nil
end

vim.api.nvim_create_user_command("Nv4jMark", function()
  local path, err = M.mark()
  if err == "already exists" then
    vim.notify(".nv4j already exists at " .. path, vim.log.levels.INFO, TITLE)
  elseif err then
    vim.notify("Could not create .nv4j: " .. err, vim.log.levels.WARN, TITLE)
  else
    vim.notify("Created " .. path .. " (restart Neovim so jdt.ls uses this root)", vim.log.levels.INFO, TITLE)
  end
end, { desc = "Create a .nv4j project marker in the current working directory" })

return M
