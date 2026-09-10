app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, button, div, input, p, text]
import html.Attribute exposing [id, on_click, on_input, value]
import pf.DOM
import pf.Effect exposing [Effect]

# Fixture for DOM.focus (tests/check_focus.mjs and tests/e2e/focus_test.roc).
# "Edit" reveals an input that did not exist in the previous render and
# focuses it in the same update: the effect runs after the paint, so the
# selector finds the element. "Focus nothing" names a selector that matches
# nothing, which must be a harmless no-op.

Model : { editing : Bool, name : Str, missing : U64 }

Msg : [
	UserClickedEdit,
	UserTyped(Str),
	UserClickedDone,
	UserClickedFocusNothing,
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ editing: Bool.False, name: "Ada", missing: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedEdit => ({ ..model, editing: Bool.True }, [DOM.focus("#name")])
		UserTyped(name) => ({ ..model, name }, [])
		UserClickedDone => ({ ..model, editing: Bool.False }, [])
		UserClickedFocusNothing => ({ ..model, missing: model.missing + 1 }, [DOM.focus("#nope")])
	}

render : Model -> Html(Msg)
render = |model| {
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
			div([id("editor")], editor),
		],
	)
}
