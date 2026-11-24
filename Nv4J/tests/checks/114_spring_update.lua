-- :Nv4JSpringUpdate (specs/features/spring-language-server.md "Updating the server"): pure, no network, no real file touched
-- (installs go to /tmp/nv4j/d114-<pid> through NV4J_SPRING_HOME, the lookup cache to the same tree; vim.system untouched:
-- the module's runner is replaced by a fake that answers from the recorded OpenVSX fixture tests/fixtures/spring-update/).
--  zero_startup    : nv4j.springupdate is not loaded when the config has started, and spring.lua's version/jar lookups and
--                    the health report neither load it for a network call nor spawn a process (vim.system/jobstart counted).
--  parse_order     : 2.4.0 < 2.4.1 < 2.5.2026111900 < 2.10.0 (numeric, not string), equal = 0, aliases and junk = nil.
--  api_versions    : the recorded API answer: aliases dropped, newest first, newest() = 2.5.2026111900, 207-version list sorted.
--  stable_choice   : stable_from picks 2.4.1 only after its `preRelease` flag is known false; asks for it first (never guesses);
--                    a version flagged pre-release is skipped for the next one.
--  channel         : latest / prerelease / exact / empty falls back to vim.g.nv4j_spring_version / junk = nil.
--  cmdlines        : curl has -f, -L, both timeouts, the exact vsix and sha URLs; unzip has -d.
--  pin_resolution  : managed_version(): env override > pinned g that is installed > current file; a pin that is not
--                    installed and a "../x" name are ignored; jars() / ls_jar() follow it.
--  install_flow    : fake run: download, checksum fetch, sha256sum, unzip in that order, `<v>.part` renamed to `<v>`, the vsix and
--                    the part dir gone, `current` untouched.
--  install_bad_sha / install_bad_zip / install_unusable / install_download_fail : each failure leaves no `<v>`, no `.part`,
--                    no vsix, the old install and `current` as they were, and exactly one ERROR message.
--  failure_messages: unreachable (curl 6), timeout (28), not JSON, curl missing (127): one ERROR each, saying nothing changed.
--  cmd_latest / cmd_prerelease / cmd_exact : the command installs and switches `current` to 2.4.1 / 2.5.2026111900 / the exact
--                    version, prints old -> new and tells the user to restart; exact makes no API call.
--  cmd_check       : --check changes nothing, writes the lookup cache; health shows it (and says unknown without it).
--  cmd_same        : the version in use again = a message, no download.
--  cmd_verify_fail / cmd_verify_ok : --verify runs the script, a failing script leaves `current` alone and says FAILED
--                    with the FAIL lines; a passing one switches. Without the script file the command refuses.
--  rollback_back   : `:Nv4JSpringUpdate mason` removes `current` (installs stay), and switching to an installed version
--                    again needs no download.
local lsp = require("lsp")
local P = "114_spring_update."
local function rep(name, ok, detail) lsp.report(P .. name, ok and true or false, detail) end

rep("zero_startup", package.loaded["nv4j.springupdate"] == nil, "loaded at startup: " .. tostring(package.loaded["nv4j.springupdate"] ~= nil))

local TMP = "/tmp/nv4j/d114-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
local HERE = debug.getinfo(1, "S").source:sub(2):match("^(.*)/checks/")
local FIX = HERE .. "/fixtures/spring-update"
local function read(p) local f = assert(io.open(p)) local s = f:read("*a") f:close() return s end
local API, V241, VPRE = read(FIX .. "/api.json"), read(FIX .. "/v-2.4.1.json"), read(FIX .. "/v-pre-release.json")

-- ── zero cost: version and jar lookups, and the health report, spawn nothing and do not load the module ──
local spawned = 0
local sys, jobstart = vim.system, vim.fn.jobstart
vim.system = function(...) spawned = spawned + 1 return sys(...) end
vim.fn.jobstart = function(...) spawned = spawned + 1 return jobstart(...) end
vim.env.NV4J_SPRING_HOME = TMP .. "/home"
local SP = require("nv4j.spring")
SP.installed_version() SP.ls_jar() SP.managed_version()
rep("zero_startup_spring", package.loaded["nv4j.springupdate"] == nil and spawned == 0,
  ("springupdate loaded after spring.lua lookups: %s, spawned %d"):format(tostring(package.loaded["nv4j.springupdate"] ~= nil), spawned))
vim.system, vim.fn.jobstart = sys, jobstart

local U = require("nv4j.springupdate")
U.state_file = function() return TMP .. "/state/lookup.json" end

-- ── pure ──
local c = U.compare
rep("parse_order", c("2.4.0", "2.4.1") == -1 and c("2.4.1", "2.5.2026111900") == -1 and c("2.5.2026111900", "2.10.0") == -1
  and c("2.10.0", "2.9.9") == 1 and c("2.4.1", "2.4.1") == 0 and c("2.4", "2.4.0") == 0 and U.parse("latest") == nil and U.parse("2.x") == nil
  and c("latest", "2.4.1") == nil,
  ("2.4.0<2.4.1 %s, 2.5.x<2.10.0 %s, 2.10.0>2.9.9 %s, equal %s, alias nil %s"):format(tostring(c("2.4.0", "2.4.1")),
    tostring(c("2.5.2026111900", "2.10.0")), tostring(c("2.10.0", "2.9.9")), tostring(c("2.4.1", "2.4.1")), tostring(U.parse("latest"))))

local api = vim.json.decode(API)
local vs = U.versions(api)
local sorted = true
for i = 2, #vs do if U.compare(vs[i - 1], vs[i]) ~= 1 then sorted = false end end
rep("api_versions", #vs >= 90 and sorted and vs[1] == "2.5.2026111900" and U.newest(api) == "2.5.2026111900" and vim.tbl_contains(vs, "2.4.1")
  and not vim.tbl_contains(vs, "latest") and not vim.tbl_contains(vs, "pre-release"),
  ("%d versions, first %s, newest %s, sorted %s"):format(#vs, tostring(vs[1]), tostring(U.newest(api)), tostring(sorted)))

local s0, ask0 = U.stable_from(api, function() return nil end)
local s1 = U.stable_from(api, function(v) if v == "2.4.1" then return vim.json.decode(V241).preRelease end end)
local s2 = U.stable_from(api, function(v) if v == "2.4.1" then return true end if v == "2.4.0" then return false end end)
rep("stable_choice", s0 == nil and ask0 == "2.4.1" and s1 == "2.4.1" and s2 == "2.4.0" and vim.json.decode(VPRE).preRelease == true,
  ("unknown flag -> %s asks %s; flag false -> %s; 2.4.1 flagged pre-release -> %s"):format(tostring(s0), tostring(ask0), tostring(s1), tostring(s2)))

local k1, e1 = U.channel("2.4.1")
local k2 = U.channel("")
local k3 = U.channel(nil, "prerelease")
local k4, e4 = U.channel(nil, "2.3.0")
rep("channel", k1 == "exact" and e1 == "2.4.1" and k2 == "latest" and U.channel("latest") == "latest" and U.channel("prerelease") == "prerelease"
  and k3 == "prerelease" and k4 == "exact" and e4 == "2.3.0" and U.channel("banana") == nil,
  ("exact %s/%s, empty %s, g=prerelease %s, g=2.3.0 %s/%s, banana %s"):format(k1, tostring(e1), k2, k3, k4, tostring(e4), tostring(U.channel("banana"))))

local cu = U.curl_cmd(U.api_url())
local cd = U.curl_cmd(U.vsix_url("2.5.2026111900"), "/tmp/x.vsix")
local cl = table.concat(cd, " ")
rep("cmdlines", cu[1] == "curl" and vim.tbl_contains(cu, "--max-time") and cu[#cu] == "https://open-vsx.org/api/VMware/vscode-spring-boot"
  and cl:find("-fsSL", 1, true) and cl:find("--connect-timeout 10", 1, true) and cl:find("-o /tmp/x.vsix", 1, true)
  and cd[#cd] == "https://open-vsx.org/api/VMware/vscode-spring-boot/2.5.2026111900/file/VMware.vscode-spring-boot-2.5.2026111900.vsix"
  and U.sha_url("2.4.1"):match("VMware%.vscode%-spring%-boot%-2%.4%.1%.sha256$") and table.concat(U.unzip_cmd("a.vsix", "d"), " ") == "unzip -q -o a.vsix -d d",
  cl)

-- ── a fake extension tree, a fake runner, a recording notifier ──
local HOME = TMP .. "/home"
local function mkext(dir, version, opts)
  opts = opts or {}
  vim.fn.mkdir(dir .. "/extension/language-server", "p")
  vim.fn.mkdir(dir .. "/extension/jars", "p")
  if not opts.nojar then io.open(dir .. "/extension/language-server/spring-boot-language-server-" .. version .. "-exec.jar", "w"):close() end
  local jars = { "a.jar", "b.jar" }
  for _, j in ipairs(jars) do if not (opts.missing and j == "b.jar") then io.open(dir .. "/extension/jars/" .. j, "w"):close() end end
  local f = io.open(dir .. "/extension/package.json", "w")
  f:write(vim.json.encode({ version = version, contributes = { javaExtensions = { "./jars/a.jar", "./jars/b.jar" } } }))
  f:close()
end
local msgs, calls = {}, {}
U.notify = function(m, l) msgs[#msgs + 1] = { m, l or vim.log.levels.INFO } end
local function errors() local n = 0 for _, m in ipairs(msgs) do if m[2] == vim.log.levels.ERROR then n = n + 1 end end return n end
local function last() return msgs[#msgs] and msgs[#msgs][1] or "" end
local script = {} -- overrides per scenario
--- Answers the module's process calls from the fixtures; records argv strings.
U.run = function(argv, cb)
  local line = table.concat(argv, " ")
  calls[#calls + 1] = line
  local code, out, err = 0, "", ""
  if script.fail and line:find(script.fail.match, 1, true) then
    code, out, err = script.fail.code, script.fail.out or "", script.fail.err or ""
  elseif argv[1] == "curl" then
    local url = argv[#argv]
    if url == U.API and script.window then
      -- OpenVSX's `allVersions` holds only the newest 100: 100 pre-releases, no stable among them
      local d = vim.json.decode(API)
      for k in pairs(d.allVersions) do if U.parse(k) and not U.looks_prerelease(k) then d.allVersions[k] = nil end end
      out = vim.json.encode(d)
    elseif url == U.API then out = API
    elseif url == U.API .. "/2.4.1" then out = V241
    elseif url:match("%.sha256$") then out = ("%s  VMware.vsix\n"):format(string.rep("a", 64))
    elseif url:find("/versions?size=100&offset=", 1, true) then out = vim.json.encode({ versions = vim.json.decode(API).allVersions })
    elseif url:match("%.vsix$") then local f = io.open(argv[#argv - 1], "w") f:write("fake") f:close()
    else code, err = 22, "404" end
  elseif argv[1] == "sha256sum" then out = string.rep(script.badsha and "b" or "a", 64) .. "  " .. argv[2] .. "\n"
  elseif argv[1] == "unzip" then
    local v = argv[#argv]:match("/([^/]+)%.part$")
    if script.badzip then code, err = 9, "bad zip" else mkext(argv[#argv], v, script.ext) end
  elseif argv[1]:match("verify_spring%.sh$") then code, out = script.verify_code or 0, script.verify_out or ""
  end
  vim.schedule(function() cb(code, out, err) end)
end
local function reset() msgs, calls, script = {}, {}, {} end
local function wait_for(f) vim.wait(5000, f, 20) return f() end
local function exists(p) return vim.uv.fs_stat(p) ~= nil end
local function cur() local f = io.open(HOME .. "/current") if not f then return nil end local v = vim.trim(f:read("*a")) f:close() return v end
local function ls() return vim.fn.glob(HOME .. "/*", false, true) end

-- an old install and its pointer, shared by the failure cases
mkext(HOME .. "/2.4.0", "2.4.0")
U.activate("2.4.0")
local function untouched() return cur() == "2.4.0" and exists(HOME .. "/2.4.0/extension") end

-- ── pin resolution ──
mkext(HOME .. "/2.4.9", "2.4.9")
local v_cur = SP.managed_version()
vim.g.nv4j_spring_version = "2.4.9"
local v_pin = SP.managed_version()
vim.g.nv4j_spring_version = "2.7.7" -- not installed
local v_miss = SP.managed_version()
vim.g.nv4j_spring_version = "../2.4.9"
local v_trav = SP.managed_version()
vim.g.nv4j_spring_version = nil
vim.env.NV4J_SPRING_LS_VERSION = "2.4.9"
local v_env = SP.managed_version()
local jar_env = SP.ls_jar()
local jars_n = #SP.jars()
vim.env.NV4J_SPRING_LS_VERSION = "9.9.9"
local v_envbad = SP.managed_version()
vim.env.NV4J_SPRING_LS_VERSION = nil
rep("pin_resolution", v_cur == "2.4.0" and v_pin == "2.4.9" and v_miss == "2.4.0" and v_trav == "2.4.0" and v_env == "2.4.9" and v_envbad == nil
  and jar_env and jar_env:find("2.4.9-exec.jar", 1, true) and jars_n == 2,
  ("current %s, pinned %s, pin not installed %s, traversal %s, env %s, env not installed %s, jar %s, bundles %d"):format(tostring(v_cur), tostring(v_pin),
    tostring(v_miss), tostring(v_trav), tostring(v_env), tostring(v_envbad), tostring(jar_env), jars_n))
vim.fn.delete(HOME .. "/2.4.9", "rf")

-- ── install: success order and failures ──
reset()
local done, okres
U.install("2.4.2", function(ok) done, okres = true, ok end)
wait_for(function() return done end)
local order = {}
for _, l in ipairs(calls) do order[#order + 1] = l:match("^(%S+)") .. (l:match("%.sha256$") and ":sha" or l:match("%.vsix$") and ":vsix" or "") end
rep("install_flow", okres == true and table.concat(order, ",") == "curl:vsix,curl:sha,sha256sum:vsix,unzip" and exists(HOME .. "/2.4.2/extension/package.json")
  and not exists(HOME .. "/2.4.2.part") and not exists(HOME .. "/2.4.2.vsix") and untouched() and errors() == 0,
  ("ok=%s order=%s dest=%s part=%s vsix=%s current=%s errors=%d"):format(tostring(okres), table.concat(order, ","), tostring(exists(HOME .. "/2.4.2/extension/package.json")),
    tostring(exists(HOME .. "/2.4.2.part")), tostring(exists(HOME .. "/2.4.2.vsix")), tostring(cur()), errors()))

local function failing(name, v, setup, want)
  reset()
  setup()
  local d, o
  U.install(v, function(ok) d, o = true, ok end)
  wait_for(function() return d end)
  local clean = not exists(HOME .. "/" .. v) and not exists(HOME .. "/" .. v .. ".part") and not exists(HOME .. "/" .. v .. ".vsix")
  rep(name, d and o == false and clean and untouched() and errors() == 1 and last():find(want, 1, true) and last():find("Nothing was changed", 1, true),
    ("done=%s ok=%s clean=%s old kept=%s errors=%d msg=%s"):format(tostring(d), tostring(o), tostring(clean), tostring(untouched()), errors(), last()))
end
failing("install_bad_sha", "2.6.0", function() script.badsha = true end, "SHA-256")
failing("install_bad_zip", "2.6.1", function() script.badzip = true end, "unzip of 2.6.1")
failing("install_unusable", "2.6.2", function() script.ext = { nojar = true } end, "no language-server/*-exec.jar")
failing("install_missing_bundle", "2.6.3", function() script.ext = { missing = true } end, "missing bundle ./jars/b.jar")
failing("install_download_fail", "2.6.4", function() script.fail = { match = ".vsix", code = 22, err = "The requested URL returned error: 404" } end, "download of 2.6.4")

-- ── failure messages through the command (lookup) ──
local function cmd_fail(code, out, err, want)
  reset()
  script.fail = { match = U.API, code = code, out = out, err = err }
  U.run_command({ "latest" })
  wait_for(function() return errors() > 0 end)
  vim.wait(100)
  return errors() == 1 and last():find(want, 1, true) and last():find("Nothing was changed", 1, true) and untouched() and #calls == 1, last()
end
local f1, m1 = cmd_fail(6, "", "Could not resolve host", "exit 6")
local f2, m2 = cmd_fail(28, "", "", "timed out")
local f3, m3 = cmd_fail(0, "<html>oops</html>", "", "not JSON")
local f4, m4 = cmd_fail(127, "", "", "curl, unzip or sha256sum is not installed")
rep("failure_messages", f1 and f2 and f3 and f4, ("unreachable %s | timeout %s | json %s | missing %s"):format(m1, m2, m3, m4))

-- ── the command ──
local function run_cmd(args, want_msgs)
  reset()
  U.run_command(args)
  wait_for(function() return #msgs >= (want_msgs or 3) end)
  vim.wait(150)
end
run_cmd({ "latest" }, 3)
rep("cmd_latest", cur() == "2.4.1" and exists(HOME .. "/2.4.1/extension") and errors() == 0 and last():find("2.4.0 -> 2.4.1", 1, true) and last():find("Restart Neovim", 1, true)
  and vim.tbl_contains(calls, "curl -fsSL --connect-timeout 10 --max-time 30 https://open-vsx.org/api/VMware/vscode-spring-boot/2.4.1"),
  ("current %s, last %s, calls %s"):format(tostring(cur()), last(), table.concat(calls, " | "):sub(1, 400)))
-- 2.4.1 is already installed: "latest" again is the same-version case
run_cmd({ "latest" }, 2)
local dl = 0 for _, l in ipairs(calls) do if l:find(".vsix", 1, true) then dl = dl + 1 end end
rep("cmd_same", dl == 0 and last():find("already the one in use", 1, true) and cur() == "2.4.1", ("downloads %d, last %s"):format(dl, last()))

-- the newest 100 versions (the API's window) hold no stable one: the command asks `versions?size=100&offset=100`, then the flag of 2.4.1
local fresh = HOME .. "/2.4.1"
U.activate("2.4.0")
vim.fn.delete(fresh, "rf")
reset()
script.window = true
U.run_command({ "latest" })
wait_for(function() return cur() == "2.4.1" end)
local widened = vim.tbl_contains(calls, "curl -fsSL --connect-timeout 10 --max-time 30 https://open-vsx.org/api/VMware/vscode-spring-boot/versions?size=100&offset=100")
rep("cmd_window", widened and cur() == "2.4.1" and errors() == 0, ("widened %s, current %s, calls %d"):format(tostring(widened), tostring(cur()), #calls))
U.activate("2.4.1")

run_cmd({ "prerelease" }, 4)
rep("cmd_prerelease", cur() == "2.5.2026111900" and exists(HOME .. "/2.5.2026111900/extension") and last():find("2.4.1 -> 2.5.2026111900", 1, true)
  and msgs[2] and msgs[2][2] == vim.log.levels.WARN and msgs[2][1]:find("pre-release", 1, true) and msgs[2][1]:find("--verify", 1, true),
  ("current %s, msgs %d, second %s"):format(tostring(cur()), #msgs, msgs[2] and msgs[2][1] or "nil"))

run_cmd({ "2.3.0" }, 2)
local api_calls = 0 for _, l in ipairs(calls) do if l:find("curl", 1, true) and l:find("/file/", 1, true) == nil and l:find("vscode%-spring%-boot$") then api_calls = api_calls + 1 end end
rep("cmd_exact", cur() == "2.3.0" and api_calls == 0 and last():find("2.5.2026111900 -> 2.3.0", 1, true), ("current %s, api calls %d, last %s"):format(tostring(cur()), api_calls, last()))

-- --check: nothing installed or switched, cache written, health reads it
local before = cur()
run_cmd({ "--check" }, 1)
local cache = U.cached()
local out, saved = {}, {}
for _, lv in ipairs({ "start", "ok", "warn", "error", "info" }) do saved[lv] = vim.health[lv] vim.health[lv] = function(m) out[#out + 1] = m end end
local H = require("nv4j.health")
pcall(H.check)
for lv, f in pairs(saved) do vim.health[lv] = f end
local htxt = table.concat(out, "\n")
vim.fn.delete(U.state_file())
out = {}
for _, lv in ipairs({ "start", "ok", "warn", "error", "info" }) do saved[lv] = vim.health[lv] vim.health[lv] = function(m) out[#out + 1] = m end end
pcall(H.check)
for lv, f in pairs(saved) do vim.health[lv] = f end
local htxt0 = table.concat(out, "\n")
rep("cmd_check", cur() == before and cache and cache.stable == "2.4.1" and cache.prerelease == "2.5.2026111900" and last():find("newest stable 2.4.1", 1, true)
  and htxt:find("stable 2.4.1, pre-release 2.5.2026111900", 1, true) and htxt:find("Spring LS version: 2.3.0", 1, true) and htxt0:find("Spring LS newest: unknown", 1, true),
  ("current %s->%s, cache %s, health %s | without cache %s"):format(tostring(before), tostring(cur()), vim.inspect(cache), htxt:match("Spring LS[^\n]*") or "none", htxt0:match("Spring LS newest[^\n]*") or "none"))

-- --verify
U.activate("2.3.0")
local real_vs = U.verify_script
U.verify_script = function() return nil end
run_cmd({ "2.4.1", "--verify" }, 1)
local refused = errors() == 1 and last():find("needs the Nv4J repo", 1, true) and cur() == "2.3.0"
U.verify_script = function() return HERE .. "/lib/verify_spring.sh" end
reset()
script.verify_code, script.verify_out = 1, "PASS 50_spring_ls.attached\nFAIL 51_spring_completion.props_first no item\nDONE 51_spring_completion 19 1\nnoise\n"
U.run_command({ "2.4.1", "--verify" })
wait_for(function() return errors() > 0 end)
rep("cmd_verify_fail", refused and cur() == "2.3.0" and last():find("FAILED verification", 1, true) and last():find("not switched, 2.3.0 stays", 1, true)
  and last():find("FAIL 51_spring_completion.props_first", 1, true) and not last():find("noise", 1, true) and calls[#calls]:find("verify_spring.sh 2.4.1", 1, true) ~= nil,
  ("refused %s, current %s, last %s"):format(tostring(refused), tostring(cur()), (last():gsub("\n", " | "))))
reset()
script.verify_code = 0
U.run_command({ "2.4.1", "--verify" })
wait_for(function() return cur() == "2.4.1" end)
rep("cmd_verify_ok", cur() == "2.4.1" and errors() == 0 and last():find("2.3.0 -> 2.4.1", 1, true), ("current %s, last %s"):format(tostring(cur()), last()))
U.verify_script = real_vs
local sh_ok = vim.fn.system({ "bash", "-n", HERE .. "/lib/verify_spring.sh" })
rep("verify_script_syntax", vim.v.shell_error == 0 and vim.fn.executable(HERE .. "/lib/verify_spring.sh") == 1 and real_vs() ~= nil, sh_ok)

-- rollback: the installs stay, mason = remove the pointer
reset()
local n_before = #ls()
U.run_command({ "mason" })
local removed = cur() == nil and #ls() == n_before - 1 and last():find("back to the Mason package", 1, true) ~= nil
U.activate("2.4.1")
run_cmd({ "2.5.2026111900" }, 2)
rep("rollback_back", removed and cur() == "2.5.2026111900" and #vim.tbl_filter(function(l) return l:find(".vsix", 1, true) ~= nil end, calls) == 0,
  ("pointer removed %s, current %s, calls %s"):format(tostring(removed), tostring(cur()), table.concat(calls, " | "):sub(1, 200)))

vim.env.NV4J_SPRING_HOME = nil
vim.fn.delete(TMP, "rf")
return lsp.finish()
