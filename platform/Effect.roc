## An effect: an asynchronous action described as *data*, returned from `init`
## or `update` and executed by the host. The response callback is a real typed
## function (`... -> msg`), boxed so the host can store and call it without
## knowing the app's Msg layout.
##
## Why data instead of effectful platform functions: hosted functions are
## monomorphic C symbols, so they cannot accept a callback that is generic
## over the app's `msg`. Effects flow through `update`'s return type, where
## `msg` is properly in scope. Msg-free effects (logging, navigation,
## modals, timer cancellation) are data too: as data they can be matched
## on, so a pure test can assert exactly which effects an update produced.
## The boundary rule: every app entrypoint is pure and the compiler
## enforces it, every observable effect is an `Effect` value returned from
## `init` or `update`, and `init` receives the app's flags string, into
## which the embedder puts any boot data the app needs (time, url,
## whatever). Recurring event sources are subscriptions (see `Sub`).
##
## Apps normally use the constructors in `Http`, `Time` and `WebCrypto` rather
## than these variants directly. Payload fields are positional for a simpler
## host walk. File ids come from a file input's `Attribute.on_file`; the
## browser side holds the actual File object, so its bytes never cross into
## wasm unless you hash or upload them.
Effect(msg) := [

	## CSS selector of the `<dialog>` to close (see `DOM.close_modal`)
	CloseModal(Str),

	## message drained to the browser console (see `Console.log`)
	ConsoleLog(Str),

	## algorithm (a Web Crypto name: "SHA-1", "SHA-256", "SHA-384", "SHA-512"),
	## bytes to hash, on_hash (called with the hash bytes; empty on failure)
	CryptoDigest(Str, List(U8), Box((List(U8) -> Box(msg)))),

	## algorithm, file id, start byte, byte count (0 = through end of file),
	## on_hash (called with the hash bytes; empty on failure/unknown file)
	CryptoDigestFile(Str, U32, U64, U64, Box((List(U8) -> Box(msg)))),

	## method, url, headers, body, timeout in ms (0 = no timeout),
	## on_response. The raw status doubles as the transport channel: 0 means
	## the request never completed and 1 means it timed out (real HTTP
	## statuses start at 100). Http decodes that into a Try before the app
	## sees it.
	HttpSend(Str, Str, List({ name : Str, value : Str }), List(U8), U64, Box(({ status : U16, headers : List({ name : Str, value : Str }), body : List(U8) } -> Box(msg)))),

	## method, url, headers, file id, start byte, byte count (0 = through end
	## of file), timeout in ms (0 = no timeout), on_response. The file's
	## bytes are streamed by the browser and never enter wasm memory.
	HttpSendFile(Str, Str, List({ name : Str, value : Str }), U32, U64, U64, U64, Box(({ status : U16, headers : List({ name : Str, value : Str }), body : List(U8) } -> Box(msg)))),

	## url for a full page load (see `DOM.navigate`)
	Navigate(Str),

	## port name, value delivered to the JS handler registered for that name
	PortSend(Str, Str),

	## url for a history entry without a reload (see `DOM.push_url`)
	PushUrl(Str),

	## url rewritten in place, no reload, no history entry (see
	## `DOM.replace_url`)
	ReplaceUrl(Str),

	## CSS selector of the `<dialog>` to open as a modal (see
	## `DOM.show_modal`)
	ShowModal(Str),

	## delay in ms, on_fire (called once with the current time in ms since epoch)
	TimeAfter(U32, Box((I64 -> Box(msg)))),

	## debounce key whose pending timer is discarded (see `Time.cancel`)
	TimeCancel(Str),

	## debounce key, delay in ms, on_fire. Issuing the effect re-arms the
	## pending timer with the same key, so only the last of a burst fires;
	## `Time.cancel` discards a pending key entirely.
	TimeDebounce(Str, U32, Box((I64 -> Box(msg)))),
].{

	## Re-target an effect to a parent message type: the response callback's
	## message is passed through `f` on its way to `update`, so components can
	## own their effects too.
	map : Effect(a), (a -> b) -> Effect(b)
	map = |cmd, f|
		match cmd {
			CloseModal(selector) => CloseModal(selector)
			ConsoleLog(message) => ConsoleLog(message)
			CryptoDigest(algorithm, bytes, cb) =>
				CryptoDigest(
					algorithm,
					bytes,
					Box.box(
						|hash| {
							inner = Box.unbox(cb)
							Box.box(f(Box.unbox(inner(hash))))
						},
					),
				)
			CryptoDigestFile(algorithm, file, start, len, cb) =>
				CryptoDigestFile(
					algorithm,
					file,
					start,
					len,
					Box.box(
						|hash| {
							inner = Box.unbox(cb)
							Box.box(f(Box.unbox(inner(hash))))
						},
					),
				)
			HttpSend(method, url, headers, body, timeout, cb) =>
				HttpSend(
					method,
					url,
					headers,
					body,
					timeout,
					Box.box(
						|resp| {
							inner = Box.unbox(cb)
							Box.box(f(Box.unbox(inner(resp))))
						},
					),
				)
			HttpSendFile(method, url, headers, file, start, len, timeout, cb) =>
				HttpSendFile(
					method,
					url,
					headers,
					file,
					start,
					len,
					timeout,
					Box.box(
						|resp| {
							inner = Box.unbox(cb)
							Box.box(f(Box.unbox(inner(resp))))
						},
					),
				)
			Navigate(url) => Navigate(url)
			PortSend(name, value) => PortSend(name, value)
			PushUrl(url) => PushUrl(url)
			ReplaceUrl(url) => ReplaceUrl(url)
			ShowModal(selector) => ShowModal(selector)
			TimeAfter(ms, cb) =>
				TimeAfter(
					ms,
					Box.box(
						|now| {
							inner = Box.unbox(cb)
							Box.box(f(Box.unbox(inner(now))))
						},
					),
				)
			TimeCancel(key) => TimeCancel(key)
			TimeDebounce(key, ms, cb) =>
				TimeDebounce(
					key,
					ms,
					Box.box(
						|now| {
							inner = Box.unbox(cb)
							Box.box(f(Box.unbox(inner(now))))
						},
					),
				)
			}

	close_modal : Str -> Effect(msg)
	close_modal = |selector| CloseModal(selector)

	console_log : Str -> Effect(msg)
	console_log = |message| ConsoleLog(message)

	crypto_digest : Str, List(U8), (List(U8) -> msg) -> Effect(msg)
	crypto_digest = |algorithm, bytes, on_hash|
		CryptoDigest(algorithm, bytes, Box.box(|hash| Box.box(on_hash(hash))))

	crypto_digest_file : Str, U32, U64, U64, (List(U8) -> msg) -> Effect(msg)
	crypto_digest_file = |algorithm, file, start, len, on_hash|
		CryptoDigestFile(algorithm, file, start, len, Box.box(|hash| Box.box(on_hash(hash))))

	http_send : Str, Str, List({ name : Str, value : Str }), List(U8), U64, ({ status : U16, headers : List({ name : Str, value : Str }), body : List(U8) } -> msg) -> Effect(msg)
	http_send = |method, url, headers, body, timeout, on_response|
		HttpSend(method, url, headers, body, timeout, Box.box(|resp| Box.box(on_response(resp))))

	http_send_file : Str, Str, List({ name : Str, value : Str }), U32, U64, U64, U64, ({ status : U16, headers : List({ name : Str, value : Str }), body : List(U8) } -> msg) -> Effect(msg)
	http_send_file = |method, url, headers, file, start, len, timeout, on_response|
		HttpSendFile(method, url, headers, file, start, len, timeout, Box.box(|resp| Box.box(on_response(resp))))

	navigate : Str -> Effect(msg)
	navigate = |url| Navigate(url)

	port_send : Str, Str -> Effect(msg)
	port_send = |name, value| PortSend(name, value)

	push_url : Str -> Effect(msg)
	push_url = |url| PushUrl(url)

	replace_url : Str -> Effect(msg)
	replace_url = |url| ReplaceUrl(url)

	show_modal : Str -> Effect(msg)
	show_modal = |selector| ShowModal(selector)

	time_after : U32, (I64 -> msg) -> Effect(msg)
	time_after = |ms, on_fire| TimeAfter(ms, Box.box(|now| Box.box(on_fire(now))))

	time_cancel : Str -> Effect(msg)
	time_cancel = |key| TimeCancel(key)

	time_debounce : Str, U32, (I64 -> msg) -> Effect(msg)
	time_debounce = |key, ms, on_fire| TimeDebounce(key, ms, Box.box(|now| Box.box(on_fire(now))))
}

# `map` is Box plumbing: a mistake there (wrong unbox depth, dropped wrap)
# only shows up in the wasm harnesses as corruption, so pin it here by
# firing the mapped callbacks directly.

expect {
	match Effect.time_after(250, |now| "fired:${now.to_str()}").map(|s| "outer:${s}") {
		TimeAfter(ms, cb) => {
			inner = Box.unbox(cb)
			ms == 250 and Box.unbox(inner(9)) == "outer:fired:9"
		}
		_ => Bool.False
	}
}

expect {
	match Effect.time_debounce("search", 300, |_| "fire").map(|s| "outer:${s}") {
		TimeDebounce(key, ms, cb) => {
			inner = Box.unbox(cb)
			key == "search" and ms == 300 and Box.unbox(inner(0)) == "outer:fire"
		}
		_ => Bool.False
	}
}

expect {
	cmd = Effect.http_send(
		"POST",
		"/api/quotes",
		[{ name: "content-type", value: "application/json" }],
		"{}".to_utf8(),
		5000,
		|resp| "status:${resp.status.to_str()}:${resp.headers.len().to_str()}",
	)
	match cmd.map(|s| "outer:${s}") {
		HttpSend(method, url, headers, body, timeout, cb) => {
			inner = Box.unbox(cb)
			method == "POST"
				and url == "/api/quotes"
					and headers == [{ name: "content-type", value: "application/json" }]
						and body == "{}".to_utf8()
							and timeout == 5000
								and Box.unbox(inner({ status: 200, headers: [{ name: "server", value: "test" }], body: [] })) == "outer:status:200:1"
		}
		_ => Bool.False
	}
}

expect {
	cmd = Effect.http_send_file("PUT", "/upload", [], 3, 100, 50, 0, |resp| resp.status)
	match cmd.map(|status| status + 1) {
		HttpSendFile(method, url, headers, file, start, len, timeout, cb) => {
			inner = Box.unbox(cb)
			method == "PUT"
				and url == "/upload"
					and headers == []
						and file == 3
							and start == 100
								and len == 50
									and timeout == 0
										and Box.unbox(inner({ status: 201, headers: [], body: [] })) == 202
		}
		_ => Bool.False
	}
}

expect {
	match Effect.crypto_digest("SHA-256", [1, 2, 3], |hash| hash.len()).map(|n| n * 2) {
		CryptoDigest(algorithm, bytes, cb) => {
			inner = Box.unbox(cb)
			algorithm == "SHA-256" and bytes == [1, 2, 3] and Box.unbox(inner([0, 0, 0, 0])) == 8
		}
		_ => Bool.False
	}
}

expect {
	match Effect.crypto_digest_file("SHA-384", 7, 0, 0, |hash| hash.len()).map(|n| n + 1) {
		CryptoDigestFile(algorithm, file, start, len, cb) => {
			inner = Box.unbox(cb)
			algorithm == "SHA-384" and file == 7 and start == 0 and len == 0 and Box.unbox(inner([9])) == 2
		}
		_ => Bool.False
	}
}

# The msg-free effects carry no callback: map must pass them through
# untouched.
expect {
	match Effect.port_send("chart", "[1,2]").map(|s| "${s}!") {
		PortSend(name, value) => name == "chart" and value == "[1,2]"
		_ => Bool.False
	}
}

expect {
	match Effect.navigate("?reloaded=1").map(|s| "${s}!") {
		Navigate(url) => url == "?reloaded=1"
		_ => Bool.False
	}
}

expect {
	match Effect.push_url("?demo=push").map(|s| "${s}!") {
		PushUrl(url) => url == "?demo=push"
		_ => Bool.False
	}
}

expect {
	match Effect.replace_url("?q=hats").map(|s| "${s}!") {
		ReplaceUrl(url) => url == "?q=hats"
		_ => Bool.False
	}
}

expect {
	match Effect.show_modal("#confirm").map(|s| "${s}!") {
		ShowModal(selector) => selector == "#confirm"
		_ => Bool.False
	}
}

expect {
	match Effect.close_modal("#confirm").map(|s| "${s}!") {
		CloseModal(selector) => selector == "#confirm"
		_ => Bool.False
	}
}

expect {
	match Effect.time_cancel("search").map(|s| "${s}!") {
		TimeCancel(key) => key == "search"
		_ => Bool.False
	}
}

expect {
	match Effect.console_log("booted").map(|s| "${s}!") {
		ConsoleLog(message) => message == "booted"
		_ => Bool.False
	}
}
