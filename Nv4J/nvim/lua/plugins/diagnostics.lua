return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      -- tiny-inline-diagnostic.nvim renders diagnostics instead; keeping
      -- LazyVim's default virtual_text on too would show every diagnostic twice.
      opts.diagnostics.virtual_text = false
      return opts
    end,
  },
  {
    "rachartier/tiny-inline-diagnostic.nvim",
    event = "LspAttach",
    priority = 1000,
    opts = {
      preset = "powerline",
      options = {
        show_source = { enabled = false },
        multilines = { enabled = true },
        overflow = { mode = "wrap" },
      },
    },
  },
}
