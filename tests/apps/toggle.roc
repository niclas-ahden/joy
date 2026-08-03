app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, element, button, text]
import html.Attribute exposing [on_click]
import pf.Effect exposing [Effect]

# Exercises the diff's REPLACE path: the second child alternates between a text
# node (even) and a `<b>` element (odd), so each click swaps its kind.
Model : { count : I64 }

Msg : [Next]

# No recurring event sources.
subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ count: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Next => ({ count: model.count + 1 }, [])
	}

# A named helper rather than `element(...)` inline in the match arm: joining
# a direct `element` call with a `text` call in one arm crashes roc build
# with an out-of-bounds panic in the solved-type digest, a known compiler
# bug. Routing the element through a top-level function sidesteps it.
odd_view : Str -> Html(Msg)
odd_view = |label| element("b", [], [text("odd ${label}")])

render : Model -> Html(Msg)
render = |model| {
	label = model.count.to_str()
	child =
		match model.count % 2 {
			0 => text("even ${label}")
			_ => odd_view(label)
		}
	div([], [button([on_click(Next)], [text("next")]), child])
}
