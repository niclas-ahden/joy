app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
	pf: platform "../../../../platform/main.roc",
	url: "https://github.com/niclas-ahden/roc-url/releases/download/0.7.1/AuBv5v9TGGUS4yRtC8tLEVyEr7MkaReZCeuu2sYANn8F.tar.zst",
}

import /Page/About as AboutPage
import /Page/Home as HomePage
import /Page/Quote as QuotePage
import Route
import html.Html exposing [a, div, h1, header, nav, p, text]
import html.Attribute exposing [aria, href]
import pf.DOM
import pf.Effect
import pf.Http
import pf.Sub

Model : {
	route : Try(Route.Route, [NotFound]),
	count : I64,
	quote : QuotePage.Quote,
}

Msg : [
	UserClickedLink(Str),
	UrlChanged(Str),
	UserClickedDecrement,
	UserClickedIncrement,
	ServerReturnedQuote(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
	UserClickedAnotherQuote,
]

## `url` is the URL the page was opened at. public/index.html passes it in
## as the flags, so that a refresh or a shared link opens the right page.
init : Str -> (Model, List(Effect(Msg)))
init = |url| show_route({ route: Err(NotFound), count: 0, quote: NotRequestedYet }, Route.parse(url))

## Called when you navigate to another page. This is where we fetch what the
## new page needs: Quote needs a quote, unless we already have one.
show_route : Model, Try(Route.Route, [NotFound]) -> (Model, List(Effect(Msg)))
show_route = |model, route| {
	at = { ..model, route }
	(shown, effects) =
		match route {
			Ok(Quote) =>
				match model.quote {
					NotRequestedYet | Failed(_) => ask_for_quote(at)
					Loading | Loaded(_) => (at, [])
				}

			Ok(Home) | Ok(About) | Err(NotFound) => (at, [])
		}
	(shown, effects.append(DOM.set_title(title(route))))
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedLink(url) =>
			match Route.parse(url) {
				Ok(_) => (model, [DOM.push_url(url)])

				# Not one of our pages, e.g. a file in public/. Let the browser
				# load it like any other link.
				Err(NotFound) => (model, [DOM.navigate(url)])
			}

		UrlChanged(url) => {
			route = Route.parse(url)
			if route == model.route {
				# We're already on this page, e.g. only the #fragment changed,
				# so there's nothing to do.
				(model, [])
			} else {
				show_route(model, route)
			}
		}

		UserClickedDecrement => ({ ..model, count: model.count - 1 }, [])
		UserClickedIncrement => ({ ..model, count: model.count + 1 }, [])

		ServerReturnedQuote(answer) => ({ ..model, quote: QuotePage.read(answer) }, [])

		# One quote at a time: a click while we're waiting for the server does
		# nothing.
		UserClickedAnotherQuote =>
			if model.quote == Loading {
				(model, [])
			} else {
				ask_for_quote(model)
			}
	}

ask_for_quote : Model -> (Model, List(Effect(Msg)))
ask_for_quote = |model|
	({ ..model, quote: Loading }, [Http.get(QuotePage.url, |answer| ServerReturnedQuote(answer))])

subscriptions : Model -> List(Sub(Msg))
subscriptions = |_model| [
	DOM.on_link_click(|url| UserClickedLink(url)),
	DOM.on_url_change(|url| UrlChanged(url)),
]

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			header([], [nav([], Route.menu.map(|route| link(model, route)))]),
			Html.main([], [view_page(model)]),
		],
	)

view_page : Model -> Html(Msg)
view_page = |model|
	match model.route {
		Ok(Home) => HomePage.view({ count: model.count, on_decrement: UserClickedDecrement, on_increment: UserClickedIncrement })
		Ok(Quote) => QuotePage.view({ quote: model.quote, on_another: UserClickedAnotherQuote })
		Ok(About) => AboutPage.view({})
		Err(NotFound) => div([], [h1([], [text("Not found")]), p([], [text("There is no page here.")])])
	}

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
	current = if (model.route == Ok(route)) [aria("current", "page")] else []
	a([href(Route.to_path(route))].concat(current), [text(Route.label(route))])
}
