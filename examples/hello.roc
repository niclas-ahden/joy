app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../platform/main.roc",
}

import html.Html exposing [div, text]
import pf.Effect

Model : Str

Msg : []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ("Roc", [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, _msg| (model, [])

view : Model -> Html(Msg)
view = |model|
	div([], [text("Hello, ${model}!")])

# No subs needed for this example!
subscriptions = |_model| []
