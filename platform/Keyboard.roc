## Key presses anywhere on the page.
##
## Each function here gives a subscription. It listens for as long as it is
## in the list `subscriptions` returns.
##
## ```roc
## Msg : [UserPressedEsc]
##
## subscriptions = |_model| [
##     Keyboard.on_down_keys(["Escape"], |_| UserPressedEsc),
## ]
## ```
##
## ## Which key
##
## Your function gets a [Sub.KeyEvent], which says which key it was and
## whether Ctrl, Shift, Alt or Meta was held.
##
## Keys are named the way the browser names them: `"a"`, `"Enter"`,
## `"Escape"`, `"ArrowLeft"`, and `" "` for the space bar. The match is exact,
## and capitals count: with Shift held, `"a"` arrives as `"A"`. List both to
## catch either.
##
## ## One element or the whole page
##
## These subscriptions hear keys wherever the focus is. For keys typed in one
## field, put `on_keydown`, `on_keyup` or `on_key` from joy-html's `Attribute`
## on that element.
##
## The guide has [a keyboard example](../../#example-keyboard) to try.
import Sub
import Wire

Keyboard := [].{

	## A message for every key that goes down.
	##
	## ```roc
	## Keyboard.on_down(|event| UserPressedKey(event.key))
	## ```
	on_down : (Sub.KeyEvent -> msg) -> Sub(msg)
	on_down = |to_msg| listen_keys("keydown", [], Bool.False, to_msg)

	## A message when one of these keys goes down.
	##
	## ```roc
	## Keyboard.on_down_keys(
	##     ["ArrowLeft", "ArrowRight"],
	##     |event| UserPressedArrow(event.key),
	## )
	## ```
	on_down_keys : List(Str), (Sub.KeyEvent -> msg) -> Sub(msg)
	on_down_keys = |keys, to_msg| listen_keys("keydown", keys, Bool.False, to_msg)

	## Like [Keyboard.on_down_keys], and the browser does not do what it normally
	## does with those keys. Use it to keep Space from scrolling the page, or Tab
	## from moving the focus.
	##
	## ```roc
	## Keyboard.on_down_keys_prevent_default(
	##     [" "],
	##     |_| UserPressedSpace,
	## )
	## ```
	##
	## A key typed in a field outside your app keeps its normal effect.
	on_down_keys_prevent_default : List(Str), (Sub.KeyEvent -> msg) -> Sub(msg)
	on_down_keys_prevent_default = |keys, to_msg| listen_keys("keydown", keys, Bool.True, to_msg)

	## A message for every key that comes back up.
	##
	## ```roc
	## Keyboard.on_up(|event| UserReleasedKey(event.key))
	## ```
	on_up : (Sub.KeyEvent -> msg) -> Sub(msg)
	on_up = |to_msg| listen_keys("keyup", [], Bool.False, to_msg)

	## A message when one of these keys comes back up.
	##
	## ```roc
	## Keyboard.on_up_keys([" "], |_| UserReleasedSpace)
	## ```
	on_up_keys : List(Str), (Sub.KeyEvent -> msg) -> Sub(msg)
	on_up_keys = |keys, to_msg| listen_keys("keyup", keys, Bool.False, to_msg)

	## Like [Keyboard.on_up_keys], and the browser does not do what it normally
	## does when those keys come up. A key typed in a field outside your app keeps
	## its normal effect.
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

read_key : List(U8) -> Try({ key : Str, code : Str, flags : U8 }, Wire.Problem)
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
