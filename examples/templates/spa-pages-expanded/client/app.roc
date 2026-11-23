app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../../../platform/main.roc",
	url: "https://github.com/niclas-ahden/roc-url/releases/download/0.7.1/AuBv5v9TGGUS4yRtC8tLEVyEr7MkaReZCeuu2sYANn8F.tar.zst",
}

import Notebook
import Page
import Route
import html.Html exposing [a, div, header, nav, text]
import html.Attribute exposing [aria, href]
import pf.DOM
import pf.Effect
import pf.Navigation
import pf.Sub

## `notebook` holds your notes. It belongs to the app, so the notes remain
##            regardless of what page you're on.
## `page` holds the page you're on, along with that page's own state. It's
##        replaced whenever you navigate, which is what clears a page's
##        state when you leave it.
Model : { notebook : Notebook, page : Page }

Msg : [
	UserClickedLink(Str),
	UrlChanged(Str),
	PageMsg(Page.Msg),
]

## `url` is the URL the page was opened at. public/index.html passes it in
## as the flags, so that a refresh or a shared link opens the right page.
init : Str -> (Model, List(Effect(Msg)))
init = |url| show_route({ notebook: Notebook.start, page: NotFound }, Route.parse(url))

show_route : Model, Try(Route.Route, [NotFound]) -> (Model, List(Effect(Msg)))
show_route = |model, route| {
	(page, effects) = Page.init(route)
	({ ..model, page }, Effect.map_all(effects, |m| PageMsg(m)).append(DOM.set_title(title(route))))
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedLink(url) =>
			match Route.parse(url) {
				Ok(_) => (model, [Navigation.push_url(url)])

				# Not one of our pages, e.g. a file in public/. Let the browser
				# load it like any other link.
				Err(NotFound) => (model, [Navigation.navigate(url)])
			}

		UrlChanged(url) => {
			route = Route.parse(url)
			if route == model.page.route() {
				# We're already on this page, e.g. only the #fragment changed,
				# so there's nothing to do.
				(model, [])
			} else {
				show_route(model, route)
			}
		}

		PageMsg(page_msg) => {
			(page, notebook, effects) = model.page.update(page_msg, model.notebook)
			({ notebook, page }, Effect.map_all(effects, |m| PageMsg(m)))
		}
	}

subscriptions : Model -> List(Sub(Msg))
subscriptions = |model|
	[
		Navigation.on_link_click(|url| UserClickedLink(url)),
		Navigation.on_url_change(|url| UrlChanged(url)),
	].concat(Sub.map_all(model.page.subscriptions(), |m| PageMsg(m)))

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			header([], [nav([], Route.menu.map(|route| link(model, route)))]),
			Html.main([], [model.page.view(model.notebook).map(|m| PageMsg(m))]),
		],
	)

title : Try(Route.Route, [NotFound]) -> Str
title = |route|
	match route {
		Ok(found) => "${Route.label(found)} - Joy app"
		Err(NotFound) => "Not found - Joy app"
	}

## A link in the menu. The link to the page you're on gets `aria-current`,
## which the stylesheet uses to highlight it, and screen readers read out.
link : Model, Route.Route -> Html(Msg)
link = |model, route| {
	current = if (model.page.route() == Ok(route)) [aria("current", "page")] else []
	a([href(Route.to_path(route))].concat(current), [text(Route.label(route))])
}
