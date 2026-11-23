app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../platform/main.roc",
}

import html.Html exposing [button, div, text]
import html.Attribute exposing [id, on_click]
import pf.Effect

Model : { count : I64 }

Msg : [Increment, Decrement]

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ count: 0 }, [])

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			button([id("increment"), on_click(Increment)], [text("+")]),
			text(model.count.to_str()),
			button([id("decrement"), on_click(Decrement)], [text("-")]),
		],
	)

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Increment => ({ count: model.count + 1 }, [])
		Decrement => ({ count: model.count - 1 }, [])
	}

# No subs needed for this example!
subscriptions = |_model| []
