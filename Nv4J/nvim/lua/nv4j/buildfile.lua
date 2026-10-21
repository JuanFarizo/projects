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

local function jdtls_errors(buf)
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR })) do
    local ns = vim.diagnostic.get_namespace(d.namespace)
    if ns and ns.name:find("jdtls", 1, true) then
      out[#out + 1] = ("L%d: %s"):format(d.lnum + 1, d.message:gsub("%s+", " "):sub(1, 200))
    end
  end
  return out
end

function M.on_changed(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if not BUILD_FILES[vim.fs.basename(name)] then return end
  local errs = jdtls_errors(buf)
  local text = table.concat(errs, "\n")
  local prev = last[name] or ""
  if text == prev then return end
  last[name] = text
  local short = vim.fn.fnamemodify(name, ":~:.")
  if text ~= "" then
    vim.notify(("%s: %d build error(s), the project classpath may be stale\n%s"):format(short, #errs, text),
      vim.log.levels.ERROR, { title = "Build file" })
  else
    vim.notify(short .. ": build errors fixed", vim.log.levels.INFO, { title = "Build file" })
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = vim.api.nvim_create_augroup("nv4j_buildfile", { clear = true }),
    callback = function(args) M.on_changed(args.buf) end,
  })
end

return M
