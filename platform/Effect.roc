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
## which are built on `call` and `send`: JavaScript the runtime has under
## an id, with its arguments and answer as Wire bytes. A custom effect, one an
## app or a package brings with its own JavaScript, is built the same way.
## An app's runtime.js holds the JavaScript its wasm uses.
Effect(msg) := [

	## JavaScript that answers (see Features in the runtime): its id as `Id`
	## marks it, its arguments (see Wire), on_reply. The reply is a status byte, 0 for done
	## and 1 for failed, then the answer (see Wire) or the reason as UTF-8.
	Call(Str, List(U8), Box((List(U8) -> Box(msg)))),

	## message drained to the browser console (see `Console.log`)
	ConsoleLog(Str),

	## JavaScript that answers nothing: its id and its arguments (see Wire).
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
						|answer_bytes| {
							inner = Box.unbox(cb)
							Box.box(f(Box.unbox(inner(answer_bytes))))
						},
					),
				)
			ConsoleLog(message) => ConsoleLog(message)
			Send(id, args) => Send(id, args)
		}

	## Re-target every effect of a list, as a page's effects become the
	## app's: `Effect.map_all(effects, |m| PageMsg(m))`.
	map_all : List(Effect(a)), (a -> b) -> List(Effect(b))
	map_all = |effects, f| effects.map(|effect| effect.map(f))

	## The id of an effect, `joy/media/record` say: what its Roc and its
	## JavaScript share. It is written as a string, `"my_app/share_link"`,
	## and only as one: the compiler makes an `Id` of a string literal and of
	## nothing else, so every id an app uses is in its source and, marked, in
	## its wasm. That is where a build reads which JavaScript the app needs,
	## and checks that each id has some.
	Id :: Str.{
		from_quote : Str -> Try(Id, [BadQuotedBytes(Str)])
		from_quote = |raw|
			if raw.count_utf8_bytes() > 100 {
				Err(BadQuotedBytes("The id of an effect is at most 100 bytes long."))
			} else if raw.is_empty() {
				Err(BadQuotedBytes("The id of an effect cannot be empty. Give it a name, like my_app/share_link."))
			} else if !Str.to_utf8(raw).all(in_an_id) {
				Err(BadQuotedBytes("The id of an effect is made of letters, digits and _ - . / only, like my_app/share_link."))
			} else {
				Ok(Id.(Str.concat(Str.concat(Str.concat("<joy-", "effect "), raw), ">")))
			}

		## The id as it was written.
		to_str : Id -> Str
		to_str = |Id.(marked)| plain(marked)
	}

	## The id and the arguments of an effect, for tests that check what an
	## `update` returned. A line for the console has no id, and its text as
	## its arguments.
	identity : Effect(msg) -> { id : Str, args : List(U8) }
	identity = |effect|
		match effect {
			Call(marked, args, _) => { id: plain(marked), args }
			Send(marked, args) => { id: plain(marked), args }
			ConsoleLog(message) => { id: "", args: message.to_utf8() }
		}

	## Run the JavaScript of an effect by its id, and hear its reply. Platform
	## modules like `Media` are built on it, and so is a custom effect, whose
	## JavaScript is in the .js file beside its Roc module. `args` is what the
	## JavaScript reads (see Wire), and the reply goes through `reply` on the
	## way back.
	call : Id, List(U8), (List(U8) -> msg) -> Effect(msg)
	call = |Id.(marked), args, on_reply| Call(marked, args, Box.box(|answer_bytes| Box.box(on_reply(answer_bytes))))

	## Run the JavaScript of an effect that answers nothing, by its id.
	send : Id, List(U8) -> Effect(msg)
	send = |Id.(marked), args| Send(marked, args)

	## An effect's reply: its answer, or why it failed, as the name and the
	## message of the error its JavaScript threw. A browser that refuses says
	## `NotAllowedError`, and an id without JavaScript `MissingEffectError`.
	reply : List(U8) -> Try(List(U8), [EffectFailed({ name : Str, message : Str })])
	reply = |bytes|
		match bytes {
			[0, .. as answer] => Ok(answer)
			[_, .. as reason] => Err(EffectFailed(failure(Str.from_utf8_lossy(reason))))
			[] => Err(EffectFailed({ name: "Error", message: "no reply" }))
		}
}

## An id without its mark. The mark is put together from two short strings
## here and in `from_quote`, so that it is in a wasm only where an id is.
plain : Str -> Str
plain = |marked| marked.drop_prefix("<joy-").drop_prefix("effect ").drop_suffix(">")

## Whether a byte can be part of an id. A build reads an id out of the wasm up
## to the `>` that ends its mark, so that and what a browser would not take
## in a file's name stay out.
in_an_id : U8 -> Bool
in_an_id = |byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9') or byte == '_' or byte == '-' or byte == '.' or byte == '/'

## A failure as the runtime writes it, "<error name>: <message>".
failure : Str -> { name : Str, message : Str }
failure = |reason|
	match reason.split_first(": ") {
		Ok({ before, after }) => { name: before, message: after }
		Err(_) => { name: "Error", message: reason }
	}

# `map` is Box plumbing: a mistake there (wrong unbox depth, dropped wrap)
# only shows up in the wasm harnesses as corruption, so pin it here by
# firing the mapped callback directly.

expect {
	match Effect.call("joy/media/play", "{}".to_utf8(), |reply| reply.len()).map(|n| n + 1) {
		Call(marked, args, cb) => {
			inner = Box.unbox(cb)
			plain(marked) == "joy/media/play" and args == "{}".to_utf8() and Box.unbox(inner([0, 1])) == 3
		}
		_ => Bool.False
	}
}

# The effects with no reply carry no callback: map passes them through.
expect {
	match Effect.send("joy/dom/navigate", [1, 2]).map(|s| "${s}!") {
		Send(marked, args) => plain(marked) == "joy/dom/navigate" and args == [1, 2]
		_ => Bool.False
	}
}

# An id is what was written, and its mark is what a build finds in the wasm.
expect Effect.send("my_app/share_link", [7]).identity() == { id: "my_app/share_link", args: [7] }
expect {
	match Effect.send("my_app/share_link", []) {
		Send(marked, _) => marked == "<joy-effect my_app/share_link>"
		_ => Bool.False
	}
}

expect {
	logged : Effect(Str)
	logged = ConsoleLog("booted")
	match logged.map(|s| "${s}!") {
		ConsoleLog(message) => message == "booted"
		_ => Bool.False
	}
}

expect Effect.reply([0, 104, 105]) == Ok([104, 105])
expect Effect.reply([1, 110, 111]) == Err(EffectFailed({ name: "Error", message: "no" }))
expect Effect.reply([1].concat(Str.to_utf8("NotAllowedError: Permission denied: now"))) == Err(EffectFailed({ name: "NotAllowedError", message: "Permission denied: now" }))
expect Effect.reply([]) == Err(EffectFailed({ name: "Error", message: "no reply" }))

# `map_all` re-targets each effect of the list and keeps their order.
expect {
	effects : List(Effect(U64))
	effects = [Effect.send("my_app/first", [1]), Effect.call("my_app/second", [2], |reply| reply.len())]
	mapped = Effect.map_all(effects, |n| n + 1)
	fired =
		match mapped {
			[_, Call(_, _, cb)] => Box.unbox(Box.unbox(cb)([0, 0, 0]))
			_ => 0
		}
	mapped.map(|effect| effect.identity().id) == ["my_app/first", "my_app/second"] and fired == 4
}

expect {
	none : List(Effect(U64))
	none = []
	Effect.map_all(none, |n| n + 1).len() == 0
}
