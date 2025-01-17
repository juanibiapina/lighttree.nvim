--This file should have all functions that are in the public api and either set
--or read the state of this source.

local vim = vim
local utils = require("neo-tree.utils")
local fs_scan = require("neo-tree.sources.filesystem.lib.fs_scan")
local renderer = require("neo-tree.ui.renderer")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")
local git = require("neo-tree.git")

local M = {
  name = "filesystem",
}

local wrap = function(func)
  return utils.wrap(func, "filesystem")
end

M._navigate_internal = function(state, path, path_to_reveal, callback, async)
  local path_changed = false
  if not path then
    path = state.path
  end
  if path == nil then
    log.debug("navigate_internal: path is nil, using cwd")
    path = manager.get_cwd(state)
  end
  if path ~= state.path then
    log.debug("navigate_internal: path changed from ", state.path, " to ", path)
    state.path = path
    path_changed = true
  end

  if path_to_reveal then
    renderer.position.set(state, path_to_reveal)
    log.debug(
      "navigate_internal: in path_to_reveal, state.position is ",
      state.position.node_id,
      ", restorable = ",
      state.position.is.restorable
    )
    fs_scan.get_items(state, nil, path_to_reveal, callback)
  else
    local success, msg = pcall(renderer.position.save, state)
    if success then
      log.trace("navigate_internal: position saved")
    else
      log.trace("navigate_internal: FAILED to save position: ", msg)
    end
    fs_scan.get_items(state, nil, nil, callback, async)
  end

  local config = require("neo-tree").config
  if config.enable_git_status then
    git.status_async(state.path, state.git_base, config.git_status_async_options)
  end
end

---Navigate to the given path.
---@param path string Path to navigate to. If empty, will navigate to the cwd.
---@param path_to_reveal string Node to focus after the items are loaded.
---@param callback function Callback to call after the items are loaded.
M.navigate = function(state, path, path_to_reveal, callback, async)
  log.trace("navigate", path, path_to_reveal, async)
  utils.debounce("filesystem_navigate", function()
    M._navigate_internal(state, path, path_to_reveal, callback, async)
  end, utils.debounce_strategy.CALL_FIRST_AND_LAST, 100)
end

M.show_new_children = function(state, node_or_path)
  local node = node_or_path
  if node_or_path == nil then
    node = state.tree:get_node()
    node_or_path = node:get_id()
  elseif type(node_or_path) == "string" then
    node = state.tree:get_node(node_or_path)
    if node == nil then
      local parent_path, _ = utils.split_path(node_or_path)
      node = state.tree:get_node(parent_path)
      if node == nil then
        M.navigate(state, nil, node_or_path)
        return
      end
    end
  else
    node = node_or_path
    node_or_path = node:get_id()
  end

  if node.type ~= "directory" then
    return
  end

  M.navigate(state, nil, node_or_path)
end

---Configures the plugin, should be called before the plugin is used.
---@param config table Configuration table containing any keys that the user
--wants to change from the defaults. May be empty to accept default values.
M.setup = function(config, global_config)
  for _, key in ipairs({ "hide_by_name" }) do
    local list = config.filtered_items[key]
    if type(list) == "table" then
      config.filtered_items[key] = utils.list_to_dict(list)
    end
  end

  if global_config.enable_git_status then
    manager.subscribe("filesystem", {
      event = events.GIT_STATUS_CHANGED,
      handler = wrap(manager.git_status_changed),
    })
  end
end

---Expands or collapses the current node.
M.toggle_directory = function(state, node, path_to_reveal, skip_redraw, recursive)
  local tree = state.tree
  if not node then
    node = tree:get_node()
  end
  if node.type ~= "directory" then
    return
  end
  state.explicitly_opened_directories = state.explicitly_opened_directories or {}
  if node.loaded == false then
    local id = node:get_id()
    state.explicitly_opened_directories[id] = true
    renderer.position.set(state, nil)
    fs_scan.get_items(state, id, path_to_reveal, nil, false, recursive)
  elseif node:has_children() then
    local updated = false
    if node:is_expanded() then
      updated = node:collapse()
      state.explicitly_opened_directories[node:get_id()] = false
    else
      updated = node:expand()
      state.explicitly_opened_directories[node:get_id()] = true
    end
    if updated and not skip_redraw then
      renderer.redraw(state)
    end
    if path_to_reveal then
      renderer.focus_node(state, path_to_reveal)
    end
  end
end

return M
