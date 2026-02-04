module [
    log!,
]

import Host

## Log a message to the browser console.
log! : Str => {}
log! = |msg| Host.console_log!(msg)
