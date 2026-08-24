app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, pre, button, text]
import html.Attribute exposing [style, on_click]
import pf.Effect exposing [Effect]
import pf.Http
import pf.Console

Model : {
	quote : [NotRequestedYet, Loading, Loaded(Str), Error(Str)],
}

Msg : [
	UserRequestedQuote,
	GotQuote(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
]

# No subscriptions
subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ quote: NotRequestedYet }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |_model, msg|
	match msg {
		UserRequestedQuote => {
			(
				{ quote: Loading },
				[
					Console.log("Requesting a quote..."),
					Http.get(
						"https://ron-swanson-quotes.herokuapp.com/v2/quotes",
						|result| GotQuote(result),
					),
				],
			)
		}

		GotQuote(Ok(resp)) =>
			if resp.status == 200 {
				# The body is a JSON array of lines, like: ["A quote from Ron"]
				match Json.parse(Str.from_utf8_lossy(resp.body)) {
					Ok(lines) =>
						(
							{
								quote: Loaded(Str.join_with(lines, "\n")),
							},
							[],
						)
					Err(e) => ({ quote: Error("Failed to decode the quote JSON: ${Str.inspect(e)}") }, [])
				}
			} else {
				({ quote: Error("Request failed with status ${resp.status.to_str()}") }, [])
			}

		GotQuote(Err(HttpErr(Timeout))) =>
			({ quote: Error("The request timed out") }, [])

		GotQuote(Err(HttpErr(NetworkError))) =>
			({ quote: Error("The request never completed") }, [])
		}

render : Model -> Html(Msg)
render = |model|
	match model.quote {
		NotRequestedYet =>
			div(
				[],
				[
					text("Would you like a Ron Swanson quote?"),
					request_quote_button,
				],
			)

		Loading => div([], [text("Getting a quote...")])

		Loaded(quote) =>
			div(
				[],
				[
					text("Ron once said:"),
					pre([], [text(quote)]),
					request_quote_button,
				],
			)

		Error(error) =>
			div(
				[],
				[
					text("Couldn't get quote, cause: ${error}"),
					request_quote_button,
				],
			)
		}

request_quote_button : Html(Msg)
request_quote_button =
	button(
		[style([("display", "block")]), on_click(UserRequestedQuote)],
		[text("Treat Yo Self")],
	)
