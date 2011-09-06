" $Id: //brazil/src/appgroup/envImprovement/apps/NinjaHooks/mainline/vim/plugin/wiki_browser.vim#7 $
" 
" A vim plugin that allows editing of wiki nodes from directly within vim.
"
" Authors: Dave Goodell <goodell@amazon.com> and 
"          Ben Bernard <bernard@amazon.com>
"
" TODO:
" - handle wikiUtil failures more gracefully, right now you get cryptic messages
" - check for inside '[[ ]]' for tag handling.
" - perhaps allow browsing of nodes that are rendered with `links`
" - handle names with ':' in them properly
" - handle tag stack popping

" autocommands

augroup AmazonWiki
  " should this go somewhere else? filetype.vim
  au BufReadCmd    wiki://*   setlocal filetype=Wikipedia

  au BufReadCmd    wiki://*   exe "WikiRead " . expand("<amatch>")
  au BufWriteCmd   wiki://*   call <SID>_WikiWrite(expand('<amatch>'))
augroup END

" command definitions
com! -nargs=1     WikiRead call <SID>_WikiRead(<f-args>)
com! -nargs=0     WikiTag call <SID>_WikiTag(<f-args>)

" internal utility functions

let s:WikiUtil = g:ApolloRoot . "/bin/wikiUtil"
let s:WikiDir = tempname()
let s:DefaultSummary = "Automated upload from " . hostname()
let s:WikiUtilGuiOpt = has("gui_running") ? " --gui " : ""

silent exe "!mkdir -m 755 " . s:WikiDir . " 1>/dev/null 2>/dev/null"

function! <SID>_WikiRead(url)
  " pull the node out of the URL
  " syntax is: wiki://NodeName
  let b:wiki_node = substitute(a:url, 'wiki://', '', '')

  call <SID>_WikiReadNode()
endfunction

function! <SID>_WikiReadNode()
  silent exe "r !" . s:WikiUtil . " --directory " . s:WikiDir 
        \ . " --get " . b:wiki_node . s:WikiUtilGuiOpt
        \ . " --flatten 2>/dev/null"

  let b:wiki_file = getline(line('.'))
  let b:wiki_file = escape(b:wiki_file, '#')

  silent exe "silent %!cat '" . s:WikiDir . '/' . b:wiki_file . "'"

  map <buffer> <C-]> :WikiTag<CR>
  set buftype=acwrite
  redraw!
  set nomodified
  file
endfunction

" pull the current node name out from the cursor position and call WikiRead
function! <SID>_WikiTag()
  let b:wiki_node = expand('<cword>')
  " TODO We should really check here to see that we're inside of '[[ ]]' before
  " jumping.  Also, is there any way we can add the old spot back into the tag
  " stack? [goodell@]
  " 
  " From tsurban@: I believe you need to maintain your own tag stack, a buffer
  " local array variable or the faking of one will do (see
  " $VIMRUNTIME/ftplugin/man.vim for an example).  C-T must be buffer mapped
  " also to pop the tag stack.
  silent exe "silent edit wiki://" . b:wiki_node
endfunction

function! <SID>_WikiWrite(url)
  " pull the node out of the URL
  " syntax is: wiki://NodeName
  let b:wiki_node = substitute(a:url, 'wiki://', '', '')

  call <SID>_WikiWriteNode()
endfunction

" Actually write the node back to wiki
function! <SID>_WikiWriteNode()
  silent exe "w! " . s:WikiDir . '/' . b:wiki_file . ""

  let summary = input("change summary [blank for default]: ")
  if strlen(summary) == 0
    let summary = s:DefaultSummary
  endif

  silent exe "!cd " s:WikiDir . " && " 
        \ . s:WikiUtil . " --put '" . b:wiki_file . "'"
        \ . " --summary '" . summary . "'" .  s:WikiUtilGuiOpt
        \ . " --flatten"

  call delete(s:WikiDir . "/" . b:wiki_file)

  set nomodified
  silent redraw!
endfunction

