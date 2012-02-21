" These functions are used by the screenpaste plugin.
" $Id: screenpaste.vim,v 1bdf402abcdd 2008-10-30 16:27 +0100 blacktrash $

" Script Vars: characters to be escaped on cmdline {{{1
" static:

" dynamic:
" these contain the current values for cmdline conversion, and,
" at startup, are set to the values corresponding to 'noesc'
" because for 'search' and 'sub' Screen_ClConfig is called with
" the current value of screen_clmode everytime Screen_CPut is called
" with the purpose to adapt to current setting of 'magic'
let s:cl_esc = ''
let s:cl_eol = '\\n'

" Function: Screen_ClCfgComplete for cmdline-completion {{{1
function! screenpaste#Screen_ClCfgComplete(A, L, P)
  return "search\nsub\nnoesc"
endfunction

" Function: Screen_ClConfig configures cmdline insertion {{{1
" variables configured here and used by Screen_CPut function:
" global:
" g:screen_clmode     cmdline behaviour
" internal:
" s:cl_eol            eol-conversion
" s:cl_esc            character group pattern to be escaped
" s:esc_info          displays escaped characters
" s:eol_info          displays eol-conversion

function! screenpaste#Screen_ClConfig(mod, msg)
  if a:mod !~# '^\%(s\%(earch\|ub\)\|noesc\)$'
    echohl WarningMsg
    echon "`" a:mod "': invalid value for screen_clmode\n"
          \ "use one of: search | sub | noesc"
    echohl None
    return ""
  endif
 
  " patterns and strings (for user info)
  let l:esc_search_ma    = '][/\^$*.~'
  let l:esc_search_noma  = ']/\^$'
  let l:esc_sub_ma       = '/\~&'
  let l:esc_sub_noma     = '/\'
  let l:info_search_ma   = "] [ / \\ ^ $ ~ * . (magic)"
  let l:info_search_noma = "] / \\ ^ $ (nomagic)"
  let l:info_sub_ma      = "/ \\ ~ & (magic)"
  let l:info_sub_noma    = "/ \\ (nomagic)"
  " dict vars
  let l:cl_esc_dict = {
        \ "search": {0: l:esc_search_noma, 1: l:esc_search_ma},
        \ "sub":    {0: l:esc_sub_noma,    1: l:esc_sub_ma   },
        \ "noesc":  {0: '',                1: ''             }
        \ }
  let l:cl_info_dict = {
        \ "search": {0: l:info_search_noma, 1: l:info_search_ma},
        \ "sub"   : {0: l:info_sub_noma,    1: l:info_sub_ma   },
        \ "noesc" : {0: 'none',             1: 'none'          }
        \ }
  let l:eol_conv_dict =
        \ {"search": '\\n', "sub": '\\r', "noesc": '\\n'}
  let l:eol_info_dict =
        \ {"search": '\n', "sub": '\r', "noesc": '\n'}

  let g:screen_clmode = a:mod
  let s:cl_esc   =   l:cl_esc_dict[g:screen_clmode][&magic]
  let s:esc_info =  l:cl_info_dict[g:screen_clmode][&magic]
  let s:cl_eol   = l:eol_conv_dict[g:screen_clmode]
  let s:eol_info = l:eol_info_dict[g:screen_clmode]
  if a:msg
    echon "set '" g:screen_clmode "' "
          \ "for Screen buffer insertion in cmdline:\n"
          \ "eol-conversion to literal " s:eol_info "\n"
          \ "escaped characters        " s:esc_info
  endif
endfunction
" }}}1
" ============================================================================
" Function: Screen_Yank snatches current Screen buffer {{{1
" Function: Screen_ReadBuf subroutine returns Screen buffer as text {{{2

function! s:Screen_ReadBuf(screen_tmpfile)
  if !filereadable(a:screen_tmpfile)
    " wait in case screen is late in writing screen-exchange file
    execute "sleep" g:screen_wait
  endif
  try
    return join(readfile(a:screen_tmpfile, "b"), "\n")
  catch /^Vim\%((\a\+)\)\=:E484/
    " Screen buffer empty, no tmpfile created
    return ""
  endtry
endfunction
" }}}2

function! screenpaste#Screen_Yank(...)
  let l:screen_tmpfile = tempname()
  call system(g:screen_executable." -X writebuf ".l:screen_tmpfile)
  if !a:0
    return <SID>Screen_ReadBuf(l:screen_tmpfile)
  else
    let l:screen_buf = <SID>Screen_ReadBuf(l:screen_tmpfile)
    if strlen(l:screen_buf)
      if strlen(a:1)
        call setreg(a:1, l:screen_buf)
      else
        call setreg(g:screen_register, l:screen_buf)
      endif
      return 1
    elseif g:screen_register =~ '\u'
      " do nothing
      return 1
    else
      echohl WarningMsg
      echo "Screen buffer is empty"
      echohl None
      return 0
    endif
  endif
endfunction

" Function: Screen_NPut pastes in normal mode {{{1
function! screenpaste#Screen_NPut(p)
  if screenpaste#Screen_Yank(g:screen_register)
    execute 'normal! "'.g:screen_register.a:p
  endif
endfunction

" Function: Screen_IPut pastes in insert mode {{{1

" Function: Screen_TwRestore subroutine restores 'paste' {{{2
" helper function, only called right after Screen_IPut
" because Screen_IPut must return result before
" being able to restore paste its previous value
function! screenpaste#Screen_TwRestore()
  let &paste = s:curr_paste
  return ""
endfunction
" }}}2

function! screenpaste#Screen_IPut()
  let s:curr_paste = &paste
  let &paste = 1
  let l:screen_buf = screenpaste#Screen_Yank()
  return l:screen_buf
endfunction

" Function: Screen_VPut pastes in visual mode {{{1
function! screenpaste#Screen_VPut(go)
  if screenpaste#Screen_Yank(g:screen_register)
    if g:screen_register =~ '["@]'
      " we have to use another register because
      " visual selection is deleted into unnamed register
      let l:store_reg = @z
      let @z = @"
      let g:screen_register = "z"
    endif
    execute 'normal! gv"'.g:screen_register.a:go.'p'
    if g:screen_visualselect
      execute "normal! `[".visualmode()."`]"
    endif
    if exists("l:store_reg")
      let g:screen_register = '"'
      let @0 = @z
      let @z = l:store_reg
    endif
  else
    " reset visual after showing message for 3 secs
    sleep 3
    execute "normal! gv"
  endif
endfunction

" Function: Screen_PutCommand is called from :ScreenPut {{{1
function! screenpaste#Screen_PutCommand(line, bang, reg)
  if !strlen(a:reg)
    let l:reg = g:screen_register
  else
    let l:reg = a:reg
  endif
  if screenpaste#Screen_Yank(l:reg)
    if a:line
      execute a:line "put".a:bang l:reg
    else
      execute "put".a:bang l:reg
    endif
  endif
endfunction

" Function: Screen_CPut pastes in cmdline according to cmdtype {{{1
function! screenpaste#Screen_CPut()
  " automatically adapt 'screen_clmode' to cmdtype if possible
  " or instant paste in case of :insert or :append
  let l:cmdtype = getcmdtype()
  if l:cmdtype == '-' && exists("$STY")
    " Screen call needed for :insert and :append commands in Screen_CPut
    " using slowpaste avoids need for manual redraw
    let l:screen_slowpaste =
          \ g:screen_executable." -X slowpaste 10;".
          \ g:screen_executable." -X paste .;".
          \ g:screen_executable." -X slowpaste 0"
    " :insert, :append inside Screen session
    call system(l:screen_slowpaste)
    return ""
  endif
  " store current cmdline behaviour
  let l:save_clmode = g:screen_clmode
  " detect cmdtype if not 'noesc'
  if g:screen_clmode != "noesc"
    if l:cmdtype =~ '[/?]'
      " search: always call config to adapt to 'magic'
      call screenpaste#Screen_ClConfig("search", 0)
    elseif l:cmdtype =~ '[@-]'
      " input() or :insert, :append outside Screen session
      call screenpaste#Screen_ClConfig("noesc", 0)
    else
      " search, sub: always call config to adapt to 'magic'
      call screenpaste#Screen_ClConfig(g:screen_clmode, 0)
    endif
  endif
  " escape chars in Screen buffer for cmdline
  let l:screen_buf = screenpaste#Screen_Yank()
  if strlen(s:cl_esc)
    let l:screen_buf = escape(l:screen_buf, s:cl_esc)
  endif
  let l:screen_buf = substitute(l:screen_buf, "\<C-J>", s:cl_eol, 'g')
  " restore global 'screen_clmode' if changed
  if l:save_clmode != g:screen_clmode
    call screenpaste#Screen_ClConfig(l:save_clmode, 0)
  endif
  return l:screen_buf
endfunction
" }}}1
" EOF vim600: set foldmethod=marker:
