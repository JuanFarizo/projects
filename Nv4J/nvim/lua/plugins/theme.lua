return {
  {
    "folke/tokyonight.nvim",
    opts = {
      style = "night",
      transparent = false,
      terminal_colors = true,
      styles = {
        comments = { italic = true },
        keywords = { italic = true },
      },
    },
  },
  -- IntelliJ's default "Darcula" theme — self-contained colorscheme at
  -- colors/darcula-intellij.lua (no plugin needed), used for Java/Spring
  -- projects, see lua/config/autocmds.lua.
  -- Extra colorschemes, available via the picker (Space uC), not auto-selected.
  { "rebelot/kanagawa.nvim", lazy = true },
  {
    "nvim-telescope/telescope.nvim",
    keys = {
      {
        "<leader>uC",
        function()
          local hidden = { tokyonight = true, ["tokyonight-day"] = true, ["tokyonight-storm"] = true, ["tokyonight-moon"] = true }
          local colors = vim.tbl_filter(function(name)
            if hidden[name] then
              return false
            end
            -- Hide Neovim's bundled schemes (blue, desert, ...).
            -- Not-yet-loaded lazy plugins have no runtime file: keep those.
            for _, path in ipairs(vim.api.nvim_get_runtime_file("colors/" .. name .. ".*", true)) do
              if vim.startswith(path, vim.env.VIMRUNTIME) then
                return false
              end
            end
            return true
          end, vim.fn.getcompletion("", "color"))
          require("telescope.builtin").colorscheme({ enable_preview = true, colors = colors })
        end,
        desc = "Colorscheme with Preview",
      },
    },
  },
  { "catppuccin/nvim", name = "catppuccin", lazy = true },
  { "ellisonleao/gruvbox.nvim", lazy = true, opts = { terminal_colors = true } },
  {
    "bluz71/vim-moonfly-colors",
    name = "moonfly",
    lazy = true,
    -- vim.g.moonfly* globals, not an opts table — must be set before
    -- `:colorscheme moonfly` runs, so `init` (always runs at load) not `config`.
    init = function()
      -- Snacks floats/noice popups/blink.cmp menu all inherit the theme,
      -- instead of the default contrasting/black float background.
      vim.g.moonflyNormalFloat = true
      vim.g.moonflyNormalPmenu = true
      -- Diagnostics virtual text (jdtls errors/warnings) colored per severity.
      vim.g.moonflyVirtualTextColor = true
      -- Thin single-line window separators, matches the rest of the setup
      -- (no separator = harder to tell splits apart; blocks are too heavy).
      vim.g.moonflyWinSeparator = 2
    end,
  },
}
