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
" Author: Ben Bernard <bernard@amazon.com>
"         moved to after/ and modified by goodell@
"
" TODO:
" - convert addressComplete to be a filter, such that the temp file is
"   unnecessary

"map tab to move between empty fields
map <Tab> /<++><CR>c4l
imap <Tab> <Esc>/<++><CR>c4l

" Writes current file to temp file,
" and filters it through the addressComplete script
function! CreateMailFields ()
  let tmpfile = tempname()

  silent exe 'write! ' . tmpfile
  silent exe '!' . '/home/benbernard/bin/createMailFields --file ' . tmpfile
  silent exe '%!cat ' . tmpfile
  silent exe '!rm ' . tmpfile
endfunction

if exists("g:useMailFieldTabbing")
  call CreateMailFields()
endif

let b:hasRunComplete = 0
