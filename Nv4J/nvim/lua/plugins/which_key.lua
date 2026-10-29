return {
  {
    "folke/which-key.nvim",
    opts = {
      preset = "modern",
      -- <leader>a* AI agents (plugins/ai.lua). The `{ "<leader>a", nil, desc = ... }` lazy key in ai.lua
      -- is dropped once snacks.nvim is loaded (it is not lazy), so the group label is declared here.
      spec = { { "<leader>a", group = "AI agents", mode = { "n", "x" } } },
      delay = 100,
      win = {
        border = "rounded",
        padding = { 1, 2 },
        no_overlap = true,
        title = true,
        title_pos = "center",
      },
    },
  },
}
