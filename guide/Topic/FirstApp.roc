import html.Html exposing [a, code, em, h1, h2, li, p, span, text, ul]
import html.Attribute exposing [class, href]
import /Doc
import /Walk

## The topic "Your first app".
FirstApp := [].{
	body : Doc.Body
	body = [
		p([class("eyebrow")], [text("Start here")]),
		h1([], [text("Your first app")]),
		p(
			[class("lead")],
			[
				text("Joy is a full-stack framework, but let's start with a simple front-end app. It's a single Roc file that provides six things: "),
				code([], [text("Model")]),
				text(", "),
				code([], [text("Msg")]),
				text(", "),
				code([], [text("init")]),
				text(", "),
				code([], [text("update")]),
				text(", "),
				code([], [text("view")]),
				text(" and "),
				code([], [text("subscriptions")]),
				text("."),
			],
		),
		p(
			[],
			[
				text("The guide for adding a server comes with the next release of Joy. It shares the same "),
				code([], [text("view")]),
				text("."),
			],
		),
		h2([], [text("How it works")]),
		p([], [text("Here's how it all works, step-by-step. Scroll down or click "), em([], [text("Next")]), text(" to follow along...")]),
		Walk.view({
			file: "counter.roc",
			code: [
				Walk.lines(
					"",
					\\Model : { count : I64 }
				),
				Walk.gap,
				Walk.lines(
					"3",
					\\Msg : [UserClickedIncrement, UserClickedDecrement]
				),
				Walk.gap,
				Walk.lines(
					"1",
					\\init : Str -> (Model, List(Effect(Msg)))
					\\init = |_flags| ({ count: 0 }, [])
				),
				Walk.gap,
				Walk.lines(
					"4",
					\\update : Model, Msg -> (Model, List(Effect(Msg)))
					\\update = |model, msg|
					\\    match msg {
				),
				Walk.lines(
					"5",
					\\        UserClickedIncrement => ({ count: model.count + 1 }, [])
				),
				Walk.lines(
					"",
					\\        UserClickedDecrement => ({ count: model.count - 1 }, [])
					\\    }
				),
				Walk.gap,
				Walk.lines(
					"2 6",
					\\view : Model -> Html(Msg)
					\\view = |model|
					\\    div(
					\\        [],
					\\        [
					\\            button([on_click(UserClickedDecrement)], [text("-")]),
					\\            text(model.count.to_str()),
				),
				Walk.lines(
					"2 3 6",
					\\            button([on_click(UserClickedIncrement)], [text("+")]),
				),
				Walk.lines(
					"2 6",
					\\        ],
					\\    )
				),
				Walk.gap,
				Walk.lines(
					"",
					\\subscriptions = |_model| []
				),
			],
			screen: [
				Walk.at("0 1", [text("Nothing on the page yet")]),
				Walk.at("2 4 5", [counter("0", "walk-key")]),
				Walk.at("3", [counter("0", "walk-key pressed")]),
				Walk.at("6", [counter("1", "walk-key")]),
			],
			values: [
				{
					name: "The model",
					states: [Walk.at("0", [text("none yet")]), Walk.at("1 2 3 4", [text("{ count: 0 }")]), Walk.at("5 6", [text("{ count: 1 }")])],
				},
				{
					name: "The message",
					states: [Walk.at("0 1 2 6", [text("none")]), Walk.at("3 4 5", [text("UserClickedIncrement")])],
				},
			],
			steps: [
				{
					title: [text("Put Joy into your HTML")],
					body: [
						text("Specify which element you want Joy to run in and add our "),
						code([], [text("joy.js")]),
						text(" script, which loads your wasm bundle and starts your app."),
					],
					more: [
						Walk.excerpt(
							Html,
							\\<div data-joy-bundle="counter"></div>
							\\<script type="module" src="/joy.js"></script>
						),
					],
				},
				{
					title: [code([], [text("init")]), text(" is called")],
					body: [
						text("Joy finds your element and starts your app. "),
						code([], [text("init")]),
						text(" builds the first state of your app, the "),
						code([], [text("Model")]),
						text(". Here it's "),
						code([], [text("{ count: 0 }")]),
						text(". There is still nothing on the page."),
					],
					more: [
						Walk.excerpt(
							Roc,
							\\init : Str -> (Model, List(Effect(Msg)))
							\\init = |_flags| ({ count: 0 }, [])
						),
					],
				},
				{
					title: [text("Then "), code([], [text("view")]), text(" is called to render your app")],
					body: [text("It gets the model and returns HTML. Joy puts that on the page, and the app waits.")],
					more: [
						Walk.excerpt(
							Roc,
							\\view : Model -> Html(Msg)
							\\view = |model|
							\\    div(
							\\        [],
							\\        [
							\\            button([on_click(UserClickedDecrement)], [text("-")]),
							\\            text(model.count.to_str()),
							\\            button([on_click(UserClickedIncrement)], [text("+")]),
							\\        ],
							\\    )
						),
					],
				},
				{
					title: [text("The user clicks +, and a "), code([], [text("Msg")]), text(" is sent")],
					body: [
						text("The button was made with "),
						code([], [text("on_click(UserClickedIncrement)")]),
						text(", so that is the message Joy gets. A message is a plain Roc value that says what happened."),
					],
					more: [
						Walk.excerpt(
							Roc,
							\\button([on_click(UserClickedIncrement)], [text("+")]),
						),
					],
				},
				{
					title: [text("Joy calls "), code([], [text("update")]), text(" with "), code([], [text("Model")]), text(" and "), code([], [text("Msg")])],
					body: [
						text("Your "),
						code([], [text("update")]),
						text(" gets "),
						code([], [text("{ count: 0 }")]),
						text(" and "),
						code([], [text("UserClickedIncrement")]),
						text(" in this case."),
					],
					more: [
						Walk.excerpt(
							Roc,
							\\update : Model, Msg -> (Model, List(Effect(Msg)))
							\\update = |model, msg|
							\\    match msg {
						),
					],
				},
				{
					title: [code([], [text("update")]), text(" returns the next "), code([], [text("Model")])],
					body: [
						text("The "),
						code([], [text("match")]),
						text(" finds the row for this message, and increments the count to 1. "),
						code([], [text("update")]),
						text(" then returns the new state and any effects you want Joy to run (none in this case)."),
					],
					more: [
						Walk.excerpt(
							Roc,
							\\UserClickedIncrement => ({ count: model.count + 1 }, [])
						),
					],
				},
				{
					title: [code([], [text("view")]), text(" is called again")],
					body: [
						text("Joy changes the page to match the new model. From here it repeats for every click: a message, "),
						code([], [text("update")]),
						text(", "),
						code([], [text("view")]),
						text("."),
					],
					more: [],
				},
			],
		}),
		h2([], [text("That's all folks!")]),
		p([], [text("It's just six things:")]),
		ul(
			[],
			[
				li([], [code([], [text("Model")]), text(": The whole state of the application. Here it's a single count.")]),
				li([], [code([], [text("Msg")]), text(": Everything that can happen, as a tag union. Here two buttons.")]),
				li([], [code([], [text("init")]), text(": How we start the app and produce the initial state ("), code([], [text("Model")]), text(").")]),
				li([], [code([], [text("update")]), text(": The next model after a message, and the effects to run.")]),
				li([], [code([], [text("view")]), text(": How the HTML for your app is rendered. It is called after every update.")]),
				li([], [code([], [text("subscriptions")]), text(": Events you want your app to react to, like timers. We didn't need any.")]),
			],
		),
		h2([], [text("Your turn:")]),
		p([], [text("Edit the code below, and add a Reset button that sets the count to 0. You can do it!")]),
		p(
			[],
			[
				text("You'll have to add a third message, a button with its own "),
				code([], [text("on_click")]),
				text(", and another line in the "),
				code([], [text("update")]),
				text(" which sets the "),
				code([], [text("count")]),
				text(" to "),
				code([], [text("0")]),
				text(". Try adding the new message and see what the compiler says."),
			],
		),
		Doc.playground(
			Doc.code(
				Roc,
				"counter.roc",
				\\app [Model, Msg, init, update, view, subscriptions] {
				\\    pf: platform "https://github.com/niclas-ahden/joy/releases/download/VERSION/HASH.tar.zst",
				\\    html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
				\\}
				\\
				\\import html.Html exposing [div, button, text]
				\\import html.Attribute exposing [on_click]
				\\import pf.Effect
				\\
				\\Model : { count : I64 }
				\\
				\\Msg : [UserClickedIncrement, UserClickedDecrement]
				\\
				\\init : Str -> (Model, List(Effect(Msg)))
				\\init = |_flags| ({ count: 0 }, [])
				\\
				\\update : Model, Msg -> (Model, List(Effect(Msg)))
				\\update = |model, msg|
				\\    match msg {
				\\        UserClickedIncrement => ({ count: model.count + 1 }, [])
				\\        UserClickedDecrement => ({ count: model.count - 1 }, [])
				\\    }
				\\
				\\view : Model -> Html(Msg)
				\\view = |model|
				\\    div(
				\\        [],
				\\        [
				\\            button([on_click(UserClickedDecrement)], [text("-")]),
				\\            text(model.count.to_str()),
				\\            button([on_click(UserClickedIncrement)], [text("+")]),
				\\        ],
				\\    )
				\\
				\\subscriptions = |_model| []
			),
		),
		h2([], [text("The header")]),
		p(
			[],
			[
				text("Perhaps you're curious about the first few lines of the app? That's the \"app header\" and says what platform and packages you want to use. When you "),
				a([href("#install")], [text("start a new Joy app")]),
				text(" it'll be added for you automatically, and you can add more packages as you need them."),
			],
		),
	]
}

## The counter as the page shows it, with what it counts to and the class of
## its + button.
counter : Str, Str -> Html([])
counter = |count, plus|
	span(
		[class("walk-counter")],
		[span([class("walk-key")], [text("-")]), span([class("walk-number")], [text(count)]), span([class(plus)], [text("+")])],
	)
