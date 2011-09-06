
" Vim plugin for common perforce commands.
" Maintainer: Jason McHugh <jmchugh@amazon.com>
" Last Change: 2006 May 08

"
" This file defines a bunch of useful perforce commands.  This is, IMO, the
" required minimal set of vim commands to work with content checked into p4.
"
" The mappings in this file use the <Leader> as a prefix.  I prefer setting the <Leader> to be
" the comma character via this command in my .vimrc:
"    let mapleader = ","
" I like this better than the default <Leader> character.  If you don't know what your leader
" character is then use the following
"     :echo mapleader
" to see what it is defined for your currently running vim.  Do a ":help leader" for more information.
"
" Maps
" ----
" While editing a file under p4 control use the following maps to get information/manipulate it:
"   <Leader>xi  Info       - get information about current file
"   <Leader>xI  Info       - get more information about current file (basically includes full
"                            notes information)
"   <Leader>xr  Revert     - backup current changes to <file>.yourchanges and then p4 revert
"   <Leader>xd  diff       - see diffs between current file and p4 version
"   <Leader>xD  diff       - see contextual diffs between current file and p4 version
"   <Leader>xw  windowdiff - open a window to show side-by-side changes
"
" The following work over an entire p4 client specification:
"   <Leader>xo  opened     - show a list of all opened files 
"   <Leader>xO  opened     - show a list of all opened files in a new window
"
" Vim administrative commands for this script:
"   <Leader>xe  perforce   - edit this file
"   <Leader>xs  source     - source this file
"
"
" Commands
" --------
"  :W      - p4 edit a file, then chmod the file, then write it.  The chmod is useful if you 
"            don't happen to have a good connection with the p4 server as a p4 sync will not 
"            clobber the file as the write bit will be set.
"            
"  :PReset - Used to reset the windowed diff when it gets messed up or you do something silly.
"
" Global variables
" ----------------
" This file makes use of the following global variables.  If your system differs in some way
" from the default values assigned to these variables then set them in your .vimrc via 
"   let g:[variable] = "[value]"
"
"  g:p4 - the location and name of the p4 executable
"  g:diffpgm - the location and name of the diff program used by windowed diff
"


" ----------------------------------------------------------------
" Globals
" ----------------------------------------------------------------
if !exists("g:p4")
  let g:p4 = "p4"
endif
if !exists("g:diffpgm")
  let g:diffpgm = "diff"
endif


" ----------------------------------------------------------------
" Commands
" ----------------------------------------------------------------
command! -nargs=0 W call s:WriteFile()
command! -nargs=0 PReset call s:ClearDiffSettings()


" ----------------------------------------------------------------
" The guts
" ----------------------------------------------------------------
function! s:WriteFile()
  let file=expand("%")
  exec ":silent !" . g:p4 . " open " . file . ""
  exec ":silent !chmod +w %"
  w!
  redraw!
endfunction

function! s:GetPerforceCLN( line )
  let mx='^Change \(\d\+\) '
  let line = matchstr( a:line, mx )
  let changenum = substitute( line, mx, '\1', '' )

  if changenum == line 
    let changenum = 0
  endif

  return changenum
endfunction

function! s:GetFileNameFromPerforceDescription( line )
  " Strip away the extra cruft surrounding the perforce file designation
  let pattern='^\([^\#]*\)\#'
  let line = matchstr( a:line, pattern )
  let p4filename = substitute( line, pattern, '\1', '' )
  
  " Use the p4 where command and get the 3rd result
  let command = "p4 where " . p4filename . " | cut -d' ' -f 3"

  " echo "Executing: " . command

  let filename = system( command )

  return filename
endfunction

function! <SID>ViewVisualEntry( line1, line2 )
  " Get the topmost change #
  let topmostchangenum = s:GetPerforceCLN( a:line1 ) 

  " Get the bottommost change #
  let bottommostchangenum = s:GetPerforceCLN( a:line2 )

  if topmostchangenum == 0 
    echo "Invalid topmost change number"
    return
  endif
  if bottommostchangenum == 0 
    echo "Invalid bottommost change number"
    return
  endif

  call s:ClearDiffSettings()
  let currentFileName = getline(3)

  new
  only
  put='  ---~~~~ Version ' . topmostchangenum . ' ~~~~~-----'
  silent exec ":r! " . g:p4 . " print " . currentFileName . "@" . topmostchangenum  
  set nomod
  diffthis
  1

  vnew
  put='  ---~~~~ Version ' . bottommostchangenum . ' ~~~~~-----'
  silent exec ":r! " . g:p4 . " print " . currentFileName . "@" . bottommostchangenum  
  set nomod
  diffthis
  1

endfunction


function! <SID>ViewEntry()
  let l = getline(".")
  " Get the Change #
  let changenum = s:GetPerforceCLN( l )

  " If I didn't get a valid change number
  if changenum == 0 
    echo "Sorry, no change number"
    return
  endif

  call s:MarkChangeNumber( changenum )

  " Get the file name
  let currentFileName = getline(3)
  new
  exec ":r! " . g:p4 . " print " . currentFileName . "@" . changenum  
  set nomod
  1
endfunction

" Highlight the "Change <number>" part of an entry
function! s:MarkChangeNumber( changenumber ) 

  " Clear the old highlight
  syn clear marked

  " Highlight the new changenumber
  exe ":syn match marked \"Change " . a:changenumber . "\""
  exe ":mark m"
endfunction


function! <SID>InfoEntry()
  let l = getline(".")
  " Get the Change #
  let changenum = s:GetPerforceCLN( l )

  " If I didn't get a valid change number
  if changenum == 0 
    echo "Sorry, no change number"
    return
  endif
  call s:MarkChangeNumber( changenum )

  new
  exec ":r! " . g:p4 . " describe " . changenum  
  set nomod
  1
endfunction


function! <SID>DiffsForEntry()
  let l = getline(".")
  " Get the file name
  let filename = s:GetFileNameFromPerforceDescription( l )
  if filename != "" 
    new
    exec ":r! " . g:p4 . " diff " . filename 
  else
    new
    exec ":r! " . g:p4 . " diff ..."
  endif
  set nomod
endfunction

function! <SID>DiffEntry()
  " Get the change #
  let changenum = s:GetPerforceCLN( getline(".") )
  call s:MarkChangeNumber( changenum )
  
  " Go down one line to get the prior change #
  normal j
  let prevchangenum = s:GetPerforceCLN( getline(".") )

  call s:DiffTwoEntries( changenum, prevchangenum )
endfunction


function! <SID>DiffVisualSelection( line1, line2 )
  " Get the topmost change #
  let topmostchangenum = s:GetPerforceCLN( a:line1 ) 

  " Get the bottommost change #
  let bottommostchangenum = s:GetPerforceCLN( a:line2 )

  call s:DiffTwoEntries( topmostchangenum, bottommostchangenum )
endfunction

function! s:DiffTwoEntries( cl1, cl2 )

  " If I didn't get a valid change number
  if a:cl1 == 0 
    echo "Invalid top change number"
    return
  endif
  if a:cl2 == 0 
    echo "Invalid bottom change number"
    return
  endif

  " Get the file name
  let l = getline(3)
  new
  put=' Differences between version ' . a:cl1 . ' and version ' . a:cl2 
  put=''
  exec ":r! " . g:p4 . " diff2 -dc " . l . "@" . a:cl1 . " " . l . "@" .  a:cl2
  set nomod
  1
endfunction

function! <SID>FstatEntry()
  " Get the file name
  let l = getline(3)
  new
  exec ":r! " . g:p4 . " fstat " . l 
  set nomod
  1
endfunction


nmap <Leader>xi :call <SID>PerforceInfo( "" )<CR>
nmap <Leader>xI :call <SID>PerforceInfo( "-l" )<CR>
function! <SID>PerforceInfo( Options )
  let i = expand("%")
  10new
  let cmd = g:p4 . " changes " . a:Options . " " . i . " "
  silent exec ":r! " . cmd 
  1
  put='  Changes to the file: '
  put='  ' . i
  put=''
  put='  Valid commands per entry: d - diff, i - info, <CR> - view, <visual selection - d> - multiversion diff'
  put='  Valid commands (non-entry): f - fstat'
  put=''
  silent exec( "%s/@[^ ]*/\t/g" )
  set nomod
  1
  setlocal ts=20
  nnoremap <buffer> <cr> :call <SID>ViewEntry()<cr>
  nnoremap <buffer> i    :call <SID>InfoEntry()<cr>
  nnoremap <buffer> d    :call <SID>DiffEntry()<cr>
  nnoremap <buffer> f    :call <SID>FstatEntry()<cr>
  vnoremap <buffer> d    <ESC>:call <SID>DiffVisualSelection( getline( "'<" ), getline( "'>" ) )<cr>
  vnoremap <buffer> <cr> <ESC>:call <SID>ViewVisualEntry( getline( "'<" ), getline( "'>" ) )<cr>
  if has("syntax") 
    syn match changesLine       "  Changes to the file:"
    syn match fileLine          "^  [^.]*\.[a-z]*"
    syn match changeLine        "Change [0-9]* " contains=changeLine2
    syn match changeLine2       "on [^/]*/[^/]*/[^/]* " contains=changeLine3
    syn match changeLine3       "by [^ ]*"
    syn match reviewer          "reviewer: "
    syn match submitComment     "\'.*\'"

    hi def link fileLine          Statement
    hi def link changesLine       String
    hi def link changeLine        Type
    hi def link changeLine2       String
    hi def link changeLine3       Comment
    hi def link submitComment     Comment
    hi def link reviewer          Comment
    hi marked                     gui=reverse term=bold cterm=reverse
  endif
endfunction

nmap <Leader>xr :call <SID>PerforceRevert( 1 )<CR>
function! <SID>PerforceRevert( Options )
  let i = expand("%")
  if( a:Options == 1 ) 
    exec ":w! ". i . ".yourchanges" 
  endif
  1
  exec ":! " . g:p4 . " revert ". i ." "
  exec ":e!"
endfunction

function! <SID>OpenPerforceFile( NewWindow )
  let l = getline(".")
  let filename = s:GetFileNameFromPerforceDescription( l )
  echo filename
  if( a:NewWindow == 1 ) 
    close
    exe ":new " filename
  elseif( a:NewWindow == 0 ) 
    exe ":e " filename
  else
    exe ":pedit " filename
  end
endfunction

nmap <Leader>xd :call <SID>PerforceDiff( "" )<CR>
nmap <Leader>xD :call <SID>PerforceDiff( "-dc" )<CR>
function! <SID>PerforceDiff( Options )
  let i = expand("%")
  new
  exec ":r! " . g:p4 . " diff " . a:Options " " . i . ""
  1
  put=' // ----------'
  put=' // ----------'
  put=' // - Changes I have made to '.i
  put=' // ----------'
  put=' // ----------'
  put=''
  set nomod
endfunction

nmap <Leader>xc :call <SID>PerforceChanges( 0 )<CR>
nmap <Leader>xo :call <SID>PerforceChanges( 0 )<CR>
nmap <Leader>xO :call <SID>PerforceChanges( 1 )<CR>
function! <SID>PerforceChanges( NewWindow )
  new
  if( a:NewWindow == 0 ) 
    only
  endif
  exec ":r! " . g:p4 . " opened "
  1
  put='  Opened files: '
  put=''
  put='  Valid commands per entry: '
  put='    d - see diffs, r - revert file, <CR> - open file'
  put='    O - open file in new window, p - preview file' 
  put=''
  1
  nnoremap <buffer> <cr> :call <SID>OpenPerforceFile( 0 )<cr>
  nnoremap <buffer> O    :call <SID>OpenPerforceFile( 1 )<cr>
  nnoremap <buffer> p    :call <SID>OpenPerforceFile( 2 )<cr>
  nnoremap <buffer> d    :call <SID>DiffsForEntry()<cr>
  if has("syntax") 
    syn match changesLine       "  Opened files:"
    syn match fileLine          "//.*"

    hi def link fileLine          Statement
    hi def link changesLine       String
  endif
  set nomod
endfunction

nmap <Leader>xe :edit ~/.vim/plugin/Perforce.vim<CR>
nmap <Leader>xE :new ~/.vim/plugin/Perforce.vim<CR>
nmap <Leader>xs :source ~/.vim/plugin/Perforce.vim<CR>

if has("diff" ) 
  function! MyDiff()
    let opt = ""
    if &diffopt =~ "icase"
      let opt = opt . "-i "
    endif
    if &diffopt =~ "iwhite"
      let opt = opt . "-b "
    endif

    let in = substitute( v:fname_in, "\\", "/", "g")
    let new = substitute( v:fname_new, "\\", "/", "g")
    let out = substitute( v:fname_out, "\\", "/", "g")

    " echo "In = " . in . ", new = " . new . ", out = " . out

    silent execute "!". g:diffpgm . " ". opt . in . " " . new .  " > " . out
  endfunction
  set diffexpr=MyDiff()
endif


map <Leader>xw :call <SID>PerforceDiffToggle( )<CR>
function! <SID>PerforceDiffToggle()
  if has( "diff" ) 
    if( &diff == 1 ) 
       call s:ClearPerforceDiffWindow()
    else
       call s:SetPerforceDiffWindow()
    endif
  else 
    echo "No diff in this build"
  endif
endfunction

function! s:ClearPerforceDiffWindow()
  if exists("b:filediff")
    winc w
  endif
  call s:ClearDiffSettings()
  winc w
  silent exec ":bd!"
endfunction

function! s:ClearDiffSettings()
  set nofoldenable
  set foldcolumn=0
  set nodiff
  diffoff!
endfunction

function! s:SetPerforceDiffWindow()
  let l = expand("%")
  let extension = expand("%:e")
  let tempfile = tempname() . "." . extension
  silent exec ":!" .g:p4. " print " .l. " > " . tempfile
  silent exec ":only"
  silent exec "vert diffsplit " . tempfile
  1d
  let b:filediff="true"
  set nomod
  call s:Dset()
  winc w
  winc r
endfunction

function! s:Dset()
  set nofoldenable
  winc w
  set nofoldenable
  winc w
  winc =
  0
endfunction
com! -nargs=0 Dset call s:Dset()

" vim: set sw=2 ts=2 :
