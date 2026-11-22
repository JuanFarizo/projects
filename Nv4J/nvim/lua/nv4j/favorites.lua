-- java.completion.favoriteStaticMembers generated from the project's test classpath.
-- jdt.ls proposes the static members of these types without an import (accepting one adds `import static`).
-- Every group adds items to every identifier list, so a group is sent only when its library is on the
-- classpath (specs/features/completion-ranking.md, experiment 2). The JDK groups are always sent.
-- The list is computed once per jdt.ls client at ServiceReady (nv4j/warmup.lua) and pushed with
-- workspace/didChangeConfiguration; before that the client has the JDK groups only.
local M = {}

-- jar: Lua pattern on the classpath entry's file name; nil = always (JDK).
M.GROUPS = {
  { members = { "java.util.Objects.*", "java.util.stream.Collectors.*", "java.util.Map.entry" } },
  { jar = "^junit%-4", members = { "org.junit.Assert.*" } },
  { jar = "^junit%-jupiter%-api", members = { "org.junit.jupiter.api.Assertions.*" } },
  { jar = "^mockito%-core", members = { "org.mockito.Mockito.*", "org.mockito.ArgumentMatchers.*" } },
  { jar = "^assertj%-core", members = { "org.assertj.core.api.Assertions.*" } },
  { jar = "^hamcrest", members = { "org.hamcrest.Matchers.*", "org.hamcrest.MatcherAssert.assertThat" } },
  { jar = "^spring%-test", members = {
    "org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*",
    "org.springframework.test.web.servlet.result.MockMvcResultMatchers.*",
    "org.springframework.test.web.servlet.result.MockMvcResultHandlers.*",
  } },
}

--- The favourites for a classpath (a list of jar or folder paths), JDK groups first, no duplicates.
function M.for_classpath(paths)
  local names = {}
  for _, p in ipairs(paths or {}) do names[#names + 1] = vim.fs.basename(p) end
  local out, seen = {}, {}
  for _, g in ipairs(M.GROUPS) do
    local on = g.jar == nil
    for _, n in ipairs(names) do
      if not on and n:find(g.jar) then on = true end
    end
    if on then
      for _, m in ipairs(g.members) do
        if not seen[m] then seen[m], out[#out + 1] = true, m end
      end
    end
  end
  return out
end

local applied = {} -- client id -> the list that was pushed

--- The list pushed to this client, or nil before the classpath answered.
function M.applied(client) return client and applied[client.id] end

--- Ask jdt.ls for the test classpath of the client's first Java buffer, then set and push the favourites. Once per client.
function M.apply(client)
  if not client or applied[client.id] ~= nil or client.nv4j_favorites_asked then return end
  for bufnr in pairs(client.attached_buffers) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "java" then
      client.nv4j_favorites_asked = true
      client:request("workspace/executeCommand", {
        command = "java.project.getClasspaths",
        arguments = { vim.uri_from_bufnr(bufnr), vim.json.encode({ scope = "test" }) },
      }, function(err, res)
        client.nv4j_favorites_asked = nil
        if err or type(res) ~= "table" or type(res.classpaths) ~= "table" or client:is_stopped() then return end
        local list = M.for_classpath(res.classpaths)
        applied[client.id] = list
        for _, st in ipairs({ client.config.settings or {}, client.settings or {} }) do
          st.java = st.java or {}
          st.java.completion = st.java.completion or {}
          st.java.completion.favoriteStaticMembers = list
        end
        client.config.settings = client.config.settings or client.settings
        client:notify("workspace/didChangeConfiguration", { settings = client.config.settings })
      end, bufnr)
      return
    end
  end
end

return M
