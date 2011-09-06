" File:        screenpaste.vim
" Description: Pastes/inserts current GNUscreen buffer in (almost) every mode
" Author:      Christian Ebert <blacktrash@gmx.net>
" Version:     1.0
" Mercurial:   $Hg: screenpaste.vim,v 5c262b142164 Sun Apr 09 15:01:37 2006 +0200 $
" Requirement: GNUscreen must be in $PATH
" Install:     As plugin eg. in ~/.vim/plugin/ or
"              put in ~/.vim/macros/ and source it eg. like so:
"              if &term == "screen"
"                runtime macros/screenpaste.vim
"              endif
" Usage:       Supposing the default map leader "\" you can type
"              \p in normal mode to paste screen buffer at cursor position
"              \i in normal mode to insert screen buffer before cursor
"              \p in insert mode to insert screen buffer

" Section: init {{{1
if exists("loaded_screenpaste")
  finish
endif
let loaded_screenpaste = 1

let s:save_cpo = &cpo
set cpo&vim
" }}}

" Function: ScreenPaste {{{1
function s:ScreenPaste(...)
  let l:curr_paste = &paste
  let l:curr_mode = mode()
  if l:curr_paste == "nopaste"
    set paste
  endif
  " caveat: if &paste is on it only works in normal mode
  if l:curr_mode == "n"
    if a:0 == 0
      let l:save_ve = &virtualedit
      set virtualedit=all
      normal! l
      if col(".") != col("$")
	startinsert
      else
	startinsert!
      endif
      let &virtualedit = l:save_ve
    elseif a:1 == "bc"  " insert before cursor
      startinsert
    else
      echo 'screenpaste: only "bc" as optional argument allowed'
      return
    endif
    let l:enter_mode = ""
  elseif l:curr_mode == "i"
    let l:enter_mode = "a"
  elseif l:curr_mode == "R"
    let l:enter_mode = "R"
  endif
  " Use octal to pass <Esc> (\033) and <CR> (\015) to screen
  if l:curr_paste == "nopaste"
    " echo an empty string for quietness
    call system("screen -X paste .; screen -X stuff '\033:set nopaste\015:echo\015'".l:enter_mode)
    redraw!
  else
    call system("screen -X paste .; screen -X stuff '\033'".l:enter_mode)
  endif
  if l:curr_mode != "n"
    return ""
  endif
endfunction
" }}}

" Internal Maps: {{{1
nmap <silent> <Plug>ScreenBufferPaste :call <SID>ScreenPaste()<CR>
nmap <silent> <Plug>ScreenBufferInsert :call <SID>ScreenPaste("bc")<CR>
imap <silent> <Plug>ScreenBufferPaste <C-R>=<SID>ScreenPaste()<CR>
" }}}

" Maps: propose defaults {{{1
if !hasmapto("<Plug>ScreenBufferPaste", "n")
  nmap <unique> <Leader>p <Plug>ScreenBufferPaste
endif
if !hasmapto("<Plug>ScreenBufferInsert", "n")
  nmap <unique> <Leader>i <Plug>ScreenBufferInsert
endif
if !hasmapto("<Plug>ScreenBufferPaste", "i")
" BEGIN AMAZON MODIFICATION
"  REMOVING imap statement, since insert mode maps are annoying
"  imap <unique> <Leader>p <Plug>ScreenBufferPaste
" END AMAZON MODIFICATION
endif
" }}}

" Finale: restore 'compatible' settings {{{1
let &cpo = s:save_cpo
" }}}

" EOF vim:fdm=marker
