import html.Html exposing [a, code, div, em, h1, h2, h3, p, span, table, tbody, td, text, th, thead, tr]
import html.Attribute exposing [class, href]
import /Doc
import /Walk

## The topic "Effects".
Effects := [].{
	body : Doc.Body
	body = [
		p([class("eyebrow")], [text("Start here")]),
		h1([], [text("Effects")]),
		p([class("lead")], [text("Now you know how to render an app and handle state, so let's get to making stuff happen!")]),
		h2([], [text("The simplest effect")]),
		p([], [text("You'll be amazed: we'll be writing to the console!")]),
		Walk.view({
			file: "counter.roc",
			code: [
				Walk.lines(
					"",
					\\Model : { count : I64 }
				),
				Walk.gap,
				Walk.lines(
					"",
					\\Msg : [UserClickedIncrement]
				),
				Walk.gap,
				Walk.lines(
					"",
					\\init : Str -> (Model, List(Effect(Msg)))
					\\init = |_flags| ({ count: 0 }, [])
				),
				Walk.gap,
				Walk.lines(
					"1",
					\\update : Model, Msg -> (Model, List(Effect(Msg)))
					\\update = |model, msg|
					\\    match msg {
					\\        UserClickedIncrement =>
				),
				Walk.lines(
					"2",
					\\            (
					\\                { count: model.count + 1 },
				),
				Walk.lines(
					"2 3 4",
					\\                [Console.log("Someone clicked +")],
				),
				Walk.lines(
					"2",
					\\            )
				),
				Walk.lines(
					"",
					\\    }
				),
				Walk.gap,
				Walk.lines(
					"",
					\\view : Model -> Html(Msg)
					\\view = |model|
					\\    div(
					\\        [],
					\\        [
					\\            text(model.count.to_str()),
				),
				Walk.lines(
					"1",
					\\            button([on_click(UserClickedIncrement)], [text("+")]),
				),
				Walk.lines(
					"",
					\\        ],
					\\    )
				),
			],
			screen: [
				Walk.at("0 2 3", [plus_app("0", "walk-key")]),
				Walk.at("1", [plus_app("0", "walk-key pressed")]),
				Walk.at("4", [plus_app("1", "walk-key")]),
			],
			values: [
				{
					name: "The model",
					states: [Walk.at("0 1", [text("{ count: 0 }")]), Walk.at("2 3 4", [text("{ count: 1 }")])],
				},
				{
					name: "The console",
					states: [Walk.at("0 1 2 3", [text("nothing yet")]), Walk.at("4", [text("Someone clicked +")])],
				},
			],
			steps: [
				{
					title: [text("We render the counter")],
					body: [text("It is the counter you know, with only a + button and one new line. Take a moment to read it.")],
					more: [
						Walk.excerpt(
							Roc,
							\\Model : { count : I64 }
							\\
							\\Msg : [UserClickedIncrement]
							\\
							\\init : Str -> (Model, List(Effect(Msg)))
							\\init = |_flags| ({ count: 0 }, [])
							\\
							\\update : Model, Msg -> (Model, List(Effect(Msg)))
							\\update = |model, msg|
							\\    match msg {
							\\        UserClickedIncrement =>
							\\            (
							\\                { count: model.count + 1 },
							\\                [Console.log("Someone clicked +")],
							\\            )
							\\    }
							\\
							\\view : Model -> Html(Msg)
							\\view = |model|
							\\    div(
							\\        [],
							\\        [
							\\            text(model.count.to_str()),
							\\            button([on_click(UserClickedIncrement)], [text("+")]),
							\\        ],
							\\    )
						),
					],
				},
				{
					title: [text("The user clicks +")],
					body: [
						text("The button sends "),
						code([], [text("UserClickedIncrement")]),
						text(", and Joy calls "),
						code([], [text("update")]),
						text(" with it, as before."),
					],
					more: [
						Walk.excerpt(
							Roc,
							\\button([on_click(UserClickedIncrement)], [text("+")]),
						),
					],
				},
				{
					title: [code([], [text("update")]), text(" returns two things")],
					body: [
						text("They come as a pair in parentheses: first the next model, then a list of effects. So far we've just returned an empty list for the effects: "),
						code([], [text("[]")]),
						text("."),
					],
					more: [
						Walk.excerpt(
							Roc,
							\\(
							\\    { count: model.count + 1 },
							\\    [Console.log("Someone clicked +")],
							\\)
						),
					],
				},
				{
					title: [text("This time the list holds an effect")],
					body: [
						text("Returning "),
						Doc.api("Console.log"),
						text(" in the list means we're asking Joy to write to the console for us."),
					],
					more: [
						Walk.excerpt(
							Roc,
							\\[Console.log("Someone clicked +")],
						),
					],
				},
				{
					title: [text("Joy runs the effect")],
					body: [text("Joy takes the list and does what it says. The text is now in your browser's console, and the page shows the new count.")],
					more: [],
				},
			],
		}),
		h2([], [text("Sending an HTTP request")]),
		p([], [text("Now let's make it more interesting! HTTP requests have "), em([], [text("responses")]), text(", so how do we handle those?")]),
		p(
			[],
			[
				text("First off we ask Joy to make an HTTP request by returning an "),
				Doc.api("Http.get"),
				text(" effect in "),
				code([], [text("update")]),
				text(". The "),
				Doc.api("Http.get"),
				text(" effect takes, as an argument, the message to send when the response comes back."),
			],
		),
		p([], [text("Have a look at this example 👇")]),
		Walk.view({
			file: "quote.roc",
			code: [
				Walk.lines(
					"",
					\\Model : { quote : [NotRequestedYet, Loading, Loaded(Str), Failed(Str)] }
				),
				Walk.gap,
				Walk.lines(
					"",
					\\Msg : [
				),
				Walk.lines(
					"1",
					\\    UserRequestedQuote,
				),
				Walk.lines(
					"5",
					\\    ServerReturnedQuote(
					\\        Try(Http.Response, [HttpErr([Timeout, NetworkError])]),
					\\    ),
				),
				Walk.lines(
					"",
					\\]
				),
				Walk.gap,
				Walk.lines(
					"",
					\\update : Model, Msg -> (Model, List(Effect(Msg)))
					\\update = |_model, msg|
					\\    match msg {
				),
				Walk.lines(
					"1 2",
					\\        UserRequestedQuote =>
				),
				Walk.lines(
					"2",
					\\            (
					\\                { quote: Loading },
				),
				Walk.lines(
					"2 4 5",
					\\                [Http.get(quote_url, |result| ServerReturnedQuote(result))],
				),
				Walk.lines(
					"2",
					\\            )
				),
				Walk.gap,
				Walk.lines(
					"6",
					\\        ServerReturnedQuote(Ok(response)) =>
					\\            ({ quote: Loaded(Str.from_utf8_lossy(response.body)) }, [])
				),
				Walk.gap,
				Walk.lines(
					"6",
					\\        ServerReturnedQuote(Err(_)) =>
					\\            ({ quote: Failed("The request failed") }, [])
				),
				Walk.lines(
					"",
					\\    }
				),
				Walk.gap,
				Walk.lines(
					"4",
					\\quote_url = "https://ron-swanson-quotes.herokuapp.com/v2/quotes"
				),
			],
			screen: [
				Walk.at("1", [quote_app("walk-button pressed", "No quote yet")]),
				Walk.at("0 2", [quote_app("walk-button", "No quote yet")]),
				Walk.at("3 4 5 6", [quote_app("walk-button", "Loading...")]),
				Walk.at("7", [quote_app("walk-button", "[\"A quote from Ron\"]")]),
			],
			values: [
				{
					name: "The model",
					states: [
						Walk.at("0 1", [text("{ quote: NotRequestedYet }")]),
						Walk.at("2 3 4 5", [text("{ quote: Loading }")]),
						Walk.at("6 7", [text("{ quote: Loaded(...) }")]),
					],
				},
				{
					name: "The message",
					states: [
						Walk.at("1 2", [text("UserRequestedQuote")]),
						Walk.at("0 3 4 7", [text("none")]),
						Walk.at("5 6", [text("ServerReturnedQuote(Ok(...))")]),
					],
				},
			],
			steps: [
				{
					title: [text("We render the \"Get a quote\" button")],
					body: [
						text("The app starts as the counter did. Take a moment to read its "),
						code([], [text("Model")]),
						text(", its "),
						code([], [text("Msg")]),
						text(" and its "),
						code([], [text("update")]),
						text(" before anything happens."),
					],
					more: [
						Walk.excerpt(
							Roc,
							\\Model : { quote : [NotRequestedYet, Loading, Loaded(Str), Failed(Str)] }
							\\
							\\Msg : [
							\\    UserRequestedQuote,
							\\    ServerReturnedQuote(
							\\        Try(Http.Response, [HttpErr([Timeout, NetworkError])]),
							\\
							\\update : Model, Msg -> (Model, List(Effect(Msg)))
							\\update = |_model, msg|
							\\    match msg {
							\\        UserRequestedQuote =>
							\\            (
							\\                { quote: Loading },
							\\                [Http.get(quote_url, |result| ServerReturnedQuote(result))],
							\\            )
							\\
							\\        ServerReturnedQuote(Ok(response)) =>
							\\            ({ quote: Loaded(Str.from_utf8_lossy(response.body)) }, [])
							\\
							\\        ServerReturnedQuote(Err(_)) =>
							\\            ({ quote: Failed("The request failed") }, [])
							\\    }
							\\
							\\quote_url = "https://ron-swanson-quotes.herokuapp.com/v2/quotes"
						),
					],
				},
				{
					title: [text("The user asks for a quote")],
					body: [
						text("The button sends "),
						code([], [text("UserRequestedQuote")]),
						text(", and Joy calls "),
						code([], [text("update")]),
						text(" with it. So far this is the counter all over again."),
					],
					more: [
						Walk.excerpt(
							Roc,
							\\UserRequestedQuote =>
						),
					],
				},
				{
					title: [code([], [text("update")]), text(" returns an effect")],
					body: [
						text("Beside the next model, "),
						code([], [text("update")]),
						text(" returns a list with the desired effect: "),
						Doc.api("Http.get"),
						text(" with an address and a function. Nothing is sent yet. We are simply asking Joy to send the GET request."),
					],
					more: [
						Walk.excerpt(
							Roc,
							\\(
							\\    { quote: Loading },
							\\    [Http.get(quote_url, |result| ServerReturnedQuote(result))],
							\\)
						),
					],
				},
				{
					title: [code([], [text("view")]), text(" shows the new model")],
					body: [
						text("The model says "),
						code([], [text("Loading")]),
						text(", so the page says so right away. "),
						code([], [text("update")]),
						text(" did not wait for anything."),
					],
					more: [],
				},
				{
					title: [text("Joy runs the effect")],
					body: [text("Now Joy sends the request, and does not wait for the answer. The app keeps running and can handle other messages while the request is out.")],
					more: [
						Walk.excerpt(
							Roc,
							\\[Http.get(quote_url, |result| ServerReturnedQuote(result))],
							\\quote_url = "https://ron-swanson-quotes.herokuapp.com/v2/quotes"
						),
					],
				},
				{
					title: [text("The answer comes back as a "), code([], [text("Msg")])],
					body: [
						text("When the request is done, Joy calls the function you gave "),
						Doc.api("Http.get"),
						text(" with the result. Yours wraps it in "),
						code([], [text("ServerReturnedQuote")]),
						text(", and that is the next message."),
					],
					more: [
						Walk.excerpt(
							Roc,
							\\ServerReturnedQuote(
							\\    Try(Http.Response, [HttpErr([Timeout, NetworkError])]),
							\\),
						),
					],
				},
				{
					title: [code([], [text("update")]), text(" handles the answer")],
					body: [
						text("The result is "),
						code([], [text("Ok")]),
						text(" with the response, or "),
						code([], [text("Err")]),
						text(" when the request failed. Each has its own row, so a failed request is one more case to handle and not a surprise."),
					],
					more: [
						Walk.excerpt(
							Roc,
							\\ServerReturnedQuote(Ok(response)) =>
							\\    ({ quote: Loaded(Str.from_utf8_lossy(response.body)) }, [])
							\\ServerReturnedQuote(Err(_)) =>
							\\    ({ quote: Failed("The request failed") }, [])
						),
					],
				},
				{
					title: [code([], [text("view")]), text(" shows the quote")],
					body: [
						text("The quote is on the page. Its state was one tag union all along, not a loading flag plus an error string."),
					],
					more: [],
				},
			],
		}),
		h2([], [text("Your turn:")]),
		p(
			[],
			[
				text("Edit the code below and break the address in "),
				code([], [text("quote_url")]),
				text(". Ask for a quote and see which row of "),
				code([], [text("update")]),
				text(" answers."),
			],
		),
		Doc.editor_folded(
			Doc.code(
				Roc,
				"quote.roc",
				\\app [Model, Msg, init, subscriptions, update, view] {
				\\    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
				\\    pf: platform "https://github.com/niclas-ahden/joy/releases/download/VERSION/HASH.tar.zst",
				\\}
				\\
				\\import html.Html exposing [button, div, p, text]
				\\import html.Attribute exposing [on_click]
				\\import pf.Effect
				\\import pf.Http
				\\
				\\Model : { quote : [NotRequestedYet, Loading, Loaded(Str), Failed(Str)] }
				\\
				\\Msg : [
				\\    UserRequestedQuote,
				\\    ServerReturnedQuote(
				\\        Try(Http.Response, [HttpErr([Timeout, NetworkError])]),
				\\    ),
				\\]
				\\
				\\init : Str -> (Model, List(Effect(Msg)))
				\\init = |_flags| ({ quote: NotRequestedYet }, [])
				\\
				\\update : Model, Msg -> (Model, List(Effect(Msg)))
				\\update = |_model, msg|
				\\    match msg {
				\\        UserRequestedQuote =>
				\\            (
				\\                { quote: Loading },
				\\                [Http.get(quote_url, |result| ServerReturnedQuote(result))],
				\\            )
				\\
				\\        ServerReturnedQuote(Ok(response)) =>
				\\            ({ quote: Loaded(Str.from_utf8_lossy(response.body)) }, [])
				\\
				\\        ServerReturnedQuote(Err(_)) =>
				\\            ({ quote: Failed("The request failed") }, [])
				\\    }
				\\
				\\quote_url = "https://ron-swanson-quotes.herokuapp.com/v2/quotes"
				\\
				\\view : Model -> Html(Msg)
				\\view = |model| {
				\\    quote = match model.quote {
				\\        NotRequestedYet => "No quote yet"
				\\        Loading => "Loading..."
				\\        Loaded(words) => words
				\\        Failed(problem) => problem
				\\    }
				\\    div(
				\\        [],
				\\        [
				\\            button([on_click(UserRequestedQuote)], [text("Get a quote")]),
				\\            p([], [text(quote)]),
				\\        ],
				\\    )
				\\}
				\\
				\\subscriptions = |_model| []
			),
		),
		h2([], [text("What else can we do?")]),
		p(
			[],
			[
				text("Joy comes with a number of "),
				a([href(Doc.api_docs)], [text("built-in effects")]),
				text(", but it doesn't stop there! You can define your own "),
				a([href("#custom-effects")], [text("Custom effects")]),
				text(" so that you're never limited by the framework. Nice!"),
			],
		),
		h3([], [text("Built-ins")]),
		div(
			[class("table-wrap")],
			[
				table(
					[],
					[
						thead([], [tr([], [th([], [text("Module")]), th([], [text("For example")])])]),
						tbody(
							[],
							[
								tr(
									[],
									[
										td([], [Doc.api("pf.Http")]),
										td(
											[],
											[
												Doc.api("Http.get(url, to_msg)"),
												text(", "),
												Doc.api("Http.post"),
												text(", "),
												Doc.api("Http.request"),
												text(", file uploads"),
											],
										),
									],
								),
								tr(
									[],
									[
										td([], [Doc.api("pf.Time")]),
										td(
											[],
											[
												Doc.api("Time.after(ms, to_msg)"),
												text(", "),
												Doc.api("Time.debounce(key, ms, to_msg)"),
												text(", "),
												Doc.api("Time.cancel(key)"),
											],
										),
									],
								),
								tr(
									[],
									[
										td([], [Doc.api("pf.DOM")]),
										td(
											[],
											[
												Doc.api("DOM.show_modal(\"#confirm\")"),
												text(", "),
												Doc.api("DOM.close_modal"),
												text(", "),
												Doc.api("DOM.focus"),
												text(", "),
												Doc.api("DOM.set_title"),
												text(", "),
												Doc.api("DOM.scroll_to"),
											],
										),
									],
								),
								tr(
									[],
									[
										td([], [Doc.api("pf.Navigation")]),
										td(
											[],
											[
												Doc.api("Navigation.push_url(url)"),
												text(", "),
												Doc.api("Navigation.replace_url"),
												text(", "),
												Doc.api("Navigation.navigate"),
											],
										),
									],
								),
								tr(
									[],
									[
										td([], [Doc.api("pf.Clipboard")]),
										td([], [Doc.api("Clipboard.write_text(text, to_msg)"), text(", "), Doc.api("Clipboard.write_text_of(selector, to_msg)")]),
									],
								),
								tr(
									[],
									[
										td([], [Doc.api("pf.Console")]),
										td([], [Doc.api("Console.log(text)")]),
									],
								),
								tr(
									[],
									[
										td([], [Doc.api("pf.Port")]),
										td([], [text("Sending values to your own JavaScript and hearing back from it")]),
									],
								),
								tr(
									[],
									[
										td([], [Doc.api("pf.WebCrypto")]),
										td([], [text("Hashing data and files in the browser")]),
									],
								),
								tr(
									[],
									[
										td([], [Doc.api("pf.Media")]),
										td([], [text("Recording from the microphone or camera, playing audio and video")]),
									],
								),
							],
						),
					],
				),
			],
		),
		h3([], [text("Custom effects")]),
		p(
			[],
			[
				text("You can define your own "),
				a([href("#custom-effects")], [text("Custom effects")]),
				text(" by writing Roc and JavaScript. If you're feeling generous you may also share them with others as Roc packages."),
			],
		),
		p([], [text("Since JavaScript doesn't have the same guarantees as Joy, you must remember: with great power comes great responsibility!")]),
	]
}

## The quote app as the page shows it: its button, with the class it has, and
## what it says under it.
quote_app : Str, Str -> Html([])
quote_app = |button, says|
	span([class("walk-stack")], [span([class(button)], [text("Get a quote")]), span([], [text(says)])])

## The one-button counter as the page shows it, with what it counts to and the
## class of its + button.
plus_app : Str, Str -> Html([])
plus_app = |count, plus|
	span([class("walk-counter")], [span([class("walk-number")], [text(count)]), span([class(plus)], [text("+")])])
