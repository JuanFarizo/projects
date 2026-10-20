return {
  "nvim-telescope/telescope.nvim",
  opts = {
    defaults = {
      path_display = { "filename_first" },
      layout_strategy = "vertical",
      -- Default cutoff (40 lines) silently hides the preview in shorter windows.
      layout_config = { vertical = { preview_height = 0.65, preview_cutoff = 1, mirror = true } },
    },
  },
}
