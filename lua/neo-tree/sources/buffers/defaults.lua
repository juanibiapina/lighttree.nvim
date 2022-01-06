local highlights = require('neo-tree.ui.highlights')
local components = require('neo-tree.sources.buffers.components')

local filesystem = {
  window = {
    position = "left",
    width = 40,
    -- Mappings for tree window. See https://github.com/nvim-neo-tree/neo-tree.nvim/blob/main/lua/neo-tree/sources/filesystem/commands.lua
    -- for built-in commands. You can also create your own commands by
    -- providing a function instead of a string. See the built-in
    -- commands for examples.
    mappings = {
      ["<2-LeftMouse>"] = "open",
      ["<cr>"] = "open",
      ["S"] = "open_split",
      ["s"] = "open_vsplit",
      ["<bs>"] = "navigate_up",
      ["."] = "set_root",
      ["R"] = "refresh",
      --["/"] = "filter_as_you_type",
      --["f"] = "filter_on_submit",
      --["<C-x>"] = "clear_filter",
    }
  },
  bind_to_cwd = true,
  before_render = function(state)
    -- This function is called after the file system has been scanned,
    -- but before the tree is rendered. You can use this to gather extra
    -- data that can be used in the renderers.
    local utils = require("neo-tree.utils")
    state.git_status_lookup = utils.get_git_status()
  end,
-- This section provides the renderers that will be used to render the tree.
-- The first level is the node type.
-- For each node type, you can specify a list of components to render.
-- Components are rendered in the order they are specified.
-- The first field in each component is the name of the function to call.
-- The rest of the fields are passed to the function as the "config" argument.
  renderers = {
    directory = {
      {
        "icon",
        folder_closed = "",
        folder_open = "",
        padding = " ",
      },
      { "name" },
    },
    file = {
      {
        "icon",
        default = "*",
        padding = " ",
      },
      { "name" },
      { "bufnr" },
      { "git_status", highlight = highlights.DIM_TEXT },
    },
  }
}

return filesystem