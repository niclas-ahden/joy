## A subscription: something your app listens to for a while, like the clock,
## the keyboard or a port.
##
## `subscriptions` looks at the model and returns what your app wants to hear
## right now. Joy starts what is new in the list and stops what is gone. So to
## stop listening, leave it out:
##
## ```roc
## subscriptions : Model -> List(Sub(Msg))
## subscriptions = |model|
##     if model.paused {
##         []
##     } else {
##         [Time.every(1000, |now| Tick(now))]
##     }
## ```
##
## You rarely make a `Sub` yourself. The other modules make them:
## [Time.every], [Keyboard.on_down], [Port.listen], [Navigation.on_url_change] and
## [Media.stream]. What this module adds:
##
## - [Sub.map] and [Sub.map_all], for an app split into pages or parts.
## - [Sub.KeyEvent], what a key handler gets.
## - [Sub.listen], for a custom effect: a browser feature Joy lacks, with
##   JavaScript of your own.
## - [Sub.identity] and [Sub.deliver], for tests.
##
## ## When a subscription starts over
##
## A subscription is known by what it listens to, not by the function you give
## it. `Time.every(1000, ...)` is the same timer on every call, and it keeps
## running. Change the 1000 to 500 and the old timer stops and a new one
## starts.
##
## Two subscriptions to the same thing share it, and each event gives both of
## them a message.
##
## The guide has [a page on subscriptions](../../#subscriptions).
Sub(msg) := { id : Str, args : List(U8), on_event : Box((List(U8) -> Box(msg))) }.{

	# A record with `:=`, not an opaque `::`: the compiler keeps an opaque
	# type's value behind a pointer in a `List`, and the host reads the list
	# `subscriptions` returns as the records themselves. The callback is
	# boxed so the host can store and call it without knowing the app's Msg
	# layout.

	## What a key handler gets about a key press. The subscriptions in `Keyboard`
	## hand you one, and so do the key handlers in joy-html's `Attribute`.
	##
	## - `key`: what the key means, like `"a"`, `"Enter"` or `"Escape"`. It
	##   follows the keyboard layout and Shift, so with Shift held `"a"` arrives
	##   as `"A"`.
	## - `code`: which physical key it was, like `"KeyA"` or `"Space"`. It ignores
	##   the layout and Shift, which is what controls like WASD want.
	## - `ctrl`, `shift`, `alt`, `meta`: whether that key was held at the time. A
	##   Ctrl+S shortcut is `event.ctrl and event.key == "s"`.
	## - `repeat`: true for the repeats a held key sends. Skip those to react once
	##   for each press.
	## - `is_composing`: true while the user puts a character together from
	##   several key presses, as input methods for Chinese, Japanese and Korean
	##   do. Skip those to ignore the steps in between.
	KeyEvent : {
		key : Str,
		code : Str,
		ctrl : Bool,
		shift : Bool,
		alt : Bool,
		meta : Bool,
		repeat : Bool,
		is_composing : Bool,
	}

	## Turn a subscription of one message type into one of another. An app split
	## into pages uses it to wrap a page's messages in its own:
	##
	## ```roc
	## Sub.map(Time.every(1000, |now| Tick(now)), |m| ClockMsg(m))
	## ```
	##
	## The subscription listens to the same thing as before, so it keeps running.
	map : Sub(a), (a -> b) -> Sub(b)
	map = |Sub.({ id, args, on_event }), f|
		Sub.(
			{
				id: id,
				args: args,
				on_event: Box.box(
					|bytes| {
						inner = Box.unbox(on_event)
						Box.box(f(Box.unbox(inner(bytes))))
					},
				),
			},
		)

	## [Sub.map] for a whole list, as a page's subscriptions become the app's:
	##
	## ```roc
	## subscriptions = |model|
	##     Sub.map_all(
	##         Clock.subscriptions(model.clock),
	##         |m| ClockMsg(m),
	##     )
	## ```
	map_all : List(Sub(a)), (a -> b) -> List(Sub(b))
	map_all = |subs, f| subs.map(|sub| sub.map(f))

	## The name of a subscription's JavaScript, like `"my_app/network_changes"`.
	##
	## You write it as a plain string where an `Id` is asked for. It has to be
	## written out in the code, not put together while the app runs: a build reads
	## the names out of your app to know which JavaScript it needs.
	Id :: Str.{

		## How the compiler turns a string in your code into an `Id`. You do not call
		## it. It refuses a name that is empty, longer than 100 bytes, or made of
		## anything but letters, digits and `_ - . /`.
		from_quote : Str -> Try(Id, [BadQuotedBytes(Str)])
		from_quote = |raw|
			if raw.count_utf8_bytes() > 100 {
				Err(BadQuotedBytes("The id of a subscription is at most 100 bytes long."))
			} else if raw.is_empty() {
				Err(BadQuotedBytes("The id of a subscription cannot be empty. Give it a name, like my_app/network_changes."))
			} else if !Str.to_utf8(raw).all(in_an_id) {
				Err(BadQuotedBytes("The id of a subscription is made of letters, digits and _ - . / only, like my_app/network_changes."))
			} else {
				Ok(Id.(Str.concat(Str.concat(Str.concat("<joy-", "listen "), raw), ">")))
			}

		## The name as you wrote it.
		to_str : Id -> Str
		to_str = |Id.(marked)| plain(marked)
	}

	## For a custom effect. Hear the events of your own JavaScript, by its name.
	##
	## `args` is what the JavaScript is started with, and each event's bytes go
	## through your function on their way to `update`. Both are written and read
	## with `Wire`.
	##
	## ```roc
	## on_change : (Status -> msg) -> Sub(msg)
	## on_change = |to_msg|
	##     Sub.listen(
	##         "my_app/network_changes",
	##         [],
	##         |event| to_msg(status(event)),
	##     )
	## ```
	##
	## The guide's page on [custom effects](../../#custom-effects) shows the
	## JavaScript that goes with it.
	listen : Id, List(U8), (List(U8) -> msg) -> Sub(msg)
	listen = |Id.(marked), args, on_event| Sub.({ id: marked, args: args, on_event: Box.box(|bytes| Box.box(on_event(bytes))) })

	## For tests. What a subscription listens to: its name and its arguments.
	##
	## ```roc
	## expect {
	##     sub = Time.every(1000, |now| Tick(now))
	##     sub.identity().id == "joy/time/every"
	## }
	## ```
	identity : Sub(msg) -> { id : Str, args : List(U8) }
	identity = |Sub.({ id, args, on_event: _ })| { id: plain(id), args: args }

	## For tests. Hand a subscription an event, the way Joy does, and get the
	## message it makes.
	##
	## ```roc
	## expect {
	##     sub = Network.on_change(|status| NetworkChanged(status))
	##     event = Wire.writer({}).bool(Bool.True).done()
	##     sub.deliver(event) == NetworkChanged(Online)
	## }
	## ```
	deliver : Sub(msg), List(U8) -> msg
	deliver = |Sub.({ id: _, args: _, on_event }), bytes| Box.unbox(Box.unbox(on_event)(bytes))
}

# `map` is Box plumbing: a mistake there (wrong unbox depth, dropped wrap)
# only shows up in the wasm harnesses as corruption, so pin it here by
# firing the mapped callback directly.
expect {
	sub = Sub.listen("joy/media/levels", [1, 2], |b| "level:${b.len().to_str()}").map(|m| "outer:${m}")
	sub.identity() == { id: "joy/media/levels", args: [1, 2] } and sub.deliver([7]) == "outer:level:1"
}

# `map_all` re-targets each subscription of the list and keeps their order.
expect {
	subs = [Sub.listen("my_app/first", [], |b| b.len()), Sub.listen("my_app/second", [], |b| b.len() * 10)]
	mapped = Sub.map_all(subs, |n| n + 1)
	mapped.map(|sub| sub.identity().id) == ["my_app/first", "my_app/second"] and mapped.map(|sub| sub.deliver([7, 7])) == [3, 21]
}

## An id without its mark, see `plain` in Effect.
plain : Str -> Str
plain = |marked| marked.drop_prefix("<joy-").drop_prefix("listen ").drop_suffix(">")

in_an_id : U8 -> Bool
in_an_id = |byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9') or byte == '_' or byte == '-' or byte == '.' or byte == '/'
