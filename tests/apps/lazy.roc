app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, span, button, article, h2, p, a, text, element]
import html.Attribute exposing [class, href, attribute, on_click]
import pf.Effect exposing [Effect]
import pf.Sub exposing [Sub]
import pf.Time

# WHY Html.lazy exists
#
# Joy re-runs `render` on every message and diffs the whole tree. That is
# usually plenty fast, but when one region is big (here: a card grid you can
# grow to tens of thousands of nodes) and something small changes often
# (here: a spinner ticking every 16 ms), every tick rebuilds and rediffs the
# entire grid just to move the spinner.
#
# This page makes that cost visible. A timer ticks 60 times a second and the
# header shows the average gap between ticks. Start with lazy OFF, double
# the rows until the gap climbs past 16 ms and the spinner stutters, then
# flip lazy ON: the gap drops back toward 16 ms, because the grid is no
# longer rebuilt at all.
#
# Lazy only removes the app's work (rebuild and rediff). The browser still
# pays per-frame costs that grow with total DOM size (layout, paint, hit
# testing), so past roughly 8000 cards the gap climbs above 16 ms even with
# lazy ON while the app's own work stays around a millisecond. Run
# `await import('/perf.js')` in the devtools console for a live meter that
# splits each frame into app time and browser render time and makes exactly
# that visible. Lists that big want
# windowing (see the infinite_scroll example) rather than lazy alone.
#
# HOW to use it
#
# Hand the expensive region's view function to `Html.lazy` together with the
# model slices it reads. The runtime runs the view only when those inputs
# changed since the previous render, otherwise the retained subtree is reused
# untouched (handlers inside keep working). The rules:
#
#   1. Pass the slices as arguments, not the model:
#          Html.lazy(grid, model.rows)
#      The arguments are what gets compared, so passing `model` compares the
#      whole model and any unrelated field changing forces the region.
#      `lazy2` through `lazy8` take more inputs, and past eight, pass a
#      record to `lazy`.
#   2. The view must be a named function. A lambda written at the call site
#      is a new value on every render and never compares equal. So is any
#      argument built during the render (a mapped list, an interpolated
#      string): safe, but never skips.
#   3. Produce the surrounding Msg type inside the region. Wrapping a lazy
#      region in `Html.map` rebuilds the thunk every render and defeats it.
#
# Run it from the repo root with `./watch.roc examples/lazy.roc` and open
# http://localhost:8000 (run `await import('/perf.js')` in the devtools
# console for the frame-time meter)

Model : {
	ticks : I64,
	last_tick_ms : I64,
	# Average gap between ticks in tenths of a millisecond (an integer
	# exponential moving average; 160 = the ideal 16.0 ms).
	avg_gap_tenths : I64,
	rows : I64,
	use_lazy : Bool,
}

Msg : [Tick(I64), MoreRows, FewerRows, ToggleLazy, CardClicked]

subscriptions : Model -> List(Sub(Msg))
subscriptions = |_model| [Time.every(16, |t| Tick(t))]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ ticks: 0, last_tick_ms: 0, avg_gap_tenths: 0, rows: 4000, use_lazy: Bool.False }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Tick(t) => {
			gap_tenths = (t - model.last_tick_ms) * 10
			avg =
				if model.last_tick_ms == 0 {
					0
				} else if model.avg_gap_tenths == 0 {
					gap_tenths
				} else {
					(model.avg_gap_tenths * 9 + gap_tenths + 5) // 10
				}
			({ ..model, ticks: model.ticks + 1, last_tick_ms: t, avg_gap_tenths: avg }, [])
		}
		MoreRows => (
			{
				..model,
				rows: if model.rows < 64000 {
					model.rows * 2
				} else {
					model.rows
				},
			},
			[],
		)
		FewerRows => (
			{
				..model,
				rows: if model.rows > 1000 {
					model.rows // 2
				} else {
					model.rows
				},
			},
			[],
		)
		ToggleLazy => ({ ..model, use_lazy: !model.use_lazy }, [])
		# Proves handlers inside a skipped region keep dispatching: the
		# click advances the spinner just like a tick.
		CardClicked => ({ ..model, ticks: model.ticks + 1 }, [])
	}

card : I64 -> Html(Msg)
card = |i|
	article(
		[class("card")],
		[
			element(
				"img",
				[
					class("card__image"),
					attribute("src", "/images/${i.to_str()}/hero-800w.avif"),
					attribute("srcset", "/images/${i.to_str()}/hero-400w.avif 400w, /images/${i.to_str()}/hero-800w.avif 800w"),
					attribute("alt", "Länsmansvägen ${i.to_str()}"),
				],
				[],
			),
			h2([class("card__title")], [text("Länsmansvägen ${i.to_str()}")]),
			p([class("card__price")], [text("${(i * 950).to_str()} 000 kr")]),
			a([class("card__link"), href("/bostad/${i.to_str()}")], [text("Visa bostad")]),
		],
	)

# The expensive region, as a function of exactly what it reads. The button
# at the top shows that events inside a skipped region still dispatch.
grid : I64 -> Html(Msg)
grid = |rows|
	div(
		[class("grid")],
		[
			button([class("grid-btn"), on_click(CardClicked)], [text("a button inside the grid")]),
			div([class("grid-cards")], (1..=rows).iter().map(card).collect()),
		],
	)

render : Model -> Html(Msg)
render = |model| {
	avg = model.avg_gap_tenths
	gap_text = if avg == 0 {
		"-"
	} else {
		"${(avg // 10).to_str()}.${(avg % 10).to_str()} ms"
	}
	spinner =
		match model.ticks % 4 {
			0 => "◐"
			1 => "◓"
			2 => "◑"
			_ => "◒"
		}
	rows = model.rows
	div(
		[],
		[
			div(
				[class("header")],
				[
					span([class("spinner")], [text(spinner)]),
					text(" tick gap ${gap_text} (target 16.0 ms) · ${rows.to_str()} cards · "),
					button([on_click(FewerRows)], [text("÷2")]),
					button([on_click(MoreRows)], [text("×2")]),
					button(
						[on_click(ToggleLazy)],
						[
							text(
								if model.use_lazy {
									"Html.lazy: ON"
								} else {
									"Html.lazy: OFF"
								},
							),
						],
					),
				],
			),
			# The demo's whole point, side by side: the same grid, wrapped
			# or not. With lazy ON the grid is skipped on every tick because
			# `rows` did not change; only ×2/÷2 rebuild it.
			if model.use_lazy {
				Html.lazy(grid, rows)
			} else {
				grid(rows)
			},
		],
	)
}
