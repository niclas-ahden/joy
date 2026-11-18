app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [button, div, text]
import html.Attribute exposing [on_click]
import pf.Effect

# Crashes on purpose, for tests/check_crash.mjs: in init when the flags ask for
# it, and in update with a text short enough to sit inside the Str and with one
# that is not.

Model : {}

Msg : [UserClickedShort, UserClickedLong]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |flags|
	if flags == "crash in init" {
		crash "Could not read the flags: ${flags}"
	} else {
		({}, [])
	}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |_model, msg|
	match msg {
		UserClickedShort => crash "No"
		UserClickedLong => crash "Brödil has no karma left, and that should never happen"
	}

view : Model -> Html(Msg)
view = |_model|
	div(
		[],
		[
			button([on_click(UserClickedShort)], [text("Short")]),
			button([on_click(UserClickedLong)], [text("Long")]),
		],
	)
