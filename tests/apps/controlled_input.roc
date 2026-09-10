app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [div, button, input, text]
import html.Attribute exposing [id, type, value, checked, on_input, on_check, on_click]
import pf.Effect

# Probe: `value` and `checked` name live DOM properties that drift as the
# user types or clicks. A dispatch that leaves the model unchanged renders
# nothing for them, so the runtime pins the property back after the
# control's own event, or the DOM keeps what the model rejected. The update
# below rejects text containing "!" and refuses to un-agree, so a rejected
# keystroke and a refused uncheck are exactly the unchanged-model dispatches
# the pin exists for. "Pin" toggles whether the view declares `value` and
# `checked` at all: undeclared, the controls are uncontrolled and the pin
# must leave them alone, and declaring them again re-asserts the model.

Model : { name : Str, agreed : Bool, ticks : U64, pinned : Bool }

Msg : [UserTyped(Str), UserToggledAgree(Bool), UserClickedTick, UserClickedPin]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ name: "init", agreed: Bool.False, ticks: 0, pinned: Bool.True }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserTyped(s) =>
			if s.contains("!") {
				(model, [])
			} else {
				({ ..model, name: s }, [])
			}

		UserToggledAgree(now) =>
			if now {
				({ ..model, agreed: Bool.True }, [])
			} else {
				(model, [])
			}

		UserClickedTick => ({ ..model, ticks: model.ticks + 1 }, [])

		UserClickedPin => ({ ..model, pinned: !model.pinned }, [])
	}

render : Model -> Html(Msg)
render = |model| {
	value_attr = if model.pinned [value(model.name)] else []
	checked_attr = if model.pinned [checked(model.agreed)] else []
	div(
		[],
		[
			input([id("name"), type("text"), on_input(|s| UserTyped(s))].concat(value_attr)),
			input([id("agree"), type("checkbox"), on_check(|now| UserToggledAgree(now))].concat(checked_attr)),
			button([id("tick"), on_click(UserClickedTick)], [text(model.ticks.to_str())]),
			button([id("pin"), on_click(UserClickedPin)], [text(if model.pinned "pinned" else "unpinned")]),
		],
	)
}
