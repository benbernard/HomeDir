" Copyright 2010 Google Inc. All Rights Reserved.
" Author: mbrukman@google.com (Misha Brukman),
"         plakal@google.com (Manoj Plakal),
"         mheule@google.com (Markus Heule)
"
" ncl.vim: Vim syntax file for Nickel files.
" Some parts taken from gcl.vim by plakal@ and mheule@ .
"
" To use this file:
" 1. % mkdir -p ~/.vim/syntax
"    % cp configlang/ncl/ide/ncl.vim ~/.vim/syntax
"
" 2. Add the following to ~/.vimrc:
"
"    augroup filetypedetect
"      au! BufRead,BufNewFile *.ncl setfiletype ncl
"    augroup END
"
" 3. You should already have the following in ~/.vimrc (add if you don't):
"
"    filetype on
"    syntax on

if version < 600
  syntax clear
elseif exists("b:current_syntax")
  finish
endif

syn keyword nclConstant true false
syn keyword nclInclude  include
syn keyword nclType     bool bytes number string
syn keyword nclKeyword  as and assert def defaults else enum expect for forall
syn keyword nclKeyword  if in is_default lambda let local namespace not or
syn keyword nclKeyword  otherwise extension
syn keyword nclKeyword  return then type union where with withrec div
syn match   nclComment  "//.*$" contains=nclTodo display
syn keyword nclTodo     contained TODO FIXME

" Future keywords, currently not highlighted.
syn keyword nclFuture   match mutable ref variant

" Taken from gcl.vim as these are compatible.
"
" Numeric literals = integers and floats.
" Integer literals are the usual octal, decimal, hex except that they can
" include underscores and have a trailing unit (K/M/G/T/P). In addition,
" we also allow integers of the form <decimal-fraction>[K/M/G/T/P], e.g., 1.5G
"
" TODO(mbrukman): support 64-bit literals, e.g., 1234567890L .
syn match   nclNumber  "\<0\o[0-7_]\+[KMGTP]\?\>" display
syn match   nclNumber  "\<\d[0-9_]*[KMGTP]\?\>" display
syn match   nclNumber  "\<0x\x[0-9a-fA-F_]\+[KMGTP]\?>" display
syn match   nclNumber  "\<\d+\.\d+[KMGTP]\>" display
syn match   nclNumber  "\<\d*\(\.\(\d+\)\?\)\?\([eE][+-]\?\d\+\)\>" display

" Taken from gcl.vim as these are compatible.
"
" Strings.
" String literals are delimited by "" and contain the usual escapes.
" We ignore the escaping of ordinary characters for now.
syn region  nclString  matchgroup=Normal start=+"+ end=+"+ skip=+\\\\\|\\"+

" Taken from gcl.vim as these are compatible.
"
" Identifiers.
" Normally these don't require highlighting but GCL allows
" identifiers with arbitrary characters inside backquotes.
"
" This is needed, e.g., for Java flags which have "." in their name.
" Nickel may want to support this in the future.
" syn region  nclRawIdent matchgroup=Normal start=+`+ end=+`+ oneline keepend

if version >= 508 || !exists("did_ncl_syn_inits")
  if version <= 508
    let did_ncl_syn_inits = 1
    command -nargs=+ HiLink hi link <args>
  else
    command -nargs=+ HiLink hi def link <args>
  endif

  HiLink nclComment            Comment
  HiLink nclConstant           Constant
  HiLink nclInclude            Include
  HiLink nclKeyword            Keyword
  HiLink nclNumber             Number
  HiLink nclString             String
  HiLink nclTodo               Todo
  HiLink nclType               Type
  " TODO(mbrukman): enable this?
  "HiLink nclRawIdent           String

  delcommand HiLink
endif

let b:current_syntax = "ncl"
