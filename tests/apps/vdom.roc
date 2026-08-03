app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, p, ul, li, a, button, input, text, element]
import html.Attribute exposing [attribute, class, value, checked, type, href, on_click]
import pf.Effect exposing [Effect]

# Steps through view shapes so the node harness can exercise every diff path:
# text patched in place, attribute add/remove/change, boolean attributes,
# handler remove/re-add, unsafe attributes, tag changes (REPLACE) and unkeyed
# child-list edits. `clicks` counts Clicked dispatches, so the harness can
# assert exactly how many times a handler fired.
Model : { step : I64, clicks : I64 }

Msg : [Next, Clicked]

# No recurring event sources.
subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ step: 0, clicks: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Next => ({ ..model, step: model.step + 1 }, [])
		Clicked => ({ ..model, clicks: model.clicks + 1 }, [])
	}

render : Model -> Html(Msg)
render = |model| {
	stage =
		match model.step {
			0 => stage0
			1 => stage1
			_ => stage2
		}
	div(
		[],
		[
			button([on_click(Next)], [text("next")]),
			text("clicks ${model.clicks.to_str()}"),
			stage,
		],
	)
}

# Baseline: attributes, live form state, an armed handler, a safe link and an
# unkeyed list.
stage0 : Html(Msg)
stage0 =
	div(
		[],
		[
			p([class("alpha"), attribute("title", "greeting")], [text("hello")]),
			input([type("text"), value("v0")]),
			input([type("checkbox"), checked(Bool.True)]),
			button([on_click(Clicked)], [text("target")]),
			a([href("https://example.com")], [text("link")]),
			ul([], [li([], [text("one")]), li([], [text("two")]), li([], [text("three")])]),
		],
	)

# Everything changes: class swapped, title dropped, data-x added, text patched
# in place, value attribute removed, checkbox unchecked, the target handler
# removed, unsafe href/onclick attempted, a middle item inserted.
stage1 : Html(Msg)
stage1 =
	div(
		[],
		[
			p([class("beta"), attribute("data-x", "1"), attribute("onclick", "evil()")], [text("world")]),
			input([type("text")]),
			input([type("checkbox"), checked(Bool.False)]),
			button([], [text("target")]),
			a([href("javascript:alert(1)")], [text("link")]),
			ul([], [li([], [text("one")]), li([], [text("mid")]), li([], [text("two")]), li([], [text("three")])]),
		],
	)

# The handler comes back (must dispatch exactly once per click), the paragraph
# becomes a <b> (tag change forces REPLACE), the link is safe again, the value
# is host-controlled again, the checkbox re-checked, and the list shrinks.
stage2 : Html(Msg)
stage2 =
	div(
		[],
		[
			element("b", [class("beta")], [text("world")]),
			input([type("text"), value("v2")]),
			input([type("checkbox"), checked(Bool.True)]),
			button([on_click(Clicked)], [text("target")]),
			a([href("https://example.com")], [text("link")]),
			ul([], [li([], [text("one")]), li([], [text("three")])]),
		],
	)
