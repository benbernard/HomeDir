" Initialize pathogen, a plugin management system that lets plugins live in
" their own directories

call pathogen#infect()

" First setup variable for other variables
"let g:useNinjaTagList=1

syntax on

if ( filereadable($HOME . "/.vimrc.site") )
  source $HOME/.vimrc.site
endif

""""""""""""""" Global Setup """"""""""""""""""""
"First source the environment location
source $HOME/.eihooks/dotfiles/vimrc

""""""""""""""" Global Options """"""""""""""""""""

colorscheme zellner         "changes color scheme to something that looks decent on the mac

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
set softtabstop=2                    " use 4 space indenting
set ts=2                             " Default to 4 spaces for tabs
set tags=./tags,~/fieldbook/tags     " Setup the standard tags files
set textwidth=0                      " turn wrapping off
set visualbell                       " Use a flash instead of a sound for bells
set wildmode=longest:full            " Matches only to longest filename, displays to menu possible matches
set complete=.,w,b,u                 " complete from current file, and current buffers default: .,w,b,u,t,i  trying to keep down completion time
set directory=$HOME/.vim/tmp         " set directory for tmp files to be in .vim, so that .swp files are not littered
set clipboard=unnamed                " Use the * register when a register is not specified - unifies with system clipboard!
set omnifunc=syntaxcomplete#Complete " Turn on omni completion
scriptencoding utf-8                 " Use utf-8 to encode vimscript (so that options key maps can work)

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

""""""""""""""" Plugin Settings """"""""""""""""

" javascript-libraries-syntax settings
  let g:used_javascript_libs = 'underscore,backbone,jquery'


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
  let g:rvSaveDirectoryName = "$HOME/.vim/RCSFiles/" "Place to save RCS files

  "Setup exlcude expressions for rcs
  "1. Mutt mail files
  "2. p4 submit descriptions
  "3. tmp files from perforce form commands
  let g:rvExcludeExpression = 'muttng-bernard-\d\+\|p4submitdesc\.txt\|\/tmp\.\d\+\.\d\+'

  let g:rvRlogOptions = '-zLT' "Display log in local timezone

"YankRing settings...
  "Don't remap <C-N> and <C-P>
  let g:yankring_replace_n_pkey = '<F3>'
  let g:yankring_replace_n_nkey = '<F2>'

  nnoremap <silent> <Leader>yr :YRShow<CR>

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
  let g:EasyMotion_leader_key = '-'

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

"Syntastic Settings
  " Automatically open the location list when there are errors
  let g:syntastic_auto_loc_list = 1

  " Use my jshintrc file rather than default
  let g:syntastic_javascript_jshint_args="-c ~/.jshintrc"

  let g:syntastic_ignore_files = [
          \ '\m^/Users/bernard/fieldbook/node_modules',
          \ '\m^/Users/bernard/fieldbook/lib/js',
          \ '\m^/Users/bernard/jquery-handsontable',
          \ '\m^/Users/bernard/test-destributer',
          \ '.*.user.js$' ]

  " Map <leader>st to SyntasticToggleMode
  map <Leader>st :SyntasticReset<CR>

  " Set js checkers to include jscs
  let g:syntastic_javascript_checkers = ['jshint', 'jscs']

  " Setup javascript as the only active syntax
  let g:syntastic_mode_map = { 'mode': 'passive',
                             \ 'active_filetypes': ['javascript'],
                             \ 'passive_filetypes': [] }

" Super tab Settings
  " Have supertab look at characters before cursor to determine completion
  " type
  let g:SuperTabDefaultCompletionType = "context"

" Gundo Settings
  nmap <Leader>gu :GundoToggle<CR>

""""""""""""""" Command mappings """"""""""""""""

"Map statements
  "map comma to yank to mark a
  map , y'a

  " Make Y work like C, D (to the end of the line)
  map Y y$

  "map the buff explorer open key
  map <F8> \be

  "Map for YRShow
  map <F4> :YRShow<CR>
  map <Leader>yr :YRShow<CR>

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

  " Map \r to grab the last paragraph, copy it, select the new copy, and pipe
  " it through a recs command
  :nmap <leader>r GV{yGpGV{j!recs-

  " Map to make tabs more usable
  nmap <Leader>TN :tabn<CR>
  nmap <Leader>tN :tabn<CR>
  nmap <Leader>tP :tabp<CR>
  nmap <Leader>TP :tabp<CR>

  " map \uo to open the first url on the line
  map <Leader>ou :call OpenUrl()<CR>

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

" Insert test data
 " let @t = 'O"*Pvi]:s/^ *- *"/"/gvi]='
 let @t = '"*pvi]:s/^ *- */<80>kb"<80>kb//^Mvi]=vi]:s/([^,])$/\1,/^Mu^Rvi]:s/$/,/^M:nohl^M'
 nmap <Leader>ti @t

" Neocomplete
 source $HOME/.vimrc.neocomplete

" Ultisnips
  "let g:UltiSnipsJumpForwardTrigger="<c-w>"
  "let g:UltiSnipsJumpBackwardTrigger="<c-q>"

  " Map \us to unit search for snips
  nnoremap <leader>us :<C-u>Unite -buffer-name=snippets -start-insert -no-empty ultisnips<cr>
  let g:UltiSnipsEditSplit="vertical" " Open ultisnips editor vertically

  let g:UltiSnipsExpandTrigger="<s-tab>"

  " Use C-e / C-w to move forward / back between placeholders
  nmap  ?<++><cr>v3l
  nmap  /<++><cr>v3l
  smap  <esc>?<++><cr>v3l
  smap  <esc>/<++><cr>v3l
  imap  <esc>?<++><cr>v3l
  imap  <esc>/<++><cr>v3l

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

  let g:multi_cursor_next_key='<C-i>'
  let g:multi_cursor_prev_key='<C-p>'
  let g:multi_cursor_skip_key='<C-x>'
  let g:multi_cursor_quit_key='<Esc>'

  " Called once right before you start selecting multiple cursors
  function! Multiple_cursors_before()
    if exists(':NeoCompleteLock')==2
      exe 'NeoCompleteLock'
    endif
  endfunction

  " Called once only when the multiple selection is canceled (default <Esc>)
  function! Multiple_cursors_after()
    if exists(':NeoCompleteUnlock')==2
      exe 'NeoCompleteUnlock'
    endif
  endfunction

  let g:multi_cursor_exit_from_visual_mode=0 " Do not exist multi cursors with esc from visual mode
  let g:multi_cursor_exit_from_insert_mode=0 " Do not exist multi cursors with esc from insert mode

  let g:multi_cursor_normal_maps = {'d': 1, 'c': 1, 't': 1} " Map dw and cw work with multiple cursors


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
  set undodir=$HOME/.vim/tmp     " set directory for undo files
endif

""""""""""""""" Filetype Settings """"""""""""""""""""

" Do not use a backup file when editing a crontab, because OSX complains with
" crontab: temp file must be edited in place
autocmd filetype crontab setlocal nobackup nowritebackup

""""""""""""""" Version 7 Settings """"""""""""""""""""

" Changing spelling highlight to be underline, must come at the end
hi clear SpellBad
hi SpellBad cterm=underline

hi clear SpellCap
hi SpellCap cterm=underline
