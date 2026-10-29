app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.1/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [div, p, button, text]
import html.Attribute exposing [on_click]
import pf.Effect
import pf.Sub

# Fixture for check_features.mjs: Effect.call's reply, done and failed, an
# operation the runtime.js lacks, and Sub.listen's events, which run exactly
# while the subscription is listed.

Model : { echo : Str, broken : Str, absent : Str, listening : Bool, events : List(Str) }

Msg : [
	UserClickedEcho,
	UserClickedBroken,
	UserClickedSend,
	UserClickedAbsent,
	GotEcho(Try(List(U8), [FeatureFailed(Str)])),
	GotBroken(Try(List(U8), [FeatureFailed(Str)])),
	GotAbsent(Try(List(U8), [FeatureFailed(Str)])),
	UserToggledListening,
	GotEvent(Str),
]

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ echo: "", broken: "", absent: "", listening: Bool.False, events: [] }, [])

subscriptions : Model -> List(Sub(Msg))
subscriptions = |model|
	if model.listening {
		[Sub.listen("joy/test/ticks", [5], |event| GotEvent(Str.from_utf8_lossy(event)))]
	} else {
		[]
	}

show : Try(List(U8), [FeatureFailed(Str)]) -> Str
show = |reply|
	match reply {
		Ok(answer) => "ok ${Str.from_utf8_lossy(answer)}"
		Err(FeatureFailed(reason)) => "failed ${reason}"
	}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedEcho => (model, [Effect.call("joy/test/echo", "hej".to_utf8(), |r| GotEcho(Effect.reply(r)))])
		UserClickedBroken => (model, [Effect.call("joy/test/broken", [], |r| GotBroken(Effect.reply(r)))])
		UserClickedSend => (model, [Effect.send("joy/test/sent", "note".to_utf8())])
		UserClickedAbsent => (model, [Effect.call("joy/test/absent", [], |r| GotAbsent(Effect.reply(r)))])
		GotEcho(r) => ({ ..model, echo: show(r) }, [])
		GotBroken(r) => ({ ..model, broken: show(r) }, [])
		GotAbsent(r) => ({ ..model, absent: show(r) }, [])
		UserToggledListening => ({ ..model, listening: !model.listening }, [])
		GotEvent(event) => ({ ..model, events: model.events.append(event) }, [])
	}

render : Model -> Html.Html(Msg)
render = |model|
	div(
		[],
		[
			button([on_click(UserClickedEcho)], [text("Echo")]),
			button([on_click(UserClickedBroken)], [text("Broken")]),
			button([on_click(UserClickedSend)], [text("Send")]),
			button([on_click(UserClickedAbsent)], [text("Absent")]),
			button([on_click(UserToggledListening)], [text("Listen")]),
			p([], [text("echo: ${model.echo}")]),
			p([], [text("broken: ${model.broken}")]),
			p([], [text("absent: ${model.absent}")]),
			p([], [text("events: ${Str.join_with(model.events, ",")}")]),
		],
	)
