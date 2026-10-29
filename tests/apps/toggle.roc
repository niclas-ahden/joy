app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.1/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [div, element, button, text]
import html.Attribute exposing [on_click]
import pf.Effect

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

view : Model -> Html(Msg)
view = |model| {
	label = model.count.to_str()
	child =
		match model.count % 2 {
			0 => text("even ${label}")
			_ => element("b", [], [text("odd ${label}")])
		}
	div([], [button([on_click(Next)], [text("next")]), child])
}
