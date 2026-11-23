app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../platform/main.roc",
}

import html.Html exposing [text]
import pf.Effect

Model : { name : Str, karma : I32 }

Msg : []

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |flags|
	match Json.parse(flags) {
		Ok(model) => (model, [])
		Err(problem) => crash "Could not read the flags: ${Str.inspect(problem)}"
	}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, _msg| (model, [])

view : Model -> Html(Msg)
view = |model| text(model.name)
