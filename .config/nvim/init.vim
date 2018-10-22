" First setup variable for other variables
"let g:useNinjaTagList=1

" Disable ALE conflict warnings, must be before ALE load
let g:ale_emit_conflict_warnings = 0
""""""""""""""""" Plugins Setup """"""""""""""""""""""""""""""""

call plug#begin('~/.local/share/nvim/plugged')

Plug 'tpope/vim-endwise'
Plug 'vim-ruby/vim-ruby'
Plug 'kana/vim-textobj-user'
Plug 'kana/vim-textobj-function'
Plug 'nelstrom/vim-textobj-rubyblock'
Plug 'haya14busa/vim-textobj-function-syntax'
Plug 'Shougo/vimproc.vim', { 'do': 'make' }
Plug 'Shougo/unite.vim'
Plug 'bkad/CamelCaseMotion'
Plug 'vim-scripts/UnconditionalPaste'
Plug 'jiangmiao/auto-pairs'
Plug 'junegunn/fzf', { 'do': 'yes \| ./install' }
Plug 'sjl/gundo.vim'
Plug 'bruschill/madeofcode'
Plug 'Shougo/neomru.vim'
Plug 'Shougo/neoyank.vim'
Plug 'exu/pgsql.vim'
Plug 'AndrewRadev/splitjoin.vim'
Plug 'godlygeek/tabular'
Plug 'SirVer/ultisnips'
Plug 'tsukkee/unite-help'
Plug 'Shougo/unite-outline'
Plug 'Shougo/unite.vim'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'ntpeters/vim-better-whitespace'
Plug 'altercation/vim-colors-solarized'
Plug 'tpope/vim-commentary'
Plug 'Lokaltog/vim-easymotion'
Plug 'tommcdo/vim-exchange'
Plug 'terryma/vim-expand-region'
Plug 'tpope/vim-fugitive'
Plug 'airblade/vim-gitgutter'
Plug 'nathanaelkane/vim-indent-guides'
Plug 'wizicer/vim-jison'
Plug 'elzr/vim-json'
Plug 'plasticboy/vim-markdown'
Plug 'xolox/vim-misc'
Plug 'terryma/vim-multiple-cursors'
Plug 'mustache/vim-mustache-handlebars'
Plug 'tpope/vim-repeat'
Plug 'honza/vim-snippets'
Plug 'benbernard/vim-stylus'
Plug 'wavded/vim-stylus'
Plug 'tpope/vim-surround'
Plug 'tmux-plugins/vim-tmux'
Plug 'tpope/vim-unimpaired'
Plug 'thinca/vim-unite-history'
Plug 'triglav/vim-visual-increment'
Plug 'jlanzarotta/bufexplorer'
Plug '~/.config/nvim/bundle/custom-colors'
Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'junegunn/fzf.vim'
Plug 'justinmk/vim-sneak'
Plug 'machakann/vim-highlightedyank'
Plug 'tpope/vim-rhubarb'
Plug 'sheerun/vim-polyglot'
Plug 'AndrewRadev/splitjoin.vim'
Plug 'tomtom/tcomment_vim'
Plug 'pangloss/vim-javascript'
Plug 'mxw/vim-jsx'
Plug 'othree/javascript-libraries-syntax.vim'
Plug 'vim-scripts/JavaScript-Indent'
Plug 'w0rp/ale'
Plug 'prettier/vim-prettier', { 'do': 'yarn install' }
Plug 'andymass/vim-matchup'

" Disabled plugins:
" Plug 'ternjs/tern_for_vim', {'do': 'npm install'} " Doesn't seem to work well

call plug#end()

syntax on

if ( filereadable($HOME . "/.vimrc.site") )
  source $HOME/.vimrc.site
endif

""""""""""""""" Global Setup """"""""""""""""""""
"First source the environment location
source $HOME/.eihooks/dotfiles/vimrc

" Setup 256 colors
set t_Co=256

""""""""""""""" Global Options """"""""""""""""""""

colorscheme madeofcode         "changes color scheme to something that looks decent on the mac

set background=dark                  " Tell vim that I'm using a dark background terminal
set fo+=qr                           " q: gq foramts with comments, see :help fo-table, r: auto insert comments on new lines
set foldcolumn=0                     " turn off the foldcolumn
set history=200                      " Remember 100 lines of history, for commands and searches
set hls                              " highlight search terms
set list                             " Show tabs differently
set listchars=tab:>-                 " Use >--- for tabs
set nolinebreak                      " don't wrap at words, messes up copying
set smartcase                        " if any capitol in search, turns search case sensitive
set shiftwidth=2                     " use 2 space indenting
set softtabstop=2                    " really use 2 space indenting
set ts=2                             " Default to 4 spaces for tabs
set tags=./.tags,~/flexport/.tags                      " Setup the standard tags files
set textwidth=0                      " turn wrapping off
set visualbell                       " Use a flash instead of a sound for bells
set wildmode=longest:full            " Matches only to longest filename, displays to menu possible matches
set complete=.,w,b,u                 " complete from current file, and current buffers default: .,w,b,u,t,i  trying to keep down completion time
set directory=$HOME/.config/nvim/tmp " set directory for tmp files to be in .vim, so that .swp files are not littered
set omnifunc=syntaxcomplete#Complete " Turn on omni completion
set updatetime=250                   " In ms, how often to update gitgutter and swap file
set mouse=                           " Turn off mouse support, don't want it in terminal
set lazyredraw                       " Turn on lazy redraw, don't redraw during macros
set splitright                       " When splitting windows vertically, new window is on right instead of left
set splitbelow                       " When splitting horiztonally, new file is on bottom
set ttimeoutlen=30                   " timeout on key-codes after 30ms (shorter than ei)
set signcolumn=yes                   " Always display the notes column for ALE/gitgutter
set inccommand=nosplit               " Increment display of s commands (maybe others in future)
scriptencoding utf-8                 " Use utf-8 to encode vimscript (so that options key maps can work)

if (has('macunix'))
  set clipboard=unnamed                " Use the * register when a register is not specified - unifies with system clipboard!
endif

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

""""""""""""""" Status Line """"""""""""""""""""

" Set the status line
set statusline=%f\ %y%{GetStatusEx()}[b:%n]\ %{fugitive#statusline()}\ %m%r%=(%l/%L,%c%V)\ %P

" Function for getting the file format and the encoding for the status line.
function! GetStatusEx()
  let str = ' [' . &fileformat
  if has('multi_byte') && &fileencoding != ''
    let str = str . ':' . &fileencoding
  endif
  let str = str . '] '
  return str
endfunction

" Setup the status line to display the tagname, if the taglist plugin has been
" loaded
autocmd VimEnter * try
autocmd VimEnter *   call Tlist_Get_Tagname_By_Line()
autocmd VimEnter *   set statusline=%f\ %y%{GetStatusEx()}[b:%n]\ [t:%{Tlist_Get_Tagname_By_Line()}]\ %m%r%=(%l/%L,%c%V)\ %P
autocmd VimEnter *   map <silent> <Leader>tap :TlistAddFilesRecursive . *pm<CR>
autocmd VimEnter * catch
autocmd VimEnter * endt

""""""""""""""" Filetype Settings """"""""""""""""

" explicitly map file extension .t to perl syntax instead of tads
" which is auto detected by file type plug-in on
" This line should always be after file type plug-in
autocmd BufNewFile,BufRead *.t set syntax=perl

" .jake files are javascript
autocmd BufNewFile,BufRead *.jake set syntax=javascript

"Set an autocommand to turn off cindenting for mail types
au FileType mail set nocindent

" Turn off cursor line in mail
au Filetype mail  highlight! CursorLine cterm=NONE ctermbg=NONE

" Fold the headers out of view
" au FileType mail 1,/^\s*$/fold

" Correct indenting behavior for # in non C++ code (it used to force it to the
" beginning, since # starts a preprocessor line in C++, but in perl we want to
" to be at the indent level of the code)
set cinkeys-=0#
au FileType c,cpp set cinkeys+=0#

" Settings for stylus
" Keep keyword movement commands the same instead of including '-' in w,b
au FileType stylus setl iskeyword-=#,-

""""""""""""""" General speedups """"""""""""""""

" Do not display the command mode editing window on q:
map q: :q

" Setup CTRL-X to be CTRL-O.  I almost never use CTRL-X, fixes problem with
" CTRL-O sending tmux prefix
nnoremap <C-X> <C-O>

nmap <Leader>ra mb[{?function<CR>eli *<ESC>/(<CR>%/{<CR>%s}.async()<ESC>`b
nmap <Leader>rA mb[{?function<CR>el2x/(<CR>%/{<CR>%l8x`b

" Add commands for copying current buffer's location
if has("mac")
  command CopyPath let @* = expand("%")
  command CopyFullPath let @* = expand("%:p")
  command CopyFilename let @* = expand("%:t")
  command CopyFile CopyFilename
else
  " Same as above with + buffer instead of *
  command CopyPath let @+ = expand("%")
  command CopyFullPath let @+ = expand("%:p")
  command CopyFilename let @+ = expand("%:t")
  command CopyFile CopyFilename
endif

""""""""""""""" Plugin Settings """"""""""""""""
" Mustache settings
  autocmd BufNewFile,BufRead *.hbs set noai " Turn off autoindent, it gets in the way

" Vim-sneak settings
  " 2-character Sneak (default)
  nmap <Leader>z <Plug>Sneak_s
  nmap <Leader>Z <Plug>Sneak_S
  " visual-mode
  xmap <Leader>z <Plug>Sneak_s
  xmap <Leader>Z <Plug>Sneak_S

  " Let repeated 'z' or 'Z' re-invoke sneak with same args
  let g:sneak#s_next = 1

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

" vim todo settings
  autocmd BufNewFile,BufRead *.todo set foldlevelstart=0 "todo files have a fold level..
  autocmd BufNewFile,BufRead *.todo set filetype=todo " .todo files to filetype todo

  " Force folds to display
  autocmd BufNewFile,BufRead *.todo normal zX

  " map \dg to insearch daily goals todo at the end of the list
  autocmd BufNewFile,BufRead *.todo map <Leader>dg GoTODO ds {ds} Send daily goal email<ESC>

  " map tds in insert mode
  autocmd BufNewFile,BufRead *.todo iab tds <C-R>=strftime("%Y-%m-%d", localtime()+86400)<CR>
  autocmd BufNewFile,BufRead *.todo iab {tds} {<C-R>=strftime("%Y-%m-%d", localtime()+86400)<CR>}

  let g:todo_done_file = ".todo_done_log.todo" " Set file to put done tasks in
  let g:todo_browser = "open" " what browser to use to open incidents
  let g:todo_log_into_drawer = "" " Do not log timestamps of state changes
  let g:todo_log_done = 0 " Do not log timestamps of done

" calendar settings
" PrePad taken from stackoverflow:
" http://stackoverflow.com/questions/4964772/string-formatting-padding-in-vim
  function! PrePad(s,amt,...)
      if a:0 > 0
          let char = a:1
      else
          let char = ' '
      endif
      return repeat(char,a:amt - len(a:s)) . a:s
  endfunction

  function InsertCalendarDueDate(day,month,year,week,dir)
    " day   : day you actioned
    " month : month you actioned
    " year  : year you actioned
    " week  : day of week (Mo=1 ... Su=7)
    " dir   : direction of calendar
    exe 'q'
    exe 'normal A {' . a:year . '-' . PrePad(a:month, 2, '0') . '-' . PrePad(a:day, 2, '0') . '}'
  endfunction
  let calendar_action = 'InsertCalendarDueDate'

  let g:calendar_no_mappings=0 " turn off default mappings
  nmap <unique> <Leader>cal <Plug>CalendarH
  nmap <unique> <Leader>caL <Plug>CalendarV

"rcsvers.vim settings
  let g:rvSaveDirectoryType = 1 "Use single directory for all files
  let g:rvSaveDirectoryName = "$HOME/.config/nvim/tmp/RCSFiles/" "Place to save RCS files

  "Setup exlcude expressions for rcs
  "1. Mutt mail files
  "2. p4 submit descriptions
  "3. tmp files from perforce form commands
  let g:rvExcludeExpression = 'muttng-bernard-\d\+\|p4submitdesc\.txt\|\/tmp\.\d\+\.\d\+'

  let g:rvRlogOptions = '-zLT' "Display log in local timezone

"AddressComplete Settings
  "automatically address complete on exit
  let g:addressCompleteOnExit = 1

  " setup <++> in empty header fields, redefine tab to move between them
  let g:useMailFieldTabbing = 1

"Buff explorer settings
  let g:bufExplorerSplitOutPathName=-1 " Don't split the path and file name.

" Large file settings in MB
  let g:LargeFile = 4

" EasyMotion settings
  " Use - as the leader for EasyMotion
  let g:EasyMotion_leader_key = '\|'

" Session settings
  "When opened with a session, save the changes
  let g:session_autosave = 'yes'

  "When opened, use the latest session
  "let g:session_default_to_last = 'yes'

  "Auto open the last session
  let g:session_autoload = 'no'

"Ctrlp settings
  "Default to using regexes
  let g:ctrlp_regexp = 1

  " Use Ctrl-, rather than Ctrl-p
  let g:ctrlp_map = '<leader>aa'

  " Keep the cache file across restarts for faster startup
  let g:ctrlp_clear_cache_on_exit = 0

  " Setup alternate command maps TODO: why don't they display?
  nn <silent> <Leader>ab :CtrlPBuffer<CR>
  nn <silent> <Leader>aq :CtrlPQuickfix<CR>

" Setup CamelCaseMotion
  call camelcasemotion#CreateMotionMappings(',')

" Airline
  let g:airline_powerline_fonts = 1 " Use special fonts

" Disable javascript/jsx from polyglot
  let g:polyglot_disabled = ['jsx', 'javascript']

" VimPrettier settings
  let g:prettier#config#single_quote = 'false'
  let g:prettier#config#jsx_bracket_same_line = 'false'
  let g:prettier#config#arrow_parens = 'avoid'
  let g:prettier#config#trailing_comma = 'es5'

" ALE settings (on the fly linter)
  let g:ale_echo_msg_format='%severity%[%linter%] %s'

  " Map [s, s] to location jumps
  nmap [s :ALEPreviousWrap<CR>
  nmap ]s :ALENextWrap<CR>

  " Turn off html linters
  let g:ale_linters = {
  \   'html': [],
  \   'javascript': ['eslint'],
  \   'ruby': ['rubocop'],
  \}

  " Turn on prettier and eslint fixers for javascript
  let b:ale_fixers = {'javascript': ['prettier', 'eslint']}

  let g:ale_javascript_prettier_options = '--no-bracket-spacing --trailing-comma es5'

  " Let ALE fixers run on save
  let g:ale_fix_on_save = 1

  function! HandleStylintFormat(buffer, lines) abort
    " Matches patterns line the following:
    "
    " /var/folders/sh/g5y55d5j77g9b2_6lckp6lgw0000gn/T/nvimIjLLlP/9/app.styl
    " 306:9 colons warning unnecessary colon found
    let l:pattern = '^\(\d\+\):\?\(\d\+\)\?\s\+\(\S\+\)\s\+\(\S\+\)\s\+\(.\+\)$'
    let l:output = []

    for l:line in a:lines
        let l:match = matchlist(l:line, l:pattern)

        if len(l:match) == 0
            continue
        endif

        " vcol is Needed to indicate that the column is a character.
        call add(l:output, {
        \   'bufnr': a:buffer,
        \   'lnum': l:match[1] + 0,
        \   'vcol': 0,
        \   'col': l:match[2] + 1,
        \   'text': l:match[3] . ': ' . l:match[5],
        \   'type': 'E',
        \   'nr': -1,
        \})
    endfor

    return l:output
  endfunction

  " Add stylint linker
  call ale#linter#Define('stylus', {
        \   'name': 'stylint',
        \   'executable': 'stylint',
        \   'command': 'stylint %t',
        \   'callback': 'HandleStylintFormat',
        \})

" Gundo Settings
  nmap <Leader>gu :GundoToggle<CR>

""""""""""""""" Command mappings """"""""""""""""

"Map statements
  "map comma to yank to mark a
  map , y'a

  " Make Y work like C, D (to the end of the line)
  " Not working?!?
  nnoremap Y y$

  "map the buff explorer open key
  map <F8> \be

  " Make enter and Sift-Enter insert lines without going to insert mode
  " Next Line Doesn't work, why not?
  "noremap <Shift-Enter> O<ESC>j
  "nmap <Enter> o<ESC>k

  "Use EnhancedCommentify for commenting
  noremap <silent> - :call EnhancedCommentify('no', 'comment')<CR>j
  noremap <silent> _ :call EnhancedCommentify('no', 'decomment')<CR>j

  " Make Y work as expected
  nnoremap Y y$

  " Resize windows with the arrow keys
  nnoremap <up>    <C-W>+
  nnoremap <down>  <C-W>-
  nnoremap <left>  3<C-W>>
  nnoremap <right> 3<C-W><

"Normal Mode Maps
  "map control arrow to move between buffers
  nmap <C-n> :bn<CR>
  nmap <C-p> :bp<CR>

  "map F1 to paste in the selection buffer (*)
  nmap <F1> "*p

  " Make "." go back to the starting point on the line
  nmap . .`[

  " Make \tp toggle paste mode
  nmap \tp :set paste!<CR>

  " " Map \r to grab the last paragraph, copy it, select the new copy, and pipe
  " " it through a recs command
  " :nmap <leader>r GV{yGpGV{j!recs-

  " Map to make tabs more usable
  nmap <Leader>TN :tabn<CR>
  nmap <Leader>tN :tabn<CR>
  nmap <Leader>tP :tabp<CR>
  nmap <Leader>TP :tabp<CR>

  " map \uo to open the first url on the line
  map <Leader>ou :call OpenUrl()<CR>

  " Mapping for quick fix window controls
  map <Leader>cn :cnext<CR>
  map <Leader>cp :cprev<CR>
  map <Leader>cc :cclose<CR>

"Visual Mode Maps

"Insert Mode Maps
  "map ctrl-a and ctrl-e to act like emacs
  imap <C-A> <C-O>^
  imap <C-E> <C-O>$

" Do not use folds in vim-markdown
let g:vim_markdown_folding_disabled=1

" Unite
  " Got annoying having it all in this file, I've moved it to .vimrc.unite
  source $HOME/.vimrc.unite

" FZF Stuff
  source $HOME/.vimrc.fzf

" Insert test data
 " let @t = 'O"*Pvi]:s/^ *- *"/"/gvi]='
 let @t = '"*pvi]:s/^ *- */<80>kb"<80>kb//^Mvi]=vi]:s/([^,])$/\1,/^Mu^Rvi]:s/$/,/^M:nohl^M'
 nmap <Leader>ti @t

" Deoplete config
  let g:deoplete#enable_at_startup = 0

  " omni complete functions
  if !exists('g:deoplete#omni#input_patterns')
    let g:deoplete#omni#input_patterns = {}
  endif

  " omnifuncs
  augroup omnifuncs
    autocmd!
    autocmd FileType css setlocal omnifunc=csscomplete#CompleteCSS
    autocmd FileType html,markdown setlocal omnifunc=htmlcomplete#CompleteTags
    autocmd FileType javascript setlocal omnifunc=javascriptcomplete#CompleteJS
    autocmd FileType python setlocal omnifunc=pythoncomplete#Complete
    autocmd FileType xml setlocal omnifunc=xmlcomplete#CompleteTags
  augroup end

    let g:deoplete#auto_complete_delay=150

  " tern
  " if exists('g:plugs["tern_for_vim"]')
  "   let g:tern_show_argument_hints = 'on_hold'
  "   let g:tern_show_signature_in_pum = 1
  "   autocmd FileType javascript setlocal omnifunc=tern#Complete
  " endif

  " let g:tern_request_timeout = 1
  " let g:tern#command = ["tern"]
  " let g:tern#arguments = ["--persistent"]

  " " deoplete tab-complete
  " inoremap <expr><tab> pumvisible() ? "\<c-n>" : "\<tab>"
  " " tern
  " autocmd FileType javascript nnoremap <silent> <buffer> gb :TernDef<CR>

  " autocmd InsertLeave,CompleteDone * if pumvisible() == 0 | pclose | endif

" Neocomplete
 " source $HOME/.vimrc.neocomplete

" Ultisnips
  "let g:UltiSnipsJumpForwardTrigger="<c-w>"
  "let g:UltiSnipsJumpBackwardTrigger="<c-q>"

  " Map \us to unit search for snips
  nnoremap <leader>us :<C-u>Unite -buffer-name=snippets -start-insert -no-empty ultisnips<cr>
  let g:UltiSnipsEditSplit="vertical" " Open ultisnips editor vertically

  let g:UltiSnipsExpandTrigger="<s-tab>"

  " Use C-e / C-w to move forward / back between placeholders

  nmap  /<++><cr>v3l
  smap  <esc>/<++><cr>v3l
  imap  <esc>/<++><cr>v3l

  " Do not use CTRL-W mapping, conflicts with CTRL-W equals, and I don't use
  " it anyway
  " nmap  ?<++><cr>v3l
  " smap  <esc>?<++><cr>v3l
  " imap  <esc>?<++><cr>v3l


" Better Whitespace
  let g:strip_whitespace_on_save = 1 " Strip whitespace on save
  let g:better_whitespace_filetypes_blacklist = ['unite'] " Do not highlight trailing spaces in unite buffers

" Auto pairs
  " Make meta (option/alt) key work for autopairs stuff
  let g:AutoPairsShortcutToggle     = 'π' " <m-p>
  let g:AutoPairsShortcutFastWrap   = '∑' " <m-w>
  let g:AutoPairsShortcutJump       = '∆' " <m-j>
  let g:AutoPairsShortcutBackInsert = '∫' " <m-b>

  let g:AutoPairsCenterLine = 0 " Do not center line after auto-inserting a CR

" Multiple Cursors config
  let g:multi_cursor_use_default_mapping=0 " Turn off default maps

  let g:multi_cursor_next_key='<M-n>'
  let g:multi_cursor_prev_key='<M-p>'
  let g:multi_cursor_skip_key='<M-x>'
  let g:multi_cursor_quit_key='<Esc>'

  let g:multi_cursor_start_key='<Leader>m'

  " Called once right before you start selecting multiple cursors
  function! Multiple_cursors_before()
    let b:deoplete_disable_auto_complete=1
  endfunction

  " Called once only when the multiple selection is canceled (default <Esc>)
  function! Multiple_cursors_after()
    let b:deoplete_disable_auto_complete=0
  endfunction

  let g:multi_cursor_exit_from_visual_mode=0 " Do not exist multi cursors with esc from visual mode
  let g:multi_cursor_exit_from_insert_mode=0 " Do not exist multi cursors with esc from insert mode

" Indent guides
  let g:indent_guides_enable_on_vim_startup = 1 " Use guides
  let g:indent_guides_exclude_filetypes = ['help', 'unite', 'fzf'] " No guildes in help or unite windows
  let g:indent_guides_guide_size = 1 " Only use 1 character for indent guides

  " Define custom colors, better greys for terminal, need to be autocmd,
  " because evidently the colorscheme resets them a bunch of times. (taken
  " from documentation)
  let g:indent_guides_auto_colors = 0
  autocmd VimEnter,Colorscheme * :hi IndentGuidesOdd  guibg=red   ctermbg=236
  autocmd VimEnter,Colorscheme * :hi IndentGuidesEven guibg=green ctermbg=240

" Add incremental move commands
  " This is adapted from this article:
  " http://reefpoints.dockyard.com/2013/09/26/vim-moving-lines-aint-hard.html
  "
  " Note: Ô - Option-shift-j on mac,  - Option-shift-k on mac
  "

  " Normal mode
  nnoremap Ô :m .+1<CR>==
  nnoremap  :m .-2<CR>==

  " Insert mode
  inoremap Ô <ESC>:m .+1<CR>==gi
  inoremap  <ESC>:m .-2<CR>==gi

  " Visual mode
  vnoremap Ô :m '>+1<CR>gv=gv
  vnoremap  :m '<-2<CR>gv=gv


""""""""""""""" Typos """"""""""""""""""""
" A list of iabbrev to correct common typos

iabbrev colleicton collection
iabbrev Colleicton Collection
iabbrev restaurnt restaurant
iabbrev restauarnt restaurant
iabbrev colleciton collection

""""""""""""""" Syntax """"""""""""""""""""

" turn on syntax coloring
syntax on

" Add support for spitfire comments
function EnhCommentifyCallback(ft)
  if a:ft == 'htmlspitfire'
    let b:ECcommentOpen = '##'
    let b:ECcommentClose = ''
  endif
endfunction
let g:EnhCommentifyCallbackExists = 'Yes'


" Syntax highlight by region
function! TextEnableCodeSnip(filetype,start,end,textSnipHl) abort
  let ft=toupper(a:filetype)
  let group='textGroup'.ft
  if exists('b:current_syntax')
    let s:current_syntax=b:current_syntax
    " Remove current syntax definition, as some syntax files (e.g. cpp.vim)
    " do nothing if b:current_syntax is defined.
    unlet b:current_syntax
  endif
  execute 'syntax include @'.group.' syntax/'.a:filetype.'.vim'
  try
    execute 'syntax include @'.group.' after/syntax/'.a:filetype.'.vim'
  catch
  endtry
  if exists('s:current_syntax')
    let b:current_syntax=s:current_syntax
  else
    unlet b:current_syntax
  endif
  execute 'syntax region textSnip'.ft.'
  \ matchgroup='.a:textSnipHl.'
  \ start="'.a:start.'" end="'.a:end.'"
  \ contains=@'.group
endfunction

""""""""""""""" Version 7 Settings """"""""""""""""""""

if ( v:version >= 700 )
  " Vim 7.0c+ options
  "set cursorline " Get a highlight of the line the cursor is on

  " Change cursor line to highlight the line
  "highlight! CursorLine cterm=NONE ctermbg=0

  " Change spelling colors to not suck, green and brown respectively
  highlight! SpellCap ctermbg=3
  highlight! SpellBad ctermbg=2
endif


if ( v:version >= 703 )
  set undofile                   " Keep undo history around, across vim reboots
  set undodir=$HOME/.config/nvim/tmp     " set directory for undo files
endif

""""""""""""""" Filetype Settings """"""""""""""""""""

" Do not use a backup file when editing a crontab, because OSX complains with
" crontab: temp file must be edited in place
autocmd filetype crontab setlocal nobackup nowritebackup

autocmd filetype vim setlocal keywordprg=:help
autocmd filetype javascript setlocal keywordprg=$HOME/bin/openKeyword
autocmd filetype css setlocal keywordprg=$HOME/bin/openKeyword

" Syntax highlighting for SQL template tag
autocmd FileType javascript call TextEnableCodeSnip('pgsql', 'SQL`', '`', 'NONE')

" Use pgsql.vim for sql highlighting
let g:sql_type_default = 'pgsql'

""""""""""""""" Version 7 Settings """"""""""""""""""""

" Changing spelling highlight to be underline, must come at the end
hi clear SpellBad
hi SpellBad cterm=underline

hi clear SpellCap
hi SpellCap cterm=underline

" Change search hilights
hi IncSearch guifg=NONE guibg=#233466 guisp=#233466 gui=NONE ctermfg=blue ctermbg=yellow cterm=NONE
hi Search ctermfg=17 ctermbg=45 guifg=#00005f guibg=#00dfff guisp=#233466 gui=NONE
