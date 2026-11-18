app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../platform/main.roc",
}

import html.Html exposing [button, div, form, h1, input, label, p, text, textarea]
import html.Attribute exposing [checked, cols, id, on_check, on_input, on_submit, rows, type]
import pf.Effect
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

view : Model -> Html(Msg)
view = |model| {
	secret_status = if (model.secret) "on" else "off"
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
			p([id("draft")], [text(model.draft)]),
			p([id("saved")], [text("Saved: ${model.saved}")]),
		],
	)
}
