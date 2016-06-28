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

"Putting this back in would cause comment lines to be ignored for determining
"current indent level... Among other things this causes follow-on comment
"lines to be indented at a different level
"let b:indent_ignore = '^\s*##'

"setlocal indentexpr=GenericIndent(v:lnum)
setlocal indentexpr=SpitfireIndent(v:lnum)
setlocal indentkeys+=o,O,!^F,0=#end,0=#else,0=#elif

function! SpitfireIndent(lnum)
  let no_blank_lnum = prevnonblank(a:lnum - 1)

  " If the current line or the previous non blank line starts with a #, then
  " use the generic indent, otherwise to html indenting
  if getline(a:lnum) =~ '^\s*#' || getline(no_blank_lnum) =~ '^\s*#'
    return HtmlSpitfireGenericIndent(a:lnum)
  else
    return HtmlIndent()
  endif
endfunction

" This function is taken verbatim from the very useful genindent.vim plugin,
" so that I don't have to bundle it with the syntax files
function! HtmlSpitfireGenericIndent(lnum)
  if !exists('b:indent_ignore')
    " this is safe, since we skip blank lines anyway
    let b:indent_ignore='^$'
  endif
  " Find a non-blank line above the current line.
  let lnum = prevnonblank(a:lnum - 1)
  while lnum > 0 && getline(lnum) =~ b:indent_ignore
    let lnum = prevnonblank(lnum - 1)
  endwhile
  if lnum == 0
    return 0
  endif
  let curline = getline(a:lnum)
  let prevline = getline(lnum)
  let indent = indent(lnum)
  if ( prevline =~ b:indent_block_start )
    let indent = indent + &sw
  endif
  if (curline =~ b:indent_block_end )
    let indent = indent - &sw
  endif
  return indent
endfunction

