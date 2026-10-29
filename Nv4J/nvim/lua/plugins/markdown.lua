return {
  -- Replaces the LazyVim lang.markdown extra's default previewer
  -- (iamcco/markdown-preview.nvim), which is effectively unmaintained
  -- (no commits since mid-2024, hundreds of open issues).
  { "iamcco/markdown-preview.nvim", enabled = false },
  -- markview.nvim did the same in-buffer rendering job (plus LaTeX/Typst/
  -- HTML/Asciidoc) but its hybrid mode hides the render on cursor move/
  -- typing, which breaks writing flow. Switched to render-markdown.nvim
  -- (2026-09-14): renders persistently regardless of cursor position, only
  -- renders the visible range (lighter on large files), and just shipped a
  -- wide-table wrap fix (commit a778444, 2026-09-14) that markview's own
  -- table renderer still lacked (open "optimize table renderer" TODO).
  { "OXY2DEV/markview.nvim", enabled = false },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    -- lazy (the lang.markdown extra gives it ft = markdown, ...): a Java session does not load it.
    opts = {
      -- LazyVim's lang.markdown extra sets heading.icons = {} (no
      -- per-level icon). Restored to the plugin's own default here so
      -- H1-H6 are visually distinct again.
      heading = { icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " } },
      -- pipe_table.wrap (multiline cell wrapping) shipped 2026-09-13,
      -- defaults true, and is the author's own "experimental... hopefully
      -- none completely breaking" release. Independent of Neovim's
      -- `wrap`/`nowrap` window option — toggling that has no effect on
      -- it. Disabled until it stabilizes; falls back to the previous
      -- stable padded-cell table renderer.
      pipe_table = { wrap = false },
    },
    keys = {
      { "<leader>cp", "<cmd>RenderMarkdown toggle<cr>", ft = "markdown", desc = "Toggle Markdown Preview" },
      { "<leader>um", "<cmd>RenderMarkdown toggle<cr>", ft = "markdown", desc = "Toggle Markdown Preview" },
    },
  },
  -- markdownlint-cli2 only reads a config file from the SAME directory as
  -- the file being linted (confirmed — it does not walk up to parent
  -- directories, so a single repo-root or $HOME config silently doesn't
  -- apply). Passing --config explicitly makes ~/.markdownlint-cli2.jsonc
  -- (MD013 line-length disabled — that rule fights normal prose writing)
  -- apply to every markdown file regardless of location.
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          prepend_args = { "--config", vim.fn.expand("~/.markdownlint-cli2.jsonc") },
        },
      },
    },
  },
  -- Diagnostics (markdownlint and any future markdown linter) render as
  -- a gutter sign + underline only, not inline virtual text — prose notes
  -- get unreadable fast with an error message appended after every line.
  -- Full message still available on hover / Space cd. Every other
  -- filetype (Java, TS, etc.) keeps LazyVim's normal icon-prefixed inline
  -- virtual text unchanged — the original table is captured and returned
  -- as-is for those, only markdown gets `false`.
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local default_virtual_text = opts.diagnostics.virtual_text
      opts.diagnostics.virtual_text = function(namespace, bufnr)
        if vim.bo[bufnr].filetype == "markdown" then
          return false
        end
        if type(default_virtual_text) == "function" then
          return default_virtual_text(namespace, bufnr)
        end
        return default_virtual_text
      end
    end,
  },
}
