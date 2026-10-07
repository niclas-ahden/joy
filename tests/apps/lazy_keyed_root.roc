app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [div, button, text]
import html.Attribute exposing [id, on_click]
import pf.Effect

# Probe: a thunk whose view returns Html.keyed at its root. The host must
# keep unwrapping after forcing, or the region emits nothing (a blank
# render) and the differ misreads the wrapper as an element.

Model : { n : U64 }

Msg : [UserClickedTick]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ n: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedTick => ({ n: model.n + 1 }, [])
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			button([id("tick"), on_click(UserClickedTick)], [text("tick")]),
			div([id("out")], [Html.lazy(keyed_view, model.n)]),
		],
	)

keyed_view : U64 -> Html(Msg)
keyed_view = |n|
	Html.keyed("row-${n.to_str()}", div([id("kv")], [text("v${n.to_str()}")]))
