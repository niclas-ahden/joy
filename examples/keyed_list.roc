app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, button, ul, li, text]
import html.Attribute exposing [on_click]
import pf.Effect exposing [Effect]

# A reorderable list whose items are wrapped in `Html.keyed`. Keys give
# items identity across renders: rotating, prepending or removing moves
# the existing DOM nodes (keeping their state) instead of rewriting every
# position. Compare `counters.roc`, whose unkeyed children are only ever
# patched positionally.

Model : {
	items : List(Str),
	next_id : U64,
}

Msg : [
	UserClickedRotate,
	UserClickedPrepend,
	UserClickedRemoveSecond,
	UserClickedReverse,
]

# No recurring event sources.
subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ items: ["apple", "banana", "cherry", "date"], next_id: 1 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedRotate =>
		# Move the first item to the end.
			match model.items.first() {
				Ok(head) => ({ ..model, items: model.items.drop_at(0).append(head) }, [])
				Err(_) => (model, [])
			}
		UserClickedPrepend =>
			(
				{
					items: model.items.prepend("new ${model.next_id.to_str()}"),
					next_id: model.next_id + 1,
				},
				[],
			)
		UserClickedRemoveSecond => ({ ..model, items: model.items.drop_at(1) }, [])
		# Worst case for the differ's LIS pass: everything moves.
		UserClickedReverse =>
			({ ..model, items: model.items.fold([], |acc, item| acc.prepend(item)) }, [])
		}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			button([on_click(UserClickedRotate)], [text("rotate")]),
			button([on_click(UserClickedPrepend)], [text("prepend")]),
			button([on_click(UserClickedRemoveSecond)], [text("remove second")]),
			button([on_click(UserClickedReverse)], [text("reverse")]),
			ul(
				[],
				model.items.map(|item| Html.keyed(item, li([], [text(item)]))),
			),
		],
	)
