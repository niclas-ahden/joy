app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../platform/main.roc",
}

import html.Html exposing [a, button, div, h1, nav, p, text]
import html.Attribute exposing [href, id, on_click]
import pf.Effect
import pf.Navigation
import pf.Sub

# An app with three pages and a URL for each.
#
# The menu is made of ordinary links. `Navigation.on_link_click` hands us a
# click on one, `Navigation.push_url` changes the URL without loading a page,
# and `Navigation.on_url_change` tells us where we are, also after Back and
# Forward. So the page on screen always comes from the URL, in one place.
#
# This app starts on Home whatever URL it was opened at. One that should
# open the page a URL names reads that URL from its flags.

Page : [Home, About, Contact, NotFound]

Model : { page : Page, opened : U64 }

Msg : [
	UserClickedLink(Str),
	UrlChanged(Str),
	UserClickedSkip,
	UserClickedReload,
]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ page: Home, opened: 1 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		# A new step in the history: Back returns to the page before.
		UserClickedLink(url) => (model, [Navigation.push_url(url)])

		UrlChanged(url) =>
			({ page: page_at(url), opened: model.opened + 1 }, [])

		# No step in the history: Back skips the page we left.
		UserClickedSkip => (model, [Navigation.replace_url("/contact")])

		# A full page load. The app starts over, so the count does too.
		UserClickedReload => (model, [Navigation.navigate("/")])
	}

subscriptions : Model -> List(Sub(Msg))
subscriptions = |_model| [
	Navigation.on_link_click(|url| UserClickedLink(url)),
	Navigation.on_url_change(|url| UrlChanged(url)),
]

# The page a URL names, by the last part of its path.
page_at : Str -> Page
page_at = |url| {
	path =
		match url.split_last("/") {
			Ok(split) => split.after
			Err(_) => ""
		}
	match path {
		"" => Home
		"about" => About
		"contact" => Contact
		_ => NotFound
	}
}

expect page_at("https://example.com/") == Home
expect page_at("https://example.com/about") == About
expect page_at("https://example.com/contact") == Contact
expect page_at("https://example.com/nope") == NotFound

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			nav(
				[],
				[
					a([href("/")], [text("Home")]),
					text(" | "),
					a([href("/about")], [text("About")]),
					text(" | "),
					a([href("/contact")], [text("Contact")]),
					text(" | "),
					a([href("/nope")], [text("A page that is not there")]),
				],
			),
			h1([id("page")], [text(title(model.page))]),
			p([id("opened")], [text("Pages opened: ${model.opened.to_str()}")]),
			p([], [text("Follow a few links, then try Back and Forward.")]),
			button([id("skip"), on_click(UserClickedSkip)], [text("To Contact, with no step for Back")]),
			button([id("reload"), on_click(UserClickedReload)], [text("Load the start page")]),
		],
	)

title : Page -> Str
title = |page|
	match page {
		Home => "Home"
		About => "About"
		Contact => "Contact"
		NotFound => "Not found"
	}
