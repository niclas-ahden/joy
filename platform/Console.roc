module [
    log!,
]

import Host

log! : Str => {}
log! = |msg| Host.log!(msg)
