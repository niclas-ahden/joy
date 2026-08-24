app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, p, input, button, text]
import html.Attribute exposing [id, on_input, on_click, placeholder]
import pf.Effect exposing [Effect]
import pf.Time

# Search-as-you-type with a trailing-edge debounce: every keystroke re-arms
# the "search" timer, so the (pretend) search runs once, 200ms after typing
# pauses, with only the final text. Escape hatch included: the `Time.cancel`
# effect discards the pending timer entirely.

Model : { typed : Str, searched : Str, searches : U64 }

Msg : [
	UserTyped(Str),
	SearchFired,
	UserCanceled,
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ typed: "", searched: "", searches: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserTyped(s) =>
		# Same key each time: a fresh keystroke replaces the pending
		# timer, so only the last of a burst fires.
			({ ..model, typed: s }, [Time.debounce("search", 200, |_| SearchFired)])

		SearchFired =>
			({ ..model, searched: model.typed, searches: model.searches + 1 }, [])

		UserCanceled =>
			(model, [Time.cancel("search")])
		}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			input([id("search"), placeholder("Search..."), on_input(|s| UserTyped(s))]),
			button([id("cancel"), on_click(UserCanceled)], [text("Cancel")]),
			p([id("searched")], [text("searched for: ${model.searched}")]),
			p([id("searches")], [text("searches: ${model.searches.to_str()}")]),
		],
	)
