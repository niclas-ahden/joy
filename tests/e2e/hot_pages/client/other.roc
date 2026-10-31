# Another bundle on the same page as Shop/cart, which moves the URL.
app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [button, div, span, text]
import html.Attribute exposing [id, on_click]
import pf.DOM
import pf.Effect

Model : I64

Msg : [Inc, Move]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| (0, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Inc => (model + 1, [])
		Move => (model, [DOM.push_url("/moved")])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			span([id("other-label")], [text("other one")]),
			button([id("other-inc"), on_click(Inc)], [text("+")]),
			button([id("other-move"), on_click(Move)], [text("move")]),
			span([id("other-count")], [text(model.to_str())]),
		],
	)
