app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, dialog, p, button, text]
import html.Attribute exposing [id, on_click]
import pf.Effect exposing [Effect]
import pf.DOM

# Native <dialog> modals. The dialog and its contents render from the model
# like any other element; only the open/closed state lives in the browser,
# so `update` flips it with the `DOM.show_modal`/`DOM.close_modal` effects
# (addressed by CSS selector) while updating the model it renders from.

Model : { opened : U64, confirmed : U64 }

Msg : [
	UserOpened,
	UserConfirmed,
	UserDismissed,
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ opened: 0, confirmed: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserOpened =>
			({ ..model, opened: model.opened + 1 }, [DOM.show_modal("#confirm")])

		UserConfirmed =>
			({ ..model, confirmed: model.confirmed + 1 }, [DOM.close_modal("#confirm")])

		UserDismissed =>
			(model, [DOM.close_modal("#confirm")])
		}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			button([id("open"), on_click(UserOpened)], [text("Delete everything")]),
			p([id("counts")], [text("opened ${model.opened.to_str()}, confirmed ${model.confirmed.to_str()}")]),
			dialog(
				[id("confirm")],
				[
					p([id("prompt")], [text("Really delete everything?")]),
					button([id("yes"), on_click(UserConfirmed)], [text("Yes, delete")]),
					button([id("keep"), on_click(UserDismissed)], [text("Keep it")]),
				],
			),
		],
	)
