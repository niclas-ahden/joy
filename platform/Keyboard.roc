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
