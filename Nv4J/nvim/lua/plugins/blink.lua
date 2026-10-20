-- Additions on top of LazyVim's `coding.blink` extra.
return {
  {
    "saghen/blink.cmp",
    dependencies = {
      "xzbdmw/colorful-menu.nvim",
    },
    opts = {
      -- Signature + docs while typing a call's args; LSP signatureHelp works on unfinished code.
      signature = { enabled = true, window = { border = "rounded", show_documentation = true } },
      -- TESTING: blink-ripgrep ("Proj" source) removed to check whether the
      -- menu feels less noisy/laggy. Restore it if project-wide words are missed.
      fuzzy = {
        -- Typo-tolerant matching shows items that don't contain what you typed.
        max_typos = function() return 0 end,
        -- No custom `sorts`: a kind-rank sort buried `return`/`if` under JDK classes and
        -- benchmarked worse than blink's default (score, sort_text) on real Java code.
      },
      completion = {
        ghost_text = { enabled = true },
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 200,
          window = {
            border = "rounded",
            max_width = 100,
            max_height = 20,
            -- Docs go below/above the menu at full width; the side column was too narrow for long descriptions.
            direction_priority = {
              menu_north = { "n", "e", "w" },
              menu_south = { "s", "e", "w" },
            },
          },
        },
        menu = {
          border = "rounded",
          draw = {
            columns = {
              { "kind_icon" },
              { "label", "label_description", gap = 1 },
              { "kind" },
            },
            components = {
              label = {
                text = function(ctx)
                  return require("colorful-menu").blink_components_text(ctx)
                end,
                highlight = function(ctx)
                  return require("colorful-menu").blink_components_highlight(ctx)
                end,
              },
            },
          },
        },
      },
    },
  },
}
