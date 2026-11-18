## The app: which page is on screen, the links between the pages, and the
## URL. Each page is a module of its own under Page/, and Route.roc spells
## every URL the app has.
app [Model, Msg, init, view, subscriptions, update] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
	pf: platform "../../../../platform/main.roc",
}

import /Page/About as AboutPage
import /Page/Home as HomePage
import Route
import html.Html exposing [a, div, header, main, nav, p, text]
import html.Attribute exposing [class_list, href, on_click]
import pf.DOM
import pf.Effect
import pf.Sub

## The page on screen, with that page's state.
Model : [Home(HomePage.Model), About, NotFound]

Msg : [
	UserClickedLink(Route.Route),
	UserWentBackOrForward(Str),
	HomeMsg(HomePage.Msg),
]

## The page passes the URL it was opened at as the flags (see
## public/index.html), so a refresh or a shared link opens the same page.
init : Str -> (Model, List(Effect(Msg)))
init = |url| open(Route.parse(url))

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		# A link to the page on screen changes nothing. Any other opens its
		# page at the top, and adds its URL to the history so Back returns.
		UserClickedLink(route) =>
			if on_screen(model) == Ok(route) {
				(model, [])
			} else {
				(page, effects) = open(Ok(route))
				(page, effects.concat([DOM.push_url(Route.to_path(route)), DOM.scroll_to({ x: 0, y: 0 })]))
			}

		# The browser has changed the URL already. A URL that still names the
		# page on screen leaves the page as it is.
		UserWentBackOrForward(url) => {
			found = Route.parse(url)
			if found == on_screen(model) {
				(model, [])
			} else {
				open(found)
			}
		}

		HomeMsg(page_msg) =>
			match model {
				Home(page) => on_page(HomePage.update(page, page_msg), |p| Home(p), |m| HomeMsg(m))
				# A message for a page that is no longer on screen, like a late timer.
				_ => (model, [])
			}
	}

## Back and Forward change the URL without a message of the app's own, so
## the app listens for them. The page on screen adds its own subscriptions.
subscriptions : Model -> List(Sub(Msg))
subscriptions = |model| {
	page =
		match model {
			Home(home) => HomePage.subscriptions(home).map(|sub| sub.map(|m| HomeMsg(m)))
			About | NotFound => []
		}
	[DOM.on_url_change(|url| UserWentBackOrForward(url))].concat(page)
}

view : Model -> Html(Msg)
view = |model| {
	page =
		match model {
			Home(home) => Html.map(HomePage.view(home), |m| HomeMsg(m))
			About => AboutPage.view({})
			NotFound => p([], [text("There is no page here.")])
		}
	div(
		[],
		[
			header([], [nav([], [link("Home", Home, model), link("About", About, model)])]),
			main([], [page]),
		],
	)
}

## The page a route opens, from the start, with its title on the tab.
open : Try(Route.Route, [NotFound]) -> (Model, List(Effect(Msg)))
open = |found| {
	(model, effects) =
		match found {
			Ok(Home) => on_page(HomePage.init({}), |p| Home(p), |m| HomeMsg(m))
			Ok(About) => (About, [])
			Err(NotFound) => (NotFound, [])
		}
	(model, effects.append(DOM.set_title("${title(model)} - Joy app")))
}

## The route of the page on screen.
on_screen : Model -> Try(Route.Route, [NotFound])
on_screen = |model|
	match model {
		Home(_) => Ok(Home)
		About => Ok(About)
		NotFound => Err(NotFound)
	}

title : Model -> Str
title = |model|
	match model {
		Home(_) => "Home"
		About => "About"
		NotFound => "Not found"
	}

## A page's update, put back into the app's model and messages.
on_page : (page, List(Effect(page_msg))), (page -> Model), (page_msg -> Msg) -> (Model, List(Effect(Msg)))
on_page = |(page, effects), to_model, to_msg| (to_model(page), effects.map(|effect| effect.map(to_msg)))

## A link to another page. A click switches the page in place, and the href
## keeps it a real link.
link : Str, Route.Route, Model -> Html(Msg)
link = |label, route, model|
	a(
		[
			href(Route.to_path(route)),
			class_list([("current", on_screen(model) == Ok(route))]),
			on_click(UserClickedLink(route)).prevent_default(),
		],
		[text(label)],
	)
