app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, button, input, text]
import html.Attribute exposing [id, type, value, on_input, on_click]
import pf.Effect exposing [Effect]

# Probe: `value` names a live DOM property that drifts as the user types.
# A render that leaves the model's value unchanged must still re-pin the
# property, or the DOM keeps text the model rejected. The update below
# rejects anything containing "!", so a rejected keystroke is exactly the
# unchanged-model render the re-pin exists for.

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
			input([id("name"), type("text"), value(model.name), on_input(|s| UserTyped(s))]),
			button([id("tick"), on_click(UserClickedTick)], [text(model.ticks.to_str())]),
		],
	)
