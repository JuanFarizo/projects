-- snacks.image is off in LazyVim. It is switched on only after `:Nv4JMermaid install` (nv4j/mermaid.lua), so a
-- machine without mmdr pays nothing (no terminal query for graphics support, no treesitter attach).
-- Rollback: `:Nv4JMermaid remove` and restart, or `vim.g.nv4j_mermaid = false`, or delete this file.
return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    local m = require("nv4j.mermaid")
    if vim.g.nv4j_mermaid == false or not m.installed() then return end
    opts.image = vim.tbl_deep_extend("force", opts.image or {}, {
      enabled = true,
      doc = { inline = true, float = false, max_width = 100, max_height = 30 },
    })
  end,
}
