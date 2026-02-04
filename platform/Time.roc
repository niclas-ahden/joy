module [
    after!,
    every!,
    debounce!,
    cancel!,
]

import Host

## Fire an event once after `delay_ms` milliseconds. Returns a timer ID for cancellation.
after! : U32, Str => I32
after! = |delay_ms, event| Host.time_after!(delay_ms, event)

## Fire an event repeatedly every `interval_ms` milliseconds. Returns a timer ID for cancellation.
every! : U32, Str => I32
every! = |interval_ms, event| Host.time_every!(interval_ms, event)

## Debounce an event by `key`: resets the `delay_ms` timer on each call.
debounce! : Str, U32, Str => {}
debounce! = |key, delay_ms, event| Host.time_debounce!(key, delay_ms, event)

## Cancel a timer by its ID (returned from `after!` or `every!`).
cancel! : I32 => {}
cancel! = |timer_id| Host.time_cancel!(timer_id)
