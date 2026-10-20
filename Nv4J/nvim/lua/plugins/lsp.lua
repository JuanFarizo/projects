-- Custom overrides on top of LazyVim's LSP defaults.
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      -- Inlay hints (inline type/param hints) off by default — noisy on
      -- every new buffer. Toggle back on ad-hoc with Space uh if wanted.
      opts.inlay_hints.enabled = false
      -- Needed for jdtls's "n references" lens above methods/classes (see java.lua).
      opts.codelens.enabled = true
    end,
  },
}
