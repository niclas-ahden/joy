module [
    log!,
]

import Effect

log! : Str => {}
log! = \msg -> Effect.log! msg
