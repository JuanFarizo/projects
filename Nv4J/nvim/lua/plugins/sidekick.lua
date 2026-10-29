-- No keys/cmd/event: loads on first require("sidekick.cli") from util/ai.lua,
-- so it costs nothing at startup. NES (Copilot next-edit) and the tmux
-- backend are off; this setup only wants CLI terminals.
return {
  "folke/sidekick.nvim",
  lazy = true,
  opts = {
    nes = { enabled = false },
    cli = {
      mux = { enabled = false },
      tools = {
        cursor = { cmd = { "cursor-agent" } },
        cursor_resume = { cmd = { "cursor-agent", "--resume" } },
        cursor_continue = { cmd = { "cursor-agent", "--continue" } },
      },
    },
  },
}
