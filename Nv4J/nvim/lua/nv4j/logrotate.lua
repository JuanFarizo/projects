-- Log housekeeping at Neovim start (never during a session), so /tmp/nv4j/logs does not grow for ever.
-- 1. lsp.log, spring-route.log, spring-boot-ls.log above vim.g.nv4j_log_max_mb (default 20; 0 = never rotate) are renamed
--    to <name>.1 (the one old copy, replaced each time) and start fresh. A rename is safe while another Neovim has the file
--    open: it keeps writing to the renamed file (Neovim appends through a handle it opened with "a+").
-- 2. test-*.log, lsp-capture-*.bin and the per-session lsp-<project>-<pid>.log older than vim.g.nv4j_log_keep_days (default 14; 0 = keep for ever) are deleted.
-- Only regular files in the one directory given are touched. Everything is in pcall: a failure is silent, startup never fails.
local M = {}

local uv = vim.uv
local ROTATED = { "lsp.log", "spring-route.log", "spring-boot-ls.log" }
local DELETED = { "^test%-.*%.log$", "^lsp%-capture%-.*%.bin$", "^lsp%-.+%-%d+%.log$" } -- last: per-session LSP logs (paths.lsp_log)

--- Rotates and cleans `dir`. `opts` (tests): max_mb, keep_days, now (epoch seconds). Returns { rotated = {names}, deleted = {names} }.
---@param dir string
---@param opts? { max_mb?: number, keep_days?: number, now?: integer }
function M.run(dir, opts)
  opts = opts or {}
  local done = { rotated = {}, deleted = {} }
  pcall(function()
    local max_mb = opts.max_mb or tonumber(vim.g.nv4j_log_max_mb) or 20
    local keep_days = opts.keep_days or tonumber(vim.g.nv4j_log_keep_days) or 14
    if max_mb > 0 then
      for _, name in ipairs(ROTATED) do
        local path = dir .. "/" .. name
        local st = uv.fs_stat(path)
        if st and st.type == "file" and st.size > max_mb * 1024 * 1024 and uv.fs_rename(path, path .. ".1") then
          done.rotated[#done.rotated + 1] = name
        end
      end
    end
    if keep_days > 0 then
      local limit = (opts.now or os.time()) - keep_days * 86400
      local handle = uv.fs_scandir(dir)
      while handle do
        local name = uv.fs_scandir_next(handle)
        if not name then break end
        for _, pat in ipairs(DELETED) do
          if name:match(pat) then
            local path = dir .. "/" .. name
            local st = uv.fs_lstat(path)
            if st and st.type == "file" and st.mtime.sec < limit and uv.fs_unlink(path) then
              done.deleted[#done.deleted + 1] = name
            end
            break
          end
        end
      end
    end
  end)
  return done
end

return M
