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

# The status decoding and the constructor wiring are pure, so pin them here.
# A wrong wire field (say, a swapped start/len) would otherwise only show up
# in the wasm harnesses.

# Show a Try as a short string, so one helper covers every outcome a
# callback can see.
try_label = |result|
	match result {
		Ok(resp) => "ok:${resp.status.to_str()}"
		Err(HttpErr(Timeout)) => "timeout"
		Err(HttpErr(NetworkError)) => "network"
		_ => "other"
	}

# Raw status 0 means the request never completed.
expect try_label(to_try({ status: 0, headers: [], body: [] })) == "network"

# Raw status 1 means the timeout ran out.
expect try_label(to_try({ status: 1, headers: [], body: [] })) == "timeout"

# Anything the server actually sent is Ok, 4xx and 5xx included.
expect try_label(to_try({ status: 200, headers: [], body: [] })) == "ok:200"
expect try_label(to_try({ status: 404, headers: [], body: [] })) == "ok:404"
expect try_label(to_try({ status: 500, headers: [], body: [] })) == "ok:500"

# 100 is the lowest real HTTP status, right above the transport band.
expect try_label(to_try({ status: 100, headers: [], body: [] })) == "ok:100"

# Ok passes the response through untouched.
expect {
	raw = { status: 200, headers: [{ name: "server", value: "test" }], body: [104, 105] }
	to_try(raw) == Ok(raw)
}

expect Http.method_to_str(OPTIONS) == "OPTIONS"
expect Http.method_to_str(GET) == "GET"
expect Http.method_to_str(POST) == "POST"
expect Http.method_to_str(PUT) == "PUT"
expect Http.method_to_str(DELETE) == "DELETE"
expect Http.method_to_str(HEAD) == "HEAD"
expect Http.method_to_str(TRACE) == "TRACE"
expect Http.method_to_str(CONNECT) == "CONNECT"
expect Http.method_to_str(PATCH) == "PATCH"
expect Http.method_to_str(EXTENSION("BREW")) == "BREW"

expect Http.default_request == { method: GET, uri: "", headers: [], body: [], timeout_ms: NoTimeout }

expect timeout_to_u64(NoTimeout) == 0
expect timeout_to_u64(TimeoutMilliseconds(750)) == 750

# get wires up a GET with no headers, body or timeout, and its callback runs
# the raw response through to_try before the app sees it.
expect {
	match Http.get("/api/hats", try_label) {
		HttpSend(method, url, headers, body, timeout, cb) => {
			inner = Box.unbox(cb)
			method == "GET"
				and url == "/api/hats"
					and headers == []
						and body == []
							and timeout == 0
								and Box.unbox(inner({ status: 200, headers: [], body: [] })) == "ok:200"
									and Box.unbox(inner({ status: 0, headers: [], body: [] })) == "network"
		}
		_ => Bool.False
	}
}

# post carries the body and still decodes transport failures.
expect {
	match Http.post("/api/hats", "{}".to_utf8(), try_label) {
		HttpSend(method, url, headers, body, timeout, cb) => {
			inner = Box.unbox(cb)
			method == "POST"
				and url == "/api/hats"
					and headers == []
						and body == "{}".to_utf8()
							and timeout == 0
								and Box.unbox(inner({ status: 1, headers: [], body: [] })) == "timeout"
		}
		_ => Bool.False
	}
}

# request passes every field through, method and timeout converted for the
# wire.
expect {
	req = {
		method: PATCH,
		uri: "/api/hats/7",
		headers: [{ name: "content-type", value: "application/json" }],
		body: "{}".to_utf8(),
		timeout_ms: TimeoutMilliseconds(2500),
	}
	match Http.request(req, try_label) {
		HttpSend(method, url, headers, body, timeout, cb) => {
			inner = Box.unbox(cb)
			method == "PATCH"
				and url == "/api/hats/7"
					and headers == [{ name: "content-type", value: "application/json" }]
						and body == "{}".to_utf8()
							and timeout == 2500
								and Box.unbox(inner({ status: 204, headers: [], body: [] })) == "ok:204"
		}
		_ => Bool.False
	}
}

# post_file sends the whole file (start 0, len 0) with no timeout.
expect {
	match Http.post_file("/upload", 3, [{ name: "x-tag", value: "a" }], try_label) {
		HttpSendFile(method, url, headers, file, start, len, timeout, cb) => {
			inner = Box.unbox(cb)
			method == "POST"
				and url == "/upload"
					and headers == [{ name: "x-tag", value: "a" }]
						and file == 3
							and start == 0
								and len == 0
									and timeout == 0
										and Box.unbox(inner({ status: 201, headers: [], body: [] })) == "ok:201"
		}
		_ => Bool.False
	}
}

expect {
	match Http.put_file("/upload/7", 9, [], try_label) {
		HttpSendFile(method, url, headers, file, start, len, timeout, _cb) =>
			method == "PUT" and url == "/upload/7" and headers == [] and file == 9 and start == 0 and len == 0 and timeout == 0
		_ => Bool.False
	}
}

# request_file keeps the byte range and the timeout, the chunked upload
# building block.
expect {
	req = {
		method: EXTENSION("PATCH-CHUNK"),
		uri: "/upload/7",
		headers: [],
		file: 4,
		start: 65536,
		len: 32768,
		timeout_ms: TimeoutMilliseconds(9000),
	}
	match Http.request_file(req, try_label) {
		HttpSendFile(method, url, headers, file, start, len, timeout, cb) => {
			inner = Box.unbox(cb)
			method == "PATCH-CHUNK"
				and url == "/upload/7"
					and headers == []
						and file == 4
							and start == 65536
								and len == 32768
									and timeout == 9000
										and Box.unbox(inner({ status: 0, headers: [], body: [] })) == "network"
		}
		_ => Bool.False
	}
}
