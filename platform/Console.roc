module [
    log!,
]

import Host

log! : Str => {}
log! = |msg| Host.console_log!(msg)
