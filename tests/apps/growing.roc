# A text that is a little longer after every click, as a log, a transcript or
# a document being typed is. Each version needs a little more memory than the
# one before it, which is the pattern an allocator has to give back what it
# freed for, or the app's memory grows with every update it ever made.
app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
}

import html.Html exposing [button, div, p, text]
import html.Attribute exposing [id, on_click]
import pf.Effect

Model : { lines : List(Str), text : Str }

Msg : [UserClickedAdd]

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ lines: [], text: "" }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, UserClickedAdd| {
	line = "line ${model.lines.len().to_str()} of the log"
	({ lines: model.lines.append(line), text: Str.concat(model.text, "${line}\n") }, [])
}

subscriptions = |_model| []

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			button([id("add"), on_click(UserClickedAdd)], [text("add")]),
			# One text built anew from the list, and one carried in the model.
			p([id("joined")], [text(Str.join_with(model.lines, ", "))]),
			p([id("kept")], [text(model.text)]),
			p([id("count")], [text(model.lines.len().to_str())]),
		],
	)
