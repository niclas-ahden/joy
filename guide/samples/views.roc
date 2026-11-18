app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../platform/main.roc",
}

import html.Html exposing [button, div, p, text]
import html.Attribute exposing [on_click]
import pf.Effect

Model : { guests : List(Str) }

Msg : [UserClickedClear]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ guests: ["Ada", "Grace"] }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |_model, msg|
	match msg {
		UserClickedClear => ({ guests: [] }, [])
	}

guest_count : List(Str) -> Html(msg)
guest_count = |guests| p([], [text("${guests.len().to_str()} coming")])

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			button([on_click(UserClickedClear)], [text("Clear")]),
			guest_count(model.guests),
		],
	)
