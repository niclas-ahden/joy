app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../platform/main.roc",
}

import html.Html exposing [button, div, p, text]
import html.Attribute exposing [on_click]
import pf.Effect
import pf.Port
import pf.Sub

Model : { ticks : U64 }

Msg : [JavaScriptTicked, UserClickedCheer]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ ticks: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		JavaScriptTicked => ({ ticks: model.ticks + 1 }, [])
		UserClickedCheer => (model, [Port.send("cheer", "Roc cheers after ${model.ticks.to_str()} ticks!")])
	}

subscriptions : Model -> List(Sub(Msg))
subscriptions = |_model| [Port.listen("tick", |_text| JavaScriptTicked)]

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			p([], [text("Roc heard ${model.ticks.to_str()} ticks from JavaScript")]),
			button([on_click(UserClickedCheer)], [text("Cheer")]),
		],
	)
