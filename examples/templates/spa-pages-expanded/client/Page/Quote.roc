import html.Html exposing [blockquote, button, div, element, figure, h1, p, text]
import html.Attribute exposing [class, disabled, on_click]
import pf.Effect
import pf.Http

## Show a quote from a Ron Swanson Quotes API. The API is external,
## meaning that it's not part of this app. It's hosted by someone
## else on an unrelated server. There'll be other examples that show
## how to run your own Joy server and host your own APIs.
##
## Now, to the page:
##
## `quote` holds the quote, or how far we've come in fetching it.
##
## It belongs to the page itself, so it's cleared whenever you navigate
## away, and fetched again the next time you visit.
Quote := { quote : [Loading, Loaded(Str), Failed(Str)] }.{
	Msg : [
		ServerReturnedQuote(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
		UserClickedAnother,
	]

	init : (Quote, List(Effect(Msg)))
	init = ask

	update : Quote, Msg -> (Quote, List(Effect(Msg)))
	update = |model, msg|
		match msg {
			# Take an answer only while we're waiting for one. If you leave this
			# page and come back before the server has answered, two answers
			# are on their way, and we only want one of them.
			ServerReturnedQuote(answer) =>
				if model.quote == Loading {
					(Quote.{ quote: read(answer) }, [])
				} else {
					(model, [])
				}

			# One quote at a time: a click while we're waiting does nothing.
			UserClickedAnother =>
				if model.quote == Loading {
					(model, [])
				} else {
					ask
				}
		}

	view : Quote -> Html(Msg)
	view = |model|
		div(
			[],
			[
				h1([], [text("Quote")]),
				match model.quote {
					Loading => p([], [text("Loading a quote")])
					Loaded(words) => figure([], [blockquote([], [text(words)]), element("figcaption", [], [text("Ron Swanson")])])
					Failed(reason) => p([class("problem")], [text(reason)])
				},
				button([on_click(UserClickedAnother), disabled(model.quote == Loading)], [text("Treat yo' self")]),
			],
		)
}

ask : (Quote, List(Effect(Quote.Msg)))
ask = (
	Quote.{ quote: Loading },
	[Http.get("https://ron-swanson-quotes.herokuapp.com/v2/quotes", |answer| ServerReturnedQuote(answer))],
)

## The API responds with a JSON list holding a single quote, e.g.
## `["Never half-ass two things."]`.
read : Try(Http.Response, [HttpErr([Timeout, NetworkError])]) -> [Loading, Loaded(Str), Failed(Str)]
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
