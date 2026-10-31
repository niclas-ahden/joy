app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [button, text]
import html.Attribute exposing [on_click]
import pf.Effect
import pf.Media

# Fixture for check_runtime_features.mjs: an app that only plays a media
# element, so its runtime.js must hold Media.play's code and none of the
# rest of Media's.

Model : {}

Msg : [UserClickedPlay, Played(Try({}, Media.Problem))]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({}, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedPlay => (model, [Media.play("#clip", |done| Played(done))])
		Played(_) => (model, [])
	}

view : Model -> Html.Html(Msg)
view = |_| button([on_click(UserClickedPlay)], [text("Play")])
