" File Name: htmlspitfire.vim
" Maintainer: Ben Bernard <benbernard@google.com
" Original Date: Feb 3, 2012
" Description: indent file for htmlspitfire

" Only load this indent file when no other was loaded.
if exists("b:did_indent")
  finish
endif

" This is super ugly, be we don't want to re-write html vim indenting
" Taken from http://www.vim.org/scripts/script.php?script_id=2075
" since built in indenter didn't work well with interleaved spitfire
runtime indent/html-for-spitfire.vim

let b:did_indent = 1

let b:indent_block_start = '^\s*#\(for\|if\|def\|else\|elif\|strip_lines\)'
let b:indent_block_end = '^\s*#\(end\|else\|elif\)'
let b:indent_ignore = '^\s*##'

"setlocal indentexpr=GenericIndent(v:lnum)
setlocal indentexpr=SpitfireIndent(v:lnum)
setlocal indentkeys+=o,O,!^F,0=#end,0=#else,0=#elif

function! SpitfireIndent(lnum)
  let no_blank_lnum = prevnonblank(a:lnum - 1)

  " If the current line or the previous non blank line starts with a #, then
  " use the generic indent, otherwise to html indenting
  if getline(a:lnum) =~ '^\s*#' || getline(no_blank_lnum) =~ '^\s*#'
    return GenericIndent(a:lnum)
  else
    return HtmlIndent()
  endif
endfunction
