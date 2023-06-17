--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local renderer = require("neo-tree.ui.renderer")
local inputs = require("neo-tree.ui.inputs")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local fs_watch = require("neo-tree.sources.filesystem.lib.fs_watch")

local M = {}
local source_data = {}
local all_states = {}
local default_configs = {}

local get_source_data = function()
  source_name = "filesystem"

  local sd = source_data[source_name]
  if sd then
    return sd
  end
  sd = {
    name = source_name,
    state_by_tab = {},
    state_by_win = {},
    subscriptions = {},
  }
  source_data[source_name] = sd
  return sd
end

local function create_state(tabid, sd, winid)
  local default_config = default_configs[sd.name]
  local state = vim.deepcopy(default_config, { noref = 1 })
  state.tabid = tabid
  state.winid = winid
  state.id = winid or tabid
  state.dirty = true
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
  local sd = get_source_data()
  for tabid, tab_config in pairs(sd.state_by_tab) do
    sd.state_by_tab[tabid] = vim.tbl_deep_extend("force", tab_config, config)
  end
end

--TODO: we need to track state per window when working with netwrw style "current"
--position. How do we know which one to return when this is called?
M.get_state = function(tabid, winid)
  tabid = tabid or vim.api.nvim_get_current_tabpage()
  local sd = get_source_data()
  if type(winid) == "number" then
    local win_state = sd.state_by_win[winid]
    if not win_state then
      win_state = create_state(tabid, sd, winid)
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
      tab_state = create_state(tabid, sd)
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
  local sd = get_source_data()
  if not sd.subscriptions then
    sd.subscriptions = {}
  end
  if not utils.truthy(event.id) then
    event.id = sd.name .. "." .. event.event
  end
  log.trace("subscribing to event: " .. event.id)
  sd.subscriptions[event] = true
  events.subscribe(event)
end

M.unsubscribe = function(source_name, event)
  if source_name == nil then
    error("unsubscribe: source_name cannot be nil")
  end
  local sd = get_source_data()
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
  local sd = get_source_data()
  if sd.subscriptions then
    for event, subscribed in pairs(sd.subscriptions) do
      if subscribed then
        events.unsubscribe(event)
      end
    end
  end
  sd.subscriptions = {}
end

---Redraws the tree with updated diagnostics without scanning the filesystem again.
M.diagnostics_changed = function(source_name, args)
  if not type(args) == "table" then
    error("diagnostics_changed: args must be a table")
  end
  M._for_each_state(source_name, function(state)
    state.diagnostics_lookup = args.diagnostics_lookup
    renderer.redraw(state)
  end)
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
      state.dirty = true
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

local dispose_state = function(state)
  pcall(fs_scan.stop_watchers, state)
  pcall(renderer.close, state)
  source_data[state.name].state_by_tab[state.id] = nil
  source_data[state.name].state_by_win[state.id] = nil
end

M.dispose_invalid_tabs = function()
  -- Iterate in reverse because we are removing items during loop
  for i = #all_states,1,-1 do
    local state = all_states[i]
    -- if not valid_tabs[state.tabid] then
    if not vim.api.nvim_tabpage_is_valid(state.tabid) then
      log.trace(state.name, " disposing of tab: ", state.tabid, state.name)
      dispose_state(state)
      table.remove(all_states, i)
    end
  end
end

M.dispose_window = function(winid)
  if not winid then
    error("dispose_window: winid cannot be nil")
  end
  for i, state in ipairs(all_states) do
    if state.winid == winid then
      log.trace(state.name, " disposing of window: ", winid, state.name)
      dispose_state(state)
      table.remove(all_states, i)
    end
  end
end

---Redraws the tree with updated modified markers without scanning the filesystem again.
M.opened_buffers_changed = function(source_name, args)
  if not type(args) == "table" then
    error("opened_buffers_changed: args must be a table")
  end
  if type(args.opened_buffers) == "table" then
    M._for_each_state(source_name, function(state)
      if utils.tbl_equals(args.opened_buffers, state.opened_buffers) then
        -- no changes, no need to redraw
        return
      end
      state.opened_buffers = args.opened_buffers
      renderer.redraw(state)
    end)
  end
end

---Navigate to the given path.
---@param state_or_source_name string|table The state or source name to navigate.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
---@param path_to_reveal string Node to focus after the items are loaded.
---@param callback function Callback to call after the items are loaded.
---@param async boolean Whether to load the items asynchronously, may not be respected by all sources.
M.navigate = function(state_or_source_name, path, path_to_reveal, callback, async)
  local state, source_name
  if type(state_or_source_name) == "string" then
    state = M.get_state()
    source_name = state_or_source_name
  elseif type(state_or_source_name) == "table" then
    state = state_or_source_name
    source_name = "filesystem"
  else
    log.error("navigate: state_or_source_name must be a string or a table")
  end
  log.trace("navigate", source_name, path, path_to_reveal)
  local mod = get_source_data().module
  if not mod then
    mod = require("neo-tree.sources." .. source_name)
  end
  mod.navigate(state, path, path_to_reveal, callback, async)
end

---Redraws the tree without scanning the filesystem again. Use this after
-- making changes to the nodes that would affect how their components are
-- rendered.
M.redraw = function(source_name)
  M._for_each_state(source_name, function(state)
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
    else
      state.dirty = true
    end
  end
end

M.validate_source = function(source_name, module)
  if source_name == nil then
    error("register_source: source_name cannot be nil")
  end
  if module == nil then
    error("register_source: module cannot be nil")
  end
  if type(module) ~= "table" then
    error("register_source: module must be a table")
  end
  local required_functions = {
    "navigate",
    "setup",
  }
  for _, name in ipairs(required_functions) do
    if type(module[name]) ~= "function" then
      error("Source " .. source_name .. " must have a " .. name .. " function")
    end
  end
end

---Configures the plugin, should be called before the plugin is used.
---@param source_name string Name of the source.
---@param config table Configuration table containing merged configuration for the source.
---@param global_config table Global configuration table, shared between all sources.
---@param module table Module containing the source's code.
M.setup = function(source_name, config, global_config, module)
  log.debug(source_name, " setup ", config)
  M.unsubscribe_all(source_name)
  M.set_default_config(source_name, config)
  if module == nil then
    module = require("neo-tree.sources." .. source_name)
  end
  local success, err = pcall(M.validate_source, source_name, module)
  if success then
    success, err = pcall(module.setup, config, global_config)
    if success then
      get_source_data().module = module
    else
      log.error("Source " .. source_name .. " setup failed: " .. err)
    end
  else
    log.error("Source " .. source_name .. " is invalid: " .. err)
  end
end

return M
