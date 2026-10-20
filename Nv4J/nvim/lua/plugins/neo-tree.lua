return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    window = {
      width = 35,
    },
    filesystem = {
      filtered_items = {
        visible = false,
        hide_dotfiles = false,
        hide_gitignored = false,
      },
      -- Disabled: was auto-revealing/jumping to the current file on every
      -- buffer switch (open or close). Use <leader>ef to reveal on demand.
      follow_current_file = { enabled = false },
    },
    -- neo-tree creates files on disk directly (no BufNewFile) — scaffold here instead.
    event_handlers = {
      {
        event = "file_added", -- neo-tree.events.FILE_ADDED
        handler = function(destination)
          if destination:match("%.java$") then
            require("util.java_scaffold").scaffold_file(destination)
          end
        end,
      },
    },
  },
}
