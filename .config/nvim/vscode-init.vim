let g:ale_emit_conflict_warnings = 0

" cspell:disable

""""""""""""""""" Plugins Setup """"""""""""""""""""""""""""""""

" Disable javascript/jsx from polyglot, must be before polyglot loads
let g:polyglot_disabled = ['jsx', 'javascript']

call plug#begin('~/.local/share/nvim/plugged')

Plug 'vim-ruby/vim-ruby'
Plug 'kana/vim-textobj-user'
Plug 'kana/vim-textobj-function'
Plug 'haya14busa/vim-textobj-function-syntax'
Plug 'bkad/CamelCaseMotion'
Plug 'AndrewRadev/splitjoin.vim'
Plug 'tpope/vim-commentary'
Plug 'xolox/vim-misc'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-unimpaired'
Plug 'jlanzarotta/bufexplorer'
Plug 'machakann/vim-highlightedyank'
Plug 'sheerun/vim-polyglot'
Plug 'andymass/vim-matchup'
Plug 'tpope/vim-abolish'

" Plug 'mustache/vim-mustache-handlebars'
" Plug 'triglav/vim-visual-increment'
" Plug 'tpope/vim-rhubarb'
" Plug 'tpope/vim-endwise'
" Plug 'nelstrom/vim-textobj-rubyblock'
" Plug 'vim-scripts/UnconditionalPaste'
" Plug 'Shougo/neomru.vim'
" Plug 'Shougo/neoyank.vim'
" Plug 'godlygeek/tabular'
" Plug 'ntpeters/vim-better-whitespace' " Doesn't do anything
" Plug 'tommcdo/vim-exchange'
" Plug 'terryma/vim-expand-region'
" Plug 'tpope/vim-fugitive'
" Plug 'wizicer/vim-jison'
" Plug 'elzr/vim-json'
" Plug 'plasticboy/vim-markdown'
" Plug 'tomtom/tcomment_vim'
" Plug 'pangloss/vim-javascript'
" Plug 'mxw/vim-jsx'
" Plug 'othree/javascript-libraries-syntax.vim'
" Plug 'vim-scripts/JavaScript-Indent'
" Plug 'Raimondi/delimitMate' " Trying this instead of auto-pairs for TabNine compatability
" Disabling syntax and expensive plugins (already have a bunch missing)
" Plug 'mityu/vim-applescript'
" Plug 'airblade/vim-gitgutter'
" Plug 'mr-ubik/vim-hackerman-syntax'
" Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }
" Plug 'dracula/vim', { 'as': 'dracula-vim' }
" Plug 'thinca/vim-unite-history'
" Plug 'honza/vim-snippets'
" Plug 'nathanaelkane/vim-indent-guides'
" Plug 'Lokaltog/vim-easymotion'
" Plug 'altercation/vim-colors-solarized'
" Plug 'exu/pgsql.vim'
" Plug 'bruschill/madeofcode'

call plug#end()

syntax on

""""""""""""""" Global Setup """"""""""""""""""""
"First source the environment location
source $HOME/.eihooks/dotfiles/vimrc

set ic                               " Ignore case when searching by default, in vscode this must be set in additiont to smartcase
set background=dark                  " Tell vim that I'm using a dark background terminal
"set fo+=cqr                           " q: gq foramts with comments, see :help fo-table, r: auto insert comments on new lines
set foldcolumn=0                     " turn off the foldcolumn
set history=200                      " Remember 100 lines of history, for commands and searches
set hls                              " highlight search terms
" set list                             " Show tabs differently
set nolist                           " Do not show tabs different (*sigh* go)
set listchars=tab:>-                 " Use >--- for tabs
set nolinebreak                      " don't wrap at words, messes up copying
set smartcase                        " if any capitol in search, turns search case sensitive
set shiftwidth=2                     " use 2 space indenting
set softtabstop=2                    " really use 2 space indenting
set ts=2                             " Default to 2 spaces for tabs
set tags=./.tags                     " Setup the standard tags files
"set textwidth=120                      " turn wrapping off
set visualbell                       " Use a flash instead of a sound for bells
set wildmode=longest:full            " Matches only to longest filename, displays to menu possible matches
set complete=.,w,b,u                 " complete from current file, and current buffers default: .,w,b,u,t,i  trying to keep down completion time
set directory=$HOME/.config/nvim/tmp " set directory for tmp files to be in .vim, so that .swp files are not littered
set updatetime=250                   " In ms, how often to update gitgutter and swap file
set lazyredraw                       " Turn on lazy redraw, don't redraw during macros
set splitright                       " When splitting windows vertically, new window is on right instead of left
set splitbelow                       " When splitting horiztonally, new file is on bottom
set ttimeoutlen=30                   " timeout on key-codes after 30ms (shorter than ei)
set inccommand=nosplit               " Increment display of s commands (maybe others in future)
set completeopt=menu,preview,noinsert " Do not auto-insert completions
scriptencoding utf-8                 " Use utf-8 to encode vimscript (so that options key maps can work)
set clipboard=unnamed                " Use the system clipboard for yanking and pasting
set nospell                          " Turn off spell checking

let g:clipboard = g:vscode_clipboard " Use the vscode clipboard for yanking and pasting

" set signcolumn=yes                   " Always display the notes column for ALE/gitgutter
" set omnifunc=syntaxcomplete#Complete " Turn on omni completion
" set mouse=                           " Turn off mouse support, don't want it in terminal

let g:vimsyn_embed = 'lPr' " Enable embedded lua / python/ ruby in VIML files

" colorscheme dracula " current colorscheme

"set foldmethod=indent   " use indent unless overridden
"set foldlevel=0         " show contents of all folds
"set foldcolumn=2        " set a column incase we need it
set foldlevelstart=9999

filetype plugin on          "turns on filetype plugin, lets matchit work well
filetype plugin indent on

" Set the vim info options
" In order: local marks for N files are saved, global marks are saved,
" a maximum of 500 lines for each register is saved,
" command history number, search history number,
" restore the buffer list and restore global variables

"if so that older versions of vim won't barf on standard systems
if (v:version >= 603)
  set viminfo='1000,f1,<500,:100,/100,%,!
endif

" Open a the quickfix window after any grep-style event
autocmd QuickFixCmdPost *grep* cwindow

" --------------------------- Key Mappings ---------------------------

" Map <leader>vr to vscode rename
nmap <leader>vr <Cmd>lua require('vscode-neovim').action('editor.action.rename')<CR>

" Map <leader>gi to vscode go to implementation
nmap gi <Cmd>lua require('vscode-neovim').action('editor.action.goToImplementation')<CR>

" Map <leader>gd to vscode go to definition
nmap gd <Cmd>lua require('vscode-neovim').action('editor.action.goToDefinition')<CR>

" Map <leader>h to showHover
nmap <leader>h <Cmd>lua require('vscode-neovim').action('editor.action.showHover')<CR>

" Map <leader>sn to focusNextSearchResult
nmap <leader>sn <Cmd>lua require('vscode-neovim').action('editor.action.focusNextSearchResult')<CR>

" Map <leader>sp to focusPreviousSearchResult
nmap <leader>sp <Cmd>lua require('vscode-neovim').action('editor.action.focusPreviousSearchResult')<CR>

" Map <leader>ei to edit the vscode-init.vim file
nmap <leader>vi <Cmd>e $HOME/.config/nvim/vscode-init.vim<CR>

" map <leader>ul to search for the current word under the cursor
nmap <leader>ul viw<Cmd>lua require('vscode-neovim').action('workbench.action.findInFiles')<CR>

" map ]c to go to next git change
nmap ]c <Cmd>lua require('vscode-neovim').action('workbench.action.editor.nextChange')<CR>

" map [c to go to previous git change
nmap [c <Cmd>lua require('vscode-neovim').action('workbench.action.editor.previousChange')<CR>

" Copy entire file with <Leader>ca
map <Leader>ca maggVGy`a

" make gq work
map gq <Cmd>lua require('vscode-neovim').action('rewrap.rewrapComment')<CR>

" Navigation keybinds, from https://medium.com/@shaikzahid0713/integrate-neovim-inside-vscode-5662d8855f9d
  nnoremap <silent> <C-j> :call VSCodeNotify('workbench.action.navigateDown')<CR>
  xnoremap <silent> <C-j> :call VSCodeNotify('workbench.action.navigateDown')<CR>
  nnoremap <silent> <C-k> :call VSCodeNotify('workbench.action.navigateUp')<CR>
  xnoremap <silent> <C-k> :call VSCodeNotify('workbench.action.navigateUp')<CR>
  nnoremap <silent> <C-h> :call VSCodeNotify('workbench.action.navigateLeft')<CR>
  xnoremap <silent> <C-h> :call VSCodeNotify('workbench.action.navigateLeft')<CR>
  nnoremap <silent> <C-l> :call VSCodeNotify('workbench.action.navigateRight')<CR>
  xnoremap <silent> <C-l> :call VSCodeNotify('workbench.action.navigateRight')<CR>

  nnoremap <silent> <C-w>_ :<C-u>call VSCodeNotify('workbench.action.toggleEditorWidths')<CR>

  nnoremap <silent> <Space> :call VSCodeNotify('whichkey.show')<CR>
  xnoremap <silent> <Space> :call VSCodeNotify('whichkey.show')<CR>

" Add commands for copying current buffer's location
command CopyPath let @* = expand("%")
command CopyFullPath let @* = expand("%:p")
command CopyFilename let @* = expand("%:t")
command CopyFile CopyFilename

nmap <Leader>cfn <Cmd>CopyFilename<CR>
nmap <Leader>cfp <Cmd>CopyFullPath<CR>

" map ]s to go to next problem
nmap ]s <Cmd>lua require('vscode-neovim').action('editor.action.marker.next')<CR>

" map [s to go to previous problem
nmap [s <Cmd>lua require('vscode-neovim').action('editor.action.marker.prev')<CR>

" Make Y work like C, D (to the end of the line)
" Not working?!?
nnoremap Y y$

" Make \tp toggle paste mode
nmap \tp :set paste!<CR>

" Mapping for quick fix window controls
map <Leader>cn :cnext<CR>
map <Leader>cp :cprev<CR>
map <Leader>cc :cclose<CR>

if filereadable("/Users/bernard/homebrew/bin/python3")
  let g:python3_host_prog="/Users/bernard/homebrew/bin/python3"
elseif filereadable("/usr/local/bin/python3")
  let g:python3_host_prog="/usr/local/bin/python3"
elseif filereadable("/usr/bin/python3")
  let g:python3_host_prog="/usr/bin/python3"
endif

""""""""""""""" Plugin Settings """"""""""""""""

" Setup for vim-expand-region
  vmap v <Plug>(expand_region_expand)
  vmap <C-v> <Plug>(expand_region_shrink)

" javascript-libraries-syntax settings
  let g:used_javascript_libs = 'underscore,backbone,jquery'

" splitjoin settings
  let g:splitjoin_split_mapping = ''
  let g:splitjoin_join_mapping = ''

  nmap <Leader>j :SplitjoinJoin<cr>
  nmap <Leader>s :SplitjoinSplit<cr>

"Buff explorer settings
  let g:bufExplorerSplitOutPathName=-1 " Don't split the path and file name.

" Large file settings in MB
  let g:LargeFile = 4

" EasyMotion settings
  " Use - as the leader for EasyMotion
  let g:EasyMotion_leader_key = '\|'

" Setup CamelCaseMotion
  call camelcasemotion#CreateMotionMappings(',')
  
" Disable some matchup functionality
" It causes vscode to insert random characters when typing
let g:matchup_matchparen_enabled = 0
let g:matchup_motion_enabled = 1
let g:matchup_text_obj_enabled = 1


""""""""""""""" Typos """"""""""""""""""""
" A list of iabbrev to correct common typos

iabbrev colleicton collection
iabbrev Colleicton Collection
iabbrev restaurnt restaurant
iabbrev restauarnt restaurant
iabbrev colleciton collection
iabbrev shoudl should
iabbrev coudl could
iabbrev teh the

set nospell

syntax on
