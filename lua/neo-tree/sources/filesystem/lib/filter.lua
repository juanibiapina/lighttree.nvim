-- This file holds all code for the search function.

local vim = vim
local Input = require("nui.input")
local event = require("nui.utils.autocmd").event
local fs = require("neo-tree.sources.filesystem")
local popups = require("neo-tree.ui.popups")
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")

local M = {}

local cmds = {
  move_cursor_down = function(state, scroll_padding)
    renderer.focus_node(state, nil, true, 1, scroll_padding)
  end,

  move_cursor_up = function(state, scroll_padding)
    renderer.focus_node(state, nil, true, -1, scroll_padding)
    vim.cmd("redraw!")
  end,
}

local function create_input_mapping_handle(cmd, state, scroll_padding)
  return function()
    cmd(state, scroll_padding)
  end
end

return M
