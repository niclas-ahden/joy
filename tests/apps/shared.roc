app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, button, ul, li, text]
import html.Attribute exposing [class, on_click]
import pf.Effect exposing [Effect]

# A model-resident subtree. `chunk` is rebuilt only when its input (`rows`)
# changes and lives in the model; every other render hands the differ the
# same retained value, whose allocations it recognises and skips wholesale.
# The handler inside the chunk keeps dispatching across skipped renders, and
# growing the row count still rebuilds and rediffs the chunk normally.

Model : {
	clicks : I64,
	rows : I64,
	chunk : Html(Msg),
}

Msg : [
	UserClickedBump,
	UserClickedGrow,
	UserClickedChunk,
]

# No recurring event sources.
subscriptions = |_model| []

build_chunk : I64 -> Html(Msg)
build_chunk = |rows| {
	items =
		Iter.exclusive_range(1, rows + 1, Unknown)
			.map(|n| li([], [text("row ${n.to_str()}")]))
			.collect()
	div(
		[class("chunk")],
		[
			button([class("chunk-btn"), on_click(UserClickedChunk)], [text("chunk")]),
			ul([], items),
		],
	)
}

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ clicks: 0, rows: 3, chunk: build_chunk(3) }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedBump => ({ ..model, clicks: model.clicks + 1 }, [])
		UserClickedChunk => ({ ..model, clicks: model.clicks + 1 }, [])
		UserClickedGrow => {
			rows = model.rows + 1
			({ ..model, rows, chunk: build_chunk(rows) }, [])
		}
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			button([on_click(UserClickedBump)], [text("bump")]),
			button([on_click(UserClickedGrow)], [text("grow")]),
			text("clicks ${model.clicks.to_str()}"),
			model.chunk,
		],
	)
