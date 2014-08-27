" after/ftplugin/mail.vim
"
" There are 2 important variables here:
" g:useMailFieldTabbing - Creates <++> tab fields
" g:addressCompleteOnExit - Prompts (once) to complete addresses
"
" Just sent them to anything to use.
"
" Also, there are two functions you can call on your
" own if you want:
"
" CreateMailFields
" AddressComplete
"
" Author: Ben Bernard
"         moved to after/ and modified by goodell@
"
" TODO:
" - convert addressComplete to be a filter, such that the temp file is
"   unnecessary

"map control-m to complete email adresses
map <C-a> :call AddressComplete()<CR>

"map tab to move between empty fields
map <Tab> /<++><CR>c4l
imap <Tab> <Esc>/<++><CR>c4l

" Writes current file to temp file,
" and filters it through the addressComplete script
function! CreateMailFields ()
  let tmpfile = tempname()

  silent exe 'write! ' . tmpfile
  silent exe '!' . g:ApolloRoot . '/bin/createMailFields --file ' . tmpfile
  silent exe '%!cat ' . tmpfile
  silent exe '!rm ' . tmpfile
endfunction

" Writes current file to temp file,
" and filters it through the addressComplete script
function! AddressComplete ()
  let tmpfile = tempname()

  silent exe 'write! ' . tmpfile
  silent exe '!' . g:ApolloRoot . '/bin/addressComplete --file ' . tmpfile
  silent exe '%!cat ' . tmpfile
  silent exe '!rm ' . tmpfile
  silent exe 'redraw!'
endfunction

if exists("g:useMailFieldTabbing")
  call CreateMailFields()
endif

let b:hasRunComplete = 0

au BufWrite *   if exists("g:addressCompleteOnExit")
au BufWrite *     if b:hasRunComplete == 0
au BufWrite *       let b:hasRunComplete = 1
au BufWrite *       let choice = confirm("Complete addresses?", "&yes\n&no", 1)
au BufWrite *       if choice == 1
au BufWrite *         call AddressComplete()
au BufWrite *       endif
au BufWrite *     endif
au BufWrite *   endif
