app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, form, textarea, label, input, button, p, h1, text]
import html.Attribute exposing [rows, cols, type, checked, on_input, on_submit, on_check]
import pf.Effect exposing [Effect]
import pf.Console

Model : { draft : Str, saved : Str, secret : Bool }

Msg : [
	UserTypedSomething(Str),
	UserSavedEntry,
	UserToggledSecret(Bool),
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ draft: "", saved: "", secret: Bool.False }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserTypedSomething(message) =>
			({ ..model, draft: message }, [Console.log("User typed: ${message}")])

		UserSavedEntry => ({ ..model, saved: model.draft }, [])

		UserToggledSecret(secret) => ({ ..model, secret }, [])
	}

render : Model -> Html(Msg)
render = |model| {
	secret_status = if model.secret "on" else "off"
	div(
		[],
		[
			h1([], [text("Dear diary")]),
			# Submitting (Enter or the button) never reloads the page:
			# on_submit prevents the browser default and sends the msg.
			form(
				[on_submit(UserSavedEntry)],
				[
					textarea(
						# `|s| UserTypedSomething(s)` rather than a bare `UserTypedSomething`:
						# tag constructors aren't first-class functions in Roc.
						[rows(10), cols(30), on_input(|s| UserTypedSomething(s))],
						[],
					),
					button([type("submit")], [text("Save entry")]),
				],
			),
			label(
				[],
				[
					input([type("checkbox"), checked(model.secret), on_check(|s| UserToggledSecret(s))]),
					text("Secret (${secret_status})"),
				],
			),
			p([], [text(model.draft)]),
			p([], [text("Saved: ${model.saved}")]),
		],
	)
}
