" see `:help new-filetype' for more information about this file

if exists("did_load_filetypes")
    finish
endif

augroup filetypedetect
  autocmd BufNewFile,BufRead *.o,*.so,*.ko setfiletype object " Object files

  " see: https://w.amazon.com/?VimFLLogSyntax
  autocmd BufReadPost * if ! (exists('g:disableFLLogSyntax') && g:disableFLLogSyntax)
  autocmd BufReadPost *   if (getline(1) =~ "^\\w\\{3\\} \\w\\{3\\} \\d\\{2\\} \\d\\{2\\}:\\d\\{2\\}:\\d\\{2\\} \\d\\{4\\}")
  autocmd BufReadPost *     setfiletype FLLog
  autocmd BufReadPost *   endif
  autocmd BufReadPost * endif

  autocmd BufReadPost .tags        setfiletype tags     " .tag files need love too
  autocmd BufReadPost *.mi         setfiletype mason    " mason rules
  autocmd BufReadPost *.m          setfiletype mason    " mason rules
  autocmd BufReadPost .z*          setfiletype zsh      " obscure zsh files need love too

  autocmd BufReadPost *.t          setfiletype perl     " perl unit test files

  autocmd BufReadPost *.wiki       setfiletype Wikipedia " for use with wikiUtil

  " Discover perforce type from first line of the file
  autocmd BufReadPost *  if getline(1) =~ '^# A Perforce .* Specification.'
  autocmd BufReadPost *    setfiletype perforce
  autocmd BufReadPost *  elseif getline(1) =~ '^P4SUB: -*'
  autocmd BufReadPost *    setfiletype perforce
  autocmd BufReadPost *  endif
augroup END

