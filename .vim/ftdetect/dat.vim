augroup dat
  autocmd!

  autocmd BufReadPre,FileReadPre     *.dat execute ":let s:perlExecutable = system('" . expand(g:ApolloRoot) . "/bin/determinePerlForStorable " . expand("<afile>") . "')"
  autocmd BufReadPre,FileReadPre     *.dat set bin
  autocmd BufReadPost,FileReadPost   *.dat silent execute " :'[,']!" . expand(s:perlExecutable) . " " . expand(g:ApolloRoot) . "/bin/dumpStorable " . expand("<afile>")

  autocmd BufReadPost,FileReadPost   *.dat set nobin
  autocmd BufReadPost,FileReadPost   *.dat set ft=perl
  autocmd BufReadPost,FileReadPost   *.dat execute ":doautocmd BufReadPost " . expand("%:r")

  autocmd BufWritePost,FileWritePost *.dat silent execute " :%!" . expand(s:perlExecutable) . " " . expand(g:ApolloRoot) . "/bin/rewriteStorable " . expand("<afile>")

augroup END

