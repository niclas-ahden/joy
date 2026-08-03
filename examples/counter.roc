app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, button, text]
import html.Attribute exposing [on_click]
import pf.Effect exposing [Effect]

Model : { count : I64 }

Msg : [Increment, Decrement]

# No recurring event sources.
subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ count: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Increment => ({ count: model.count + 1 }, [])
		Decrement => ({ count: model.count - 1 }, [])
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			button([on_click(Increment)], [text("+")]),
			text(model.count.to_str()),
			button([on_click(Decrement)], [text("-")]),
		],
	)
