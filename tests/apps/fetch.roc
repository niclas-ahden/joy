app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, p, button, text]
import html.Attribute exposing [id, on_click]
import pf.Effect exposing [Effect]
import pf.Http

# The Http.get shape of examples/http.roc (request, status check, JSON decode
# of the body, error branch), aimed at this repo's dev server instead of the
# public API the example calls. That makes the round trip drivable by
# tests/e2e/http_test.roc in CI: a real fetch, a real response, no network.
#
# `/quote` (served by www/serve.mjs) answers a JSON array of lines, exactly
# like the API the example uses. `/missing/quote` is served by nothing and
# drives the non-200 branch. It has two segments on purpose: the dev server
# redirects a bare `/name` to `/name/` and serves the page there, and fetch
# follows redirects, so a one-segment path would arrive as a 200 page rather
# than the 404 this asks for.

Model : {
	quote : [NotRequestedYet, Loading, Loaded(Str), Error(Str)],
}

Msg : [
	UserRequestedQuote,
	UserRequestedMissing,
	GotQuote(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ quote: NotRequestedYet }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |_model, msg|
	match msg {
		UserRequestedQuote =>
			({ quote: Loading }, [Http.get("/quote", |result| GotQuote(result))])

		UserRequestedMissing =>
			({ quote: Loading }, [Http.get("/missing/quote", |result| GotQuote(result))])

		GotQuote(Ok(resp)) =>
			if resp.status == 200 {
				# The body is a JSON array of lines, like: ["A quote"]
				match Json.parse(Str.from_utf8_lossy(resp.body)) {
					Ok(lines) => ({ quote: Loaded(lines |> Str.join_with("\n")) }, [])
					Err(e) => ({ quote: Error("Failed to decode: ${Str.inspect(e)}") }, [])
				}
			} else {
				({ quote: Error("Request failed with status ${resp.status.to_str()}") }, [])
			}

		GotQuote(Err(HttpErr(Timeout))) => ({ quote: Error("The request timed out") }, [])
		GotQuote(Err(HttpErr(NetworkError))) => ({ quote: Error("The request never completed") }, [])
	}

render : Model -> Html(Msg)
render = |model| {
	state = match model.quote {
		NotRequestedYet => "nothing yet"
		Loading => "loading"
		Loaded(quote) => "loaded: ${quote}"
		Error(error) => "error: ${error}"
	}

	div(
		[],
		[
			button([id("load"), on_click(UserRequestedQuote)], [text("Load")]),
			button([id("load-missing"), on_click(UserRequestedMissing)], [text("Load a 404")]),
			p([id("state")], [text(state)]),
		],
	)
}
