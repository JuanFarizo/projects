return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    window = {
      width = 35,
      mappings = { e = "nv4j_toggle_auto_expand" },
    },
    commands = {
      -- `e`: neo-tree's toggle_auto_expand_width, but it comes back to the width the window had BEFORE it was switched on.
      -- Neo-tree's own "width before" is overwritten by every render while auto-expand is on (ui/renderer.lua, last_user_width
      -- = current width), so opening folders step by step 35 -> 40 -> 47 -> 54 -> 69 and pressing `e` again gave 54, not 35.
      -- The cursor node is also queued for focus so the redraw cannot jump to an older saved position.
      nv4j_toggle_auto_expand = function(state)
        if state.window.position == "float" or not state.winid or not vim.api.nvim_win_is_valid(state.winid) then return end
        if not state.window.auto_expand_width then state.nv4j_base_width = vim.api.nvim_win_get_width(state.winid) end
        local node = state.tree and state.tree:get_node()
        if node then require("neo-tree.ui.renderer").position.set(state, node:get_id()) end
        require("neo-tree.sources.common.commands").toggle_auto_expand_width(state)
        if not state.window.auto_expand_width then
          local w = state.nv4j_base_width or require("neo-tree.utils").resolve_width(state.window.width)
          vim.api.nvim_win_set_width(state.winid, w)
          state.win_width = w
          state.window.last_user_width = w
        end
      end,
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
