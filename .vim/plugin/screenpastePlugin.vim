" File:          screenpaste.vim
" Description:   pastes/inserts current GNU Screen buffer in (almost) any mode
" Version:       7.0
" Mercurial:     $Id: screenpastePlugin.vim,v c90c865d65f4 2008-11-15 00:10 +0100 blacktrash $
" Author:        Christian Ebert <blacktrash@gmx.net>
" URL:           http://www.vim.org/script.php?script_id=1512
" Requirements:  GNU Screen must be in $PATH
" Documentation: in separate file, screenpaste.txt
"
" GetLatestVimScripts: 1512 1 :AutoInstall: screenpaste.zip

if exists("g:loaded_screenpaste") || &cp
  finish
endif
let g:loaded_screenpaste = "7.0"

" Init: store 'compatible' settings {{{1
let s:save_cpo = &cpo
set cpo&vim

" Run Checks: for Vim version, system() and Screen executable {{{1
function! s:Screen_CleanUp(msg) " {{{2
  echohl WarningMsg
  " echomsg "screenpaste:" a:msg "Plugin not loaded"
  echohl None
  let g:loaded_screenpaste = "no"
  let &cpo = s:save_cpo
  unlet! g:screen_clmode g:screen_executable g:screen_register
        \ g:screen_visualselect g:screen_wait
endfunction
" }}}2

" bail out if not Vim7 or greater
if v:version < 700
  call <SID>Screen_CleanUp("Vim7 or greater required.")
  finish
endif

" bail out if system() is not available
if !exists("*system")
  call <SID>Screen_CleanUp("builtin system() function not available.")
  finish
endif

" g:screen_executable: name of GNU Screen executable
if !exists("g:screen_executable")
  let g:screen_executable = "screen"
endif
" bail out if GNUscreen is not present
if !executable(g:screen_executable)
  call <SID>Screen_CleanUp("`".g:screen_executable."' not executable.")
  finish
endif

" More Global Variables: {{{1
function! s:Screen_Default(val,cur,def) " {{{2
  echomsg "screenpaste: `".a:cur."':"
        \ "invalid value for screen_clmode."
        \ "Reset to '".a:def."' (default)"
  execute "let" a:val "= '".a:def."'"
endfunction
" }}}2

" g:screen_clmode: how screenpaste behaves in Vim's command-line
if !exists("g:screen_clmode")
  let g:screen_clmode = "search"
elseif g:screen_clmode !~# '^\%(s\%(earch\|ub\)\|noesc\)$'
  call <SID>Screen_Default("g:screen_clmode",g:screen_clmode,"search")
endif

" g:screen_register: instead of register "0 use this one
if !exists("g:screen_register")
  let g:screen_register = '"'
elseif g:screen_register !~ '^["0-9a-zA-Z]$'
  call <SID>Screen_Default("g:screen_register",g:screen_register,'"')
endif

" g:screen_visualselect: select area after paste in visual mode
if !exists("g:screen_visualselect")
  let g:screen_visualselect = 0
endif

" g:screen_wait: how long to wait for Screen to write exchange file
if !exists("g:screen_wait")
  let g:screen_wait = "333m"
elseif g:screen_wait !~# '^\d\+m\?$'
  call <SID>Screen_Default("g:screen_wait",g:screen_wait,"333m")
endif

" Mappings: propose defaults {{{1
if !hasmapto("<Plug>ScreenpastePut") " nvo
  map  <unique> <Leader>p <Plug>ScreenpastePut
endif
if !hasmapto("<Plug>ScreenpasteGPut") " nvo
  map  <unique> <Leader>gp <Plug>ScreenpasteGPut
endif
if !hasmapto("<Plug>ScreenpastePutBefore", "n")
  nmap <unique> <Leader>P <Plug>ScreenpastePutBefore
endif
if !hasmapto("<Plug>ScreenpasteGPutBefore", "n")
  nmap <unique> <Leader>gP <Plug>ScreenpasteGPutBefore
endif
if !hasmapto("<Plug>ScreenpastePut", "ic")
  map! <unique> <Leader>p <Plug>ScreenpastePut
endif

" Internal Mappings: {{{1
nnoremap <script> <silent> <Plug>ScreenpastePut
      \ :call screenpaste#Screen_NPut("p")<CR>
nnoremap <script> <silent> <Plug>ScreenpasteGPut
      \ :call screenpaste#Screen_NPut("gp")<CR>
nnoremap <script> <silent> <Plug>ScreenpastePutBefore
      \ :call screenpaste#Screen_NPut("P")<CR>
nnoremap <script> <silent> <Plug>ScreenpasteGPutBefore
      \ :call screenpaste#Screen_NPut("gP")<CR>
vnoremap <script> <silent> <Plug>ScreenpastePut
      \ :<C-U> call screenpaste#Screen_VPut("")<CR>
vnoremap <script> <silent> <Plug>ScreenpasteGPut
      \ :<C-U> call screenpaste#Screen_VPut("g")<CR>
inoremap <script> <silent> <Plug>ScreenpastePut
      \ <C-R>=screenpaste#Screen_IPut()<CR><C-R>=screenpaste#Screen_TwRestore()<CR>
cnoremap <script>          <Plug>ScreenpastePut
      \ <C-R>=screenpaste#Screen_CPut()<CR>

" Commands: {{{1
" configuration for command-line-mode
command -nargs=1 -complete=custom,screenpaste#Screen_ClCfgComplete
      \ ScreenCmdlineConf call screenpaste#Screen_ClConfig(<f-args>, 1)
command ScreenCmdlineInfo call screenpaste#Screen_ClConfig(g:screen_clmode, 1)
command ScreenSearch      call screenpaste#Screen_ClConfig("search", 1)
command ScreenSub         call screenpaste#Screen_ClConfig("sub", 1)
command ScreenNoEsc       call screenpaste#Screen_ClConfig("noesc", 1)
" yank Screen buffer into register (default: screen_register)
command -register ScreenYank call screenpaste#Screen_Yank("<register>")
" buffer operation
command -count=0 -bang -register ScreenPut
      \ call screenpaste#Screen_PutCommand("<count>", "<bang>", "<register>")

" }}}1
" Finale: cleanup and restore 'compatible' settings {{{1

" Purge Functions that have done their one-time duty
delfunction <SID>Screen_CleanUp
delfunction <SID>Screen_Default

let &cpo = s:save_cpo
unlet s:save_cpo

finish
" }}}1
" EOF vim600: set foldmethod=marker:
