app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
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
