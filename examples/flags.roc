app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, p, pre, text]
import pf.Effect exposing [Effect]
import pf.Console

# Flags are how you pass in initial state to your application.
# Pass them to `mount` when you're initializing your app and whatever string
# you provide there will be passed in to `init` as its only argument.
#
# Here we'll pass in some JSON and initialize our model based on that:

Model : [
	Human({ name : Str, karma : I32 }),
	FailedToParseFlags(Str),
]

Msg : []

# No recurring event sources
subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |flags| {
	# `Json.parse` is really smart. It'll figure out the shape of the JSON you're expecting based on
	# how you're using the result of the parse. Here we're constructing a `Human({ name, karma })`
	# with the parsed result, so Roc figures out that `name` is a `Str` and `karma` is a `I32`.
	#
	# If the shape of the JSON doesn't match that, then you'll get a descriptive error. Try it out
	# yourself by messing up the field names in the flags!
	match Json.parse(flags) {
		Ok({ name, karma }) => (Human({ name, karma }), [])
		Err(e) => (
			FailedToParseFlags(flags),
			[Console.log("Failed to decode flags into model.\nFlags: ${flags}\n\nCause: ${Str.inspect(e)}")],
		)
	}
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, _msg| (model, [])

render : Model -> Html(Msg)
render = |model|
	match model {
		Human({ name, karma }) => judgement_view(name, karma)
		FailedToParseFlags(flags) => error_view(flags)
	}

judgement_view : Str, I32 -> Html(Msg)
judgement_view = |name, karma| {
	judgement =
		if karma > 0 {
			"You're alright!"
		} else {
			"Karma isn't real, anyway! Right?"
		}

	div(
		[],
		[
			p([], [text(judgement)]),
			p([], [text("Name: ${name}")]),
			p([], [text("Karma: ${karma.to_str()}")]),
		],
	)
}

error_view : Str -> Html(Msg)
error_view = |flags|
	match flags {
		"" =>
			div(
				[],
				[
					p([], [text("Let's set some flags! Open `www/index.html` and put some JSON in the `flags` option, like this:")]),
					pre(
						[],
						[
							text(
								\\window.app = await mount({
								\\    wasm: './app.wasm',
								\\    root: document.getElementById('app'),
								\\    flags: `{"name": "Brödil", "karma": 99}`,
								\\});
								,
							),
						],
					),
				],
			)

		_ =>
			div(
				[],
				[
					p([], [text("Oh, no, we couldn't parse the given flags! Make sure the flags are a valid JSON string (not an object). Here's an example that will parse correctly:")]),
					pre([], [text("flags: `{\"name\": \"Brödil\", \"karma\": 99}`")]),
					p([], [text("The flags we received were:")]),
					pre([], [text(flags)]),
				],
			)
		}
