-- Variables in `.nv4j` run defaults (`run.vm_args`, `run.env`), pure. Spec: specs/features/run-defaults.md "Variables".
-- IntelliJ's JavaParametersUtil.configureConfiguration replaces `$KEY$` in the VM parameters with the run's env values and expands
-- macros (`$PROJECT_DIR$`, `$MODULE_DIR$`, `$USER_HOME$`) through ProgramParametersUtil.expandPath; Nv4J also accepts `${NAME}`.
--  dollar_form    : `$NAME$` in vm_args takes the value from the run's env (file env), then the process environment.
--  brace_form     : `${NAME}` the same.
--  builtin        : `$PROJECT_DIR$`, `$MODULE_DIR$` = project root, `$USER_HOME$` = HOME (vm_args and env values).
--  env_values     : env values expand against built-ins and the process environment.
--  unknown_literal: an unknown name stays as written, ONE warning (title Nv4J) per file and name (two names here, so two), even on a second apply().
--  non_env_text   : `${spring.profiles.active}`, `$$`, `$5` are left alone with no warning.
--  opts_win       : vm_args / env passed by the caller are not expanded and still win.
--  control_shape  : plain args without variables come back unchanged.
local lsp = require("lsp")
local P = "112_run_vars."
local S = require("nv4j.settings")

local TMP = "/tmp/nv4j/d112-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
TMP = vim.uv.fs_realpath(TMP)
local function project(name, json)
  local d = TMP .. "/" .. name
  vim.fn.mkdir(d, "p")
  vim.fn.writefile({ vim.json.encode(json) }, d .. "/.nv4j")
  return d
end

local notes = {}
local orig_notify = vim.notify
vim.notify = function(msg, level, o) notes[#notes + 1] = { msg = tostring(msg), level = level, title = o and o.title } end

vim.env.NV4J_T112_PROC = "from-process"
vim.env.NV4J_T112_UNSET = nil

local d1 = project("a", { run = {
  env = { DATA = "/data", ROOT_REF = "$PROJECT_DIR$/x", PROC = "${NV4J_T112_PROC}-env" },
  vm_args = { "-Dd=$DATA$/out", "-Db=${DATA}/out", "-Dp=$NV4J_T112_PROC$", "-Dq=${NV4J_T112_PROC}", "-Dr=$PROJECT_DIR$/cfg",
    "-Dm=${MODULE_DIR}", "-Dh=$USER_HOME$", "-Xmx512m" } } })
local r = S.apply({}, d1)
local vm = r.vm_args or {}
lsp.report(P .. "dollar_form", vm[1] == "-Dd=/data/out" and vm[3] == "-Dp=from-process", vim.inspect(vm))
lsp.report(P .. "brace_form", vm[2] == "-Db=/data/out" and vm[4] == "-Dq=from-process", vim.inspect(vm))
lsp.report(P .. "builtin", vm[5] == "-Dr=" .. d1 .. "/cfg" and vm[6] == "-Dm=" .. d1 and vm[7] == "-Dh=" .. vim.env.HOME,
  vim.inspect(vm))
lsp.report(P .. "env_values", r.env.ROOT_REF == d1 .. "/x" and r.env.PROC == "from-process-env" and r.env.DATA == "/data",
  vim.inspect(r.env))
lsp.report(P .. "control_shape", vm[8] == "-Xmx512m", tostring(vm[8]))

local d2 = project("b", { run = { vm_args = { "-Da=$NV4J_T112_UNSET$", "-Db=${NV4J_T112_UNSET}", "-Dc=$NV4J_T112_UNSET$" },
  env = { E = "$NV4J_T112_NOPE$" } } })
notes = {}
local r2 = S.apply({}, d2)
S.apply({}, d2) -- second run: no second warning
local warns = vim.tbl_filter(function(n) return n.level == vim.log.levels.WARN and n.title == "Nv4J" end, notes)
local names = {}
for _, n in ipairs(warns) do names[#names + 1] = n.msg:match("variable (%S+)") end
lsp.report(P .. "unknown_literal",
  r2.vm_args[1] == "-Da=$NV4J_T112_UNSET$" and r2.vm_args[2] == "-Db=${NV4J_T112_UNSET}" and r2.env.E == "$NV4J_T112_NOPE$"
    and #warns == 2, ("vm_args %s env %s warnings %d (%s)"):format(vim.inspect(r2.vm_args), vim.inspect(r2.env), #warns, table.concat(names, " ")))

local d3 = project("c", { run = { vm_args = { "-Dx=${spring.profiles.active}", "-Dy=$$", "-Dz=$5", "-Dw=a$b" } } })
notes = {}
local r3 = S.apply({}, d3)
lsp.report(P .. "non_env_text", vim.deep_equal(r3.vm_args, { "-Dx=${spring.profiles.active}", "-Dy=$$", "-Dz=$5", "-Dw=a$b" })
  and #notes == 0, vim.inspect(r3.vm_args) .. " notes " .. #notes)

local r4 = S.apply({ vm_args = { "-Dc=$DATA$" }, env = { DATA = "caller" } }, d1)
lsp.report(P .. "opts_win", r4.vm_args[1] == "-Dc=$DATA$" and r4.env.DATA == "caller" and r4.env.PROC == "from-process-env",
  vim.inspect(r4))

vim.notify = orig_notify
vim.fn.delete(TMP, "rf")
lsp.finish()
