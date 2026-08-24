app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, button, text]
import html.Attribute exposing [id, on_click]
import pf.Effect exposing [Effect]

# Probe: a lazy Html value held in the model is the same thunk allocation
# on every render, so the host's lazy table only ever sees cache hits for
# it. Swapping it between unkeyed positions pairs it against a non-lazy
# sibling, the one path where a hit is all that proves the retained
# subtree is still reachable. The harness asserts the retained entry
# survives the swap and that the handler inside it still dispatches.

Model : { row : Html(Msg), swapped : Bool, clicks : U64 }

Msg : [UserClickedSwap, UserClickedInner]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_flags|
	({ row: Html.lazy(row_view, 1), swapped: Bool.False, clicks: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedSwap => ({ ..model, swapped: !model.swapped }, [])
		UserClickedInner => ({ ..model, clicks: model.clicks + 1 }, [])
	}

render : Model -> Html(Msg)
render = |model| {
	pair = if model.swapped {
		[model.row, text("plain")]
	} else {
		[text("plain"), model.row]
	}
	div(
		[],
		[
			button([id("swap"), on_click(UserClickedSwap)], [text("swap")]),
			div([id("clicks")], [text(model.clicks.to_str())]),
			div([id("pair")], pair),
		],
	)
}

row_view : U64 -> Html(Msg)
row_view = |n|
	div([], [button([id("inner"), on_click(UserClickedInner)], [text("row ${n.to_str()}")])])
