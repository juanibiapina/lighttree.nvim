local M = {}

M.input = function(message, default_value, callback, options, completion)
  local opts = {
    prompt = message .. " ",
    default = default_value,
  }
  if completion then
    opts.completion = completion
  end
  vim.ui.input(opts, callback)
end

M.confirm = function(message, callback)
  local opts = {
    prompt = message .. " y/n: ",
  }
  vim.ui.input(opts, function(value)
    callback(value == "y" or value == "Y")
  end)
end

return M
