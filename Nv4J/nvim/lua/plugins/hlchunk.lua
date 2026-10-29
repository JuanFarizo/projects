-- Treesitter-based scope/indent guides with a highlighted current-chunk
-- border. Replaces snacks.nvim's indent/scope modules (LazyVim default) —
-- keeping both would double-draw indent guides.
local exclude_ft = {
  dashboard = true,
  snacks_dashboard = true,
  alpha = true,
  help = true,
  lazy = true,
  mason = true,
  notify = true,
  checkhealth = true,
  lspinfo = true,
  qf = true,
  terminal = true,
}

return {
  {
    "snacks.nvim",
    opts = {
      indent = { enabled = false },
      scope = { enabled = false },
    },
  },
  {
    "shellRaining/hlchunk.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function(_, opts)
      require("hlchunk").setup(opts)
      -- hlchunk's debounced callback can fire after the cursor row no longer
      -- exists in the buffer (closing the last buffer swaps in an empty one),
      -- so nvim_buf_get_lines returns nil and string.sub throws.
      local helper = require("hlchunk.utils.chunkHelper")
      local orig = helper.get_chunk_range
      helper.get_chunk_range = function(arg)
        local ok, code, range = pcall(orig, arg)
        if ok then
          return code, range
        end
        return helper.CHUNK_RANGE_RET.NO_CHUNK, require("hlchunk.utils.scope")(arg.pos.bufnr, -1, -1)
      end
    end,
    opts = {
      chunk = {
        enable = true,
        -- treesitter-based matching needs a fully-valid parse tree; while
        -- actively typing inside deeply nested blocks (lambda + anonymous
        -- class + try/catch) braces are momentarily unbalanced mid-edit,
        -- treesitter can't resolve the chunk boundary, and hlchunk falls
        -- back to its error style (DiagnosticError below) — which often
        -- picks a much larger wrong range, looking like the whole file
        -- flashed color. Non-treesitter matching doesn't need a valid tree.
        use_treesitter = false,
        exclude_filetypes = exclude_ft,
        -- Link to highlight groups rather than hardcoding hex, so this
        -- follows whichever colorscheme is active per-project (Space uC).
        style = {
          { fg = vim.api.nvim_get_hl(0, { name = "Function" }).fg },
          { fg = vim.api.nvim_get_hl(0, { name = "DiagnosticError" }).fg },
        },
      },
      indent = {
        enable = false,
        use_treesitter = false,
        style = {
          { fg = vim.api.nvim_get_hl(0, { name = "Comment" }).fg },
        },
        exclude_filetypes = exclude_ft,
      },
      line_num = {
        enable = true,
        use_treesitter = true,
        exclude_filetypes = exclude_ft,
      },
      blank = { enable = false },
    },
  },
}
