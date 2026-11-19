## An effect: something your app asks the browser to do, like make a request,
## start a timer or change the URL.
##
## Your `init` and `update` never do these things themselves. They return
## effects, and Joy carries them out. When an effect has an answer, it comes
## back to `update` as a message.
##
## ```roc
## update : Model, Msg -> (Model, List(Effect(Msg)))
## update = |model, msg|
##     match msg {
##         UserClickedSave => (model, [Console.log("Saving")])
##     }
## ```
##
## You rarely make an `Effect` yourself. The other modules make them:
## [Http.get], [Time.after], [Navigation.push_url] and so on. What this module adds:
##
## - [Effect.map] and [Effect.map_all], for an app split into pages or parts.
## - [Effect.call], [Effect.send] and [Effect.reply], for a custom effect: a
##   browser feature Joy lacks, with JavaScript of your own.
## - [Effect.identity], for tests.
##
## ## Why an effect is a value
##
## `update` only says what should happen. That keeps it a plain function: the
## same model and message always give the same result. So a test can call
## `update` and look at the effects it returned, with no browser.
##
## The guide has pages on [effects](../../#effects) and on
## [custom effects](../../#custom-effects).
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

	# Why effects are data and not effectful platform functions: hosted
	# functions are monomorphic C symbols, so they cannot take a callback
	# that is generic over the app's `msg`. Effects flow through `update`'s
	# return type, where `msg` is in scope. The callback is boxed so the host
	# can store and call it without knowing the app's Msg layout.

	## Turn an effect of one message type into an effect of another. An app split
	## into pages uses it to wrap a page's messages in its own, so the answer
	## finds its way back to the page:
	##
	## ```roc
	## Effect.map(Console.log("Hello"), |m| SettingsMsg(m))
	## ```
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

	## [Effect.map] for a whole list, as a page's effects become the app's:
	##
	## ```roc
	## SettingsMsg(page_msg) => {
	##     (page, effects) = Settings.update(model.page, page_msg)
	##     (
	##         { ..model, page },
	##         Effect.map_all(effects, |m| SettingsMsg(m)),
	##     )
	## }
	## ```
	map_all : List(Effect(a)), (a -> b) -> List(Effect(b))
	map_all = |effects, f| effects.map(|effect| effect.map(f))

	## The name of an effect's JavaScript, like `"my_app/share_link"`. It is what
	## the Roc and the JavaScript of an effect have in common.
	##
	## You write it as a plain string where an `Id` is asked for. It has to be
	## written out in the code, not put together while the app runs: a build reads
	## the names out of your app to know which JavaScript it needs, and checks
	## that each one has some.
	Id :: Str.{

		## How the compiler turns a string in your code into an `Id`. You do not call
		## it. It refuses a name that is empty, longer than 100 bytes, or made of
		## anything but letters, digits and `_ - . /`.
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

		## The name as you wrote it.
		to_str : Id -> Str
		to_str = |Id.(marked)| plain(marked)
	}

	## For tests. What an effect asks for: its name and its arguments. A
	## `Console.log` has no name, and its text as its arguments.
	##
	## ```roc
	## expect {
	##     (_, effects) = update(model, UserClickedLoad)
	##     ids = effects.map(|effect| effect.identity().id)
	##     ids == ["joy/http/send"]
	## }
	## ```
	identity : Effect(msg) -> { id : Str, args : List(U8) }
	identity = |effect|
		match effect {
			Call(marked, args, _) => { id: plain(marked), args }
			Send(marked, args) => { id: plain(marked), args }
			ConsoleLog(message) => { id: "", args: message.to_utf8() }
		}

	## For a custom effect. Run your own JavaScript by its name, and get its
	## answer.
	##
	## `args` is what the JavaScript reads, written with `Wire`. What comes back
	## goes through [Effect.reply], which says whether it worked.
	##
	## ```roc
	## get : (Try(Info, Str) -> msg) -> Effect(msg)
	## get = |to_msg|
	##     Effect.call(
	##         "my_app/locale_get",
	##         [],
	##         |reply| to_msg(info(reply)),
	##     )
	## ```
	##
	## The JavaScript is in the `.js` file beside the Roc module. The guide's page
	## on [custom effects](../../#custom-effects) shows both halves.
	call : Id, List(U8), (List(U8) -> msg) -> Effect(msg)
	call = |Id.(marked), args, on_reply| Call(marked, args, Box.box(|answer_bytes| Box.box(on_reply(answer_bytes))))

	## For a custom effect. Run your own JavaScript by its name, when it has
	## nothing to answer.
	##
	## ```roc
	## args = Wire.writer({}).u32(200).done()
	##
	## Effect.send("my_app/vibrate", args)
	## ```
	send : Id, List(U8) -> Effect(msg)
	send = |Id.(marked), args| Send(marked, args)

	## For a custom effect. What your JavaScript answered, or why it failed.
	##
	## - `Ok(answer)`: the bytes your JavaScript wrote, to read with `Wire`.
	## - `Err(EffectFailed({ name, message }))`: the error your JavaScript threw.
	##   A browser that refuses says `NotAllowedError`, and a name with no
	##   JavaScript behind it says `MissingEffectError`.
	##
	## ```roc
	## info : List(U8) -> Try(Info, Str)
	## info = |reply| {
	##     answer = Effect.reply(reply) ? |_| "The browser said no"
	##     (language, _) = Wire.reader(answer).str() ? Wire.explain
	##     Ok({ language })
	## }
	## ```
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
	match Effect.send("joy/navigation/navigate", [1, 2]).map(|s| "${s}!") {
		Send(marked, args) => plain(marked) == "joy/navigation/navigate" and args == [1, 2]
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
