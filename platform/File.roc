module [
    read_bytes_at!,
]

import Host

## Read `len` bytes starting at byte offset `start` from a browser File (one
## selected via `<input type="file">` and referenced by `file_id`), and fire
## `event` with those bytes.
##
## The bytes never enter Roc memory directly. The host slices the File's blob
## in JS and returns the range in the event payload as a `U8` array, the same
## encoding HTTP response bodies use, so it decodes straight into a `List U8`.
##
## This mirrors the offset+length shape of the `read_bytes_at!` found on
## disk-backed platforms. The resource handle is a numeric `file_id` rather
## than a path, and the result arrives via an event because the client platform
## is event-driven. Reading the first bytes (`start = 0`) is handy for
## inspecting a file's signature before committing to a large upload.
##
## Fires `event` with:
## - Success: `{"file_id":<id>,"bytes":[<u8>,...]}`
## - Failure: `{"file_id":<id>,"err":"<message>"}`
##
## ```
## File.read_bytes_at!(file_id, 0, 12, "FileHeadRead")
## ```
read_bytes_at! : U32, U64, U64, Str => {}
read_bytes_at! = |file_id, start, len, event|
    Host.file_read_bytes_at!(file_id, start, len, event)
