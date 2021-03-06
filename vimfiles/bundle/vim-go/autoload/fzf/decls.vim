function! s:code(group, attr) abort
  let code = synIDattr(synIDtrans(hlID(a:group)), a:attr, "cterm")
  if code =~ '^[0-9]\+$'
    return code
  endif
endfunction

function! s:color(str, group) abort
  let fg = s:code(a:group, "fg")
  let bg = s:code(a:group, "bg")
  let bold = s:code(a:group, "bold")
  let italic = s:code(a:group, "italic")
  let reverse = s:code(a:group, "reverse")
  let underline = s:code(a:group, "underline")
  let color = (empty(fg) ? "" : ("38;5;".fg)) .
            \ (empty(bg) ? "" : (";48;5;".bg)) .
            \ (empty(bold) ? "" : ";1") .
            \ (empty(italic) ? "" : ";3") .
            \ (empty(reverse) ? "" : ";7") .
            \ (empty(underline) ? "" : ";4")
  return printf("\x1b[%sm%s\x1b[m", color, a:str)
endfunction

function! s:sink(str) abort
  if len(a:str) < 2
    return
  endif
  let cd = exists('*haslocaldir') && haslocaldir() ? 'lcd ' : 'cd '
  let dir = getcwd()
  try
    " we jump to the file directory so we can get the fullpath via fnamemodify
    " below
    execute cd . fnameescape(s:current_dir)

    let vals = matchlist(a:str[1], '|\(.\{-}\):\(\d\+\):\(\d\+\)\s*\(.*\)|')

    " i.e: main.go
    let filename =  vals[1]
    let line =  vals[2]
    let col =  vals[3]

    " i.e: /Users/fatih/vim-go/main.go
    let filepath =  fnamemodify(filename, ":p")

    let cmd = get({'ctrl-x': 'split',
          \ 'ctrl-v': 'vertical split',
          \ 'ctrl-t': 'tabe'}, a:str[0], 'e')
    execute cmd fnameescape(filepath)
    call cursor(line, col)
    silent! norm! zvzz
  finally
    "jump back to old dir
    execute cd . fnameescape(dir)
  endtry
endfunction

function! s:source(mode,...) abort
  let s:current_dir = expand('%:p:h')
  let ret_decls = []

  let bin_path = go#path#CheckBinPath('motion')
  if empty(bin_path)
    return
  endif
  let command = printf("%s -format vim -mode decls", bin_path)
  let command .= " -include ".  get(g:, "go_decls_includes", "func,type")

  call go#cmd#autowrite()

  if a:mode == 0
    " current file mode
    let fname = expand("%:p")
    if a:0 && !empty(a:1)
      let fname = a:1
    endif

    let command .= printf(" -file %s", shellescape(fname))
  else
    " all functions mode
    if a:0 && !empty(a:1)
      let s:current_dir = a:1
    endif

    let command .= printf(" -dir %s", shellescape(s:current_dir))
  endif

  let out = go#util#System(command)
  if go#util#ShellError() != 0
    call go#util#EchoError(out)
    return
  endif

  if exists("l:tmpname")
    call delete(l:tmpname)
  endif

  let result = eval(out)
  if type(result) != 4 || !has_key(result, 'decls')
    return
  endif

  let decls = result.decls

  " find the maximum function name
  let max_len = 0
  for decl in decls
    if len(decl.ident)> max_len
      let max_len = len(decl.ident)
    endif
  endfor

  for decl in decls
    " paddings
    let space = " "
    for i in range(max_len - len(decl.ident))
      let space .= " "
    endfor

    let pos = printf("|%s:%s:%s|",
          \ fnamemodify(decl.filename, ":t"),
          \ decl.line,
          \ decl.col
          \)
    call add(ret_decls, printf("%s\t%s %s\t%s",
          \ s:color(decl.ident . space, "Function"),
          \ s:color(decl.keyword, "Keyword"),
          \ s:color(pos, "SpecialComment"),
          \ s:color(decl.full, "Comment"),
          \))
  endfor

  return ret_decls
endfunc

function! fzf#decls#cmd(...) abort
  let normal_fg = s:code("Normal", "fg")
  let normal_bg = s:code("Normal", "bg")
  let cursor_fg = s:code("CursorLine", "fg")
  let cursor_bg = s:code("CursorLine", "bg")
  let colors = printf(" --color %s%s%s%s%s",
        \ &background,
        \ empty(normal_fg) ? "" : (",fg:".normal_fg),
        \ empty(normal_bg) ? "" : (",bg:".normal_bg),
        \ empty(cursor_fg) ? "" : (",fg+:".cursor_fg),
        \ empty(cursor_bg) ? "" : (",bg+:".cursor_bg),
        \)
  call fzf#run(fzf#wrap('GoDecls', {
        \ 'source': call('<sid>source', a:000),
        \ 'options': '-n 1 --ansi --prompt "GoDecls> " --expect=ctrl-t,ctrl-v,ctrl-x'.colors,
        \ 'sink*': function('s:sink')
        \ }))
endfunction

" vim: sw=2 ts=2 et
