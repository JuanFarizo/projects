-- Loads on its first key (ga / gA, mini.align's defaults) instead of at startup.
return {
  {
    "nvim-mini/mini.align",
    version = false,
    opts = {},
    keys = {
      { "ga", mode = { "n", "x" }, desc = "Align" },
      { "gA", mode = { "n", "x" }, desc = "Align with preview" },
    },
  },
}
