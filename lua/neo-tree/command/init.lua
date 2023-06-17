local parser = require("neo-tree.command.parser")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")
local utils = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")
local inputs = require("neo-tree.ui.inputs")
local completion = require("neo-tree.command.completion")
local handle_reveal

local M = {
  complete_args = completion.complete_args,
}

---Opens the Lighttree window
---@param args table The table can have the following keys:
---  reveal = boolean  Whether to reveal the current file in the Neo-tree window.
---  reveal_file = string The specific file to reveal.
---  dir = string      The root directory to set.
---  git_base = string The git base used for diff
M.execute = function(args)
  -- get current window
  local winid = vim.api.nvim_get_current_win()

  -- Get the correct state
  local state = manager.get_state("filesystem", nil, winid)

  -- Handle setting directory if requested
  local path_changed = false
  if utils.truthy(args.dir) then
    if #args.dir > 1 and args.dir:sub(-1) == utils.path_separator then
      args.dir = args.dir:sub(1, -2)
    end
    path_changed = state.path ~= args.dir
  else
    args.dir = state.path
  end

  -- Handle setting git ref
  local git_base_changed = state.git_base ~= args.git_base
  if utils.truthy(args.git_base) then
    state.git_base = args.git_base
  end

  -- Handle reveal logic
  local do_reveal = utils.truthy(args.reveal_file)
  if args.reveal and not do_reveal then
    args.reveal_file = manager.get_path_to_reveal()
    do_reveal = utils.truthy(args.reveal_file)
  end

  if do_reveal then
    handle_reveal(args, state)
  end

  manager.navigate(state, args.dir, args.reveal_file, nil, false)
end

---Parses and executes the command line. Use execute(args) instead.
---@param ... string Argument as strings.
M._command = function(...)
  local args = parser.parse({ ... }, true)
  M.execute(args)
end

handle_reveal = function(args, state)
  -- Deal with cwd if we need to
  local cwd = state.path
  if cwd == nil then
    cwd = manager.get_cwd(state)
  end

  -- Handle files outside cwd
  if not utils.is_subpath(cwd, args.reveal_file) then
    cwd, _ = utils.split_path(args.reveal_file)
    inputs.confirm("File not in cwd. Change cwd to " .. cwd .. "?", function(response)
      if response == true then
        args.dir = cwd
      else
        args.reveal_file = nil
      end
    end)
  end
end

return M
