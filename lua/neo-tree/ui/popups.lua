local vim = vim
local Input = require("nui.input")
local NuiText = require("nui.text")
local NuiPopup = require("nui.popup")
local highlights = require("neo-tree.ui.highlights")
local log = require("neo-tree.log")

local M = {}

M.popup_options = function(title, min_width, override_options)
  local min_width = min_width or 30
  local width = string.len(title) + 2

  local nt = require("neo-tree")
  local popup_border_style = nt.config.popup_border_style
  local popup_border_text = NuiText(" " .. title .. " ", highlights.FLOAT_TITLE)
  local col = 0
  -- fix popup position when using multigrid
  local popup_last_col = vim.api.nvim_win_get_position(0)[2] + width + 2
  if popup_last_col >= vim.o.columns then
    col = vim.o.columns - popup_last_col
  end
  local popup_options = {
    ns_id = highlights.ns_id,
    relative = "cursor",
    position = {
      row = 1,
      col = col,
    },
    size = width,
    border = {
      text = {
        top = popup_border_text,
      },
      style = popup_border_style,
      highlight = highlights.FLOAT_BORDER,
    },
    win_options = {
      winhighlight = "Normal:"
        .. highlights.FLOAT_NORMAL
        .. ",FloatBorder:"
        .. highlights.FLOAT_BORDER,
    },
    buf_options = {
      bufhidden = "delete",
      buflisted = false,
      filetype = "neo-tree-popup",
    },
  }

  if popup_border_style == "NC" then
    local blank = NuiText(" ", highlights.TITLE_BAR)
    popup_border_text = NuiText(" " .. title .. " ", highlights.TITLE_BAR)
    popup_options.border = {
      style = { "▕", blank, "▏", "▏", " ", "▔", " ", "▕" },
      highlight = highlights.FLOAT_BORDER,
      text = {
        top = popup_border_text,
        top_align = "left",
      },
    }
  end

  if override_options then
    return vim.tbl_extend("force", popup_options, override_options)
  else
    return popup_options
  end
end

return M
