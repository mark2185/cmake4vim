" autoload/utils/exec/job.vim - contains executable helpers
" Maintainer:   Ilya Churaev <https://github.com/ilyachur>

" Private functions {{{ "
let s:cmake4vim_job = {}
let s:cmake4vim_buf = 'cmake4vim_execute'
let s:err_fmt = ''

function! s:closeBuffer() abort
    let l:bufnr = bufnr(s:cmake4vim_buf)
    if l:bufnr == -1
        return
    endif

    let l:winnr = bufwinnr(l:bufnr)
    if l:winnr != -1
        exec l:winnr.'wincmd c'
    endif

    silent exec 'bwipeout ' . l:bufnr
endfunction

function! s:createQuickFix() abort
    let l:bufnr = bufnr(s:cmake4vim_buf)
    if l:bufnr == -1
        return
    endif
    let l:old_error = &errorformat
    if s:err_fmt !=# ''
        let &errorformat = s:err_fmt
    endif
    execute 'cgetbuffer ' . l:bufnr
    call setqflist( [], 'a', { 'title' : s:cmake4vim_job[ 'cmd' ] } )
    if s:err_fmt !=# ''
        let &errorformat = l:old_error
    endif
endfunction

function! s:vimClose(channel) abort
    call s:createQuickFix()
    call s:closeBuffer()
    if has_key(s:cmake4vim_job, 'job')
        if job_info(s:cmake4vim_job['job'])['exitval'] == 0
            call utils#common#Warning('Success!')
        else
            echom 'Failure!'
        endif
    endif
    let s:cmake4vim_job = {}

    silent cwindow
    cbottom
endfunction

function! s:nVimOut(job_id, data, event) abort
    let l:bufnr = bufnr(s:cmake4vim_buf)
    call setbufvar(l:bufnr, '&modifiable', 1)
    for val in filter(a:data, '!empty(v:val)')
        silent call appendbufline(l:bufnr, '$', trim(val, "\r\n"))
    endfor
    call setbufvar(l:bufnr, '&modifiable', 0)
endfunction

function! s:nVimExit(job_id, data, event) abort
    if empty(s:cmake4vim_job) || a:job_id != s:cmake4vim_job['job']
        return
    endif

    " just to be sure all messages were processed
    sleep 100m

    " using only appendbufline results in an empty first line
    let l:bufnr = bufnr(s:cmake4vim_buf)
    call setbufvar(l:bufnr, '&modifiable', 1)
    call deletebufline( l:bufnr, 1 )
    call setbufvar(l:bufnr, '&modifiable', 0)

    call s:createQuickFix()
    call s:closeBuffer()
    let s:cmake4vim_job = {}
    if a:data != 0
        copen
    endif
endfunction

function! s:createJobBuf() abort
    let l:cursor_was_in_quickfix = getwininfo(win_getid())[0]['quickfix']

    call s:closeBuffer()
    " qflist is open somewhere
    if !empty(filter(range(1, winnr('$')), 'getwinvar(v:val, "&ft") ==# "qf"'))
        " move the cursor there
        copen
        silent execute 'keepalt edit ' . s:cmake4vim_buf
    else
        silent execute 'keepalt belowright 10split ' . s:cmake4vim_buf
    endif
    setlocal bufhidden=hide buftype=nofile buflisted nolist
    setlocal noswapfile nowrap nomodifiable
    nmap <buffer> <C-c> :call utils#exec#job#stop()<CR>
    if !l:cursor_was_in_quickfix
        wincmd p
    endif
    return bufnr(s:cmake4vim_buf)
endfunction
" }}} Private functions "

function! utils#exec#job#stop() abort
    if empty(s:cmake4vim_job)
        call s:closeBuffer()
        return
    endif
    let l:job = s:cmake4vim_job['job']
    try
        if has('nvim')
            call jobstop(l:job)
        else
            call job_stop(l:job)
        endif
    catch
    endtry
    call s:createQuickFix()
    call s:closeBuffer()
    let s:cmake4vim_job = {}
    copen
    call utils#common#Warning('Job is cancelled!')
endfunction

function! utils#exec#job#run(cmd, err_fmt) abort
    " if there is a job or if the buffer is open, abort
    if !empty(s:cmake4vim_job) || bufnr(s:cmake4vim_buf) != -1
        call utils#common#Warning('Async execute is already running')
        return -1
    endif
    let l:outbufnr = s:createJobBuf()
    let s:err_fmt = a:err_fmt
    if has('nvim')
        let l:job = jobstart(a:cmd, {
                    \ 'on_stdout': function('s:nVimOut'),
                    \ 'on_stderr': function('s:nVimOut'),
                    \ 'on_exit': function('s:nVimExit'),
                    \ })
    else
        let l:cmd = has('win32') ? a:cmd : [&shell, '-c', a:cmd]
        let l:job = job_start(l:cmd, {
                    \ 'close_cb': function('s:vimClose'),
                    \ 'out_io' : 'buffer', 'out_buf' : l:outbufnr,
                    \ 'err_io' : 'buffer', 'err_buf' : l:outbufnr,
                    \ 'out_modifiable' : 0,
                    \ 'err_modifiable' : 0,
                    \ })
    endif
    let s:cmake4vim_job = { 'job': l:job, 'cmd': a:cmd }
    if !has('nvim')
       let s:cmake4vim_job['channel'] = job_getchannel(l:job)
    endif
    return l:job
endfunction
