app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, text]
import html.Attribute exposing [id, style, on_visible]
import pf.Effect exposing [Effect]

# A minimal infinite-scroll list. `shown` is how many items are currently
# rendered. Each time the sentinel at the bottom of the list scrolls into view
# we reveal another batch, up to `max_items`.

Model : { shown : U64 }

batch_size : U64
batch_size = 20

max_items : U64
max_items = 100

Msg : [
	# Fired by the sentinel's `on_visible` attribute whenever it enters the
	# viewport.
	SentinelVisible,
]

# No recurring event sources.
subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ shown: batch_size }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		SentinelVisible =>
			if model.shown >= max_items {
				# Nothing left to reveal. Returning `none` skips the
				# re-render, which also means the sentinel is not re-armed
				# (see `rearm_key` below), so loading stops cleanly here.
				(model, [])
			} else {
				({ shown: (model.shown + batch_size).min(max_items) }, [])
			}
		}

render : Model -> Html(Msg)
render = |model| {
	items : List(Html(Msg))
	items =
		(1..=model.shown).iter()
			.map(
				|n|
					div(
						[style([("padding", "16px"), ("border-bottom", "1px solid #ddd")])],
						[text("Item ${n.to_str()}")],
					),
			)
			.collect()

	sentinel =
	# The infinite-scroll sentinel. `on_visible` attaches an
	# IntersectionObserver whose lifetime the runtime ties to this node.
	# There is no manual setup, teardown, or querySelector.
	#
	# `root_margin: "200px"` makes the msg fire 200px before the sentinel
	# actually reaches the viewport, so the next batch is revealed just
	# ahead of the user reaching the bottom.
	#
	# An IntersectionObserver only fires on a crossing into view. After a
	# batch is revealed the sentinel can still be on screen, and with no
	# new crossing it would not fire again, so loading would stall.
	# `rearm_key` changes per batch (here the shown count), which tells
	# the runtime to re-check visibility after each reveal, so loading
	# continues until the sentinel is off-screen or `max_items` is
	# reached. A constant `rearm_key` fires once per crossing.
		div(
			[
				id("sentinel"),
				on_visible(
					SentinelVisible,
					{
						root_margin: "200px",
						rearm_key: model.shown.to_str(),
					},
				),
			],
			[
				text(
					if model.shown >= max_items {
						"No more items"
					} else {
						"Loading more..."
					},
				),
			],
		)

	div([], items.append(sentinel))
}
