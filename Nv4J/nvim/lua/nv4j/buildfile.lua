-- Build file errors made visible. jdt.ls reports a broken pom.xml (unparseable, missing artifact,
-- bad parent) as diagnostics on pom.xml itself, a file the user usually does not have open, so the
-- Java side just shows unresolved types with no hint why. IntelliJ shows a Maven sync failure in a
-- notification; here: one vim.notify per distinct set of jdt.ls errors on a build file, and one
-- when they are gone. Spec: specs/features/diagnostics-imports-actions.md.
local M = {}

local BUILD_FILES = {
  ["pom.xml"] = true,
  ["build.gradle"] = true,
  ["build.gradle.kts"] = true,
  ["settings.gradle"] = true,
  ["settings.gradle.kts"] = true,
}
local last = {} -- file name -> last notified error text
local wiping = {} -- buf -> true while it is being wiped (its diagnostics are cleared, not fixed)
local failed = {} -- project folder -> true while jdt.ls reports that its build could not be imported

local function jdtls_errors(buf)
  local out, raw = {}, {}
  for _, d in ipairs(vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR })) do
    local ns = vim.diagnostic.get_namespace(d.namespace)
    if ns and ns.name:find("jdtls", 1, true) then
      out[#out + 1] = ("L%d: %s"):format(d.lnum + 1, d.message:gsub("%s+", " "):sub(1, 200))
      raw[#raw + 1] = d
    end
  end
  return out, raw
end

-- a build file, or (folder = true) a project folder holding jdt.ls diagnostics
local function watched(name)
  if BUILD_FILES[vim.fs.basename(name)] then return true, false end
  if name ~= "" and vim.fn.isdirectory(name) == 1 then return true, true end
  return false
end

-- A build that cannot be configured at all (Gradle: a syntax error in build.gradle, G6 in specs/006) is reported
-- by jdt.ls on the project FOLDER's URI, not on the build file: "The supplied phased action failed ... Could not
-- compile build file '<path>' ... @ line 3". Neovim keeps it on a buffer named after the folder. Name the build
-- file from the message when it is there.
-- Only those count: jdt.ls also puts transient project-level errors on the folder while it rebuilds ("The project was
-- not built since its build path is incomplete", ten of them during one 62_refactor run): reacting to those meant an
-- ERROR notification per refactor and cost 62_refactor.rename_package_fallback about 1 s (T6 follow-up).
local function build_file_of(d) return d.message:match("build file '([^']+)'") end

function M.on_changed(buf)
  if wiping[buf] or not vim.api.nvim_buf_is_valid(buf) then return end
  local name = vim.api.nvim_buf_get_name(buf)
  local watch, folder = watched(name)
  if not watch then return end
  local errs, raw = jdtls_errors(buf)
  if folder then -- keep only "could not configure the build" errors (they name the build file)
    local e2, r2 = {}, {}
    for i, d in ipairs(raw) do
      if build_file_of(d) then e2[#e2 + 1], r2[#r2 + 1] = errs[i], d end
    end
    errs, raw = e2, r2
  end
  local text = table.concat(errs, "\n")
  local prev = last[name] or ""
  if text == prev then return end
  last[name] = text
  local short = vim.fn.fnamemodify(name, ":~:.")
  if folder then failed[name] = text ~= "" or nil end
  if text == "" then
    vim.notify(short .. ": build errors fixed", vim.log.levels.INFO, { title = "Build file" })
  elseif folder then
    local lines = {}
    for _, d in ipairs(raw) do
      local m = d.message:gsub("^The supplied phased action failed with an exception%.%s*", ""):gsub("%s+", " ")
      lines[#lines + 1] = m:sub(1, 400)
    end
    vim.notify(("%s: build file has errors, the project could not be imported (Java features of this project stay off until it is fixed)\n%s")
      :format(vim.fn.fnamemodify(build_file_of(raw[1]), ":~:."), table.concat(lines, "\n")), vim.log.levels.ERROR, { title = "Build file" })
  else
    vim.notify(("%s: %d build error(s), the project classpath may be stale\n%s"):format(short, #errs, text),
      vim.log.levels.ERROR, { title = "Build file" })
  end
end

-- A project whose import failed is not a jdt.ls project, so jdt.ls does not watch its build file: fixing and saving
-- it changed nothing (measured, 71_gradle_broken fixed_live). On a save of a build file inside such a folder, ask the
-- jdt.ls of that folder to import again (java.project.import, a jdt.ls delegate command). Returns the clients asked.
function M.reimport(path)
  local asked = {}
  path = vim.uv.fs_realpath(path) or path
  for dir in pairs(failed) do
    if path:sub(1, #dir + 1) == dir .. "/" then
      for _, c in ipairs(vim.lsp.get_clients({ name = "jdtls" })) do
        local r = c.config and c.config.root_dir
        r = r and (vim.uv.fs_realpath(r) or r)
        if r and (dir == r or dir:sub(1, #r + 1) == r .. "/") and not vim.tbl_contains(asked, c) then
          c:request("workspace/executeCommand", { command = "java.project.import", arguments = {} }, function() end)
          asked[#asked + 1] = c
        end
      end
    end
  end
  if #asked > 0 then
    vim.notify(vim.fn.fnamemodify(path, ":~:.") .. ": saved, importing the project again", vim.log.levels.INFO, { title = "Build file" })
  end
  return asked
end

function M.setup()
  local g = vim.api.nvim_create_augroup("nv4j_buildfile", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = g,
    pattern = { "*/build.gradle", "*/build.gradle.kts", "*/settings.gradle", "*/settings.gradle.kts", "*/pom.xml" },
    callback = function(args) M.reimport(vim.api.nvim_buf_get_name(args.buf)) end,
  })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = g,
    callback = function(args) M.on_changed(args.buf) end,
  })
  -- Forget a wiped build file: no stale entry, and no "fixed" notice for the cleared diagnostics.
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = g,
    callback = function(args)
      local name = vim.api.nvim_buf_get_name(args.buf)
      if not watched(name) then return end
      wiping[args.buf] = true
      last[name] = nil
      vim.schedule(function() wiping[args.buf] = nil end)
    end,
  })
end

return M
