" Setup for dein plugin manager by shuogo

" Required:

" Required:
call dein#begin(expand($HOME . '/.config/nvim/dein-plugins'))

" Let dein manage dein
call dein#add('Shougo/dein.vim')
call dein#add('Shougo/deoplete.nvim')
" call dein#add('ternjs/tern_for_vim', {'build': 'npm install'})
" call dein#add('carlitux/deoplete-ternjs', {'build': 'npm install -g tern'})

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

