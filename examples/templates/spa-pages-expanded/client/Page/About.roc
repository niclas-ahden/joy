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
				p([], [text("This is a Joy app with several pages. Each page has its own state and its own messages, and the notes belong to the app. Have a click around!")]),
				h2([], [text("Things to try")]),
				ul(
					[],
					[
						li([], [text("Add a note on "), a([href(Route.to_path(Notes))], [text("Notes")]), text(", visit another page and come back. Your note is still there! The notes live in the app's model, not in the page.")]),
						li([], [text("Now start typing a note or a search, leave, and come back. What you typed is gone. That was the page's own state, and a page starts fresh every time you open it.")]),
						li([], [text("Search for something. See how the list waits until you stop typing? Press Escape to clear the search.")]),
						li([], [text("Open a note from "), a([href(Route.to_path(Notes))], [text("Notes")]), text(". It has its own URL. Remove it and you're back on the list: the page only changed the URL, and the app did the rest.")]),
						li([], [text("Open "), a([href(Route.to_path(Quote))], [text("Quote")]), text(". It asks someone else's server for a Ron Swanson quote, every time you open it. Want another? Treat yo' self.")]),
					],
				),
				h2([], [text("Where things are")]),
				ul(
					[],
					[
						li([], [code([], [text("client/app.roc")]), text(" is the app: its model, its messages and the menu.")]),
						li([], [code([], [text("client/Page.roc")]), text(" says which pages there are, and how each one fits into the app.")]),
						li([], [code([], [text("client/Page/")]), text(" has a file for each page.")]),
						li([], [code([], [text("client/Notebook.roc")]), text(" is the notes.")]),
						li([], [code([], [text("client/Route.roc")]), text(" has every URL.")]),
					],
				),
				h2([], [text("Your turn")]),
				p([], [text("Add a page! The README has the steps, and the compiler tells you when you've missed one. You can do it!")]),
			],
		)
}
