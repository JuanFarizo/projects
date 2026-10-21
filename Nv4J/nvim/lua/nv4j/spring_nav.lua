-- Spring symbols picker (<leader>sp, check 52_spring_nav): the beans (`@+`) and request mappings (`@/`) the
-- Spring Boot LS indexes, asked with workspace/symbol on that client only (vim.lsp.buf.workspace_symbol, used by
-- spring-boot.nvim's :SpringBoot, asks every client, so jdt.ls answers too), shown in Telescope.
-- Not <leader>ss: that is LazyVim's Goto Symbol (telescope extra). <leader>sp is free with the telescope extra; the snacks
-- picker extra binds it to "Search for Plugin Spec" (switching pickers would collide). Spec:
-- specs/features/spring-language-server.md.
local M = {}

local QUERIES = { "@+", "@/" }
M.TIMEOUT_MS = 5000

--- The Spring Boot client for this buffer: the one attached to it, else one whose root holds the file or cwd.
local function client_for(buf)
  local c = vim.lsp.get_clients({ bufnr = buf, name = "spring-boot" })[1]
  if c then return c end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then path = vim.fn.getcwd() end
  for _, cl in ipairs(vim.lsp.get_clients({ name = "spring-boot" })) do
    local root = cl.config.root_dir
    if root and (path == root or vim.startswith(path, root .. "/")) then return cl end
  end
end

--- Calls cb(items) with quickfix-style items (filename, lnum, col, text) for beans then request mappings,
--- or notifies and returns false when the buffer has no Spring Boot LS.
function M.collect(buf, cb)
  local client = client_for(buf)
  if not client then
    vim.notify("nv4j: no Spring Boot language server for this buffer (Spring Boot projects only)", vim.log.levels.WARN)
    return false
  end
  local results, left, done = {}, #QUERIES, false
  local function fail(why)
    if done then return end
    done = true
    vim.notify("nv4j: Spring symbols: " .. why, vim.log.levels.WARN)
  end
  -- A server that never answers (busy, hung) gets a visible warning instead of silence.
  local timer = vim.defer_fn(function() fail(("no answer from the Spring Boot LS within %d ms"):format(M.TIMEOUT_MS)) end, M.TIMEOUT_MS)
  for i, q in ipairs(QUERIES) do
    local ok = client:request("workspace/symbol", { query = q }, function(err, res)
      if done then return end
      if err then
        timer:stop()
        return fail("the Spring Boot LS returned an error: " .. tostring(err.message or err))
      end
      results[i] = res or {}
      left = left - 1
      if left > 0 then return end
      done = true
      timer:stop()
      local items = {}
      for _, r in ipairs(results) do
        vim.list_extend(items, vim.lsp.util.symbols_to_items(r, buf, client.offset_encoding))
      end
      cb(items)
    end, buf)
    if not ok then
      timer:stop()
      fail("the request could not be sent (Spring Boot LS stopped?)")
      return false
    end
  end
  return true
end

function M.pick()
  local buf = vim.api.nvim_get_current_buf()
  M.collect(buf, vim.schedule_wrap(function(items)
    if #items == 0 then
      return vim.notify("nv4j: the Spring Boot LS found no beans or request mappings (yet)", vim.log.levels.INFO)
    end
    local conf = require("telescope.config").values
    require("telescope.pickers").new({}, {
      prompt_title = "Spring symbols (beans @+, request mappings @/)",
      finder = require("telescope.finders").new_table({
        results = items,
        entry_maker = require("telescope.make_entry").gen_from_quickfix({}),
      }),
      sorter = conf.generic_sorter({}),
      previewer = conf.qflist_previewer({}),
    }):find()
  end))
end

return M
