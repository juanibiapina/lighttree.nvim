local vim = vim
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local setup = require("neo-tree.setup")

local M = {}

M.set_log_level = function(level)
  log.set_level(level)
end

M.setup = function(config)
  M.config = require("neo-tree.setup").merge_config(config)

  local netrw = require("neo-tree.setup.netrw")
  if netrw.get_hijack_netrw() then
    vim.cmd("silent! autocmd! FileExplorer *")
    netrw.hijack()
  end
end

return M
