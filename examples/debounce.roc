app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../platform/main.roc",
}

import html.Html exposing [button, div, input, p, text]
import html.Attribute exposing [id, on_click, on_input, placeholder]
import pf.Effect
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

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			input([id("search"), placeholder("Search..."), on_input(|s| UserTyped(s))]),
			button([id("cancel"), on_click(UserCanceled)], [text("Cancel")]),
			p([id("searched")], [text("Searched for: ${model.searched}")]),
			p([id("searches")], [text("Searches: ${model.searches.to_str()}")]),
		],
	)

# No subs needed for this example!
subscriptions = |_model| []
