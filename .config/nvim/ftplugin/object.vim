au BufWritePost *.o,[^.]* call s:UpdateHexFile()
au BufWritePost *.binary2hex call s:UpdateObjectFile()

function! s:UpdateHexFile()
    if &ft=='object' && &bin && exists("b:corresponding_hex")
	exe "!xxd " . bufname("%") . " > " . b:corresponding_hex
    endif
endfunction

function! s:UpdateObjectFile()
    if &ft=='xxd' && &bin && exists("b:orig_obj_name")
	exe "!xxd -r " . bufname("%") . " > " . b:orig_obj_name
    endif
endfunction

function! ObjectHackTime()
    let obj_name = bufname("%")
    let elffile = tempname() . ".elfheader"
    let hexfile = tempname() . ".binary2hex"
    let objdumpfile = tempname() . ".objdump"
    exe "!readelf -a " . obj_name . " > " . elffile
    exe "!objdump -S -t -h -g -l " . obj_name . " > " . objdumpfile
    exe "!xxd " . obj_name . " > " . hexfile
    exe "e " . objdumpfile
    set ft=asm
    vs
    wincmd l
    exe "e " . elffile
    set ft=asm
    sp
    wincmd j
    exe "e " . hexfile
    set ft=xxd
    set binary
    let b:orig_obj_name = obj_name
    wincmd h
    sp
    wincmd j
    exe "e " . obj_name
    let b:corresponding_hex = hexfile
endfunction


call ObjectHackTime()
