hosted [
    close_modal!,
    get!,
    log!,
    post!,
    show_modal!,
]

# Console
log! : Str => {}

# HTTP
get! : Str, Str => {}
post! : Str, List U8, Str => {}

# DOM
close_modal! : Str => {}
show_modal! : Str => {}
