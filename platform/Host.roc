hosted [
    console_log!,
    http_get!,
    http_post!,
    dom_show_modal!,
    dom_close_modal!,
    keyboard_add_global_listener!,
]

# Console
console_log! : Str => {}

# HTTP
http_get! : Str, Str => {}
http_post! : Str, List U8, Str => {}

# DOM
dom_show_modal! : Str => {}
dom_close_modal! : Str => {}

# Keyboard
keyboard_add_global_listener! : Str, List Str => {}
