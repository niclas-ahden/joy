app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
}

import html.Html exposing [div, input, ul, li, text]
import html.Attribute exposing [placeholder, on_input]
import pf.Effect

Model : { messages : List(Msg) }

Msg : [UserTypedNewGuest(Str)]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ messages: [] }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	({ messages: List.append(model.messages, msg) }, [])

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			input([
				placeholder("Type here"),
				on_input(|typed| UserTypedNewGuest(typed)),
			]),
			ul([], List.map(model.messages, message_row)),
		],
	)

message_row : Msg -> Html(Msg)
message_row = |msg| li([], [text(Str.inspect(msg))])

subscriptions = |_model| []
