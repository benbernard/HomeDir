" Vim syntax file
" Language: Spitfire template engine
" Maintainer: Max Ischenko <mfi@ukr.net>
" Last Change: 2003-05-11
"
" Missing features:
"  match invalid syntax, like bad variable ref. or unmatched closing tag
"  PSP-style tags: <% .. %> (obsoleted feature)
"  doc-strings and header comments (rarely used feature)

" For version 5.x: Clear all syntax items
" For version 6.x: Quit when a syntax file was already loaded
if version < 600
  syntax clear
elseif exists("b:current_syntax")
  finish
endif

syntax case match

syn keyword spitfireKeyword contained if else unless elif for in not
syn keyword spitfireKeyword contained while repeat break continue pass end
syn keyword spitfireKeyword contained set del attr def global include raw echo
syn keyword spitfireKeyword contained import from extends implements
syn keyword spitfireKeyword contained assert raise try catch finally
syn keyword spitfireKeyword contained errorCatcher breakpoint silent cache filter
syn keyword spitfireKeyword contained strip_lines
syn match   spitfireKeyword contained "\<compiler-settings\>"
syn region  spitfireString  start=+"+ end=+"+ display
syn region  spitfireString  start=+'+ end=+'+ display

" Matches cached placeholders
syn match   spitfirePlaceHolder "$\(\*[0-9.]\+[wdhms]\?\*\|\*\)\?\h\w*\(\.\h\w*\)*" contains=spitfireString display
syn match   spitfirePlaceHolder "$\(\*[0-9.]\+[wdhms]\?\*\|\*\)\?{\h\w*\(\.\h\w*\)*}" contains=spitfireString display
syn match   spitfireDirective "^\s*#[^#].*$"  contains=spitfirePlaceHolder,spitfireKeyword,spitfireComment,spitfireString display

" syn match   spitfireContinuation "\\$"
syn match   spitfireComment "##.*$" display
syn region  spitfireMultiLineComment start="#\*" end="\*#"

" Define the default highlighting.
" For version 5.7 and earlier: only when not done already
" For version 5.8 and later: only when an item doesn't have highlighting yet
if version >= 508 || !exists("did_spitfire_syn_inits")
  if version < 508
    let did_spitfire_syn_inits = 1
    command -nargs=+ HiLink hi link <args>
  else
    command -nargs=+ HiLink hi def link <args>
  endif

  HiLink spitfirePlaceHolder Identifier
  HiLink spitfireDirective PreCondit
  HiLink spitfireKeyword Keyword
  HiLink spitfireContinuation Special
  HiLink spitfireComment Comment
  HiLink spitfireMultiLineComment Comment
  HiLink spitfireString String

  delcommand HiLink
endif

let b:current_syntax = "spitfire"

