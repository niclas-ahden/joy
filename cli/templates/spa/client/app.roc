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
	Home(HomePage.Msg),
]

## The page passes the path it was opened at as the flags (see
## public/index.html), so a refresh or a shared link opens the same page.
init : Str -> (Model, List(Effect(Msg)))
init = |path| open(Route.parse(path))

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match (model, msg) {
		(_, UserClickedLink(route)) => {
			(page, effects) = open(Ok(route))
			(page, effects.append(DOM.push_url(Route.to_path(route))))
		}

		(_, UserWentBackOrForward(path)) => open(Route.parse(path))
		(Home(page), Home(page_msg)) => on_page(HomePage.update(page, page_msg), |p| Home(p), |m| Home(m))

		# A message for a page that is no longer on screen, like a late timer.
		_ => (model, [])
	}

## Back and Forward change the URL without a message of the app's own, so
## the app listens for them. The page on screen adds its own subscriptions.
subscriptions : Model -> List(Sub(Msg))
subscriptions = |model| {
	page =
		match model {
			Home(home) => HomePage.subscriptions(home).map(|sub| sub.map(|m| Home(m)))
			About | NotFound => []
		}
	[DOM.on_url_change(|path| UserWentBackOrForward(path))].concat(page)
}

view : Model -> Html(Msg)
view = |model| {
	page =
		match model {
			Home(home) => Html.map(HomePage.view(home), |m| Home(m))
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

## The page a route opens, from the start.
open : Try(Route.Route, [NotFound]) -> (Model, List(Effect(Msg)))
open = |found|
	match found {
		Ok(Home) => on_page(HomePage.init({}), |p| Home(p), |m| Home(m))
		Ok(About) => (About, [])
		Err(NotFound) => (NotFound, [])
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
			class_list([("current", is_on(model, route))]),
			on_click(UserClickedLink(route)).prevent_default(),
		],
		[text(label)],
	)

is_on : Model, Route.Route -> Bool
is_on = |model, route|
	match (model, route) {
		(Home(_), Home) | (About, About) => Bool.True
		_ => Bool.False
	}
