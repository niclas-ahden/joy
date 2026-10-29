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
## Apps use the platform modules (`Http`, `Time`, `DOM`, `Media`, ...),
## which are built on `call` and `send`: an operation of a browser feature
## (see www/features/), by its id, with its arguments and answer as Wire
## bytes. An app's runtime.js holds the operations its wasm uses.
Effect(msg) := [

	## A browser feature's operation (see Features in the runtime): its id, its
	## arguments (see Wire), on_reply. The reply is a status byte, 0 for done
	## and 1 for failed, then the answer (see Wire) or the reason as UTF-8.
	Call(Str, List(U8), Box((List(U8) -> Box(msg)))),

	## message drained to the browser console (see `Console.log`)
	ConsoleLog(Str),

	## A browser feature's operation that answers nothing: its id and its
	## arguments (see Wire).
	Send(Str, List(U8)),
].{

	## Re-target an effect to a parent message type: the reply's message is
	## passed through `f` on its way to `update`, so components can own their
	## effects too.
	map : Effect(a), (a -> b) -> Effect(b)
	map = |cmd, f|
		match cmd {
			Call(id, args, cb) =>
				Call(
					id,
					args,
					Box.box(
						|reply| {
							inner = Box.unbox(cb)
							Box.box(f(Box.unbox(inner(reply))))
						},
					),
				)
			ConsoleLog(message) => ConsoleLog(message)
			Send(id, args) => Send(id, args)
		}

	## Run a browser feature's operation by its id (see Features in the
	## runtime): platform modules like `Media` are built on it. `args` is
	## for the operation (see Wire), and the reply goes through `reply` on the
	## way back.
	##
	## An id is at least 12 bytes, `joy/media/record` say: an app's runtime.js
	## holds the operations whose ids its wasm contains, and a shorter string is
	## packed into the code, where the build cannot find it.
	call : Str, List(U8), (List(U8) -> msg) -> Effect(msg)
	call = |id, args, on_reply| Call(id, args, Box.box(|reply| Box.box(on_reply(reply))))

	## A browser feature's operation that answers nothing, by its id (at least
	## 12 bytes, like `call`'s).
	send : Str, List(U8) -> Effect(msg)
	send = |id, args| Send(id, args)

	## A feature's reply: its answer, or why the operation failed (the feature
	## is missing, or the browser refused, say).
	reply : List(U8) -> Try(List(U8), [FeatureFailed(Str)])
	reply = |bytes|
		match bytes {
			[0, .. as answer] => Ok(answer)
			[_, .. as reason] => Err(FeatureFailed(Str.from_utf8_lossy(reason)))
			[] => Err(FeatureFailed("no reply"))
		}

	console_log : Str -> Effect(msg)
	console_log = |message| ConsoleLog(message)
}

# `map` is Box plumbing: a mistake there (wrong unbox depth, dropped wrap)
# only shows up in the wasm harnesses as corruption, so pin it here by
# firing the mapped callback directly.

expect {
	match Effect.call("joy/media/play", "{}".to_utf8(), |reply| reply.len()).map(|n| n + 1) {
		Call(id, args, cb) => {
			inner = Box.unbox(cb)
			id == "joy/media/play" and args == "{}".to_utf8() and Box.unbox(inner([0, 1])) == 3
		}
		_ => Bool.False
	}
}

# The effects with no reply carry no callback: map passes them through.
expect {
	match Effect.send("joy/dom/navigate", [1, 2]).map(|s| "${s}!") {
		Send(id, args) => id == "joy/dom/navigate" and args == [1, 2]
		_ => Bool.False
	}
}

expect {
	match Effect.console_log("booted").map(|s| "${s}!") {
		ConsoleLog(message) => message == "booted"
		_ => Bool.False
	}
}

expect Effect.reply([0, 104, 105]) == Ok([104, 105])
expect Effect.reply([1, 110, 111]) == Err(FeatureFailed("no"))
