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
import Sub
import Wire

Keyboard := [].{

	## Msg for every keydown.
	on_down : (Sub.KeyEvent -> msg) -> Sub(msg)
	on_down = |to_msg| listen_keys("keydown", [], Bool.False, to_msg)

	## Keydown for these keys only.
	on_down_keys : List(Str), (Sub.KeyEvent -> msg) -> Sub(msg)
	on_down_keys = |keys, to_msg| listen_keys("keydown", keys, Bool.False, to_msg)

	## Like `on_down_keys`, and preventDefault on the matching events.
	on_down_keys_prevent_default : List(Str), (Sub.KeyEvent -> msg) -> Sub(msg)
	on_down_keys_prevent_default = |keys, to_msg| listen_keys("keydown", keys, Bool.True, to_msg)

	## Msg for every keyup.
	on_up : (Sub.KeyEvent -> msg) -> Sub(msg)
	on_up = |to_msg| listen_keys("keyup", [], Bool.False, to_msg)

	## Keyup for these keys only.
	on_up_keys : List(Str), (Sub.KeyEvent -> msg) -> Sub(msg)
	on_up_keys = |keys, to_msg| listen_keys("keyup", keys, Bool.False, to_msg)

	## Like `on_up_keys`, and preventDefault on the matching events.
	on_up_keys_prevent_default : List(Str), (Sub.KeyEvent -> msg) -> Sub(msg)
	on_up_keys_prevent_default = |keys, to_msg| listen_keys("keyup", keys, Bool.True, to_msg)
}

## The document listener every helper is: the event, the keys to filter
## on (none for every key) and whether to prevent their default.
listen_keys : Str, List(Str), Bool, (Sub.KeyEvent -> msg) -> Sub(msg)
listen_keys = |event, keys, prevent_default, to_msg| {
	args = keys.fold(Wire.writer({}).str(event).u32(keys.len().to_u32_wrap()), |w, key| w.str(key)).bool(prevent_default).done()
	Sub.listen("joy/keyboard/keys", args, |bytes| to_msg(key_event(bytes)))
}

## An event's key, code, and the flags packed into a byte (1 ctrl, 2 shift,
## 4 alt, 8 meta, 16 repeat, 32 is_composing).
key_event : List(U8) -> Sub.KeyEvent
key_event = |bytes| {
	{ key, code, flags } = read_key(bytes) ?? { key: "", code: "", flags: 0 }
	set = |bit| flags.bitwise_and(bit) != 0
	{ key, code, ctrl: set(1), shift: set(2), alt: set(4), meta: set(8), repeat: set(16), is_composing: set(32) }
}

read_key : List(U8) -> Try({ key : Str, code : Str, flags : U8 }, [WireEnded])
read_key = |bytes| {
	r = Wire.reader(bytes)
	(key, r1) = r.str()?
	(code, r2) = r1.str()?
	(flags, _) = r2.u8()?
	Ok({ key, code, flags })
}

# Each helper is one listen_keys call, so what can go wrong is the event
# name, a swapped keys/prevent_default pair, or a dropped callback. Pin all
# three per helper.

listened : Sub(Str) -> { id : Str, args : List(U8), got : Str }
listened = |sub| {
	{ id, args } = sub.identity()
	{ id: id, args: args, got: sub.deliver(Wire.writer({}).str("a").str("KeyA").u8(3).done()) }
}

args_for = |event, keys, prevent| keys.fold(Wire.writer({}).str(event).u32(keys.len().to_u32_wrap()), |w, key| w.str(key)).bool(prevent).done()

expect listened(Keyboard.on_down(|e| "down:${e.key}")) == { id: "joy/keyboard/keys", args: args_for("keydown", [], Bool.False), got: "down:a" }
expect listened(Keyboard.on_down_keys(["a", "A"], |e| e.key)).args == args_for("keydown", ["a", "A"], Bool.False)
expect listened(Keyboard.on_down_keys_prevent_default(["Tab"], |e| e.key)).args == args_for("keydown", ["Tab"], Bool.True)
expect listened(Keyboard.on_up(|e| "up:${e.code}")) == { id: "joy/keyboard/keys", args: args_for("keyup", [], Bool.False), got: "up:KeyA" }
expect listened(Keyboard.on_up_keys(["Enter"], |e| e.key)).args == args_for("keyup", ["Enter"], Bool.False)
expect listened(Keyboard.on_up_keys_prevent_default([" "], |e| e.key)).args == args_for("keyup", [" "], Bool.True)
expect key_event(Wire.writer({}).str("A").str("KeyA").u8(2 + 16).done()) == { key: "A", code: "KeyA", ctrl: Bool.False, shift: Bool.True, alt: Bool.False, meta: Bool.False, repeat: Bool.True, is_composing: Bool.False }
