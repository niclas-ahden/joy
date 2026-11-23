app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../platform/main.roc",
}

import html.Html exposing [text]
import pf.Console
import pf.Effect

Model : {
	# Comes from the flags.
	human : [
		Human({ name : Str, karma : I32 }),
		FailedToParseFlags(Str),
	],
	# Only the client keeps track of this.
	retries : U8,
}

Msg : []

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |flags|
	match Json.parse(flags) {
		Ok({ name, karma }) => (
			{ human: Human({ name, karma }), retries: 0 },
			[],
		)
		Err(problem) => (
			{ human: FailedToParseFlags(flags), retries: 0 },
			[Console.log("Could not read the flags: ${Str.inspect(problem)}")],
		)
	}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, _msg| (model, [])

view : Model -> Html(Msg)
view = |model|
	match model.human {
		Human({ name, .. }) => text(name)
		FailedToParseFlags(flags) => text(flags)
	}
