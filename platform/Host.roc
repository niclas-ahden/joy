hosted [
    console_log!,
    http_get!,
    http_post!,
    http_put!,
    http_send_file!,
    dom_show_modal!,
    dom_close_modal!,
    keyboard_add_global_listener!,
    keyboard_add_global_listener_prevent_default!,
    time_after!,
    time_every!,
    time_debounce!,
    time_cancel!,
    crypto_hash_file_chunks!,
]

# Console
console_log! : Str => {}

# HTTP
http_get! : Str, Str => {}
http_post! : Str, List U8, Str => {}
http_put! : Str, List U8, Str => {}
http_send_file! : Str, Str, U32, U64, U64, List (Str, Str), Str => {}

# DOM
dom_show_modal! : Str => {}
dom_close_modal! : Str => {}

# Keyboard
keyboard_add_global_listener! : Str, List Str => {}
keyboard_add_global_listener_prevent_default! : Str, List Str => {}

# File hashing
crypto_hash_file_chunks! : U32, Str, U64, I64, Str, Str => {}

# Time
time_after! : U32, Str => I32
time_every! : U32, Str => I32
time_debounce! : Str, U32, Str => {}
time_cancel! : I32 => {}
