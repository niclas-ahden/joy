## A subscription: a recurring event source declared as *data*, returned from
## `subscriptions` and managed by the host. While a subscription stays in the
## returned list it keeps firing; leaving it out of the list stops it, so
## cancellation is by omission and nothing leaks. The callback is a real typed
## function, boxed so the host can store and call it without knowing the app's
## Msg layout.
##
## Identity is the variant plus its parameters (for `Every` the interval, for
## `PortListen` the port name). A model change that alters the parameters
## stops the old source and starts a fresh one; re-declaring the same
## identity keeps the running source and only swaps in the new callbacks
## (which may capture new model state). Two subscriptions with identical
## parameters share one underlying source (timer, document listener, port
## registration), and each firing delivers every declared callback's message,
## in declaration order.
##
## Apps normally use the constructors in `Time`, `Keyboard`, `Port` and `DOM`
## rather than these variants directly. Payloads are records so the host
## reads named fields.
Sub(msg) := [

	## Fire every `ms` milliseconds with the current time in ms since the
	## Unix epoch.
	Every({ ms : U32, on_tick : Box((I64 -> Box(msg))) }),

	## Fire on a document-level keyboard event ("keydown" or "keyup") with
	## the `KeyEvent` record (key, physical code, modifiers, repeat). An
	## empty `keys` list matches every key; a non-empty one fires (and, when
	## `prevent_default` is set, suppresses the browser default) only when
	## the event's `key` is listed.
	Keyboard({ event : Str, keys : List(Str), prevent_default : Bool, on_key : Box((KeyEvent -> Box(msg))) }),

	## Fire whenever JavaScript sends a value to the named port (see the
	## `Port` module). Identity is the name, so listening stops when the
	## subscription leaves the list, and two listeners on one name both fire.
	PortListen({ name : Str, on_value : Box((Str -> Box(msg))) }),

	## Fire when the browser's back/forward buttons change the URL (the
	## `popstate` event), with the new path (path + query + fragment). See
	## `DOM.on_url_change`.
	UrlChanged({ on_change : Box((Str -> Box(msg))) }),
].{

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
	## identity comes from the variant's parameters, never the callback.
	map : Sub(a), (a -> b) -> Sub(b)
	map = |sub, f|
		match sub {
			Every(r) =>
				Every({
					ms: r.ms,
					on_tick: Box.box(
						|now| {
							inner = Box.unbox(r.on_tick)
							Box.box(f(Box.unbox(inner(now))))
						},
					),
				})
			Keyboard(r) =>
				Keyboard({
					event: r.event,
					keys: r.keys,
					prevent_default: r.prevent_default,
					on_key: Box.box(
						|e| {
							inner = Box.unbox(r.on_key)
							Box.box(f(Box.unbox(inner(e))))
						},
					),
				})
			PortListen(r) =>
				PortListen({
					name: r.name,
					on_value: Box.box(
						|s| {
							inner = Box.unbox(r.on_value)
							Box.box(f(Box.unbox(inner(s))))
						},
					),
				})
			UrlChanged(r) =>
				UrlChanged({
					on_change: Box.box(
						|s| {
							inner = Box.unbox(r.on_change)
							Box.box(f(Box.unbox(inner(s))))
						},
					),
				})
			}

	every : U32, (I64 -> msg) -> Sub(msg)
	every = |ms, on_tick| Every({ ms: ms, on_tick: Box.box(|now| Box.box(on_tick(now))) })

	keyboard : Str, List(Str), Bool, (KeyEvent -> msg) -> Sub(msg)
	keyboard = |event, keys, prevent_default, on_key|
		Keyboard({ event: event, keys: keys, prevent_default: prevent_default, on_key: Box.box(|e| Box.box(on_key(e))) })

	port_listen : Str, (Str -> msg) -> Sub(msg)
	port_listen = |name, decoder| PortListen({ name: name, on_value: Box.box(|s| Box.box(decoder(s))) })

	url_changed : (Str -> msg) -> Sub(msg)
	url_changed = |on_change| UrlChanged({ on_change: Box.box(|s| Box.box(on_change(s))) })
}

# --- roc test (run via `roc test platform/main.roc`) ---
# `map` is Box plumbing: a mistake there (wrong unbox depth, dropped wrap)
# only shows up in the wasm harnesses as corruption, so pin it here by
# firing the mapped callbacks directly.

expect {
	mapped = Sub.every(7, |t| "tick:${t.to_str()}").map(|s| "outer:${s}")
	match mapped {
		Every(r) => {
			inner = Box.unbox(r.on_tick)
			r.ms == 7 and Box.unbox(inner(5)) == "outer:tick:5"
		}
		_ => Bool.False
	}
}

expect {
	sub = Sub.keyboard("keydown", ["Enter", "Escape"], Bool.True, |e| e.key)
	match sub.map(|k| "got:${k}") {
		Keyboard(r) => {
			ev = {
				key: "Enter",
				code: "Enter",
				ctrl: Bool.False,
				shift: Bool.False,
				alt: Bool.False,
				meta: Bool.False,
				repeat: Bool.False,
				is_composing: Bool.False,
			}
			inner = Box.unbox(r.on_key)
			r.event == "keydown"
				and r.keys == ["Enter", "Escape"]
					and r.prevent_default
						and Box.unbox(inner(ev)) == "got:Enter"
		}
		_ => Bool.False
	}
}

expect {
	match Sub.port_listen("prices", |s| "port:${s}").map(|m| "outer:${m}") {
		PortListen(r) => {
			inner = Box.unbox(r.on_value)
			r.name == "prices" and Box.unbox(inner("42")) == "outer:port:42"
		}
		_ => Bool.False
	}
}

expect {
	match Sub.url_changed(|url| "nav:${url}").map(|m| "outer:${m}") {
		UrlChanged(r) => {
			inner = Box.unbox(r.on_change)
			Box.unbox(inner("/home")) == "outer:nav:/home"
		}
		_ => Bool.False
	}
}
