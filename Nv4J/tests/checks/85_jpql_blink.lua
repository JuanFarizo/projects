-- JPQL completion inside blink.cmp's own pipeline (provider "jpql" from plugins/blink.lua), real jdt.ls, Boot 4 fixture copy.
-- HEAVY. A headless Neovim cannot hold insert mode across a vim.wait, so the menu itself is not drawn here; this runs everything
-- blink does around it: which providers are enabled for Java and in which order, the trigger characters, the provider
-- wrapper (config, score_offset, transform) calling nv4j.jpqlsource with a blink context, for a java buffer.
--  providers_java   blink's enabled providers for a Java buffer start with "jpql" and keep lsp/path/snippets/buffer after it
--  providers_other  a non-Java buffer does not have it
--  trigger_chars    `.` and `:` are trigger characters
--  fields           provider "jpql" returns Booking's fields for `SELECT b FROM Booking b WHERE b.`, each with score_offset >= 100
--  join             `JOIN b.customer c WHERE c.` returns Customer's fields
--  outside          a cursor in a comment (not a @Query string) returns no item
--  noise_dropped    blink's lsp provider drops Spring LS Method items (countBy, findByX) inside a @Query string, keeps the rest
--  noise_outside_kept  the same items outside a @Query string are all kept
local lsp = require("lsp")
local P = "85_jpql_blink."
local SRC = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/fixtures/jpa4"
local TMP = "/tmp/nv4j/jpql-blink-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
vim.fn.system({ "cp", "-R", SRC .. "/.", TMP })
vim.fn.delete(TMP .. "/target", "rf")
TMP = vim.uv.fs_realpath(TMP)
local FILE = TMP .. "/src/main/java/jpa4/BookingRepository.java"
local buf = lsp.open(FILE)
local client, why = lsp.wait_ready(buf, 300000)
if not client then lsp.report(P .. "ready", false, why) return lsp.finish() end
vim.api.nvim_set_current_buf(buf)
local base = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

require("lazy").load({ plugins = { "blink.cmp" } })
local sources = require("blink.cmp.sources.lib")

local ids = sources.get_enabled_provider_ids("default")
lsp.report(P .. "providers_java", ids[1] == "jpql" and vim.tbl_contains(ids, "lsp") and vim.tbl_contains(ids, "buffer"), table.concat(ids, ","))
local other = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(other)
vim.bo[other].filetype = "lua"
local ids2 = sources.get_enabled_provider_ids("default")
lsp.report(P .. "providers_other", not vim.tbl_contains(ids2, "jpql"), table.concat(ids2, ","))
vim.api.nvim_set_current_buf(buf)
local trig = sources.get_trigger_characters("default")
lsp.report(P .. "trigger_chars", vim.tbl_contains(trig, ".") and vim.tbl_contains(trig, ":"), #trig .. " characters")

--- Ask provider "jpql" through blink's wrapper for a line (cursor `back` chars before its end).
local next_id = 0
local function ask(line, back)
  next_id = next_id + 1
  local lines = vim.deepcopy(base)
  while lines[#lines]:match("^%s*$") do table.remove(lines) end
  lines[#lines] = nil
  lines[#lines + 1] = line
  lines[#lines + 1] = "    java.util.List<Booking> probe();"
  lines[#lines + 1] = "}"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local row, col = #lines - 2, #line - back
  vim.api.nvim_win_set_cursor(0, { row, col })
  local ctx = {
    id = next_id, bufnr = buf, cursor = { row, col }, line = line, mode = "default", providers = { "jpql" },
    bounds = { line_number = row, start_col = col + 1, length = 0 },
    trigger = { kind = vim.lsp.protocol.CompletionTriggerKind.TriggerCharacter, character = "." },
    get_cursor = function() return { row, col } end, get_line = function() return line end,
    get_keyword = function() return "" end, get_bounds = function() return { line_number = row, start_col = col + 1, length = 0 } end,
  }
  local provider = sources.get_provider_by_id("jpql")
  local got
  provider:get_completions(ctx, function(items) if got == nil then got = items end end)
  vim.wait(20000, function() return got ~= nil end, 50)
  return got or {}
end
local function labels(items) local t = {} for _, i in ipairs(items) do t[i.label] = i end return t end
local Q = '    @org.springframework.data.jpa.repository.Query("%s")'
local a = labels(ask(Q:format("SELECT b FROM Booking b WHERE b."), 2))
local boosted = a.reference and (a.reference.score_offset or 0) >= 100
lsp.report(P .. "fields", a.reference and a.status and a.total and a.customer and boosted, vim.inspect(vim.tbl_keys(a)):gsub("%s+", " ") .. " score_offset=" .. tostring(a.reference and a.reference.score_offset))
local b = labels(ask(Q:format("SELECT b FROM Booking b JOIN b.customer c WHERE c."), 2))
lsp.report(P .. "join", b.email and b.fullName, vim.inspect(vim.tbl_keys(b)):gsub("%s+", " "))
local c = ask("    // SELECT b FROM Booking b WHERE b.", 0)
lsp.report(P .. "outside", #c == 0, #c .. " item(s)")


-- Spring LS method-name items (countBy, findByX) are dropped inside a @Query string, everything else stays.
do
  local function filt(line, back)
    local lines = vim.deepcopy(base)
    while lines[#lines]:match("^%s*$") do table.remove(lines) end
    lines[#lines] = nil
    lines[#lines + 1] = line
    lines[#lines + 1] = "    java.util.List<Booking> probe();"
    lines[#lines + 1] = "}"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local row, col = #lines - 2, #line - back
    vim.api.nvim_win_set_cursor(0, { row, col })
    local items = {
      { label = "countBy", kind = 2, client_name = "spring-boot" },
      { label = "someField", kind = 5, client_name = "spring-boot" },
      { label = "equals", kind = 2, client_name = "jdtls" },
    }
    local out = sources.get_provider_by_id("lsp"):transform_items({ bufnr = buf, cursor = { row, col }, line = line, bounds = { line_number = row, start_col = col + 1, length = 0 } }, items)
    local t = {}
    for _, i in ipairs(out) do t[#t + 1] = i.label end
    return table.concat(t, ",")
  end
  local inq = filt(Q:format("SELECT b FROM Booking b WHERE b."), 2)
  lsp.report(P .. "noise_dropped", inq == "someField,equals", inq)
  local outq = filt("    // SELECT b FROM Booking b WHERE b.", 0)
  lsp.report(P .. "noise_outside_kept", outq == "countBy,someField,equals", outq)
end

vim.api.nvim_buf_set_lines(buf, 0, -1, false, base)
vim.bo[buf].modified = false
vim.fn.delete(TMP, "rf")
lsp.finish()
