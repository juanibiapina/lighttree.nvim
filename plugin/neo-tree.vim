if exists('g:loaded_neo_tree')
  finish
endif
let g:loaded_neo_tree = 1

command! -nargs=* -complete=custom,v:lua.require'neo-tree.command'.complete_args
            \ Lighttree lua require("neo-tree.command")._command(<f-args>)
