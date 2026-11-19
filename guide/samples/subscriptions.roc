app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../platform/main.roc",
}

import html.Html exposing [button, div, h1, text]
import html.Attribute exposing [on_click]
import pf.Effect
import pf.Sub
import pf.Time

Model : { level : I64, paused : Bool }

Msg : [Tick(I64), UserToggledPause]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ level: 8983, paused: False }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Tick(_now) => ({ ..model, level: model.level + 1 }, [])
		UserToggledPause => ({ ..model, paused: !model.paused }, [])
	}

subscriptions : Model -> List(Sub(Msg))
subscriptions = |model|
	if model.paused {
		[]
	} else {
		[Time.every(1000, |now| Tick(now))]
	}

view : Model -> Html(Msg)
view = |model| {
	label = if (model.paused) "Get excited!" else "Calm down"
	div(
		[],
		[
			h1([], [text("Your excitement level for Roc: ${model.level.to_str()}")]),
			button([on_click(UserToggledPause)], [text(label)]),
		],
	)
}
