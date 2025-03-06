module [
    get!,
]

import Effect

get! : Str, Str => {}
get! = |url, raw| Effect.get!(url, raw)
