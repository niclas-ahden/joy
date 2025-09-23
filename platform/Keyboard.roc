module [
    add_global_listener!,
]

import Host

add_global_listener! : Str, List Str => {}
add_global_listener! = |event_name, key_filter| Host.keyboard_add_global_listener!(event_name, key_filter)