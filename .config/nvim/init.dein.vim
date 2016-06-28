" Setup for dein plugin manager by shuogo

" Required:
set runtimepath^=.config/nvim/dein-plugins/repos/github.com/Shougo/dein.vim

" Required:
call dein#begin(expand('.config/nvim/dein-plugins'))

" Let dein manage dein
call dein#add('Shougo/dein.vim')
call dein#add('Shougo/deoplete.nvim')

" Required:
call dein#end()

" Required:
filetype plugin indent on

" If you want to install not installed plugins on startup.
if dein#check_install()
  call dein#install()
endif

" EXAMPLES:
" Add or remove your plugins here:
" call dein#add('Shougo/neosnippet.vim')
" call dein#add('Shougo/neosnippet-snippets')

" You can specify revision/branch/tag.
" call dein#add('Shougo/vimshell', { 'rev': '3787e5' })

