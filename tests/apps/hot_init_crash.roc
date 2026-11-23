app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../platform/main.roc",
}

import html.Html exposing [text]
import pf.Effect

# A build whose init crashes, which tests/check_hot.mjs reloads into to check
# that the app it would replace keeps running.

Model : { count : I64 }

Msg : [Increment]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| crash "init is broken"

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, _msg| (model, [])

view : Model -> Html(Msg)
view = |_model| text("never rendered")
