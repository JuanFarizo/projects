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
        -- Default (score, sort_text) everywhere; Java adds a project-usage tie breaker
        -- (nv4j/completion.lua). A kind-rank sort was tried before and buried `return`/`if`
        -- under JDK classes, so kinds are not ranked here.
        sorts = function() return require("nv4j.completion").sorts() end,
      },
      -- Java-only re-ranking (nv4j/completion.lua); other filetypes see blink's defaults.
      sources = {
        providers = {
          lsp = {
            transform_items = function(ctx, items) return require("nv4j.completion").transform_lsp(ctx, items) end,
          },
          snippets = {
            should_show_items = function(ctx, items) return require("nv4j.completion").snippets_should_show(ctx, items) end,
          },
        },
      },
      completion = {
        -- jdt.ls sends the auto-import (additionalTextEdits) only in completionItem/resolve, and
        -- resolving a well documented type (List, HashMap, ObjectMapper) takes 0.4-0.7 s because it
        -- also renders the javadoc. With blink's default 100 ms the item was inserted without its
        -- import. Accept now waits for resolve up to 1.5 s (only as long as resolve really takes).
        -- Measured: specs/features/diagnostics-imports-actions.md.
        accept = { resolve_timeout_ms = 1500 },
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
