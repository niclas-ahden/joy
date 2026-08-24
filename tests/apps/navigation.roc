app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
	url: "https://github.com/niclas-ahden/roc-url/releases/download/0.6.1/95CwyLo97aKZ5twTy6VtkmmhF6MFKMr7hvPeMi6U7bAF.tar.zst",
}

import html.Html exposing [Html, div, h1, h2, p, input, button, text]
import html.Attribute exposing [id, placeholder, on_input, on_click]
import pf.Effect exposing [Effect]
import pf.DOM
import url.Uri

# This example shows the three ways to change the URL from a Joy app:
#
#   DOM.replace_url  rewrite the URL in place, no reload, no history entry
#   DOM.push_url     change the URL, no reload, adds a history entry
#   DOM.navigate     a full page load (leaves the current page)
#
# and the subscription that completes the loop:
#
#   DOM.on_url_change fires when Back/Forward moves through those entries
#
# Type in the search box and watch the address bar: the "?q=..." follows what
# you type, but Back does not step through every keystroke. That is the job
# replace_url is built for. The buttons below show how push_url and
# navigate differ, and pressing Back after a push re-fills the box from the
# URL via the subscription.

Model : Str

Msg : [
	UserTypedQuery(Str),
	UserClickedPush,
	UserClickedReload,
	UrlChanged(Str),
]

# Respond when the user steps through history; the new URL arrives as a Str
# and the decoder pulls the query back out of it before update runs.
subscriptions = |_model| [DOM.on_url_change(|url| UrlChanged(query_from_search(url)))]

init : Str -> (Model, List(Effect(Msg)))
init = |flags|
# The flags are expected to be the URL search string, e.g.
# "?q=hats%20on". Wire www/index.html to pass `location.search` so a
# shared or refreshed link starts with the box filled in.
	(query_from_search(flags), [])

## Pull the "q" parameter out of a URL search string, so "?q=hats%20on"
## becomes "hats on". query_params percent-decodes each pair for us.
query_from_search : Str -> Str
query_from_search = |search| {
	params = Uri.query_params(Uri.parse(search))
	match params.find_first(|(k, _v)| k == "q") {
		Ok((_k, v)) => v
		Err(_) => ""
	}
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserTypedQuery(query) => {
			# Percent-encode the query so spaces and special characters are
			# safe in the URL, then sync it into the address bar without
			# growing history.
			encoded = Uri.percent_encode(query)
			(query, [DOM.replace_url("?q=${encoded}")])
		}

		UserClickedPush =>
		# Adds a history entry, so Back returns to where you were.
			(model, [DOM.push_url("?demo=push")])

		UserClickedReload =>
		# A full page load. The query you typed is lost because init
		# runs again, unlike the two effects above which keep the Model
		# intact.
			(model, [DOM.navigate("?reloaded=1")])

		UrlChanged(query) => {
			# Back/Forward landed on a URL we pushed or replaced earlier; the
			# subscription's decoder already re-derived the query from it, so
			# the view matches the address bar again.
			(query, [])
		}
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			h1([], [text("Navigation")]),
			h2([], [text("replace_url: search as you type")]),
			input([id("search"), placeholder("Search..."), on_input(|q| UserTypedQuery(q))]),
			p([id("query")], [text("Current query: ${model}")]),
			p([], [text("The address bar shows ?q=... as you type, but Back does not record every keystroke.")]),
			h2([], [text("push_url: adds a history entry")]),
			button([id("push"), on_click(UserClickedPush)], [text("Push ?demo=push")]),
			p([], [text("Changes the URL without reloading and lets Back return here. DOM.on_url_change keeps the view in sync when you do.")]),
			h2([], [text("navigate: full page load")]),
			button([id("reload"), on_click(UserClickedReload)], [text("Reload with ?reloaded=1")]),
			p([], [text("Leaves the current page. Notice the query above resets, because the app re-initialises.")]),
		],
	)
