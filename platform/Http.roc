module [
    FileBody,
    get!,
    post!,
    put!,
    post_file!,
    put_file!,
]

import Host

## What to send as the body of a file upload request.
## `File` sends the entire file. `Slice` sends a byte range.
##
## ```
## # Whole file
## Http.post_file!(url, File(file_id), [], event)
##
## # Chunk (bytes 0 to 95MB)
## Http.post_file!(url, Slice({ file: file_id, start: 0, len: 95_000_000 }), [], event)
## ```
FileBody : [File U32, Slice { file : U32, start : U64, len : U64 }]

## Send a GET request. The response fires the named event with a JSON payload:
## `{"ok":{"status":200,"body":[...]}}` or `{"err":"message"}`.
##
## Relative URLs (starting with `/`) are resolved against the page origin.
##
## ```
## Http.get!("/api/data", encode_event(DataLoaded))
## ```
get! : Str, Str => {}
get! = |uri, event| Host.http_get!(uri, event)

## Send a POST request with a byte body. The response fires the named event.
##
## ```
## Http.post!("/api/submit", Encode.to_bytes(payload, Json.utf8), encode_event(Submitted))
## ```
post! : Str, List U8, Str => {}
post! = |uri, body, event| Host.http_post!(uri, body, event)

## Send a PUT request with a byte body. The response fires the named event.
##
## ```
## Http.put!("/api/resource/1", Encode.to_bytes(payload, Json.utf8), encode_event(Updated))
## ```
put! : Str, List U8, Str => {}
put! = |uri, body, event| Host.http_put!(uri, body, event)

## Send a POST request with a browser File as the body. The file data stays in
## JS heap memory -- it is never copied into WASM.
##
## Use `File(file_id)` for the whole file, or `Slice({ file, start, len })` for a byte range.
## Headers are a list of `(name, value)` pairs.
##
## ```
## Http.post_file!("/upload", File(file_id), [("X-Chunk", "0")], encode_event(Uploaded))
## ```
post_file! : Str, FileBody, List (Str, Str), Str => {}
post_file! = |url, body, headers, event|
    { file_id, start, len } = file_body_to_params(body)
    Host.http_send_file!("POST", url, file_id, start, len, headers, event)

## Send a PUT request with a browser File as the body. Same as [post_file!] but uses PUT.
##
## ```
## Http.put_file!("/upload/chunk", Slice({ file: file_id, start: 0, len: chunk_size }), [], encode_event(ChunkUploaded))
## ```
put_file! : Str, FileBody, List (Str, Str), Str => {}
put_file! = |url, body, headers, event|
    { file_id, start, len } = file_body_to_params(body)
    Host.http_send_file!("PUT", url, file_id, start, len, headers, event)

file_body_to_params : FileBody -> { file_id : U32, start : U64, len : U64 }
file_body_to_params = |body|
    when body is
        File(file_id) -> { file_id, start: 0, len: 0 }  # len 0 = whole file
        Slice({ file, start, len }) -> { file_id: file, start, len }
