-- Usage: nvim -l tests/lib/jdk_home.lua <major>  -> prints home of the newest non-EA JDK with that major
-- (same discovery as the config: SDKMAN, ~/Library/Java/JavaVirtualMachines, /Library/...). Exit 1 if none.
local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)/lib/")
package.path = here .. "/../nvim/lua/?.lua;" .. package.path
local want = tonumber(arg[1])
for _, d in ipairs(require("nv4j.jdk").discover()) do
  if d.major == want and not d.ea then
    io.stdout:write(d.home, "\n")
    os.exit(0)
  end
end
os.exit(1)
