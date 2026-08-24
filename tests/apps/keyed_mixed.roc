app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, button, text]
import html.Attribute exposing [id, on_click]
import pf.Effect exposing [Effect]

# Probe: a keyed child among unkeyed siblings. Identity lives on the key,
# so swapping the keyed element past an unkeyed one must MOVE its DOM node,
# never pair it positionally with the unkeyed sibling and patch both in
# place.

Model : { swapped : Bool }

Msg : [UserClickedSwap]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ swapped: Bool.False }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedSwap => ({ swapped: !model.swapped }, [])
	}

render : Model -> Html(Msg)
render = |model| {
	keyed_child = Html.keyed("a", div([id("keyed")], [text("K")]))
	plain_child = div([id("plain")], [text("P")])
	kids = if model.swapped {
		[keyed_child, plain_child]
	} else {
		[plain_child, keyed_child]
	}
	div(
		[],
		[
			button([id("swap"), on_click(UserClickedSwap)], [text("swap")]),
			div([id("pair")], kids),
		],
	)
}
