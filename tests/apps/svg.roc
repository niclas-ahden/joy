app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.1/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [button, div, element, span, text]
import html.Attribute exposing [attribute, class, id]
import html.Event exposing [on_click]
import pf.Effect

# The namespace fixture: SVG and MathML built by the client, both on the
# first render and by every kind of patch that builds nodes later.
#
#   * names the HTML parser would adjust, written the way it would see them
#     (a lowercase viewbox and lineargradient, an xlink:href)
#   * a shape swapped inside the svg (a REPLACE under an SVG parent)
#   * keyed icons added and rotated (REORDER with NEW subtrees)
#   * a lazy region inside the svg
#   * the points where HTML comes back: foreignObject, desc and MathML's
#     text elements, and annotation-xml both ways
#   * a math block switched on and off (a REPLACE under an HTML parent)
Model : { square : Bool, icons : List(Str), next : U64, label : Str, math : Bool }

Msg : [ToggleShape, AddIcon, Rotate, Relabel, ToggleMath]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ square: Bool.False, icons: ["a", "b"], next: 0, label: "first", math: Bool.False }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		ToggleShape => ({ ..model, square: !model.square }, [])
		AddIcon => ({ ..model, icons: model.icons.append("n${model.next.to_str()}"), next: model.next + 1 }, [])
		Rotate => ({ ..model, icons: model.icons.drop_first(1).concat(model.icons.take_first(1)) }, [])
		Relabel => ({ ..model, label: "${model.label}+" }, [])
		ToggleMath => ({ ..model, math: !model.math }, [])
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			button([class("shape"), on_click(ToggleShape)], [text("shape")]),
			button([class("add"), on_click(AddIcon)], [text("add")]),
			button([class("rotate"), on_click(Rotate)], [text("rotate")]),
			button([class("relabel"), on_click(Relabel)], [text("relabel")]),
			button([class("math"), on_click(ToggleMath)], [text("math")]),
			element(
				"svg",
				[class("canvas"), attribute("viewbox", "0 0 100 100"), attribute("width", "100"), attribute("height", "100")],
				[
					element(
						"defs",
						[],
						[
							element("lineargradient", [id("grad")], [element("stop", [attribute("offset", "0"), attribute("stop-color", "red")], [])]),
							element("symbol", [id("dot"), attribute("viewBox", "0 0 10 10")], [element("circle", [attribute("cx", "5"), attribute("cy", "5"), attribute("r", "5")], [])]),
						],
					),
					if model.square {
						element("rect", [class("shape"), attribute("x", "10"), attribute("y", "10"), attribute("width", "30"), attribute("height", "30")], [])
					} else {
						element("circle", [class("shape"), attribute("cx", "25"), attribute("cy", "25"), attribute("r", "15"), attribute("fill", "url(#grad)")], [])
					},
					element("use", [class("sprite"), attribute("href", "#dot"), attribute("xlink:href", "#dot"), attribute("x", "50"), attribute("y", "5"), attribute("width", "10"), attribute("height", "10")], []),
					element(
						"foreignobject",
						[attribute("x", "0"), attribute("y", "60"), attribute("width", "100"), attribute("height", "40")],
						[div([class("inside-fo")], [text("html again")])],
					),
					element("desc", [], [span([class("in-desc")], [text("described")])]),
					element("g", [class("icons")], model.icons.map(|name| Html.keyed(name, icon(name)))),
					Html.lazy(label_view, model.label),
				],
			),
			if model.math {
				math_view
			} else {
				text("")
			},
		],
	)

icon : Str -> Html(Msg)
icon = |name|
	element(
		"g",
		[class("icon"), attribute("data-name", name)],
		[
			element("title", [], [text(name)]),
			element("circle", [attribute("cx", "80"), attribute("cy", "80"), attribute("r", "4")], []),
		],
	)

label_view : Str -> Html(Msg)
label_view = |label|
	element("text", [class("label"), attribute("x", "5"), attribute("y", "95")], [text(label)])

math_view : Html(Msg)
math_view =
	element(
		"math",
		[class("formula")],
		[
			element("mi", [], [text("x"), span([class("in-mi")], [text("html")]), element("mglyph", [], [])]),
			element("mrow", [], [element("mo", [], [text("+")]), element("mn", [], [text("1")])]),
			element("annotation-xml", [attribute("encoding", "text/html")], [div([class("in-annotation")], [text("html")])]),
			element("annotation-xml", [], [element("svg", [class("svg-in-math")], [])]),
		],
	)
