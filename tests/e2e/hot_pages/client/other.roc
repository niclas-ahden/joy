# Another bundle on the same page as Shop/cart, which moves the URL.
app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../../../platform/main.roc",
}

import html.Html exposing [button, div, span, text]
import html.Attribute exposing [id, on_click]
import pf.Effect
import pf.Navigation

Model : I64

Msg : [Inc, Move]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| (0, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Inc => (model + 1, [])
		Move => (model, [Navigation.push_url("/moved")])
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
