app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../platform/main.roc",
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
		Human({ name, karma }) => text("${name} has ${karma.to_str()} karma")
		FailedToParseFlags(flags) => text("Could not read these flags: ${flags}")
	}
