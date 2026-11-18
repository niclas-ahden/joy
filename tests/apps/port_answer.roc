# A page that answers a port at once, from inside the handler of the send
# that asked: the answer's update drops and adds subscriptions while the
# update that asked is still starting and stopping its own.
app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
}

import html.Html exposing [div, text]
import pf.Effect
import pf.Port

Model : { phase : U64, log : List(Str) }

Msg : [PageSaidGo, PageAnswered, PageSentX(Str), PageSentY(Str)]

## `x` is heard before the question and `y` after the answer.
subscriptions = |model|
	[Port.listen("answer", |_| PageAnswered), Port.listen("go", |_| PageSaidGo)]
		.concat(if model.phase == 0 [Port.listen("x", |value| PageSentX(value))] else [])
		.concat(if model.phase == 2 [Port.listen("y", |value| PageSentY(value))] else [])

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ phase: 0, log: [] }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		PageSaidGo => ({ ..model, phase: 1 }, [Port.send("ask", "")])
		PageAnswered => ({ ..model, phase: 2 }, [])
		PageSentX(value) => ({ ..model, log: model.log.append("x:${value}") }, [])
		PageSentY(value) => ({ ..model, log: model.log.append("y:${value}") }, [])
	}

view : Model -> Html(Msg)
view = |model| div([], [text("phase ${model.phase.to_str()} log ${Str.join_with(model.log, " ")}")])
