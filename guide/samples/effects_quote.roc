app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../platform/main.roc",
}

import html.Html exposing [button, div, p, text]
import html.Attribute exposing [on_click]
import pf.Effect
import pf.Http

Model : { quote : [NotRequestedYet, Loading, Loaded(Str), Failed(Str)] }

Msg : [
	UserRequestedQuote,
	ServerReturnedQuote(
		Try(Http.Response, [HttpErr([Timeout, NetworkError])]),
	),
]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ quote: NotRequestedYet }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |_model, msg|
	match msg {
		UserRequestedQuote =>
			(
				{ quote: Loading },
				[Http.get(quote_url, |result| ServerReturnedQuote(result))],
			)

		ServerReturnedQuote(Ok(response)) =>
			({ quote: Loaded(Str.from_utf8_lossy(response.body)) }, [])

		ServerReturnedQuote(Err(_)) =>
			({ quote: Failed("The request failed") }, [])
	}

quote_url = "https://ron-swanson-quotes.herokuapp.com/v2/quotes"

view : Model -> Html(Msg)
view = |model| {
	quote = match model.quote {
		NotRequestedYet => "No quote yet"
		Loading => "Loading..."
		Loaded(words) => words
		Failed(problem) => problem
	}
	div(
		[],
		[
			button([on_click(UserRequestedQuote)], [text("Get a quote")]),
			p([], [text(quote)]),
		],
	)
}

subscriptions = |_model| []
