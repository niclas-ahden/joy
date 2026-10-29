app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.1/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [div, button, input, text]
import html.Attribute exposing [id, type, value, on_input, on_click]
import pf.Effect

# Probe: a controlled input inside Html.lazy. A rejected keystroke leaves
# the thunk's capture equal, so the render skips the region and no attribute
# op reaches the input. The property pin after the event must not depend on
# the render having walked the input.

Model : { name : Str, ticks : U64 }

Msg : [UserTyped(Str), UserClickedTick]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ name: "init", ticks: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserTyped(s) =>
			if s.contains("!") {
				(model, [])
			} else {
				({ ..model, name: s }, [])
			}

		UserClickedTick => ({ ..model, ticks: model.ticks + 1 }, [])
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			button([id("tick"), on_click(UserClickedTick)], [text(model.ticks.to_str())]),
			Html.lazy(form_view, model.name),
		],
	)

form_view : Str -> Html(Msg)
form_view = |name|
	div([id("form")], [input([id("name"), type("text"), value(name), on_input(|s| UserTyped(s))])])
