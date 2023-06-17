local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")
local command = require("neo-tree.command")
local M = {}

M.get_hijack_netrw = function()
  local nt = require("neo-tree")
  local option = "hijack_netrw"
  local hijack_behavior = utils.get_value(nt.config, option, true, true)
  return hijack_behavior
end

M.hijack = function()
  local hijack = M.get_hijack_netrw()
  if not hijack then
    return false
  end

  -- ensure this is a directory
  local bufname = vim.api.nvim_buf_get_name(0)
  local stats = vim.loop.fs_stat(bufname)
  if not stats then
    return false
  end
  if stats.type ~= "directory" then
    return false
  end

  local winid = vim.api.nvim_get_current_win()
  local dir_bufnr = vim.api.nvim_get_current_buf()

  -- Now actually open the tree, with a very quick debounce because this may be
  -- called multiple times in quick succession.
  utils.debounce("hijack_netrw_" .. winid, function()
    -- We will want to replace the "directory" buffer with either the "alternate"
    -- buffer or a new blank one.
    local replace_with_bufnr = vim.fn.bufnr("#")

    if replace_with_bufnr > 0 then
      if vim.api.nvim_buf_get_option(replace_with_bufnr, "filetype") == "neo-tree" then
        replace_with_bufnr = -1
      end
    end

    if replace_with_bufnr > 0 then
      log.trace("Replacing buffer in netrw hijack", replace_with_bufnr)
      pcall(vim.api.nvim_win_set_buf, winid, replace_with_bufnr)
    end

    local remove_dir_buf = vim.schedule_wrap(function()
      log.trace("Deleting buffer in netrw hijack", dir_bufnr)
      pcall(vim.api.nvim_buf_delete, dir_bufnr, { force = true })
    end)

    local state = manager.get_state(nil, winid)

    require("neo-tree.sources.filesystem")._navigate_internal(state, bufname, nil, remove_dir_buf)
  end, 10, utils.debounce_strategy.CALL_LAST_ONLY)

  return true
end

return M
