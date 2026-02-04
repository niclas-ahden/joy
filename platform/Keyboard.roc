module [
    add_global_listener!,
    add_global_listener_prevent_default!,
]

import Host

## Listen for `keydown` events on the document. Empty `key_filter` matches all keys.
add_global_listener! : Str, List Str => {}
add_global_listener! = |event_name, key_filter| Host.keyboard_add_global_listener!(event_name, key_filter)

## Like `add_global_listener!`, but calls `preventDefault` on matching events.
add_global_listener_prevent_default! : Str, List Str => {}
add_global_listener_prevent_default! = |event_name, key_filter| Host.keyboard_add_global_listener_prevent_default!(event_name, key_filter)
