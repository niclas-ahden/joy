app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, h1, p, small, button, text]
import html.Attribute exposing [id, on_click, style]
import pf.Effect exposing [Effect]
import pf.Sub exposing [Sub]
import pf.Time

# Let's calculate your level of excitement for Roc:
# We'll set up a `subscriptions` on `Time.every(1000)` so that we get a `Tick`
# every second.

Model : {
	level : I64,
	now : I64,
	remembered : List({ level : I64, at : I64 }),
	paused : Bool,
}

Msg : [
	Tick(I64),
	UserRememberedMoment,
	UserToggledPause,
]

init : Str -> (Model, List(Effect(Msg)))
init = |flags| {
	# `init` is pure, so the clock at boot comes in through the flags: the
	# embedder passes `Date.now()` as the flags string and the app parses it.
	# This isn't strictly necessary, but we're doing it just to show how.
	#
	# Without flags the clock stays 0 until the first tick fills it in, so the
	# example still works when opened without them.
	({ level: 0, now: Json.parse(flags) ?? 0, remembered: [], paused: Bool.False }, [])
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		# For every tick, we boost your level by one and set the new time:
		Tick(t) => ({ ..model, level: model.level + 1, now: t }, [])

		# When you're feel sentimental, we store the time and level:
		UserRememberedMoment =>
			(
				{
					..model,
					remembered: model.remembered.append({ level: model.level, at: model.now }),
				},
				[],
			)

		# Pause the timer
		UserToggledPause => ({ ..model, paused: !model.paused }, [])
	}

subscriptions : Model -> List(Sub(Msg))
subscriptions = |model|
	if model.paused {
		# No tick when paused
		[]
	} else {
		# Dispatch a `Tick(I64)` carrying the current time every second
		[Time.every(1000, |t| Tick(t))]
	}

render : Model -> Html(Msg)
render = |model| {
	pause_label =
		if model.paused {
			"Get excited!"
		} else {
			"Calm down"
		}

	div(
		[],
		[
			h1([id("level")], [text("Your excitement level for Roc: ${model.level.to_str()}")]),
			p([], [text("(you don't ever have to close this page if you don't want to)")]),
			button([id("remember"), on_click(UserRememberedMoment)], [text("Remember this moment")]),
			button([id("pause"), on_click(UserToggledPause)], [text(pause_label)]),
			div(
				[id("moments")],
				model.remembered.map(
					|moment| p(
						[],
						[text("Level ${moment.level.to_str()}, reached at ${moment.at.to_str()}")],
					),
				),
			),
		],
	)
}
