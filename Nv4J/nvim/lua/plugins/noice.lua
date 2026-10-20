return {
  "folke/noice.nvim",
  opts = function(_, opts)
    -- jdtls fires $/progress noise ("Publish Diagnostics", "Building",
    -- "Validate documents") on every re-validate pass, i.e. on every save
    -- and (once debounced, see plugins/java.lua) roughly every keystroke
    -- pause. Route it away from noice's lsp_progress toast instead of
    -- disabling lsp progress display globally (still want it for other
    -- servers, e.g. long-running builds elsewhere).
    opts.routes = opts.routes or {}
    table.insert(opts.routes, {
      filter = { event = "lsp", kind = "progress", find = "jdtls" },
      opts = { skip = true },
    })
    return opts
  end,
}
