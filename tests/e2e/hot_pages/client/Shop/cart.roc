# A bundle below a folder of client/, for the hot reload tests. tests/e2e/hot_pages
# has no server, so ./joy dev serves its pages.
app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../../../../platform/main.roc",
}

import html.Html exposing [button, div, span, text]
import html.Attribute exposing [id, on_click]
import pf.Effect

Model : I64

Msg : [Inc]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| (0, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, _msg| (model + 1, [])

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			span([id("cart-label")], [text("cart one")]),
			button([id("cart-inc"), on_click(Inc)], [text("+")]),
			span([id("cart-count")], [text(model.to_str())]),
		],
	)
