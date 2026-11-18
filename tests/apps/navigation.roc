app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
	url: "https://github.com/niclas-ahden/roc-url/releases/download/0.7.1/AuBv5v9TGGUS4yRtC8tLEVyEr7MkaReZCeuu2sYANn8F.tar.zst",
}

import html.Html exposing [a, div, h1, h2, p, input, button, text]
import html.Attribute exposing [href, id, placeholder, on_input, on_click]
import pf.Effect
import pf.DOM
import url.Uri

# This example shows the three ways to change the URL from a Joy app:
#
#   DOM.replace_url  rewrite the URL in place, no reload, no history entry
#   DOM.push_url     change the URL, no reload, adds a history entry
#   DOM.navigate     a full page load (leaves the current page)
#
# and the two subscriptions that complete the loop:
#
#   DOM.on_url_change  fires each time the URL changes: by Back and Forward,
#                      and by push_url and replace_url
#   DOM.on_link_click  hands the app the clicks on its own links, so a link
#                      can change the URL without loading a page
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
	UserClickedLink(Str),
	UrlChanged(Str),
]

# The URL is where the query lives. Each change of it arrives as a Str, and
# the decoder pulls the query back out of it before update runs.
subscriptions = |_model| [
	DOM.on_url_change(|url| UrlChanged(query_from_search(url))),
	DOM.on_link_click(|url| UserClickedLink(url)),
]

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
		# Adds a history entry, so Back returns to where you were. The
		# query goes along, as the URL is where it is read from.
			(model, [DOM.push_url("?q=${Uri.percent_encode(model)}&demo=push")])

		UserClickedLink(url) =>
		# A link of our own: go there without loading a page.
			(model, [DOM.push_url(url)])

		UserClickedReload =>
		# A full page load. The query you typed is lost because init
		# runs again, unlike the two effects above which keep the Model
		# intact.
			(model, [DOM.navigate("?reloaded=1")])

		UrlChanged(query) => {
			# The URL changed, by Back or Forward or by one of the effects
			# above. The subscription's decoder already re-derived the query
			# from it, so the view matches the address bar.
			(query, [])
		}
	}

view : Model -> Html(Msg)
view = |model|
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
			h2([], [text("on_link_click: a link without a page load")]),
			p([], [a([id("link"), href("?q=linked")], [text("Search for linked")])]),
			h2([], [text("navigate: full page load")]),
			button([id("reload"), on_click(UserClickedReload)], [text("Reload with ?reloaded=1")]),
			p([], [text("Leaves the current page. Notice the query above resets, because the app re-initialises.")]),
		],
	)
