## A subscription: a recurring event source declared as *data*, returned from
## `subscriptions` and managed by the host. While a subscription stays in the
## returned list it keeps firing; leaving it out of the list stops it, so
## cancellation is by omission and nothing leaks. The callback is a real typed
## function, boxed so the host can store and call it without knowing the app's
## Msg layout.
##
## A subscription is a browser feature's events (see Features in the
## runtime): its id and its arguments (see Wire) are its identity. A model
## change that alters the arguments stops the old source and starts a fresh
## one; re-declaring the same identity keeps the running source and only
## swaps in the new callbacks (which may capture new model state). Two
## subscriptions with the same identity share one source, and each event
## delivers every declared callback's message, in declaration order.
##
## Apps use the platform modules (`Time`, `Keyboard`, `Port`, `DOM`,
## `Media`), which are built on `listen`.
##
## A record with `:=`, not an opaque `::`: the compiler keeps an opaque
## type's value behind a pointer in a `List`, and the host reads the list
## `subscriptions` returns as the records themselves.
Sub(msg) := { id : Str, args : List(U8), on_event : Box((List(U8) -> Box(msg))) }.{

	## The keyboard event record delivered to key handlers, document-level
	## (the `Keyboard` module) and element-level (`Attribute.on_key` and
	## friends) alike; annotate handlers as `Sub.KeyEvent`. `key` is the
	## logical key ("a", "Enter", "Escape", ...): it follows the active
	## layout and modifiers, so Shift makes "a" arrive as "A". `code` is the
	## physical key ("KeyA", "Space", "ControlLeft", ...): it ignores both,
	## which is what layout-independent controls (say, WASD movement) want.
	## `repeat` is true on the auto-repeated firings of a held key; skip
	## those to react once per press. The four modifier flags say whether
	## that modifier was held when the event fired, so a Ctrl+S shortcut is
	## `if e.ctrl and e.key == "s"`. `is_composing` is true while an IME
	## composition session is in progress (the browser reports such keydowns
	## as key "Process"); skip those to ignore the intermediate keystrokes
	## international text input is assembled from.
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

	## Re-target a subscription to a parent message type.
	## Note the mapped callback is a new box each render, which is fine: sub
	## identity comes from the id and the arguments, never the callback.
	map : Sub(a), (a -> b) -> Sub(b)
	map = |Sub.({ id, args, on_event }), f|
		Sub.({
			id: id,
			args: args,
			on_event: Box.box(
				|bytes| {
					inner = Box.unbox(on_event)
					Box.box(f(Box.unbox(inner(bytes))))
				},
			),
		})

	## A browser feature's events by its id, at least 12 bytes like
	## `Effect.call`'s.
	listen : Str, List(U8), (List(U8) -> msg) -> Sub(msg)
	listen = |id, args, on_event| Sub.({ id: id, args: args, on_event: Box.box(|bytes| Box.box(on_event(bytes))) })

	## The feature's id and arguments, for tests that check what an app
	## subscribes to.
	identity : Sub(msg) -> { id : Str, args : List(U8) }
	identity = |Sub.({ id, args, on_event: _ })| { id: id, args: args }

	## Deliver an event the way the host does, for tests.
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
