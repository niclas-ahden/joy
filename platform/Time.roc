module [
    after!,
    every!,
    debounce!,
    cancel!,
]

import Host

after! : U32, Str => I32
after! = |delay_ms, event| Host.time_after!(delay_ms, event)

every! : U32, Str => I32
every! = |interval_ms, event| Host.time_every!(interval_ms, event)

debounce! : Str, U32, Str => {}
debounce! = |key, delay_ms, event| Host.time_debounce!(key, delay_ms, event)

cancel! : I32 => {}
cancel! = |timer_id| Host.time_cancel!(timer_id)