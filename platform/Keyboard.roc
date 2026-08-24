## Global (document-level) keyboard subscriptions. Each firing carries the
## `KeyEvent` record: the key ("a", "Enter", "Escape", ...), the physical
## code ("KeyA", ...), the modifier flags, and whether it is a held-key
## auto-repeat. Return one of these from `subscriptions` for as long as it
## should listen; dropping it from the list removes the document listener.
##
## The key filter and preventDefault decisions are data on the subscription
## rather than logic in your app: the browser handler applies them without
## entering the app, and together with the event name they form the
## subscription's identity for diffing. An empty filter matches every key,
## and the prevent-default variant suppresses the browser default for
## exactly the filtered keys.
##
## Keys compare against the event's `key` string exactly, so the match is
## case-sensitive: Shift makes "a" arrive as "A". List both to catch either.
##
## For keyboard events on a specific element, see `Attribute.on_keydown`.
import Sub exposing [Sub]

Keyboard := [].{

	## Msg for every keydown.
	on_down : (Sub.KeyEvent -> msg) -> Sub(msg)
	on_down = |to_msg| Sub.keyboard("keydown", [], Bool.False, to_msg)

	## Keydown for these keys only.
	on_down_keys : List(Str), (Sub.KeyEvent -> msg) -> Sub(msg)
	on_down_keys = |keys, to_msg| Sub.keyboard("keydown", keys, Bool.False, to_msg)

	## Like `on_down_keys`, and preventDefault on the matching events.
	on_down_keys_prevent_default : List(Str), (Sub.KeyEvent -> msg) -> Sub(msg)
	on_down_keys_prevent_default = |keys, to_msg| Sub.keyboard("keydown", keys, Bool.True, to_msg)

	## Msg for every keyup.
	on_up : (Sub.KeyEvent -> msg) -> Sub(msg)
	on_up = |to_msg| Sub.keyboard("keyup", [], Bool.False, to_msg)

	## Keyup for these keys only.
	on_up_keys : List(Str), (Sub.KeyEvent -> msg) -> Sub(msg)
	on_up_keys = |keys, to_msg| Sub.keyboard("keyup", keys, Bool.False, to_msg)

	## Like `on_up_keys`, and preventDefault on the matching events.
	on_up_keys_prevent_default : List(Str), (Sub.KeyEvent -> msg) -> Sub(msg)
	on_up_keys_prevent_default = |keys, to_msg| Sub.keyboard("keyup", keys, Bool.True, to_msg)
}

# Each helper is one Sub.keyboard call, so what can go wrong is the event
# name, a swapped keys/prevent_default pair, or a dropped callback. Pin all
# three per helper.

key_event = |key| {
	key: key,
	code: key,
	ctrl: Bool.False,
	shift: Bool.False,
	alt: Bool.False,
	meta: Bool.False,
	repeat: Bool.False,
	is_composing: Bool.False,
}

expect {
	match Keyboard.on_down(|e| "down:${e.key}") {
		Keyboard(r) => {
			inner = Box.unbox(r.on_key)
			r.event == "keydown"
				and r.keys == []
					and r.prevent_default == Bool.False
						and Box.unbox(inner(key_event("a"))) == "down:a"
		}
		_ => Bool.False
	}
}

expect {
	match Keyboard.on_down_keys(["a", "A"], |e| e.key) {
		Keyboard(r) => r.event == "keydown" and r.keys == ["a", "A"] and r.prevent_default == Bool.False
		_ => Bool.False
	}
}

expect {
	match Keyboard.on_down_keys_prevent_default(["Tab"], |e| e.key) {
		Keyboard(r) => r.event == "keydown" and r.keys == ["Tab"] and r.prevent_default
		_ => Bool.False
	}
}

expect {
	match Keyboard.on_up(|e| "up:${e.key}") {
		Keyboard(r) => {
			inner = Box.unbox(r.on_key)
			r.event == "keyup"
				and r.keys == []
					and r.prevent_default == Bool.False
						and Box.unbox(inner(key_event("Escape"))) == "up:Escape"
		}
		_ => Bool.False
	}
}

expect {
	match Keyboard.on_up_keys(["Enter"], |e| e.key) {
		Keyboard(r) => r.event == "keyup" and r.keys == ["Enter"] and r.prevent_default == Bool.False
		_ => Bool.False
	}
}

expect {
	match Keyboard.on_up_keys_prevent_default([" "], |e| e.key) {
		Keyboard(r) => r.event == "keyup" and r.keys == [" "] and r.prevent_default
		_ => Bool.False
	}
}
