-- gd on `:name` inside @Query jumps to the method parameter (nv4j/jpqlcomplete.lua param_target / goto_param / setup wrapper).
--   param_value   @Param("businessId") wins over the Java name
--   param_java    no @Param: the Java parameter name
--   param_end     cursor right after the last letter still counts
--   text_block    same in a """ block, on a later line
--   unknown       :nope with no such parameter: nil
--   native        nativeQuery = true: nil (not JPQL)
--   not_query     a string outside @Query: nil
--   goto_moves    goto_param puts the cursor on the parameter name and jumps back with <C-o>
--   def_wrapper   vim.lsp.buf.definition takes the parameter first and falls through elsewhere
local lsp = require("lsp")
local C = require("nv4j.jpqlcomplete")
local P = "86_jpql_param_def."
local TMP = "/tmp/nv4j/jpql-def-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")
local path = TMP .. "/R.java"
vim.fn.writefile(vim.split([=[
package d;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
public interface R extends JpaRepository<Branch, Long> {
    @Query("SELECT b FROM Branch b WHERE b.business.id = :businessId AND b.slug = :slug")
    Branch one(@Param("businessId") Long x, String slug);
    @Query("SELECT b FROM Branch b WHERE b.id = :id")
    Branch two(Long id);
    @Query("""
            SELECT b FROM Branch b
            WHERE b.slug = :slug
            """)
    Branch three(@Param("slug") String s);
    @Query("SELECT b FROM Branch b WHERE b.slug = :nope")
    Branch four(String slug);
    @Query(value = "SELECT * FROM branch WHERE slug = :slug", nativeQuery = true)
    Branch five(String slug);
    @Deprecated(":slug")
    Branch six(String slug);
}
]=], "\n"), path)
vim.cmd("noautocmd edit " .. vim.fn.fnameescape(path))
vim.cmd("noautocmd set filetype=java")
local buf = vim.api.nvim_get_current_buf()

--- {row, col} 0-based of the first `needle` on the line containing `anchor`, +delta.
local function find(anchor, needle, delta)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:find(anchor, 1, true) then return i - 1, l:find(needle, l:find(anchor, 1, true), true) - 1 + (delta or 0) end
  end
  error("anchor " .. anchor)
end
local function target(anchor, needle, delta)
  local r, c = find(anchor, needle, delta)
  local t = C.param_target(buf, r, c)
  return t and (t[1] .. ":" .. t[2]) or "nil"
end
local function param_pos(anchor, name)
  local r, c = find(anchor, name)
  return r .. ":" .. c
end
local function check(name, got, want) lsp.report(P .. name, got == want, ("got %s want %s"):format(got, want)) end

check("param_value", target(":businessId", ":businessId", 2), param_pos("Branch one(", "x"))
check("param_java", target("b.id = :id", ":id", 2), param_pos("Branch two(", "id)"))
check("param_end", target("b.id = :id", ":id", 3), param_pos("Branch two(", "id)"))
check("text_block", target("WHERE b.slug = :slug", ":slug", 2), param_pos("Branch three(", "s)"))
check("unknown", target(":nope", ":nope", 2), "nil")
check("native", target("SELECT * FROM", ":slug", 2), "nil")
check("not_query", target("@Deprecated", ":slug", 2), "nil")

do
  local r, c = find("Branch b WHERE b.id = :id", ":id", 2)
  vim.api.nvim_win_set_cursor(0, { r + 1, c })
  local handled = C.goto_param()
  local pos = vim.api.nvim_win_get_cursor(0)
  local want_r, want_c = find("Branch two(", "id)")
  vim.cmd("normal! \15")
  local back = vim.api.nvim_win_get_cursor(0)
  check("goto_moves", tostring(handled) .. " " .. (pos[1] - 1) .. ":" .. pos[2] .. " back " .. back[1] .. ":" .. back[2],
    ("true %d:%d back %d:%d"):format(want_r, want_c, r + 1, c))
end

do
  C.setup()
  local called = 0
  -- the original is captured by setup(); a call on a plain position must reach it
  local r, c = find("package d", "d;")
  vim.api.nvim_win_set_cursor(0, { r + 1, c })
  local seen
  local lsp_buf = vim.lsp.buf
  local ok = pcall(lsp_buf.definition)
  local r2, c2 = find("Branch b WHERE b.id = :id", ":id", 2)
  vim.api.nvim_win_set_cursor(0, { r2 + 1, c2 })
  lsp_buf.definition()
  local pos = vim.api.nvim_win_get_cursor(0)
  local wr, wc = find("Branch two(", "id)")
  check("def_wrapper", (pos[1] - 1) .. ":" .. pos[2], wr .. ":" .. wc)
end
lsp.finish()
