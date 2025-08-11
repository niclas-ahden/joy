module [
    get!,
]

import Host

get! : Str, Str => {}
get! = |uri, raw| Host.get!(uri, raw)
