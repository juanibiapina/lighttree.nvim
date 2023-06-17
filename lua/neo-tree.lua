local vim = vim
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local setup = require("neo-tree.setup")

local M = {}

M.get_prior_window = function(ignore_filetypes)
  ignore_filetypes = ignore_filetypes or {}
  local ignore = utils.list_to_dict(ignore_filetypes)
  ignore["neo-tree"] = true

  local tabid = vim.api.nvim_get_current_tabpage()
  local wins = utils.get_value(M, "config.prior_windows", {}, true)[tabid]
  if wins == nil then
    return -1
  end
  local win_index = #wins
  while win_index > 0 do
    local last_win = wins[win_index]
    if type(last_win) == "number" then
      local success, is_valid = pcall(vim.api.nvim_win_is_valid, last_win)
      if success and is_valid then
        local buf = vim.api.nvim_win_get_buf(last_win)
        local ft = vim.api.nvim_buf_get_option(buf, "filetype")
        local bt = vim.api.nvim_buf_get_option(buf, "buftype") or "normal"
        if ignore[ft] ~= true and ignore[bt] ~= true then
          return last_win
        end
      end
    end
    win_index = win_index - 1
  end
  return -1
end

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
