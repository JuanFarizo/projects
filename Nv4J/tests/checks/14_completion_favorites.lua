-- Favourite static members generated from the project classpath (nv4j/favorites.lua,
-- specs/features/completion-ranking.md experiment 2). Run via tests/run.sh.
-- java.completion.favoriteStaticMembers makes jdt.ls propose static members without an import (the accept adds
-- `import static`). The list used to be fixed; now a group is sent only when its library is on the project's
-- test classpath, plus the JDK groups. Cases: the pure selection, the live settings of the client, and
-- completions of members that were not favourites before (MockMvc, ArgumentMatchers, Collectors, Map.entry).
vim.o.confirm = false
local lsp = require("lsp")
local C = require("completion")
local F = require("nv4j.favorites")

local function has(list, x) return vim.tbl_contains(list, x) end

-- 1. Pure selection (no server).
do
  local none = F.for_classpath({ "/m2/org/foo/foo-1.0.jar" })
  lsp.report("14_completion_favorites.pure_jdk_only",
    has(none, "java.util.stream.Collectors.*") and has(none, "java.util.Map.entry") and has(none, "java.util.Objects.*")
      and not has(none, "org.mockito.ArgumentMatchers.*") and not has(none, "org.mockito.Mockito.*"),
    "JDK groups only: " .. table.concat(none, ", "))
  local some = F.for_classpath({ "/m2/org/mockito/mockito-core/5.17.0/mockito-core-5.17.0.jar",
    "/m2/org/springframework/spring-test/6.2.8/spring-test-6.2.8.jar" })
  lsp.report("14_completion_favorites.pure_by_jar",
    has(some, "org.mockito.ArgumentMatchers.*") and has(some, "org.mockito.Mockito.*")
      and has(some, "org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*")
      and not has(some, "org.assertj.core.api.Assertions.*") and not has(some, "org.hamcrest.Matchers.*"),
    table.concat(some, ", "))
end

-- 2. Live: the client's settings follow the test classpath, and the members complete.
local src = vim.env.NV4J_FIXTURE .. "/src/test/java/demo/"
local buf = C.open_ready(lsp, src .. "GreetingPropertiesTest.java", 120000)
if not buf then
  lsp.report("14_completion_favorites.live_settings", false, "jdtls not ready within 120 s")
  lsp.finish()
  return
end
local client = vim.lsp.get_clients({ bufnr = buf, name = "jdtls" })[1]
local got = vim.wait(20000, function() return F.applied(client) ~= nil end, 50)
local cfg = vim.tbl_get(client.config.settings or {}, "java", "completion", "favoriteStaticMembers") or {}
local sent = vim.tbl_get(client.settings or {}, "java", "completion", "favoriteStaticMembers") or {}
lsp.report("14_completion_favorites.live_settings",
  got and has(cfg, "org.mockito.ArgumentMatchers.*") and has(cfg, "org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*")
    and has(cfg, "org.junit.jupiter.api.Assertions.*") and has(cfg, "java.util.stream.Collectors.*") and #sent == #cfg,
  ("applied=%s %d favourites: %s"):format(tostring(got), #cfg, table.concat(cfg, ", ")))

local fuzzy = C.blink()
local cases = {
  { name = "mockmvc_post", line = "        po", label = "post", detail = "MockMvcRequestBuilders" },
  { name = "matchers_any_string", line = "        anyS", label = "anyString", detail = "ArgumentMatchers" },
  { name = "collectors_to_list", line = "        toL", label = "toList", detail = "Collectors" },
  { name = "map_entry", line = "        entr", label = "entry", detail = "Map.entry(" },
}
for _, cs in ipairs(cases) do
  local tag = "14_completion_favorites." .. cs.name
  C.scratch(buf, function()
    local at = C.find_line(buf, "String text = props.text") + 1
    vim.api.nvim_buf_set_lines(buf, at, at, false, { cs.line })
    local m, merr = C.menu(buf, at, #cs.line)
    if not m then return lsp.report(tag, false, "menu: " .. tostring(merr)) end
    local rank = C.rank(m.items, function(it)
      return it.label == cs.label and ((it.detail or "") .. " " .. ((it.labelDetails and it.labelDetails.description) or "")):find(cs.detail, 1, true) ~= nil
    end)
    lsp.report(tag, rank ~= nil and rank <= 10,
      ("rank(%s.%s)=%s (budget <= 10) of %d shown=[%s]"):format(cs.detail, cs.label, tostring(rank), #m.items, C.labels(m.items, 6)))
  end)
end

lsp.finish()
