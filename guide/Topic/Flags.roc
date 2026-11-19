import html.Html exposing [a, code, em, h1, h2, p, text]
import html.Attribute exposing [class, href]
import /Doc
import "../samples/flags.roc" as flags_app : Str
import "../pages/flags.html" as flags_page : Str

## The topic "Flags".
Flags := [].{
	body : Doc.Body
	body = [
		p([class("eyebrow")], [text("Start here")]),
		h1([], [text("Flags")]),
		p(
			[class("lead")],
			[
				text("Flags are the data an app starts from. The page writes them on the bundle's root element, and "),
				code([], [text("init")]),
				text(" receives them as a string."),
			],
		),
		Doc.code(
			Html,
			"public/index.html",
			\\<div
			\\    data-joy-bundle="app"
			\\    data-joy-flags='{"name": "Brödil", "karma": 99}'
			\\></div>
			\\<script type="module" src="./joy.js"></script>
		),
		p(
			[],
			[
				text("You've seen these two lines before, in "),
				a([href("#first-app")], [text("Your first app")]),
				text(": the element says where your app goes, and "),
				code([], [text("joy.js")]),
				text(" starts it. The new part is "),
				code([], [text("data-joy-flags")]),
				text(". When "),
				code([], [text("joy.js")]),
				text(" starts your app, it reads that attribute and hands its text to "),
				code([], [text("init")]),
				text(", just as you wrote it. Leave the attribute out and "),
				code([], [text("init")]),
				text(" gets an empty string."),
			],
		),
		h2([], [text("JSON, maybe?")]),
		p(
			[],
			[
				text("Your flags can be in any format, and you can parse them however you want. If you make them JSON you can easily "),
				code([], [text("Json.parse")]),
				text(" them in your "),
				code([], [text("init")]),
				text(" to construct your model:"),
			],
		),
		Doc.code(
			Html,
			"public/index.html",
			\\<div
			\\    data-joy-bundle="app"
			\\    data-joy-flags='{"name": "Brödil", "karma": 99}'
			\\></div>
		),
		Doc.code(
			Roc,
			"",
			\\Model : [
			\\    Human({ name : Str, karma : I32 }),
			\\    FailedToParseFlags(Str),
			\\]
			\\
			\\init : Str -> (Model, List(Effect(Msg)))
			\\init = |flags|
			\\    match Json.parse(flags) {
			\\        Ok({ name, karma }) => (Human({ name, karma }), [])
			\\        Err(problem) => (
			\\            FailedToParseFlags(flags),
			\\            [Console.log("Could not read the flags: \${Str.inspect(problem)}")],
			\\        )
			\\    }
		),
		p(
			[],
			[
				text("Here's the whole app. Open "),
				code([], [text("index.html")]),
				text(" and change the flags: the page starts over, and your app with it 👇"),
			],
		),
		Doc.with_page("flags.roc", flags_app.replace_first("pf: platform \"../../platform/main.roc\"", Doc.platform_line), flags_page),
		h2([], [text("Partial model from your flags")]),
		p(
			[],
			[
				text("You could make the flags represent "),
				em([], [text("the whole model")]),
				text(" or just a part of it:"),
			],
		),
		Doc.code(
			Roc,
			"",
			\\Model : {
			\\    # Comes from the flags.
			\\    human : [
			\\        Human({ name : Str, karma : I32 }),
			\\        FailedToParseFlags(Str),
			\\    ],
			\\    # Only the client keeps track of this.
			\\    retries : U8,
			\\}
			\\
			\\init : Str -> (Model, List(Effect(Msg)))
			\\init = |flags|
			\\    match Json.parse(flags) {
			\\        Ok({ name, karma }) => (
			\\            { human: Human({ name, karma }), retries: 0 },
			\\            [],
			\\        )
			\\        Err(problem) => (
			\\            { human: FailedToParseFlags(flags), retries: 0 },
			\\            [Console.log("Could not read the flags: \${Str.inspect(problem)}")],
			\\        )
			\\    }
		),
		h2([], [text("Crashing out")]),
		p(
			[],
			[
				text("In the examples above we gracefully handle our flag parsing errors. That way we can show a user-friendly error message in "),
				em([], [text("the rare case")]),
				text(" that our flags are not what we expect."),
			],
		),
		p(
			[],
			[
				text("Perhaps that's "),
				em([], [text("so rare")]),
				text(" in practice that you'd rather just "),
				code([], [text("crash")]),
				text(" if that's the case? Here's how:"),
			],
		),
		Doc.code(
			Roc,
			"",
			\\Model : { name : Str, karma : I32 }
			\\
			\\init : Str -> (Model, List(Effect(Msg)))
			\\init = |flags|
			\\    match Json.parse(flags) {
			\\        Ok(model) => (model, [])
			\\        Err(problem) => crash "Could not read the flags: \${Str.inspect(problem)}"
			\\    }
		),
		h2([], [text("Getting close to full-stack")]),
		p(
			[],
			[
				text("You're probably already ahead of me, but: imagine rendering your app on the server with some state, then turning that into JSON and using it as your "),
				code([], [text("flags")]),
				text(". That'd mean your front-end starts with "),
				em([], [text("the same state")]),
				text(" as your back-end used to render. Perfect! We'll get into that in the next release of Joy, but first "),
				a([href("#install")], [text("let's get Joy onto your machine!")]),
			],
		),
	]
}
