local vim = vim
local q = require("neo-tree.events.queue")
local log = require("neo-tree.log")
local utils = require("neo-tree.utils")

local M = {
  FS_EVENT = "fs_event",
  GIT_EVENT = "git_event",
  GIT_STATUS_CHANGED = "git_status_changed",
  VIM_BUFFER_ENTER = "vim_buffer_enter",
  VIM_COLORSCHEME = "vim_colorscheme",
  VIM_DIR_CHANGED = "vim_dir_changed",
  VIM_LEAVE = "vim_leave",
  VIM_RESIZED = "vim_resized",
  VIM_WIN_ENTER = "vim_win_enter",
}

M.define_autocmd_event = function(event_name, autocmds, debounce_frequency, nested)
  local opts = {
    setup = function()
      local tpl =
        ":lua require('neo-tree.events').fire_event('%s', { afile = vim.fn.expand('<afile>') })"
      local callback = string.format(tpl, event_name)
      if nested then
        callback = "++nested " .. callback
      end

      local autocmd = table.concat(autocmds, ",")
      if not vim.startswith(autocmd, "User") then
        autocmd = autocmd .. " *"
      end
      local cmds = {
        "augroup NeoTreeEvent_" .. event_name,
        "autocmd " .. autocmd .. " " .. callback,
        "augroup END",
      }
      log.trace("Registering autocmds: %s", table.concat(cmds, "\n"))
      vim.cmd(table.concat(cmds, "\n"))
    end,
    teardown = function()
      log.trace("Teardown autocmds for ", event_name)
      vim.cmd(string.format("autocmd! NeoTreeEvent_%s", event_name))
    end,
    debounce_frequency = debounce_frequency,
    debounce_strategy = utils.debounce_strategy.CALL_LAST_ONLY,
  }
  log.debug("Defining autocmd event: %s", event_name)
  q.define_event(event_name, opts)
end

M.clear_all_events = q.clear_all_events
M.define_event = q.define_event
M.destroy_event = q.destroy_event
M.fire_event = q.fire_event

M.subscribe = q.subscribe
M.unsubscribe = q.unsubscribe

return M
