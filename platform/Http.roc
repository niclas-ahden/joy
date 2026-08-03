## HTTP requests as effects. The response arrives as a typed message:
## `Http.get(url, |result| GotData(result))` calls your function with a
## `Try(Response, ...)` and feeds the resulting msg to `update`.
##
## Any status the server actually sent is `Ok(response)`, including 4xx and
## 5xx: an `Err(HttpErr(...))` is reserved for transport failures where no
## response exists at all. `NetworkError` means the request never completed
## (network failure, CORS, ...), `Timeout` means the request's `timeout_ms`
## ran out first. A match on the result covers every outcome without magic
## status numbers.
import Effect exposing [Effect]

# The HTTP method, mirrored after basic-cli. `EXTENSION` carries any method
# name the fixed set lacks.
Method : [OPTIONS, GET, POST, PUT, DELETE, HEAD, TRACE, CONNECT, PATCH, EXTENSION(Str)]

timeout_to_u64 : [TimeoutMilliseconds(U64), NoTimeout] -> U64
timeout_to_u64 = |t|
	match t {
		TimeoutMilliseconds(ms) => ms
		NoTimeout => 0
	}

## Decode the wire response the host delivers. Statuses 1-99 are impossible
## in real HTTP, so the runtime reports transport failures in-band: raw
## status 0 means the request never completed, raw status 1 means it timed
## out. Everything else is a response the server actually sent.
to_try : { status : U16, headers : List({ name : Str, value : Str }), body : List(U8) } -> Try({ status : U16, headers : List({ name : Str, value : Str }), body : List(U8) }, [HttpErr([Timeout, NetworkError]), ..])
to_try = |raw|
	if raw.status == 0 {
		Err(HttpErr(NetworkError))
	} else if raw.status == 1 {
		Err(HttpErr(Timeout))
	} else {
		Ok(raw)
	}

Http := [].{

	## An HTTP header, e.g. `{ name: "Content-Type", value: "application/json" }`.
	Header : { name : Str, value : Str }

	## An HTTP response. Any status the server sent lands here, 4xx and 5xx
	## included, while transport failures never produce a `Response` at all.
	Response : { status : U16, headers : List(Header), body : List(U8) }

	## An HTTP request, for `Http.request`.
	Request : {
		method : Method,
		uri : Str,
		headers : List(Header),
		body : List(U8),
		timeout_ms : [TimeoutMilliseconds(U64), NoTimeout],
	}

	## A `GET` request with empty headers/body, no timeout, and an empty URI.
	## Override the fields you need, e.g.
	## `{ ..Http.default_request, uri: "https://example.com" }`.
	default_request : Request
	default_request = {
		method: GET,
		uri: "",
		headers: [],
		body: [],
		timeout_ms: NoTimeout,
	}

	## The request method as it appears on the wire.
	method_to_str : Method -> Str
	method_to_str = |method|
		match method {
			OPTIONS => "OPTIONS"
			GET => "GET"
			POST => "POST"
			PUT => "PUT"
			DELETE => "DELETE"
			HEAD => "HEAD"
			TRACE => "TRACE"
			CONNECT => "CONNECT"
			PATCH => "PATCH"
			EXTENSION(ext) => ext
		}

	get : Str, (Try(Response, [HttpErr([Timeout, NetworkError]), ..]) -> msg) -> Effect(msg)
	get = |url, on_result|
		Effect.http_send("GET", url, [], [], 0, |raw| on_result(to_try(raw)))

	post : Str, List(U8), (Try(Response, [HttpErr([Timeout, NetworkError]), ..]) -> msg) -> Effect(msg)
	post = |url, body, on_result|
		Effect.http_send("POST", url, [], body, 0, |raw| on_result(to_try(raw)))

	## Full control: method, uri, headers, body, timeout.
	request : Request, (Try(Response, [HttpErr([Timeout, NetworkError]), ..]) -> msg) -> Effect(msg)
	request = |req, on_result|
		Effect.http_send(
			method_to_str(req.method),
			req.uri,
			req.headers,
			req.body,
			timeout_to_u64(req.timeout_ms),
			|raw| on_result(to_try(raw)),
		)

	## POST a user-picked file as the request body. The file id comes from
	## `Attribute.on_file`; the browser streams the File object directly, so
	## the bytes never enter wasm memory (uploads of any size cost no wasm
	## heap).
	post_file : Str, U32, List(Header), (Try(Response, [HttpErr([Timeout, NetworkError]), ..]) -> msg) -> Effect(msg)
	post_file = |url, file, headers, on_result|
		Effect.http_send_file("POST", url, headers, file, 0, 0, 0, |raw| on_result(to_try(raw)))

	## PUT a user-picked file as the request body (see `post_file`).
	put_file : Str, U32, List(Header), (Try(Response, [HttpErr([Timeout, NetworkError]), ..]) -> msg) -> Effect(msg)
	put_file = |url, file, headers, on_result|
		Effect.http_send_file("PUT", url, headers, file, 0, 0, 0, |raw| on_result(to_try(raw)))

	## Full control over a file-body request, including a byte range and a
	## timeout. `start` and `len` slice the file (`len` 0 means through the
	## end), the building block for chunked uploads of large files.
	request_file : { method : Method, uri : Str, headers : List(Header), file : U32, start : U64, len : U64, timeout_ms : [TimeoutMilliseconds(U64), NoTimeout] }, (Try(Response, [HttpErr([Timeout, NetworkError]), ..]) -> msg) -> Effect(msg)
	request_file = |req, on_result|
		Effect.http_send_file(
			method_to_str(req.method),
			req.uri,
			req.headers,
			req.file,
			req.start,
			req.len,
			timeout_to_u64(req.timeout_ms),
			|raw| on_result(to_try(raw)),
		)
}
