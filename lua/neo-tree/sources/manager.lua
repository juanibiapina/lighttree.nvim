--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")
local inputs = require("neo-tree.ui.inputs")
local events = require("neo-tree.events")
local log = require("neo-tree.log")

local M = {}

local source_data = {
  name = "filesystem",
  state_by_tab = {},
  state_by_win = {},
  subscriptions = {},
}
local all_states = {}
local default_configs = {}

local wrap = function(func)
  return utils.wrap(func, "filesystem")
end

local function create_state(tabid, winid)
  local default_config = default_configs["filesystem"]
  local state = vim.deepcopy(default_config, { noref = 1 })
  state.tabid = tabid
  state.winid = winid
  state.id = winid
  state.position = {
    is = { restorable = false },
  }
  state.git_base = "HEAD"
  table.insert(all_states, state)
  return state
end

M._for_each_state = function(source_name, action)
  for _, state in ipairs(all_states) do
    if source_name == nil or state.name == source_name then
      action(state)
    end
  end
end

M.set_default_config = function(source_name, config)
  if source_name == nil then
    error("set_default_config: source_name cannot be nil")
  end
  default_configs[source_name] = config
  local sd = source_data
  for tabid, tab_config in pairs(sd.state_by_tab) do
    sd.state_by_tab[tabid] = vim.tbl_deep_extend("force", tab_config, config)
  end
end

--TODO: we need to track state per window when working with netwrw style "current"
--position. How do we know which one to return when this is called?
M.get_state = function(winid)
  tabid = vim.api.nvim_get_current_tabpage()
  local sd = source_data
  if type(winid) == "number" then
    local win_state = sd.state_by_win[winid]
    if not win_state then
      win_state = create_state(tabid, winid)
      sd.state_by_win[winid] = win_state
    end
    return win_state
  else
    local tab_state = sd.state_by_tab[tabid]
    if tab_state and tab_state.winid then
      -- just in case tab and window get tangled up, tab state replaces window
      sd.state_by_win[tab_state.winid] = nil
    end
    if not tab_state then
      tab_state = create_state(tabid)
      sd.state_by_tab[tabid] = tab_state
    end
    return tab_state
  end
end

M.get_path_to_reveal = function(include_terminals)
  local win_id = vim.api.nvim_get_current_win()
  local cfg = vim.api.nvim_win_get_config(win_id)
  if cfg.relative > "" or cfg.external then
    -- floating window, ignore
    return nil
  end
  if vim.bo.filetype == "neo-tree" then
    return nil
  end
  local path = vim.fn.expand("%:p")
  if not utils.truthy(path) then
    return nil
  end
  if not include_terminals and path:match("term://") then
    return nil
  end
  return path
end

M.subscribe = function(source_name, event)
  if source_name == nil then
    error("subscribe: source_name cannot be nil")
  end
  local sd = source_data
  if not sd.subscriptions then
    sd.subscriptions = {}
  end
  if not utils.truthy(event.id) then
    event.id = "filesystem." .. event.event
  end
  log.trace("subscribing to event: " .. event.id)
  sd.subscriptions[event] = true
  events.subscribe(event)
end

M.unsubscribe = function(source_name, event)
  if source_name == nil then
    error("unsubscribe: source_name cannot be nil")
  end
  local sd = source_data
  log.trace("unsubscribing to event: " .. event.id or event.event)
  if sd.subscriptions then
    for sub, _ in pairs(sd.subscriptions) do
      if sub.event == event.event and sub.id == event.id then
        sd.subscriptions[sub] = false
        events.unsubscribe(sub)
      end
    end
  end
  events.unsubscribe(event)
end

M.unsubscribe_all = function(source_name)
  if source_name == nil then
    error("unsubscribe_all: source_name cannot be nil")
  end
  local sd = source_data
  if sd.subscriptions then
    for event, subscribed in pairs(sd.subscriptions) do
      if subscribed then
        events.unsubscribe(event)
      end
    end
  end
  sd.subscriptions = {}
end

---Called by autocmds when the cwd dir is changed. This will change the root.
M.dir_changed = function(source_name)
  M._for_each_state(source_name, function(state)
    local cwd = M.get_cwd(state)
    if state.path and cwd == state.path then
      return
    end
    if renderer.window_exists(state) then
      M.navigate(state, cwd)
    else
      state.path = nil
    end
  end)
end
--
---Redraws the tree with updated git_status without scanning the filesystem again.
M.git_status_changed = function(source_name, args)
  if not type(args) == "table" then
    error("git_status_changed: args must be a table")
  end
  M._for_each_state(source_name, function(state)
    if utils.is_subpath(args.git_root, state.path) then
      state.git_status_lookup = args.git_status
      renderer.redraw(state)
    end
  end)
end

-- Vimscript functions like vim.fn.getcwd take tabpage number (tab position counting from left)
-- but API functions operate on tabpage id (as returned by nvim_tabpage_get_number). These values
-- get out of sync when tabs are being moved and we want to track state according to tabpage id.
local to_tabnr = function(tabid)
  return tabid > 0 and vim.api.nvim_tabpage_get_number(tabid) or tabid
end

local get_params_for_cwd = function(state)
  local tabid = state.tabid
  local winid = state.winid or -1

  return winid, to_tabnr(tabid)
end

M.get_cwd = function(state)
  local winid, tabnr = get_params_for_cwd(state)
  local success, cwd = false, ""
  if winid or tabnr then
    success, cwd = pcall(vim.fn.getcwd, winid, tabnr)
  end
  if success then
    return cwd
  else
    success, cwd = pcall(vim.fn.getcwd)
    if success then
      return cwd
    else
      return state.path
    end
  end
end

M.set_cwd = function(state)
  if not state.path then
    return
  end

  local winid, tabnr = get_params_for_cwd(state)

  if winid == nil and tabnr == nil then
    return
  end

  local _, cwd = pcall(vim.fn.getcwd, winid, tabnr)
  if state.path ~= cwd then
    if winid > 0 then
      vim.cmd("lcd " .. state.path)
    elseif tabnr > 0 then
      vim.cmd("tcd " .. state.path)
    else
      vim.cmd("cd " .. state.path)
    end
  end
end

M.navigate = function(state, path, path_to_reveal, callback, async)
  local mod = require("neo-tree.sources.filesystem")
  mod.navigate(state, path, path_to_reveal, callback, async)
end

---Redraws the tree without scanning the filesystem again. Use this after
-- making changes to the nodes that would affect how their components are
-- rendered.
M.redraw = function(source_name)
  M._for_each_state("filesystem", function(state)
    renderer.redraw(state)
  end)
end

---Refreshes the tree by scanning the filesystem again.
M.refresh = function(source_name, callback)
  if type(callback) ~= "function" then
    callback = nil
  end
  local current_tabid = vim.api.nvim_get_current_tabpage()
  log.trace(source_name, "refresh")
  for i = 1, #all_states, 1 do
    local state = all_states[i]
    if state.tabid == current_tabid and state.path and renderer.window_exists(state) then
      local success, err = pcall(M.navigate, state, state.path, nil, callback)
      if not success then
        log.error(err)
      end
    end
  end
end

---@param config table Configuration table containing merged configuration for the source.
---@param global_config table Global configuration table, shared between all sources.
M.setup = function(config, global_config)
  M.unsubscribe_all("filesystem")
  M.set_default_config("filesystem", config)

  local module = require("neo-tree.sources.filesystem")
  module.setup(config, global_config)

  -- Respond to git events from git_status source or Fugitive
  if global_config.enable_git_status then
    M.subscribe("filesystem", {
      event = events.GIT_EVENT,
      handler = function()
        M.refresh("filesystem")
      end,
    })
  end

  --Configure event handlers for file changes
  if config.use_libuv_file_watcher then
    M.subscribe("filesystem", {
      event = events.FS_EVENT,
      handler = wrap(M.refresh),
    })
  end

  --Configure event handlers for cwd changes
  M.subscribe("filesystem", {
    event = events.VIM_DIR_CHANGED,
    handler = wrap(M.dir_changed),
  })
end

return M
