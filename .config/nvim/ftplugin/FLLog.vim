
function! LogFoldLevel(lineNum)
    let line=getline(a:lineNum)
    if line =~ '\[FATAL\]'
        return 0
    elseif line =~ '\[ERROR\]'
        return 1
    elseif line =~ '\[WARNING\]'
        return 2
    elseif line =~ '\[INFO\]'
        return 3
    elseif line =~ '\[DEBUG\]'
        return 4
    elseif line=~ '\[VERBOSE\]'
        return 5
    elseif line=~ '\[FORCED\]'
        return 6
    else
        return -1
    endif
endfunction

setlocal foldenable
setlocal foldlevel=1
setlocal foldmethod=expr
setlocal foldexpr=LogFoldLevel(v:lnum)


