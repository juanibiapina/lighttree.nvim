local vim = vim
local utils = require("neo-tree.utils")
local log = require("neo-tree.log")
local git = require("neo-tree.git")

local function sort_items(a, b)
  if a.type == b.type then
    return a.path < b.path
  else
    return a.type < b.type
  end
end

local function deep_sort(tbl, sort_func)
  if sort_func == nil then
    sort_func = sort_items
  end
  table.sort(tbl, sort_func)
  for _, item in pairs(tbl) do
    if item.type == "directory" then
      deep_sort(item.children, sort_func)
    end
  end
end

local create_item, set_parents

function create_item(context, path, _type, bufnr)
  local parent_path, name = utils.split_path(path)
  local id = path
  if path == "[No Name]" and bufnr then
    parent_path = context.state.path
    name = "[No Name]"
    id = tostring(bufnr)
  else
    -- avoid creating duplicate items
    if context.folders[path] or context.nesting[path] then
      return context.folders[path] or context.nesting[path]
    end
  end

  if _type == nil then
    local stat = vim.loop.fs_stat(path)
    _type = stat and stat.type or "unknown"
  end
  local item = {
    id = id,
    name = name,
    parent_path = parent_path,
    path = path,
    type = _type,
  }
  if item.type == "link" then
    item.is_link = true
    item.link_to = vim.loop.fs_realpath(path)
    if item.link_to ~= nil then
      item.type = vim.loop.fs_stat(item.link_to).type
    end
  end
  if item.type == "directory" then
    item.children = {}
    item.loaded = false
    context.folders[path] = item
  else
    item.base = item.name:match("^([-_,()%s%w%i]+)%.")
    item.ext = item.name:match("%.([-_,()%s%w%i]+)$")
    item.exts = item.name:match("^[-_,()%s%w%i]+%.(.*)")
  end

  item.is_reveal_target = (path == context.path_to_reveal)
  local state = context.state
  local f = state.filtered_items
  local is_not_root = not utils.is_subpath(path, context.state.path)
  if f and is_not_root then
    if f.hide_by_name[name] then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.name = true
    end
    if f.hide_dotfiles and string.sub(name, 1, 1) == "." then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.dotfiles = true
    end
    if f.hide_hidden and utils.is_hidden(path) then
      item.filtered_by = item.filtered_by or {}
      item.filtered_by.hidden = true
    end
    -- NOTE: git_ignored logic moved to job_complete
  end

  set_parents(context, item)
  if context.all_items == nil then
    context.all_items = {}
  end
  if is_not_root then
    table.insert(context.all_items, item)
  end
  return item
end

-- function to set (or create) parent folder
function set_parents(context, item)
  -- we can get duplicate items if we navigate up with open folders
  -- this is probably hacky, but it works
  if context.item_exists[item.id] then
    return
  end
  if not item.parent_path then
    return
  end

  local parent = context.folders[item.parent_path]
  if not utils.truthy(item.parent_path) then
    return
  end
  if parent == nil then
    local success
    success, parent = pcall(create_item, context, item.parent_path, "directory")
    if not success then
      log.error("error creating item for ", item.parent_path)
    end
    context.folders[parent.id] = parent
    set_parents(context, parent)
  end

  table.insert(parent.children, item)

  context.item_exists[item.id] = true

  if item.filtered_by == nil and type(parent.filtered_by) == "table" then
    item.filtered_by = vim.deepcopy(parent.filtered_by)
  end
end

---Create context to be used in other file-items functions.
---@param state table|nil The state of the file-items.
---@return table
local create_context = function(state)
  local context = {}
  -- Make the context a weak table so that it can be garbage collected
  --setmetatable(context, { __mode = 'v' })
  context.state = state
  context.folders = {}
  context.nesting = {}
  context.item_exists = {}
  context.all_items = {}
  return context
end

return {
  create_context = create_context,
  create_item = create_item,
  deep_sort = deep_sort,
}
