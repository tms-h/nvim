" A clipboard that lives in this Neovim only, so tests never reach the
" desktop's clipboard (env.sh also hides the desktop display).
let g:clipboard = {
      \ 'name': 'test-memory',
      \ 'copy': {
      \   '+': {lines, regtype -> extend(g:, {'test_clip': [lines, regtype]})},
      \   '*': {lines, regtype -> extend(g:, {'test_clip': [lines, regtype]})},
      \ },
      \ 'paste': {
      \   '+': {-> get(g:, 'test_clip', [])},
      \   '*': {-> get(g:, 'test_clip', [])},
      \ },
      \ }
