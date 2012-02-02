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

set fo+=q                            " gq foramts with comments, see :help fo-table
set foldcolumn=0                     " turn off the foldcolumn
set history=100                      " Remember 100 lines of history, for commands and searches
set hls                              " highlight serach terms
set list                             " Show tabs differently
set listchars=tab:>-                 " Use >--- for tabs
set nolinebreak                      " don't wrap at words, messes up copying
set shiftwidth=2                     " use 2 space idnetning
set smartcase                        " if any capitol in search, turns search case sensitive
set softtabstop=2                    " use 2 space indenting
"set tags=~/.commontags,./tags       " Setup the standard tags files
set textwidth=0                      " turn wrapping off
set visualbell                       " Use a flash instead of a sound for bells
set wildmode=longest:full            " Matches only to longest filename, displays to menu possible matches
set undofile                         " Keep undo history around, across vim reboots

"set foldmethod=indent   " use indent unless overridden
set foldlevel=0         " show contents of all folds
"set foldcolumn=2        " set a column incase we need it

filetype plugin on          "turns on filetype plugin, lets matchit work well

colorscheme zellner         "changes color scheme to something that looks decent on the mac

" Set the vim info options
" In order: local marks for N files are saved, global marks are saved,
" a maximum of 500 lines for each register is saved,
" command history number, search history number,
" restore the buffer list and restore global variables

"if so that older versions of vim won't barf on standard systems
if (v:version >= 603)
  set viminfo='1000,f1,<500,:100,/100,%,!
endif

""""""""""""""" Status Line """"""""""""""""""""

" Set the status line
set statusline=%f\ %y%{GetStatusEx()}[b:%n]\ %m%r%=(%l/%L,%c%V)\ %P

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

  "Adding d'a and y'a to yankring keys
  nnoremap y'a  :<C-U>YRYankCount 'y' . "'a'"<CR>
  nnoremap d'a  :<C-U>YRYankCount 'd' . "'a'"<CR>

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
  let g:session_default_to_last = 'yes'

  "Auto open the last session
  let g:session_autoload = 'yes'

""""""""""""""" Command mappings """"""""""""""""

"Map statements
  "map comma to yank to mark a
  map , y'a

  "map the buff explorer open key
  map <F8> \be

  "Map for YRShow
  map <F4> :YRShow<CR>

  " Make enter and Sift-Enter insert lines without going to insert mode
  " Next Line Doesn't work, why not?
  "noremap <Shift-Enter> O<ESC>j
  "nmap <Enter> o<ESC>k

  "Use EnhancedCommentify for commenting
  noremap <silent> - :call EnhancedCommentify('no', 'comment')<CR>j
  noremap <silent> _ :call EnhancedCommentify('no', 'decomment')<CR>j


"Normal Mode Maps
  "map control arrow to move between buffers
  nmap <C-n> :bn<CR>
  nmap <C-p> :bp<CR>

  "map ctrl-e to make file writable
  nmap <C-E> :!chmod +w %<CR>

  "map ctrl-c to chmod +w current file
  nmap <C-C> :r /var/tmp/clipboard-bernard<CR>

  "map F1 to paste in the selection buffer (*)
  nmap <F1> "*p

  " Make "." go back to the starting point on the line
  nmap . .`[

  " Make \tp toggle paste mode
  nmap \tp :set paste!<CR>

  " Map \r to grab the last paragraph, copy it, select the new copy, and pipe
  " it through a recs command
  :nmap <leader>r GV{yGpGV{j!recs-

" Maybe if I had a real X buffer, this would be cool.  Too bad.
"  " X buffer cut/paste
"  nmap <Leader>xp "*p
"  nmap <Leader>xy :set opfunc=XBufferYank<CR>g@
"
"  function! XBufferYank(type, ...)
"    '[,']yank "*
"  endfunction

"Visual Mode Maps
  "Visual mode comment adding
  "vmap <Leader>c :s/^/#/g<enter>:nohl<enter> " leader-c comments block
  "vmap <Leader>x :s/^#//g<enter>:nohl<enter> " leader-x uncomments block
  vmap <C-A> :Align =<enter>                 " Align =  in block
  vmap <Leader>h :Align =><enter>            " Align => in block

"Insert Mode Maps
  "map ctrl-a and ctrl-e to act like emacs
  imap <C-A> <C-O>^
  imap <C-E> <C-O>$

"Commands for perforce, from Scott Windsor
  " Perforce commands
  command -nargs=0 Diff :!p4 diff %
  command -nargs=0 Changes :!p4 changes %
  command -nargs=1 Describe :!p4 describe <args> | more
  command -nargs=0 Edit :!p4 edit %
  command -nargs=0 Revert :!p4 revert %

""""""""""""""" Syntax """"""""""""""""""""

" turn on syntax coloring
syntax on

""""""""""""""" Version 7 Settings """"""""""""""""""""

" The highlight changes at least have to be at the end here... not sure why
if ( v:version >= 700 )
  " Vim 7.0c+ options
  "set cursorline " Get a highlight of the line the cursor is on

  " Change cursor line to highlight the line
  highlight! CursorLine cterm=NONE ctermbg=0

  " Change spelling colors to not suck, green and brown respectively
  highlight! SpellCap ctermbg=3
  highlight! SpellBad ctermbg=2
endif

" Highlight trailing whitespace in red so I can prevent that.
" Must be below any colorscheme setting
highlight ExtraWhitespace ctermbg=red guibg=red
match ExtraWhitespace /\s\+$/
autocmd BufWinEnter * match ExtraWhitespace /\s\+$/
autocmd InsertEnter * match ExtraWhitespace /\s\+\%#\@<!$/
autocmd InsertLeave * match ExtraWhitespace /\s\+$/
autocmd BufWinLeave * call clearmatches()
