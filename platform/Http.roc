module [
    get!,
    post!,
]

import Host

get! : Str, Str => {}
get! = |uri, event| Host.get!(uri, event)

post! : Str, List U8, Str => {}
post! = |uri, body, event| Host.post!(uri, body, event)
