module [
    get!,
    post!,
]

import Host

## Send a GET request to `uri`. The response fires the named event.
get! : Str, Str => {}
get! = |uri, event| Host.http_get!(uri, event)

## Send a POST request to `uri` with the given `body`. The response fires the named event.
post! : Str, List U8, Str => {}
post! = |uri, body, event| Host.http_post!(uri, body, event)
