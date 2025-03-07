module [
    get!,
]

import Host

get! : Str, Str => {}
get! = |url, raw| Host.get!(url, raw)
