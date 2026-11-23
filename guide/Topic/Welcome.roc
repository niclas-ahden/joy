import html.Html exposing [a, div, h1, h2, p, text]
import html.Attribute exposing [class, href, style]
import /Doc

## The topic "What is Joy?".
Welcome := [].{
	body : Doc.Body
	body = [
		p([class("eyebrow")], [text("Start here")]),
		h1([], [text("What is Joy?")]),
		p(
			[class("lead")],
			[
				text("Joy is a framework for building full-stack web apps in Roc. You get a fast, productive, and type-safe development experience across your whole stack. Hope you'll enjoy it!"),
			],
		),
		div(
			[class("features")],
			[
				feature(
					"Type-safety all the way with Roc",
					[text("Server and browser share the same types and views. An API mismatch gives you a helpful compilation error, not an error in production.")],
				),
				feature(
					"Productivity & Joy",
					[text("Quick iteration loop, hot-reloading of client and server code, great error messages, and compilation output right in the browser.")],
				),
				feature(
					"No unexpected errors",
					[text("No null, no undefined, no exceptions. Failures are values which the compiler helps you handle.")],
				),
				feature(
					"Fast",
					[
						text("Runs as WebAssembly in the browser with optimized DOM manipulations. The server is a native Roc binary. "),
						a([href("https://roc-lang.org/fast")], [text("Roc is fast")]),
						text("."),
					],
				),
			],
		),
		h2([style([("text-align", "center"), ("margin", "3.5rem 0 -0.75rem")])], [text("What does it look like?")]),
		Doc.editor_folded(
			Doc.code(
				Roc,
				"counter.roc",
				\\app [Model, Msg, init, subscriptions, update, view] {
				\\    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
				\\    pf: platform "https://github.com/niclas-ahden/joy/releases/download/VERSION/HASH.tar.zst",
				\\}
				\\
				\\import html.Html exposing [button, div, h1, p, text]
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
				\\            h1([], [text("Hello! Change me")]),
				\\            button([on_click(UserClickedDecrement)], [text("-")]),
				\\            text(model.count.to_str()),
				\\            button([on_click(UserClickedIncrement)], [text("+")]),
				\\            p([], [text("👈 Edit the code on the left, I dare ya")]),
				\\        ],
				\\    )
				\\
				\\subscriptions = |_model| []
			),
		),
		p(
			[],
			[
				text("You may recognize this as "),
				a([href("https://guide.elm-lang.org/architecture/")], [text("The Elm Architecture")]),
				text(", which is how Joy's front-end works. For the back-end you can use any architecture you'd like, and the next release of Joy, 0.36.0, will bring examples to help you get going."),
			],
		),
		h2([], [text("What kind of apps can I build with Joy?")]),
		p(
			[],
			[
				text("Joy is suitable for most web apps, from basic websites to highly interactive and rich UIs. It supports "),
				a([href("https://developer.mozilla.org/en-US/docs/Glossary/SSR")], [text("server-side rendering")]),
				text(", "),
				a([href("https://en.wikipedia.org/wiki/Hydration_(web_development)")], [text("hydration")]),
				text(", and "),
				a([href("https://developer.mozilla.org/en-US/docs/Glossary/CSR")], [text("client-side rendering")]),
				text(" which you can combine into full-stack apps, "),
				a([href("https://developer.mozilla.org/en-US/docs/Glossary/SPA")], [text("Single-Page Applications (SPA)")]),
				text(", Multi-Page Applications (MPA), "),
				a([href("https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps")], [text("Progressive Web App (PWA)")]),
				text(" etc."),
			],
		),
	]
}

## A box in the grid under the lead: what Joy gives you, in a line or two.
feature : Str, List(Html([])) -> Html([])
feature = |name, body| div([class("feature")], [p([class("feature-name")], [text(name)]), p([], body)])
