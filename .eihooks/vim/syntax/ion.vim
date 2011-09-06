" Vim syntax file
" Language:    Ion
" Maintainer:  Grant Emery (gemery@)
" Last Change: 2009-11-09
" Version:     0.9

" Syntax setup
" For version 5.x: Clear all syntax items
" For version 6.x: Quit when a syntax file was already loaded

if !exists("main_syntax")
  if version < 600
    syntax clear
  elseif exists("b:current_syntax")
    finish
  endif
  let main_syntax = 'ion'
endif

" Characters allowed in Ion symbols.  This will also affect searching through
" the file with * and the characters matched by the \< and \> patterns.
set iskeyword=$,48-57,_,a-z,A-Z

" Syntax: Ion Version Marker
" This will only highlight at the very beginning of the file.  It can be
" preceeded by any amount of whitespace.
syn match   ionVersionMarker "\%^\_s*\$ion_1_0\>"

" Syntax: Special symbol names that may appear in annotations
syn match   ionSpecialSymbol "\<\$ion_symbol_table\>" contained
syn match   ionSpecialSymbol "\<\$ion_shared_symbol_table\>" contained

" Syntax: Symbol
" this must appear before Strings, otherwise the pattern for single-quoted
" symbol names will subsume the pattern for triple-quoted strings

" Pattern for identifier symbols that appear as struct keys
syn match   ionSymbol     "\k\+\_s*:"
" Pattern for single-quoted symbols, these cannot span newlines
syn region  ionSymbol     start=+'+ skip=+\\\\\|\\'+  end=+'+  end=+$+  keepend contains=ionEscape,ionEscapeError,ionNLError
" Pattern for single-quoted symbols that appear as struct keys.  This is not
" quite perfect... we can't match symbols with escaped single-quotes to include
" the colon in the match.  These will instead be picked up by the region match
" above.
syn match   ionSymbol     "'[^']\+'\_s*:" contains=ionEscape,ionEscapeError

" Syntax: Annotation
" Pattern for identifier annotations
syn match   ionAnnotation "\k\+\_s*::" contains=ionSpecialSymbol
" Pattern for single-quoted symbols that appear as annotations.  This has
" the same problem as the one for single-quote symbols above.
syn match   ionAnnotation "'[^']\+'\_s*::" contains=ionEscape,ionEscapeError

" Syntax: Strings
" Double-quoted strings cannot span newlines
syn region  ionString    start=+"+  skip=+\\\\\|\\"+  end=+"+  end=+$+  keepend contains=ionEscape,ionEscapeError,ionNLError
" Triple-single-quoted string, these can span newlines
syn region  ionString    start=+'''+  end=+'''+  contains=ionEscape,ionNLEscape,ionEscapeError
" for JSON compatibility, strings are allowed as field names in structs.
" highlight them like symbols.  This pattern has to appear here after the basic
" ionString pattern that will match as well.
syn match   ionSymbol     "\"[^"]\+\"\_s*:" contains=ionEscape,ionEscapeError
" Similarly for triple-quoted strings being used as field names in structs.
" Multiple values can appear here, spanning lines potentially.  E.g.
" { '''Part 1'''
"   '''Part 2''' : "value" }
syn match   ionSymbol     "\('''\_[^']\+'''\_s*\)\+:" contains=ionEscape,ionEscapeError

" Syntax: Escape sequences
" Errors first, so we can override non-errors later
syn match   ionEscapeError "\\." contained
" Single-character escapes
syn match   ionEscape    "\\["\\/0abfnrtv"'?]" contained
" Other escapes for bytes or code points
syn match   ionEscape    "\\x\x\{2}" contained
syn match   ionEscape    "\\u\x\{4}" contained
syn match   ionEscape    "\\U\x\{8}" contained

syn match   ionNLEscape  "\\$" contained
syn match   ionNLError   "\\$" contained

" Syntax: Numbers
" Negative and positive numbers are split here because of some difficult
" behavior in the Ion S-Exp parser.  Notably, ( --3 ) will be parsed as the
" symbol '--' followed by the number 3.  So, in order for a number to count as
" a negative number, the initial - must not be preceeded by anything except
" whitespace, a bracket of some kind, or a quote of some kind
" Positive numbers
syn match   ionNumber    "\k\@<!\(\<\(0\|[1-9]\d*\)\(\.\d*\)\=\|\.\d\+\)\([eEdD][-+]\=\d\+\)\=\(\d\|\.\)\@!"
syn match   ionNumber    "\k\@<!\<0[xX]\x\+\>"
" Negative numbers
syn match   ionNumber    "\(^\|\s\|['"(){}\[\]]\)\@<=-\(\<\(0\|[1-9]\d*\)\(\.\d*\)\=\|\.\d\+\)\([eEdD][-+]\=\d\+\)\=\(\d\|\.\)\@!"
syn match   ionNumber    "\(^\|\s\|['"(){}\[\]]\)\@<=-\<0[xX]\x\+\>"
" Special numbers
syn keyword ionNumber    nan
syn match   ionNumber    "[+-]inf\>"

" Syntax: Number errors
" Values may not start with leading zeros.
syn match   ionNumError  "\k\@<!-\=\<0\d\+\(\.\d*\)\=\([eEdD][-+]\=\d\+\)\=\>"
" A leading + is not allowed
syn match   ionNumError  "\k\@<!+\<\d*\(\.\d*\)\=\([eEdD][-+]\=\d\+\)\=\>"

" Syntax: Boolean
syn keyword ionBoolean   true false

" Syntax: Timestamp
" This could use some work.  It will recognize all correct timestamp formats,
" but incorrectly-formatted timestamps may look very strange since parts of
" timestamp may look like numbers or symbols.

" 4-digit year, followed by T
syn match ionTimestamp "\<\d\{4}T\>"
" 4-digit year, 2-digit month, followed by T
syn match ionTimestamp "\<\d\{4}-\d\{2}T\>"
" full date followed by optional T
syn match ionTimestamp "\<\d\{4}-\d\{2}-\d\{2}T\=\>"
" full date, T, hours and minutes, followed by optional (seconds and optional
" (fractional seconds)), followed by timezone in +/- HH:MM format or
" literal Z
syn match ionTimestamp "\<\d\{4}-\d\{2}-\d\{2}T\d\{2}:\d\{2}\(:\d\{2}\(\.\d\+\)\=\)\=\(\([+-]\d\{2}:\d\{2}\)\|Z\)"

" Syntax: Null
syn match ionNull      "\<null\(\.\(null\|bool\|int\|float\|decimal\|timestamp\|string\|symbol\|blob\|clob\|struct\|list\|sexp\)\)\=\(\k\|\.\)\@!"

" Syntax: Comment
syn match   ionComment    "//.*" contains=ionTodo
syn region  ionComment    start="/\*"  end="\*/"  contains=ionTodo

" Syntax: Highlight these in comments
syn keyword ionTodo       contained TODO FIXME XXX

" Syntax: Clob / Blob
" No highlighting here for contents of the blob.  Just special highlighting
" for the blob delimiters.  If it's actually a clob, the contained string will
" have normal string highlighting.
syn region ionBlob matchgroup=ionBlobDelimiter start="{{" end="}}" contains=ionString

" Define the default highlighting.
" For version 5.7 and earlier: only when not done already
" For version 5.8 and later: only when an item doesn't have highlighting yet
if version >= 508 || !exists("did_ion_syn_inits")
  if version < 508
    let did_ion_syn_inits = 1
    command -nargs=+ HiLink hi link <args>
  else
    command -nargs=+ HiLink hi def link <args>
  endif
  HiLink ionAnnotation         PreProc
  HiLink ionBlobDelimiter      String
  HiLink ionBoolean            Boolean
  HiLink ionComment            Comment
  HiLink ionEscape             Special
  HiLink ionNLError            Error
  HiLink ionNLEscape           Special
  HiLink ionNull               Function
  HiLink ionNumber             Number
  HiLink ionSpecialSymbol      StorageClass
  HiLink ionString             String
  HiLink ionSymbol             Special
  HiLink ionTimestamp          Number
  HiLink ionTodo               Todo
  HiLink ionVersionMarker      StorageClass

  HiLink ionNumError           Error
  HiLink ionEscapeError        Error
  delcommand HiLink
endif

let b:current_syntax = "ion"
if main_syntax == 'ion'
  unlet main_syntax
endif

" Vim settings
" vim: ts=8 fdm=marker

