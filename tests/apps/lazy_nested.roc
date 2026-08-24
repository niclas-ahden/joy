app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, button, ul, li, p, text]
import html.Attribute exposing [class, on_click]
import pf.Effect exposing [Effect]

# Exercises Html.lazy: an outer lazy section (taking rows + label) holds a
# nested lazy region (taking rows only), so changing the label forces the
# outer thunk while the nested one still skips, and growing rows forces
# both. Toggling the section off and on exercises dropping and re-forcing
# retained subtrees. Handlers inside lazy regions must keep dispatching
# across skipped renders.

Model : {
	clicks : I64,
	rows : I64,
	label : Str,
	show : Bool,
}

Msg : [Bump, Grow, Relabel, Toggle, Inner]

# No recurring event sources.
subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ clicks: 0, rows: 3, label: "A", show: Bool.True }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Bump => ({ ..model, clicks: model.clicks + 1 }, [])
		Inner => ({ ..model, clicks: model.clicks + 1 }, [])
		Grow => ({ ..model, rows: model.rows + 1 }, [])
		Relabel => ({ ..model, label: "${model.label}!" }, [])
		Toggle => ({ ..model, show: !model.show }, [])
	}

deep : I64 -> Html(Msg)
deep = |rows|
	div(
		[class("deep")],
		[
			button([class("deep-btn"), on_click(Inner)], [text("deep")]),
			text("deep ${rows.to_str()}"),
		],
	)

section : I64, Str -> Html(Msg)
section = |rows, label| {
	items =
		(1..=rows).iter()
			.map(|n| li([], [text("item ${n.to_str()}")]))
			.collect()
	div(
		[class("section")],
		[
			button([class("inner-btn"), on_click(Inner)], [text("inner")]),
			p([], [text("label ${label}")]),
			Html.lazy(deep, rows),
			ul([], items),
		],
	)
}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			button([on_click(Bump)], [text("bump")]),
			button([on_click(Grow)], [text("grow")]),
			button([on_click(Relabel)], [text("relabel")]),
			button([on_click(Toggle)], [text("toggle")]),
			text("clicks ${model.clicks.to_str()}"),
			if model.show {
				Html.lazy2(section, model.rows, model.label)
			} else {
				text("hidden")
			},
		],
	)
