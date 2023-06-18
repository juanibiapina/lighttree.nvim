# Neo-tree.nvim

Neo-tree is a Neovim plugin to browse the file system and other tree like
structures in whatever style suits you, including sidebars, floating windows,
netrw split style, or all of them at once!

![Neo-tree file system](https://github.com/nvim-neo-tree/resources/blob/main/images/Neo-tree-with-right-aligned-symbols.png)

## Minimal Quickstart

#### Minimal Example for Packer:
```lua
use {
  "nvim-neo-tree/neo-tree.nvim",
    branch = "v2.x",
    requires = { 
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
      "MunifTanjim/nui.nvim",
    }
  }
```

After installing, run:
```
:Neotree
```

Press `?` in the Neo-tree window to view the list of mappings.


## Quickstart

#### Longer Example for Packer:
  
```lua
use {
  "nvim-neo-tree/neo-tree.nvim",
    branch = "v2.x",
    requires = { 
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
      "MunifTanjim/nui.nvim",
      {
        tag = "v1.*",
        config = function()
          require'window-picker'.setup({
            autoselect_one = true,
            include_current = false,
            filter_rules = {
              -- filter using buffer options
              bo = {
                -- if the file type is one of following, the window will be ignored
                filetype = { 'neo-tree', "neo-tree-popup", "notify" },

                -- if the buffer type is one of following, the window will be ignored
                buftype = { 'terminal', "quickfix" },
              },
            },
            other_win_hl_color = '#e35e4f',
          })
        end,
      }
    },
    config = function ()
      -- If you want icons for diagnostic errors, you'll need to define them somewhere:
      vim.fn.sign_define("DiagnosticSignError",
        {text = " ", texthl = "DiagnosticSignError"})
      vim.fn.sign_define("DiagnosticSignWarn",
        {text = " ", texthl = "DiagnosticSignWarn"})
      vim.fn.sign_define("DiagnosticSignInfo",
        {text = " ", texthl = "DiagnosticSignInfo"})
      vim.fn.sign_define("DiagnosticSignHint",
        {text = "", texthl = "DiagnosticSignHint"})
      -- NOTE: this is changed from v1.x, which used the old style of highlight groups
      -- in the form "LspDiagnosticsSignWarning"

      require("neo-tree").setup({
        popup_border_style = "rounded",
        enable_git_status = true,
        enable_diagnostics = true,
        default_component_configs = {
          container = {
            enable_character_fade = true
          },
          indent = {
            indent_size = 2,
            padding = 1, -- extra padding on left hand side
            -- indent guides
            with_markers = true,
            indent_marker = "│",
            last_indent_marker = "└",
            highlight = "NeoTreeIndentMarker",
            -- expander config, needed for nesting files
            with_expanders = nil, -- if nil and file nesting is enabled, will enable expanders
            expander_collapsed = "",
            expander_expanded = "",
            expander_highlight = "NeoTreeExpander",
          },
          icon = {
            folder_closed = "",
            folder_open = "",
            folder_empty = "ﰊ",
            -- The next two settings are only a fallback, if you use nvim-web-devicons and configure default icons there
            -- then these will never be used.
            default = "*",
            highlight = "NeoTreeFileIcon"
          },
          modified = {
            symbol = "[+]",
            highlight = "NeoTreeModified",
          },
          name = {
            trailing_slash = false,
            use_git_status_colors = true,
            highlight = "NeoTreeFileName",
          },
          git_status = {
            symbols = {
              -- Change type
              added     = "", -- or "✚", but this is redundant info if you use git_status_colors on the name
              modified  = "", -- or "", but this is redundant info if you use git_status_colors on the name
              deleted   = "✖",-- this can only be used in the git_status source
              renamed   = "",-- this can only be used in the git_status source
              -- Status type
              untracked = "",
              ignored   = "",
              unstaged  = "",
              staged    = "",
              conflict  = "",
            }
          },
        },
        commands = {},
        window = {
          width = 40,
          mapping_options = {
            noremap = true,
            nowait = true,
          },
          mappings = {
            ["<cr>"] = "open",
            ["C"] = "close_node",
            -- ['C'] = 'close_all_subnodes',
            ["z"] = "close_all_nodes",
            --["Z"] = "expand_all_nodes",
            ["a"] = { 
              "add",
              -- this command supports BASH style brace expansion ("x{a,b,c}" -> xa,xb,xc). see `:h neo-tree-file-actions` for details
              -- some commands may take optional config options, see `:h neo-tree-mappings` for details
              config = {
                show_path = "none" -- "none", "relative", "absolute"
              }
            },
            ["A"] = "add_directory", -- also accepts the optional config.show_path option like "add". this also supports BASH style brace expansion.
            ["d"] = "delete",
            ["r"] = "rename",
            ["y"] = "copy_to_clipboard",
            ["x"] = "cut_to_clipboard",
            ["p"] = "paste_from_clipboard",
            ["c"] = "copy", -- takes text input for destination, also accepts the optional config.show_path option like "add":
            -- ["c"] = {
            --  "copy",
            --  config = {
            --    show_path = "none" -- "none", "relative", "absolute"
            --  }
            --}
            ["m"] = "move", -- takes text input for destination, also accepts the optional config.show_path option like "add".
            ["R"] = "refresh",
            ["?"] = "show_help",
          }
        },
        hijack_netrw = true, -- netrw disabled, opening a directory opens neo-tree
                    -- false,    -- netrw left alone, neo-tree does not handle opening dirs
        filesystem = {
          filtered_items = {
            visible = false, -- when true, they will just be displayed differently than normal items
            hide_dotfiles = true,
            hide_gitignored = true,
            hide_hidden = true, -- only works on Windows for hidden files/directories
            hide_by_name = {
              --"node_modules"
            },
            hide_by_pattern = { -- uses glob style patterns
              --"*.meta",
              --"*/src/*/tsconfig.json",
            },
          },
          group_empty_dirs = false, -- when true, empty folders will be grouped together
          use_libuv_file_watcher = false, -- This will use the OS level file watchers to detect changes
                                          -- instead of relying on nvim autocmd events.
          window = {
            mappings = {
              ["<bs>"] = "navigate_up",
              ["."] = "set_root",
              ["H"] = "toggle_hidden",
              ["[g"] = "prev_git_modified",
              ["]g"] = "next_git_modified",
            },
          },

          commands = {} -- Add a custom command or override a global one using the same function name
        },
      })

      vim.cmd([[nnoremap \ :Neotree reveal<cr>]])
    end
}
```

_The above configuration is not everything that can be changed, it's just the
parts you might want to change first._


See `:h neo-tree` for full documentation. You can also preview that online at
[doc/neo-tree.txt](doc/neo-tree.txt), although it's best viewed within vim.


To see all of the default config options with commentary, you can view it online
at [lua/neo-tree/defaults.lua](lua/neo-tree/defaults.lua).

## The `:Neotree` Command

The single `:Neotree` command accepts a range of arguments.

Arguments can be specified as either a key=value pair or just as the value. The
key=value form is more verbose but may help with clarity.

All arguments are optional and can be specified in any order. If you issue the command
without any arguments, it will use default values for everything.

### Tab Completion

Neotree supports tab completion for all arguments. Once a given argument has a value,
it will stop suggesting those completions. It will also offer completions for paths.
The simplest way to disambiguate a path from another type of argument is to start
them with `/` or `./`.

### Arguments

Here is the full list of arguments you can use:

#### `dir`
The directory to set as the root/cwd of the specified window. If you include a
directory as one of the arguments, it will be assumed to be this option, you
don't need the full dir=/path. You may use any value that can be passed to the
'expand' function, such as `%:p:h:h` to specify two directories up from the
current file. For example:

```
:Neotree ./relative/path
:Neotree /home/user/relative/path
:Neotree dir=/home/user/relative/path
:Neotree dir=relative/path
```

#### `git_base`
The base that is used to calculate the git status for each dir/file.
By default it uses `HEAD`, so it shows all changes that are not yet committed.
You can for example work on a feature branch, and set it to `main`. It will
show all changes that happened on the feature branch and main since you 
branched off.

Any git ref, commit, tag, or sha will work.

```
:Neotree main
:Neotree v1.0
:Neotree git_base=8fe34be
:Neotree git_base=HEAD
```

#### `reveal`
This is a boolean flag. Adding this will make Neotree automatically find and 
focus the current file when it opens.

#### `reveal_file`
A path to a file to reveal. This supersedes the "reveal" flag so there is no
need to specify both. Use this if you want to reveal something other than the
current file. If you include a path to a file as one of the arguments, it will
be assumed to be this option. Like "dir", you can pass any value that can be
passed to the 'expand' function. For example:

```
:Neotree reveal_file=/home/user/my/file.text
:Neotree dir=%:p:h:h reveal_file=%:p
:Neotree %:p:h:h %:p
```

One neat trick you can do with this is to open a Neotree window which is
focused on the file under the cursor using the `<cfile>` keyword:

```
nnoremap gd :Neotree float reveal_file=<cfile>
```

See `:h neo-tree-commands` for details and a full listing of available arguments.


### Netrw Hijack

```
:edit .
:[v]split .
```

Any command that would open a directory will now open neo-tree in the specified
window.
