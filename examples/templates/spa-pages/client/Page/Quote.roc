import html.Html exposing [blockquote, button, div, element, figure, h1, p, text]
import html.Attribute exposing [class, disabled, on_click]
import pf.Http

## Show a quote from the Ron Swanson Quotes API. That's someone else's
## server: this app has no server of its own.
##
## The quote itself is in the app's model (see `Model` in app.roc), so it's
## still there when you come back to this page. This module only has how it
## looks, and how to read the API's response.
Quote := [].{

	## `NotRequestedYet` means we haven't fetched a quote yet, which is the case
	## until you first visit this page.
	Quote : [NotRequestedYet, Loading, Loaded(Str), Failed(Str)]

	url : Str
	url = "https://ron-swanson-quotes.herokuapp.com/v2/quotes"

	view : { quote : Quote.Quote, on_another : msg } -> Html(msg)
	view = |{ quote, on_another }|
		div(
			[],
			[
				h1([], [text("Quote")]),
				match quote {
					NotRequestedYet | Loading => p([], [text("Loading a quote")])
					Loaded(words) => figure([], [blockquote([], [text(words)]), element("figcaption", [], [text("Ron Swanson")])])
					Failed(reason) => p([class("problem")], [text(reason)])
				},
				button([on_click(on_another), disabled(quote == Loading)], [text("Treat yo' self")]),
			],
		)

	## The API responds with a JSON list holding a single quote, e.g.
	## `["There is only one bad word: taxes."]`.
	read : Try(Http.Response, [HttpErr([Timeout, NetworkError])]) -> Quote.Quote
	read = |answer|
		match answer {
			Ok(response) =>
				if response.status == 200 {
					quotes : Try(List(Str), _)
					quotes = Json.parse(Str.from_utf8_lossy(response.body))
					match quotes {
						Ok([words, ..]) => Loaded(words)
						_ => Failed("The server answered something that is not a quote.")
					}
				} else {
					Failed("The server answered ${response.status.to_str()}.")
				}

			Err(_) => Failed("The server could not be reached.")
		}
}
