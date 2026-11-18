app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../platform/main.roc",
}

import html.Html exposing [button, div, text]
import html.Attribute exposing [on_click]
import pf.Console
import pf.Effect

Model : { count : I64 }

Msg : [UserClickedIncrement]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ count: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedIncrement =>
			(
				{ count: model.count + 1 },
				[Console.log("Someone clicked +")],
			)
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			text(model.count.to_str()),
			button([on_click(UserClickedIncrement)], [text("+")]),
		],
	)

subscriptions = |_model| []
