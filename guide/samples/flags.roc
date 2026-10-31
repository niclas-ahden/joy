app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
}

import html.Html exposing [text]
import pf.Console
import pf.Effect

Model : [
	Human({ name : Str, karma : I32 }),
	FailedToParseFlags(Str),
]

Msg : []

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |flags|
	match Json.parse(flags) {
		Ok({ name, karma }) => (Human({ name, karma }), [])
		Err(problem) => (
			FailedToParseFlags(flags),
			[Console.log("Could not read the flags: ${Str.inspect(problem)}")],
		)
	}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, _msg| (model, [])

view : Model -> Html(Msg)
view = |model|
	match model {
		Human({ name, .. }) => text(name)
		FailedToParseFlags(flags) => text(flags)
	}
