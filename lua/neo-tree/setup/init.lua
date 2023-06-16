local utils = require("neo-tree.utils")
local defaults = require("neo-tree.defaults")
local mapping_helper = require("neo-tree.setup.mapping-helper")
local events = require("neo-tree.events")
local log = require("neo-tree.log")
local file_nesting = require("neo-tree.sources.common.file-nesting")
local highlights = require("neo-tree.ui.highlights")
local manager = require("neo-tree.sources.manager")
local netrw = require("neo-tree.setup.netrw")

local M = {}

local normalize_mappings = function(config)
  if config == nil then
    return false
  end
  local mappings = utils.get_value(config, "window.mappings", nil)
  if mappings then
    local fixed = mapping_helper.normalize_map(mappings)
    config.window.mappings = fixed
    return true
  else
    return false
  end
end

local events_setup = false
local define_events = function()
  if events_setup then
    return
  end

  events.define_event(events.FS_EVENT, {
    debounce_frequency = 100,
    debounce_strategy = utils.debounce_strategy.CALL_LAST_ONLY,
  })

  local v = vim.version()
  local diag_autocmd = "DiagnosticChanged"
  if v.major < 1 and v.minor < 6 then
    diag_autocmd = "User LspDiagnosticsChanged"
  end
  events.define_autocmd_event(events.VIM_DIAGNOSTIC_CHANGED, { diag_autocmd }, 500, function(args)
    args.diagnostics_lookup = utils.get_diagnostic_counts()
    return args
  end)



  local update_opened_buffers = function(args)
    args.opened_buffers = utils.get_opened_buffers()
    return args
  end

  events.define_autocmd_event(events.VIM_BUFFER_ADDED, { "BufAdd" }, 200, update_opened_buffers)
  events.define_autocmd_event(
    events.VIM_BUFFER_DELETED,
    { "BufDelete" },
    200,
    update_opened_buffers
  )
  events.define_autocmd_event(events.VIM_BUFFER_ENTER, { "BufEnter", "BufWinEnter" }, 0)
  events.define_autocmd_event(
    events.VIM_BUFFER_MODIFIED_SET,
    { "BufModifiedSet" },
    0,
    update_opened_buffers
  )
  events.define_autocmd_event(events.VIM_COLORSCHEME, { "ColorScheme" }, 0)
  events.define_autocmd_event(events.VIM_CURSOR_MOVED, { "CursorMoved" }, 100)
  events.define_autocmd_event(events.VIM_DIR_CHANGED, { "DirChanged" }, 200, nil, true)
  events.define_autocmd_event(events.VIM_INSERT_LEAVE, { "InsertLeave" }, 200)
  events.define_autocmd_event(events.VIM_LEAVE, { "VimLeavePre" })
  events.define_autocmd_event(events.VIM_RESIZED, { "VimResized" }, 100)
  events.define_autocmd_event(events.VIM_TAB_CLOSED, { "TabClosed" })
  events.define_autocmd_event(events.VIM_TERMINAL_ENTER, { "TermEnter" }, 0)
  events.define_autocmd_event(events.VIM_TEXT_CHANGED_NORMAL, { "TextChanged" }, 200)
  events.define_autocmd_event(events.VIM_WIN_CLOSED, { "WinClosed" })
  events.define_autocmd_event(events.VIM_WIN_ENTER, { "WinEnter" }, 0, nil, true)

  events.define_autocmd_event(events.GIT_EVENT, { "User FugitiveChanged" }, 100)
  events.define_event(events.GIT_STATUS_CHANGED, { debounce_frequency = 0 })
  events_setup = true

  events.subscribe({
    event = events.VIM_LEAVE,
    handler = function()
      events.clear_all_events()
    end,
  })

  events.subscribe({
    event = events.VIM_RESIZED,
    handler = function()
      require("neo-tree.ui.renderer").update_floating_window_layouts()
    end,
  })
end

local prior_window_options = {}

--- Store the current window options so we can restore them when we close the tree.
--- @param winid number | nil The window id to store the options for, defaults to current window
local store_local_window_settings = function(winid)
  winid = winid or vim.api.nvim_get_current_win()
  local neo_tree_settings_applied, _ =
    pcall(vim.api.nvim_win_get_var, winid, "neo_tree_settings_applied")
  if neo_tree_settings_applied then
    -- don't store our own window settings
    return
  end
  prior_window_options[tostring(winid)] = {
    cursorline = vim.wo.cursorline,
    cursorlineopt = vim.wo.cursorlineopt,
    foldcolumn = vim.wo.foldcolumn,
    wrap = vim.wo.wrap,
    list = vim.wo.list,
    spell = vim.wo.spell,
    number = vim.wo.number,
    relativenumber = vim.wo.relativenumber,
    winhighlight = vim.wo.winhighlight,
  }
end

--- Restore the window options for the current window
--- @param winid number | nil The window id to restore the options for, defaults to current window
local restore_local_window_settings = function(winid)
  winid = winid or vim.api.nvim_get_current_win()
  -- return local window settings to their prior values
  local wo = prior_window_options[tostring(winid)]
  if wo then
    vim.wo.cursorline = wo.cursorline
    vim.wo.cursorlineopt = wo.cursorlineopt
    vim.wo.foldcolumn = wo.foldcolumn
    vim.wo.wrap = wo.wrap
    vim.wo.list = wo.list
    vim.wo.spell = wo.spell
    vim.wo.number = wo.number
    vim.wo.relativenumber = wo.relativenumber
    vim.wo.winhighlight = wo.winhighlight
    log.debug("Window settings restored")
    vim.api.nvim_win_set_var(0, "neo_tree_settings_applied", false)
  else
    log.debug("No window settings to restore")
  end
end

M.buffer_enter_event = function()
  -- if it is a neo-tree window, just set local options
  if vim.bo.filetype == "neo-tree" then
    store_local_window_settings()

    vim.cmd([[
    setlocal cursorline
    setlocal cursorlineopt=line
    setlocal nowrap
    setlocal nolist nospell nonumber norelativenumber
    ]])

    local winhighlight =
      "Normal:NeoTreeNormal,NormalNC:NeoTreeNormalNC,SignColumn:NeoTreeSignColumn,CursorLine:NeoTreeCursorLine,FloatBorder:NeoTreeFloatBorder,StatusLine:NeoTreeStatusLine,StatusLineNC:NeoTreeStatusLineNC,VertSplit:NeoTreeVertSplit,EndOfBuffer:NeoTreeEndOfBuffer"
    if vim.version().minor >= 7 then
      vim.cmd("setlocal winhighlight=" .. winhighlight .. ",WinSeparator:NeoTreeWinSeparator")
    else
      vim.cmd("setlocal winhighlight=" .. winhighlight)
    end

    vim.api.nvim_win_set_var(0, "neo_tree_settings_applied", true)
    return
  end

  if vim.bo.filetype == "neo-tree-popup" then
    vim.cmd([[
    setlocal winhighlight=Normal:NeoTreeFloatNormal,FloatBorder:NeoTreeFloatBorder
    setlocal nolist nospell nonumber norelativenumber
    ]])
    return
  end

  -- there is nothing more we want to do with floating windows
  if utils.is_floating() then
    return
  end

  -- if vim is trying to open a dir, then we hijack it
  if netrw.hijack() then
    return
  end

  -- For all others, make sure another buffer is not hijacking our window
  -- ..but not if the position is "current"
  local prior_buf = vim.fn.bufnr("#")
  if prior_buf < 1 then
    return
  end
  local winid = vim.api.nvim_get_current_win()
  local prior_type = vim.api.nvim_buf_get_option(prior_buf, "filetype")
  if prior_type == "neo-tree" then
    local success, position = pcall(vim.api.nvim_buf_get_var, prior_buf, "neo_tree_position")
    if not success then
      -- just bail out now, the rest of these lookups will probably fail too.
      return
    end

    if position == "current" then
      -- nothing to do here, files are supposed to open in same window
      return
    end

    local current_tabid = vim.api.nvim_get_current_tabpage()
    local neo_tree_tabid = vim.api.nvim_buf_get_var(prior_buf, "neo_tree_tabid")
    if neo_tree_tabid ~= current_tabid then
      -- This a new tab, so the alternate being neo-tree doesn't matter.
      return
    end
    local neo_tree_winid = vim.api.nvim_buf_get_var(prior_buf, "neo_tree_winid")
    local current_winid = vim.api.nvim_get_current_win()
    if neo_tree_winid ~= current_winid then
      -- This is not the neo-tree window, so the alternate being neo-tree doesn't matter.
      return
    end

    local bufname = vim.api.nvim_buf_get_name(0)
    log.debug("redirecting buffer " .. bufname .. " to new split")
    vim.cmd("b#")
    -- Using schedule at this point  fixes problem with syntax
    -- highlighting in the buffer. I also prevents errors with diagnostics
    -- trying to work with the buffer as it's being closed.
    vim.schedule(function()
      -- try to delete the buffer, only because if it was new it would take
      -- on options from the neo-tree window that are undesirable.
      pcall(vim.cmd, "bdelete " .. bufname)
      local fake_state = {
        window = {
          position = position,
        },
      }
      utils.open_file(fake_state, bufname)
    end)
  end
end

M.win_enter_event = function()
  local win_id = vim.api.nvim_get_current_win()
  if utils.is_floating(win_id) then
    return
  end

  if vim.o.filetype == "neo-tree" then
    local _, position = pcall(vim.api.nvim_buf_get_var, 0, "neo_tree_position")
    if position == "current" then
      -- make sure the buffer wasn't moved to a new window
      local neo_tree_winid = vim.api.nvim_buf_get_var(0, "neo_tree_winid")
      local current_winid = vim.api.nvim_get_current_win()
      local current_bufnr = vim.api.nvim_get_current_buf()
      if neo_tree_winid ~= current_winid then
        -- At this point we know that either the neo-tree window was split,
        -- or the neo-tree buffer is being shown in another window for some other reason.
        -- Sometime the split is just the first step in the process of opening somethig else,
        -- so instead of fixing this right away, we add a short delay and check back again to see
        -- if the buffer is still in this window.
        local old_state = manager.get_state("filesystem", nil, neo_tree_winid)
        vim.schedule(function()
          local bufnr = vim.api.nvim_get_current_buf()
          if bufnr ~= current_bufnr then
            -- The neo-tree buffer was replaced with something else, so we don't need to do anything.
            return
          end
          -- create a new tree for this window
          local state = manager.get_state("filesystem", nil, current_winid)
          state.path = old_state.path
          state.current_position = "current"
          local renderer = require("neo-tree.ui.renderer")
          state.force_open_folders = renderer.get_expanded_nodes(old_state.tree)
          require("neo-tree.sources.filesystem")._navigate_internal(state, nil, nil, nil, false)
        end)
        return
      end
    end
    -- it's a neo-tree window, ignore
    return
  end

  M.config.prior_windows = M.config.prior_windows or {}

  local tabid = vim.api.nvim_get_current_tabpage()
  local tab_windows = M.config.prior_windows[tabid]
  if tab_windows == nil then
    tab_windows = {}
    M.config.prior_windows[tabid] = tab_windows
  end
  table.insert(tab_windows, win_id)

  -- prune the history when it gets too big
  if #tab_windows > 100 then
    local new_array = {}
    local win_count = #tab_windows
    for i = 80, win_count do
      table.insert(new_array, tab_windows[i])
    end
    M.config.prior_windows[tabid] = new_array
  end
end

M.set_log_level = function(level)
  log.set_level(level)
end

local function merge_global_components_config(components, config)
  local indent_exists = false
  local merged_components = {}
  local do_merge

  do_merge = function(component)
    local name = component[1]
    if type(name) == "string" then
      if name == "indent" then
        indent_exists = true
      end
      local merged = { name }
      local global_config = config.default_component_configs[name]
      if global_config then
        for k, v in pairs(global_config) do
          merged[k] = v
        end
      end
      for k, v in pairs(component) do
        merged[k] = v
      end
      if name == "container" then
        for i, child in ipairs(component.content) do
          merged.content[i] = do_merge(child)
        end
      end
      return merged
    else
      log.error("component name is the wrong type", component)
    end
  end

  for _, component in ipairs(components) do
    local merged = do_merge(component)
    table.insert(merged_components, merged)
  end

  -- If the indent component is not specified, then add it.
  -- We do this because it used to be implicitly added, so we don't want to
  -- break any existing configs.
  if not indent_exists then
    local indent = { "indent" }
    for k, v in pairs(config.default_component_configs.indent or {}) do
      indent[k] = v
    end
    table.insert(merged_components, 1, indent)
  end
  return merged_components
end

local merge_renderers = function(default_config, source_default_config, user_config)
  -- This can't be a deep copy/merge. If a renderer is specified in the target it completely
  -- replaces the base renderer.

  if source_default_config == nil then
    -- first override the default config global renderer with the user's global renderers
    for name, renderer in pairs(user_config.renderers or {}) do
      log.debug("overriding global renderer for " .. name)
      default_config.renderers[name] = renderer
    end
  else
    -- then override the global renderers with the source specific renderers
    source_default_config.renderers = source_default_config.renderers or {}
    for name, renderer in pairs(default_config.renderers or {}) do
      if source_default_config.renderers[name] == nil then
        log.debug("overriding source renderer for " .. name)
        local r = {}
        -- Only copy components that exist in the target source.
        -- This alllows us to specify global renderers that include components from all sources,
        -- even if some of those components are not universal
        for _, value in ipairs(renderer) do
          if value[1] and source_default_config.components[value[1]] ~= nil then
            table.insert(r, value)
          end
        end
        source_default_config.renderers[name] = r
      end
    end

    -- if user sets renderers, completely wipe the default ones
    local source_name = source_default_config.name
    for name, _ in pairs(source_default_config.renderers) do
      local user = utils.get_value(user_config, source_name .. ".renderers." .. name)
      if user then
        source_default_config.renderers[name] = nil
      end
    end
  end
end

M.merge_config = function(user_config, is_auto_config)
  local default_config = vim.deepcopy(defaults)
  user_config = vim.deepcopy(user_config or {})

  if user_config.log_level ~= nil then
    M.set_log_level(user_config.log_level)
  end
  log.use_file(user_config.log_to_file, true)
  log.debug("setup")

  events.clear_all_events()
  define_events()

  -- Prevent accidentally opening another file in the neo-tree window.
  events.subscribe({
    event = events.VIM_BUFFER_ENTER,
    handler = M.buffer_enter_event,
  })

  -- Setup autocmd for neo-tree BufLeave, to restore window settings.
  -- This is set to happen just before leaving the window.
  -- The patterns used should ensure it only runs in neo-tree windows where position = "current"
  local augroup = vim.api.nvim_create_augroup("NeoTree_BufLeave", { clear = true })
  local bufleave = function(data)
    -- Vim patterns in autocmds are not quite precise enough
    -- so we are doing a second stage filter in lua
    local pattern = "neo%-tree [^ ]+ %[1%d%d%d%]"
    if string.match(data.file, pattern) then
      restore_local_window_settings()
    end
  end
  vim.api.nvim_create_autocmd({ "BufWinLeave" }, {
    group = augroup,
    pattern = "neo-tree *",
    callback = bufleave,
  })

  if user_config.event_handlers ~= nil then
    for _, handler in ipairs(user_config.event_handlers) do
      events.subscribe(handler)
    end
  end

  highlights.setup()

  require("neo-tree.command.parser").setup()

  -- setup the default values for all sources
  normalize_mappings(default_config)
  normalize_mappings(user_config)
  merge_renderers(default_config, nil, user_config)

  local source_name = "filesystem"
  local mod_root = "neo-tree.sources.filesystem"

  local module = require(mod_root)
  local source_default_config = default_config[source_name]
  source_default_config.components = require("neo-tree.sources.common.components")
  source_default_config.commands = require("neo-tree.sources.filesystem.commands")
  source_default_config.name = source_name

  if user_config.use_default_mappings == false then
    default_config.window.mappings = {}
    source_default_config.window.mappings = {}
  end
  -- Make sure all the mappings are normalized so they will merge properly.
  normalize_mappings(source_default_config)
  normalize_mappings(user_config[source_name])
  -- merge the global config with the source specific config
  source_default_config.window = vim.tbl_deep_extend(
    "force",
    default_config.window or {},
    source_default_config.window or {},
    user_config.window or {}
  )

  merge_renderers(default_config, source_default_config, user_config)

  -- apply the users config
  M.config = vim.tbl_deep_extend("force", default_config, user_config)

  if not M.config.enable_git_status then
    M.config.git_status_async = false
  end

  file_nesting.setup(M.config.nesting_rules)

  for name, rndr in pairs(M.config[source_name].renderers) do
    M.config[source_name].renderers[name] = merge_global_components_config(rndr, M.config)
  end
  if M.config.commands then
    M.config[source_name].commands =
      vim.tbl_extend("keep", M.config[source_name].commands or {}, M.config.commands)
  end
  manager.setup(source_name, M.config[source_name], M.config, module)
  manager.redraw(source_name)

  events.subscribe({
    event = events.VIM_COLORSCHEME,
    handler = highlights.setup,
    id = "neo-tree-highlight",
  })

  events.subscribe({
    event = events.VIM_WIN_ENTER,
    handler = M.win_enter_event,
    id = "neo-tree-win-enter",
  })

  --Dispose ourselves if the tab closes
  events.subscribe({
    event = events.VIM_TAB_CLOSED,
    handler = function(args)
      local tabnr = tonumber(args.afile)
      log.debug("VIM_TAB_CLOSED: disposing state for tabnr", tabnr)
      -- Internally we use tabids to track state but <afile> is tabnr of a tab that has already been
      -- closed so there is no way to get its tabid. Instead dispose all tabs that are no longer valid.
      -- Must be scheduled because nvim_tabpage_is_valid does not work inside TabClosed event callback.
      vim.schedule_wrap(manager.dispose_invalid_tabs)()
    end,
  })

  --Dispose ourselves if the window closes
  events.subscribe({
    event = events.VIM_WIN_CLOSED,
    handler = function(args)
      local winid = tonumber(args.afile)
      log.debug("VIM_WIN_CLOSED: disposing state for window", winid)
      manager.dispose_window(winid)
    end,
  })

  local rt = utils.get_value(M.config, "resize_timer_interval", 50, true)
  require("neo-tree.ui.renderer").resize_timer_interval = rt

  return M.config
end

return M
