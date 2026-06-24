module [
    FileBody,
    Header,
    get!,
    json_headers,
    post!,
    put!,
    post_file!,
    put_file!,
]

import Host

## An HTTP header as a `(name, value)` pair — the same shape the host and other
## Roc libraries use.
Header : (Str, Str)

## Headers for sending and accepting a JSON body. Pass `headers: Http.json_headers`
## on a request whose body is `Encode.to_bytes(payload, Json.utf8)`.
json_headers : List Header
json_headers = [
    ("Content-Type", "application/json"),
    ("Accept", "application/json"),
]

## What to send as the body of a file upload request.
## `File` sends the entire file. `Slice` sends a byte range.
FileBody : [File U32, Slice { file : U32, start : U64, len : U64 }]

## Send a GET request. `on_response` fires with a JSON payload:
## `{"ok":{"status":200,"body":[...]}}` or `{"err":"message"}`.
##
## Relative URLs (starting with `/`) are resolved against the page origin.
##
## ```
## Http.get!({ url: "/api/data", headers: [], on_response: encode_event(DataLoaded) })
## ```
get! : { url : Str, headers : List Header, on_response : Str } => {}
get! = |{ url, headers, on_response }|
    Host.http_get!(url, headers, on_response)

## Send a POST request with a byte body. `on_response` is the event fired with
## the response (see [get!] for the payload shape).
##
## ```
## Http.post!({
##     url: "/api/submit",
##     body: Encode.to_bytes(payload, Json.utf8),
##     headers: Http.json_headers,
##     on_response: encode_event(Submitted),
## })
## ```
post! : { url : Str, body : List U8, headers : List Header, on_response : Str } => {}
post! = |{ url, body, headers, on_response }|
    Host.http_post!(url, body, headers, on_response)

## Send a PUT request with a byte body. Same shape as [post!].
##
## ```
## Http.put!({
##     url: "/api/resource/1",
##     body: Encode.to_bytes(payload, Json.utf8),
##     headers: Http.json_headers,
##     on_response: encode_event(Updated),
## })
## ```
put! : { url : Str, body : List U8, headers : List Header, on_response : Str } => {}
put! = |{ url, body, headers, on_response }|
    Host.http_put!(url, body, headers, on_response)

## Send a POST request with a browser File as the body. The file data stays in
## JS heap memory -- it is never copied into WASM. Use `File(file_id)` for the
## whole file, or `Slice({ file, start, len })` for a byte range.
##
## ```
## Http.post_file!({
##     url: "/upload",
##     body: File(file_id),
##     headers: [("X-Chunk", "0")],
##     on_response: encode_event(Uploaded),
## })
## ```
post_file! : { url : Str, body : FileBody, headers : List Header, on_response : Str } => {}
post_file! = |{ url, body, headers, on_response }|
    { file_id, start, len } = file_body_to_params(body)
    Host.http_send_file!("POST", url, file_id, start, len, headers, on_response)

## Send a PUT request with a browser File as the body. Same as [post_file!] but uses PUT.
##
## ```
## Http.put_file!({
##     url: "/upload/chunk",
##     body: Slice({ file: file_id, start: 0, len: chunk_size }),
##     headers: [],
##     on_response: encode_event(ChunkUploaded),
## })
## ```
put_file! : { url : Str, body : FileBody, headers : List Header, on_response : Str } => {}
put_file! = |{ url, body, headers, on_response }|
    { file_id, start, len } = file_body_to_params(body)
    Host.http_send_file!("PUT", url, file_id, start, len, headers, on_response)

file_body_to_params : FileBody -> { file_id : U32, start : U64, len : U64 }
file_body_to_params = |body|
    when body is
        File(file_id) -> { file_id, start: 0, len: 0 }  # len 0 = whole file
        Slice({ file, start, len }) -> { file_id: file, start, len }
