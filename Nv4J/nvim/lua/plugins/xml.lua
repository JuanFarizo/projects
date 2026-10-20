-- lemminx (XML LSP) — gives pom.xml/build.xml formatting, validation, and
-- completion. Not enabled by any LazyVim extra by default; conform.nvim's
-- `lsp_format = "fallback"` means once this attaches, Space cf / format-on-save
-- "just work" on .xml with no separate formatter config needed.
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      lemminx = {},
    },
  },
}
