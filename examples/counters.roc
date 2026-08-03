app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, button, ul, li, text]
import html.Attribute exposing [style, on_click]
import pf.Effect exposing [Effect]

# Three independent counters. Exercises messages with payloads
# (`UserClickedIncrement(Left)`) crossing the boundary as real values.

Model : {
	left : I64,
	middle : I64,
	right : I64,
}

Msg : [
	UserClickedDecrement([Left, Middle, Right]),
	UserClickedIncrement([Left, Middle, Right]),
]

# No recurring event sources.
subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| (
	{
		left: -10,
		middle: 0,
		right: 10,
	},
	[],
)

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedDecrement(Left) => ({ ..model, left: model.left - 1 }, [])
		UserClickedDecrement(Middle) => ({ ..model, middle: model.middle - 1 }, [])
		UserClickedDecrement(Right) => ({ ..model, right: model.right - 1 }, [])
		UserClickedIncrement(Left) => ({ ..model, left: model.left + 1 }, [])
		UserClickedIncrement(Middle) => ({ ..model, middle: model.middle + 1 }, [])
		UserClickedIncrement(Right) => ({ ..model, right: model.right + 1 }, [])
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[
			style([
				("display", "flex"),
				("justify-content", "space-around"),
				("padding", "20px"),
			]),
		],
		[
			counter(Left, model.left),
			counter(Middle, model.middle),
			counter(Right, model.right),
		],
	)

counter : [Left, Middle, Right], I64 -> Html(Msg)
counter = |variant, value|
	ul(
		[
			style([
				("list-style", "none"),
				("padding", "0"),
				("text-align", "center"),
			]),
		],
		[
			li(
				[],
				[
					button(
						[
							style([
								("background-color", "red"),
								("color", "white"),
								("padding", "10px 20px"),
							]),
							on_click(UserClickedDecrement(variant)),
						],
						[text("-")],
					),
				],
			),
			li(
				[style([("font-size", "24px"), ("font-weight", "bold")])],
				[text(value.to_str())],
			),
			li(
				[],
				[
					button(
						[
							style([
								("background-color", "blue"),
								("color", "white"),
								("padding", "10px 20px"),
							]),
							on_click(UserClickedIncrement(variant)),
						],
						[text("+")],
					),
				],
			),
		],
	)
