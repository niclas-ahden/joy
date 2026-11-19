import /Route
import html.Html exposing [a, code, div, h1, h2, li, p, text, ul]
import html.Attribute exposing [href]

## A page with only text and links, so it needs no state or messages of its
## own. That's why `view` returns `Html(msg)` with a lowercase `msg`: it fits
## into any app.
##
## The links are ordinary `<a>` tags. Joy tells the app when one is clicked
## (see `on_link_click` in app.roc), so the page doesn't reload.
About := [].{
	view : {} -> Html(msg)
	view = |{}|
		div(
			[],
			[
				h1([], [text("About")]),
				p([], [text("This is a small Joy app with a few pages, and each page has its own URL. Have a click around!")]),
				h2([], [text("Things to try")]),
				ul(
					[],
					[
						li([], [text("Go to "), a([href(Route.to_path(Home))], [text("Home")]), text(" and click + a few times. Now visit another page and come back. The count is still there! The app has one model, and it stays for as long as the page is open.")]),
						li([], [text("Open "), a([href(Route.to_path(Quote))], [text("Quote")]), text(". It asks someone else's server for a Ron Swanson quote, the first time you open it. Want another? Treat yo' self.")]),
						li([], [text("Use Back and Forward in your browser. Every page has a URL, so they just work. So does a refresh, and so does sending someone a link.")]),
						li([], [text("Edit some text in a page and save. The page takes the change as you save, no refresh needed :)")]),
					],
				),
				h2([], [text("Where things are")]),
				ul(
					[],
					[
						li([], [code([], [text("client/app.roc")]), text(" is the app: its model, its messages and the menu.")]),
						li([], [code([], [text("client/Route.roc")]), text(" has every URL.")]),
						li([], [code([], [text("client/Page/")]), text(" has a file for each page. A page is a view: the app hands it what to show.")]),
					],
				),
				h2([], [text("Your turn")]),
				p([], [text("Add a page! Give it a name in "), code([], [text("Route.roc")]), text(" and see what the compiler says. It'll walk you through most of it. You can do it!")]),
			],
		)
}
