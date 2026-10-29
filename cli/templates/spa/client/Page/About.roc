import html.Html exposing [div, h1, p, text]

## A page without state of its own is a view and nothing else. Its type,
## Html(msg), says it sends no messages.
About := [].{
	view : {} -> Html(msg)
	view = |{}|
		div(
			[],
			[
				h1([], [text("About")]),
				p([], [text("Route.roc has every URL of the app. Add one there, and the compiler shows what else needs it.")]),
			],
		)
}
