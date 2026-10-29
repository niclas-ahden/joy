app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.1/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [button, div, input, p, text]
import html.Attribute exposing [id, on_click, on_input, value]
import pf.DOM
import pf.Effect

# Fixture for DOM.focus (tests/check_focus.mjs and tests/e2e/focus_test.roc).
# "Edit" reveals an input that did not exist in the previous render and
# focuses it in the same update: the effect runs after the paint, so the
# selector finds the element. "Focus nothing" names a selector that matches
# nothing, which must be a harmless no-op. "Bad selector" names one that is
# not valid CSS (an id starting with a digit) for every selector effect,
# which must be just as harmless: the app keeps running.

Model : { editing : Bool, name : Str, missing : U64, invalid : U64 }

Msg : [
	UserClickedEdit,
	UserTyped(Str),
	UserClickedDone,
	UserClickedFocusNothing,
	UserClickedBadSelector,
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ editing: Bool.False, name: "Ada", missing: 0, invalid: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedEdit => ({ ..model, editing: Bool.True }, [DOM.focus("#name")])
		UserTyped(name) => ({ ..model, name }, [])
		UserClickedDone => ({ ..model, editing: Bool.False }, [])
		UserClickedFocusNothing => ({ ..model, missing: model.missing + 1 }, [DOM.focus("#nope")])
		UserClickedBadSelector =>
			({ ..model, invalid: model.invalid + 1 }, [DOM.focus("#12"), DOM.show_modal("#12"), DOM.close_modal("#12")])
	}

view : Model -> Html(Msg)
view = |model| {
	editor = if model.editing {
		[
			input([id("name"), value(model.name), on_input(|s| UserTyped(s))]),
			button([id("done"), on_click(UserClickedDone)], [text("Done")]),
		]
	} else {
		[]
	}

	div(
		[],
		[
			p([id("shown")], [text("Hello, ${model.name}")]),
			button([id("edit"), on_click(UserClickedEdit)], [text("Edit")]),
			button([id("nothing"), on_click(UserClickedFocusNothing)], [text("Focus nothing")]),
			p([id("missing")], [text("missing ${model.missing.to_str()}")]),
			button([id("bad"), on_click(UserClickedBadSelector)], [text("Bad selector")]),
			p([id("invalid")], [text("invalid ${model.invalid.to_str()}")]),
			div([id("editor")], editor),
		],
	)
}
