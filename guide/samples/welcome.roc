app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
}

import html.Html exposing [h1, div, button, p, text]
import html.Attribute exposing [on_click]
import pf.Effect

Model : { count : I64 }

Msg : [UserClickedIncrement, UserClickedDecrement]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ count: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedIncrement => ({ count: model.count + 1 }, [])
		UserClickedDecrement => ({ count: model.count - 1 }, [])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			h1([], [text("Hello! Change me")]),
			button([on_click(UserClickedDecrement)], [text("-")]),
			text(model.count.to_str()),
			button([on_click(UserClickedIncrement)], [text("+")]),
			p([], [text("👈 Edit the code on the left, I dare ya")]),
		],
	)

subscriptions = |_model| []
