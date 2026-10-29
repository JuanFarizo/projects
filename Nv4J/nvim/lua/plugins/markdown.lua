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
  -- The dotfiles also wrap diagnostics.virtual_text in a function here (markdown: no inline text, other
  -- filetypes: LazyVim's). Not ported: Nv4J turns built-in virtual text off for every filetype
  -- (plugins/diagnostics.lua, tiny-inline-diagnostic draws instead), so the wrapper changed nothing visible
  -- and made the setting a function, which 30_diagnostics one_renderer cannot read as "off".
}
