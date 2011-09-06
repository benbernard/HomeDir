" File Name: FLLog.vim
" Original Date: July 8, 2005
" Description: gurupa log file syntax

" Quit when a syntax file was already loaded
if exists("b:current_syntax")
  finish
endif

syntax region Brackets start="\[" end="\] " contained contains=info,errors,dbug nextgroup=file
syntax keyword dbug DEBUG contained
syntax keyword info FORCED VERBOSE INFO contained
syntax keyword errors WARNING ERROR FATAL contained

syntax match date "^\S\+ \S\+ \d\+ \d\+:\d\+:\d\+ \d\+ \S\+ " nextgroup=app
syntax match app "\S\+ " contained nextgroup=machine
syntax match machine "\S\+ " contained nextgroup=Brackets
syntax match file "\S\+" contained

syntax match key "\*\?\w\+\*\?=" nextgroup=value
syntax match value '"[^"]*"\|[A-Z0-9-.]\+\|true\|false' contained

highlight link info Type
highlight link errors Error
highlight link date Statement
highlight link app Constant
highlight link machine Type
highlight link file Special
highlight link key Identifier
highlight link value Folded
highlight link dbug WarningMsg

let b:current_syntax = 'FLLog'

