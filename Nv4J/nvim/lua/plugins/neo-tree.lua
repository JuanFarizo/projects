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
    -- neo-tree creates files on disk directly (no BufNewFile): fill the new empty file from the
    -- nv4j/scaffold.lua templates here. <leader>jn on a tree node creates in that node's directory.
    event_handlers = {
      {
        event = "file_added", -- neo-tree.events.FILE_ADDED
        handler = function(destination)
          if destination:match("%.java$") then
            require("nv4j.scaffold").fill_file(destination)
          end
        end,
      },
      -- Renaming/moving a .java file or a folder with Java files (a package): jdt.ls is asked
      -- (willRenameFiles) BEFORE the move and the whole rename is done by nv4j/refactor.lua (package and
      -- import lines, buffers re-pointed). LazyVim's own handler asks only after the move, which left the
      -- old `package` line (specs/features/refactors.md); it is skipped for these (ours run first).
      { event = "before_file_rename", handler = function(a) return require("nv4j.refactor").neotree_before(a) end },
      { event = "before_file_move", handler = function(a) return require("nv4j.refactor").neotree_before(a) end },
      { event = "file_renamed", handler = function(a) return require("nv4j.refactor").neotree_after(a) end },
      { event = "file_moved", handler = function(a) return require("nv4j.refactor").neotree_after(a) end },
    },
  },
}
