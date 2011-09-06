
autocmd BufReadPost,BufNewFile  *.cfg  if match(expand('<afile>:p:h'), "brazil-config") > -1
autocmd BufReadPost,BufNewFile  *.cfg    set filetype=brazil-config
autocmd BufReadPost,BufNewFile  *.cfg  endif

autocmd BufReadPost,BufNewFile  packageInfo,Config let b:brazil_package_Config = 1
autocmd BufReadPost,BufNewFile  packageInfo,Config set filetype=brazil-config

" use !=# to make sure case matters
autocmd BufReadPost,BufNewFile  *  if match(expand("<afile>:p:h"), "release-info/versionSets") > -1
autocmd BufReadPost,BufNewFile  *    if expand("<afile>:t") !=# 'details'
autocmd BufReadPost,BufNewFile  *      let b:brazil_package_Config = 1
autocmd BufReadPost,BufNewFile  *      set filetype=brazil-config
autocmd BufReadPost,BufNewFile  *    endif
autocmd BufReadPost,BufNewFile  *  endif
