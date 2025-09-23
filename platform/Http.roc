module [
    get!,
    post!,
]

import Host

get! : Str, Str => {}
get! = |uri, event| Host.http_get!(uri, event)

post! : Str, List U8, Str => {}
post! = |uri, body, event| Host.http_post!(uri, body, event)
