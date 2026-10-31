app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [div, button, text]
import html.Attribute exposing [id, on_click]
import pf.Effect

Model : { count : I64 }

Msg : [Increment, Decrement]

subscriptions = |_model| []

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
