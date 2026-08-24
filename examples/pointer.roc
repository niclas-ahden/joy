app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, p, text]
import html.Attribute exposing [id, style, on_pointer, on_pointer_down, on_pointer_move, on_pointer_up]
import pf.Effect exposing [Effect]

# Pointer events (unifying mouse, touch and pen) as typed messages: each
# handler takes a real `PointerEvent -> Msg` function, so coordinates,
# buttons and modifiers arrive in `update` with no decoding boilerplate.
# The pad tracks a drag: press to grab, move (with a button held) to draw,
# release to drop. Shift-press is counted separately to show modifiers.

Model : {
	x : F64,
	y : F64,
	dragging : Bool,
	moves : U64,
	shift_clicks : U64,
}

Msg : [
	UserPressed(Attribute.PointerEvent),
	UserDragged(Attribute.PointerEvent),
	UserReleased,
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_|
	({ x: 0.0, y: 0.0, dragging: Bool.False, moves: 0, shift_clicks: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserPressed(e) =>
			(
				{
					..model,
					x: e.offset_x,
					y: e.offset_y,
					dragging: Bool.True,
					shift_clicks: if e.shift model.shift_clicks + 1 else model.shift_clicks,
				},
				[],
			)

		UserDragged(e) =>
		# `buttons` is the held-buttons bitmask, so a plain hover (no
		# button down) never counts as dragging.
			if model.dragging and e.buttons > 0
				({ ..model, x: e.offset_x, y: e.offset_y, moves: model.moves + 1 }, [])
			else
				(model, [])

		UserReleased => ({ ..model, dragging: Bool.False }, [])
	}

render : Model -> Html(Msg)
render = |model| {
	dragging_status = if model.dragging "dragging" else "idle"
	div(
		[],
		[
			div(
				[
					id("pad"),
					# touch-action: none stops the browser from claiming
					# touch gestures for scrolling before pointermove fires.
					style([("width", "300px"), ("height", "200px"), ("touch-action", "none"), ("background", "#eee")]),
					on_pointer_down(|e| UserPressed(e)),
					# prevent_default while dragging suppresses text selection.
					on_pointer("pointermove", |e| UserDragged(e)).prevent_default(),
					on_pointer_up(|_| UserReleased),
				],
				[text("Draw here")],
			),
			p([id("position")], [text("At ${model.x.to_str()}, ${model.y.to_str()} (${dragging_status})")]),
			p([id("moves")], [text("Moves: ${model.moves.to_str()}")]),
			p([id("shift-clicks")], [text("Shift-clicks: ${model.shift_clicks.to_str()}")]),
		],
	)
}
