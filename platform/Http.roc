## Make HTTP requests, and get the answers as messages:
##
## ```roc
## Msg : [
##     UserClickedLoad,
##     ServerAnswered(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
## ]
##
## load : Effect(Msg)
## load = Http.get("/hello", |answer| ServerAnswered(answer))
##
## update = |model, msg|
##     match msg {
##         UserClickedLoad => (model, [load])
##
##         ServerAnswered(Ok(response)) => {
##             text = Str.from_utf8_lossy(response.body)
##             ({ ..model, text }, [])
##         }
##
##         ServerAnswered(Err(_)) =>
##             ({ ..model, text: "No answer" }, [])
##     }
## ```
##
## A request is an effect: return it from `init` or `update`, with a function
## that turns the answer into one of your messages.
##
## ## What you get back
##
## The answer is one of three things:
##
## - `Ok(response)`: the server answered. That includes answers like 404 and
##   500, so look at `response.status` to see how it went.
## - `Err(HttpErr(NetworkError))`: no answer came. The user may be offline,
##   or the browser refused to make the request (CORS).
## - `Err(HttpErr(Timeout))`: no answer came in the time you allowed.
##
## ## Reading the body
##
## `response.body` is bytes. `Str.from_utf8_lossy(response.body)` gives you
## its text, and `Json.parse` turns JSON text into the type you ask for:
##
## ```roc
## todos : Try(List({ title : Str, done : Bool }), _)
## todos = Json.parse(Str.from_utf8_lossy(response.body))
## ```
##
## The guide has [an HTTP example](../../#example-http) to try.
import Effect
import Wire

# The HTTP method, mirrored after basic-cli. `EXTENSION` carries any method
# name the fixed set lacks.
Method : [OPTIONS, GET, POST, PUT, DELETE, HEAD, TRACE, CONNECT, PATCH, EXTENSION(Str)]

timeout_to_u64 : [TimeoutMilliseconds(U64), NoTimeout] -> U64
timeout_to_u64 = |t|
	match t {
		TimeoutMilliseconds(ms) => ms
		NoTimeout => 0
	}

# Decode the response the http feature answers with. Statuses 1-99 are
# impossible in real HTTP, so it reports transport failures in-band: raw
# status 0 means the request never completed, raw status 1 means it timed
# out. Everything else is a response the server actually sent.
to_try : { status : U16, headers : List({ name : Str, value : Str }), body : List(U8) } -> Try({ status : U16, headers : List({ name : Str, value : Str }), body : List(U8) }, [HttpErr([Timeout, NetworkError])])
to_try = |raw|
	if raw.status == 0 {
		Err(HttpErr(NetworkError))
	} else if raw.status == 1 {
		Err(HttpErr(Timeout))
	} else {
		Ok(raw)
	}

Http := [].{

	## One header of a request or a response, like
	## `{ name: "Content-Type", value: "application/json" }`.
	Header : { name : Str, value : Str }

	## What the server answered.
	##
	## - `status` is the status code: 200 when all went well, 404 when there
	##   is nothing at that address, and so on.
	## - `headers` are the headers the server sent along.
	## - `body` is the content, as bytes. See "Reading the body" at the top of
	##   this page.
	Response : { status : U16, headers : List(Header), body : List(U8) }

	## Everything about a request, for [Http.request]. You rarely write one
	## from scratch: start from [Http.default_request] and change what you
	## need.
	##
	## - `method` is `GET`, `POST`, `PUT`, `DELETE` and so on.
	## - `uri` is the address to send it to.
	## - `headers` are the headers to send along.
	## - `body` is the content to send, as bytes. `Str.to_utf8` turns text
	##   into bytes.
	## - `timeout_ms` is how long to wait for the answer:
	##   `TimeoutMilliseconds(5000)` gives up after five seconds, and
	##   `NoTimeout` waits for as long as the browser does.
	Request : {
		method : Method,
		uri : Str,
		headers : List(Header),
		body : List(U8),
		timeout_ms : [TimeoutMilliseconds(U64), NoTimeout],
	}

	## A request to start from: a `GET` with no headers, no body and no
	## timeout. Change the fields you need:
	##
	## ```roc
	## { ..Http.default_request, uri: "/todos.json" }
	## ```
	default_request : Request
	default_request = {
		method: GET,
		uri: "",
		headers: [],
		body: [],
		timeout_ms: NoTimeout,
	}

	## A method's name as text, like `"GET"`.
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

	## Make a `GET` request.
	##
	## ```roc
	## Http.get("/todos.json", |answer| ServerSentTodos(answer))
	## ```
	##
	## The second argument is how the answer becomes one of your messages.
	## The top of this page shows what the answer can be.
	get : Str, (Try(Response, [HttpErr([Timeout, NetworkError])]) -> msg) -> Effect(msg)
	get = |url, on_result|
		send("GET", url, [], [], 0, on_result)

	## Make a `POST` request with a body. The body is bytes, and
	## `Str.to_utf8` turns text into bytes:
	##
	## ```roc
	## body = Str.to_utf8(Json.to_str({ title: "Buy milk" }))
	##
	## Http.post("/todos", body, |answer| ServerSavedTodo(answer))
	## ```
	##
	## `post` sends no headers. To tell the server that the body is JSON, or
	## to use another method, use [Http.request].
	post : Str, List(U8), (Try(Response, [HttpErr([Timeout, NetworkError])]) -> msg) -> Effect(msg)
	post = |url, body, on_result|
		send("POST", url, [], body, 0, on_result)

	## A request where you decide everything: the method, the headers, the
	## body and how long to wait. Start from [Http.default_request] and change
	## what you need:
	##
	## ```roc
	## json = { name: "Content-Type", value: "application/json" }
	## body = Str.to_utf8(Json.to_str({ title: "Buy milk" }))
	##
	## Http.request(
	##     {
	##         ..Http.default_request,
	##         method: POST,
	##         uri: "/todos",
	##         headers: [json],
	##         body,
	##         timeout_ms: TimeoutMilliseconds(5000),
	##     },
	##     |answer| ServerSavedTodo(answer),
	## )
	## ```
	request : Request, (Try(Response, [HttpErr([Timeout, NetworkError])]) -> msg) -> Effect(msg)
	request = |req, on_result|
		send(method_to_str(req.method), req.uri, req.headers, req.body, timeout_to_u64(req.timeout_ms), on_result)

	## Upload a file the user picked, with a `POST` request. The file is the
	## body.
	##
	## A file input tells you about the file with `on_file` (in joy-html's
	## `Attribute`), and what it gives you has the file's `id`:
	##
	## ```roc
	## input([type("file"), on_file(|file| UserPickedFile(file))])
	## ```
	##
	## ```roc
	## Http.post_file(
	##     "/upload",
	##     file.id,
	##     [],
	##     |answer| ServerTookFile(answer),
	## )
	## ```
	##
	## The browser sends the file straight from where it is. Your app never
	## holds its bytes, so a big file costs it no memory.
	post_file : Str, U32, List(Header), (Try(Response, [HttpErr([Timeout, NetworkError])]) -> msg) -> Effect(msg)
	post_file = |url, file, headers, on_result|
		send_file("POST", url, headers, { file, start: 0, len: 0 }, 0, on_result)

	## The same as [Http.post_file], with a `PUT` request.
	put_file : Str, U32, List(Header), (Try(Response, [HttpErr([Timeout, NetworkError])]) -> msg) -> Effect(msg)
	put_file = |url, file, headers, on_result|
		send_file("PUT", url, headers, { file, start: 0, len: 0 }, 0, on_result)

	## Upload a file, or a part of one, where you decide everything: the
	## method, the headers and how long to wait.
	##
	## `start` and `len` say which bytes of the file to send, and a `len` of
	## 0 means all the rest. Sending a big file a part at a time is how you
	## show progress, or go on after the connection dropped.
	##
	## ```roc
	## Http.request_file(
	##     {
	##         method: PUT,
	##         uri: "/upload/part/1",
	##         headers: [],
	##         file: file.id,
	##         start: 0,
	##         len: 1_000_000,
	##         timeout_ms: NoTimeout,
	##     },
	##     |answer| ServerTookPart(answer),
	## )
	## ```
	request_file : { method : Method, uri : Str, headers : List(Header), file : U32, start : U64, len : U64, timeout_ms : [TimeoutMilliseconds(U64), NoTimeout] }, (Try(Response, [HttpErr([Timeout, NetworkError])]) -> msg) -> Effect(msg)
	request_file = |req, on_result|
		send_file(method_to_str(req.method), req.uri, req.headers, { file: req.file, start: req.start, len: req.len }, timeout_to_u64(req.timeout_ms), on_result)
}

# A request with a body: method, url, headers, the body, then the timeout
# (0 for none).
send : Str, Str, List(Http.Header), List(U8), U64, (Try(Http.Response, [HttpErr([Timeout, NetworkError])]) -> msg) -> Effect(msg)
send = |method, url, headers, body, timeout, on_result|
	Effect.call("joy/http/send", request_head(method, url, headers).bytes(body).u64(timeout).done(), |reply| on_result(to_try(raw_response(reply))))

# A request with a byte range of a browser-held file as its body: method,
# url, headers, the file, its range (`len` 0 for through the end), then the
# timeout.
send_file : Str, Str, List(Http.Header), { file : U32, start : U64, len : U64 }, U64, (Try(Http.Response, [HttpErr([Timeout, NetworkError])]) -> msg) -> Effect(msg)
send_file = |method, url, headers, { file, start, len }, timeout, on_result|
	Effect.call(
		"joy/http/send_file",
		request_head(method, url, headers).u32(file).u64(start).u64(len).u64(timeout).done(),
		|reply| on_result(to_try(raw_response(reply))),
	)

request_head : Str, Str, List(Http.Header) -> Wire.Writer
request_head = |method, url, headers|
	headers.fold(Wire.writer({}).str(method).str(url).u32(headers.len().to_u32_wrap()), |w, h| w.str(h.name).str(h.value))

# The answer's status, headers and body. A reply that is not an answer (a
# runtime.js without the http feature, say) is a request that never
# completed.
raw_response : List(U8) -> Http.Response
raw_response = |reply|
	match Effect.reply(reply) {
		Ok(answer) => read_response(answer) ?? { status: 0, headers: [], body: [] }
		Err(_) => { status: 0, headers: [], body: [] }
	}

read_response : List(U8) -> Try(Http.Response, Wire.Problem)
read_response = |answer| {
	r = Wire.reader(answer)
	(status, r1) = r.u16()?
	(count, r2) = r1.u32()?
	(headers, r3) = read_headers(r2, count, [])?
	(body, _) = r3.bytes()?
	Ok({ status, headers, body })
}

read_headers : Wire.Reader, U32, List(Http.Header) -> Try((List(Http.Header), Wire.Reader), Wire.Problem)
read_headers = |r, left, acc|
	if left == 0 {
		Ok((acc, r))
	} else {
		(name, r1) = r.str()?
		(value, r2) = r1.str()?
		read_headers(r2, left - 1, acc.append({ name, value }))
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

# What a request effect carries, read back, and what its callback makes of
# an answer, so each helper is pinned to its effect and its fields.

## The wire answer for a status, headers and body.
answer_with : U16, List(Http.Header), List(U8) -> List(U8)
answer_with = |status, headers, body| [0].concat(headers.fold(Wire.writer({}).u16(status).u32(headers.len().to_u32_wrap()), |w, h| w.str(h.name).str(h.value)).bytes(body).done())

## A request effect's id, method, url, headers and the rest of its
## arguments.
sent_request : Effect(Str) -> Try({ id : Str, method : Str, url : Str, headers : List(Http.Header), rest : List(U8) }, [NotSent, WireEnded, WireMismatch({ value : U64, wanted : Str, found : Str })])
sent_request = |effect|
	match effect {
		Call(_, args, _) => {
			r = Wire.reader(args)
			(method, r1) = r.str()?
			(url, r2) = r1.str()?
			(count, r3) = r2.u32()?
			(headers, r4) = read_headers(r3, count, [])?
			Ok({ id: effect.identity().id, method, url, headers, rest: r4.remaining() })
		}
		_ => Err(NotSent)
	}

## What a request effect's callback makes of an answer.
answered : Effect(Str), List(U8) -> Str
answered = |effect, reply|
	match effect {
		Call(_, _, cb) => {
			inner = Box.unbox(cb)
			Box.unbox(inner(reply))
		}
		_ => "not a call"
	}

expect read_response(answer_with(200, [{ name: "server", value: "test" }], [104, 105]).drop_first(1)) == Ok({ status: 200, headers: [{ name: "server", value: "test" }], body: [104, 105] })
expect raw_response([1].concat("NotSupportedError: no http".to_utf8())).status == 0

# get wires up a GET with no headers, body or timeout, and its callback runs
# the answer through to_try before the app sees it.
expect {
	effect = Http.get("/api/hats", try_label)
	match sent_request(effect) {
		Ok(req) =>
			req.id == "joy/http/send"
				and req.method == "GET"
				and req.url == "/api/hats"
				and req.headers == []
				and req.rest == Wire.writer({}).bytes([]).u64(0).done()
				and answered(effect, answer_with(200, [], [])) == "ok:200"
				and answered(effect, answer_with(0, [], [])) == "network"
		Err(_) => Bool.False
	}
}

# post carries the body and still decodes transport failures.
expect {
	effect = Http.post("/api/hats", "{}".to_utf8(), try_label)
	match sent_request(effect) {
		Ok(req) =>
			req.method == "POST"
				and req.rest == Wire.writer({}).bytes("{}".to_utf8()).u64(0).done()
				and answered(effect, answer_with(1, [], [])) == "timeout"
		Err(_) => Bool.False
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
	effect = Http.request(req, try_label)
	match sent_request(effect) {
		Ok(sent) =>
			sent.method == "PATCH"
				and sent.url == "/api/hats/7"
				and sent.headers == [{ name: "content-type", value: "application/json" }]
				and sent.rest == Wire.writer({}).bytes("{}".to_utf8()).u64(2500).done()
				and answered(effect, answer_with(204, [], [])) == "ok:204"
		Err(_) => Bool.False
	}
}

# post_file sends the whole file (start 0, len 0) with no timeout.
expect {
	effect = Http.post_file("/upload", 3, [{ name: "x-tag", value: "a" }], try_label)
	match sent_request(effect) {
		Ok(req) =>
			req.id == "joy/http/send_file"
				and req.method == "POST"
				and req.headers == [{ name: "x-tag", value: "a" }]
				and req.rest == Wire.writer({}).u32(3).u64(0).u64(0).u64(0).done()
				and answered(effect, answer_with(201, [], [])) == "ok:201"
		Err(_) => Bool.False
	}
}

expect {
	match sent_request(Http.put_file("/upload/7", 9, [], try_label)) {
		Ok(req) => req.method == "PUT" and req.url == "/upload/7" and req.rest == Wire.writer({}).u32(9).u64(0).u64(0).u64(0).done()
		Err(_) => Bool.False
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
	effect = Http.request_file(req, try_label)
	match sent_request(effect) {
		Ok(sent) =>
			sent.method == "PATCH-CHUNK"
				and sent.rest == Wire.writer({}).u32(4).u64(65536).u64(32768).u64(9000).done()
				and answered(effect, answer_with(0, [], [])) == "network"
		Err(_) => Bool.False
	}
}
