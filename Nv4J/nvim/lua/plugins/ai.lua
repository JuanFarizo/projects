local function ai(action)
  return function()
    require("util.ai").run(action)
  end
end

return {
  "folke/snacks.nvim",
  optional = true,
  keys = {
    { "<leader>a", nil, desc = "AI agents" },
    { "<leader>aa", ai("toggle"), desc = "Toggle active AI" },
    { "<leader>ap", function() require("util.ai").pick() end, desc = "Pick AI provider" },
    { "<leader>ac", function() require("util.ai").direct("claude") end, desc = "Toggle Claude" },
    { "<leader>ak", function() require("util.ai").direct("cursor") end, desc = "Toggle Cursor" },
    { "<leader>as", ai("send_selection"), mode = "x", desc = "Send selection to AI" },
    { "<leader>ab", ai("add_buffer"), desc = "Add buffer to AI" },
    { "<leader>ar", ai("resume"), desc = "Resume AI session" },
    { "<leader>aC", ai("continue"), desc = "Continue AI session" },
    { "<leader>am", ai("model"), desc = "Select AI model" },
  },
}
