app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, h2, button, text]
import html.Attribute exposing [on_click]
import pf.Effect exposing [Effect]
import pf.Sub exposing [Sub]
import pf.Time

# Component composition via the map combinators: a self-contained counter
# component owns its CounterMsg, its view, its update, a boot effect and a
# tick subscription, and the parent embeds TWO of them, wrapping each with
# Html.map / Effect.map / Sub.map so the messages route back to the right one.

# --- The counter component (its own Msg, view, update, cmd, sub) ---

CounterMsg : [Increment, Decrement]

counter_view : I64 -> Html(CounterMsg)
counter_view = |count|
	div(
		[],
		[
			button([on_click(Decrement)], [text("-")]),
			text(count.to_str()),
			button([on_click(Increment)], [text("+")]),
		],
	)

counter_update : I64, CounterMsg -> I64
counter_update = |count, msg|
	match msg {
		Increment => count + 1
		Decrement => count - 1
	}

# An effect the component wants run at boot (an immediate timer), and the
# recurring event source it owns. Both are functions rather than top-level
# constants: a constant Effect/Sub holds a boxed closure, and the compiler
# segfaults materializing a closure as static data now that every value the
# constant reaches is pure.
counter_boot : {} -> Effect(CounterMsg)
counter_boot = |_| Time.after(5, |_| Increment)

counter_ticks : {} -> Sub(CounterMsg)
counter_ticks = |_| Time.every(1000, |_| Increment)

# --- The parent app: two independent counters ---

Model : { left : I64, right : I64 }

Msg : [
	Left(CounterMsg),
	Right(CounterMsg),
]

# Only the left counter auto-ticks; Sub.map routes its ticks to it.
subscriptions = |_model| [Sub.map(counter_ticks({}), |m| Left(m))]

init : Str -> (Model, List(Effect(Msg)))
init = |_|
# Effect.map routes the component's boot effect to the right counter.
	({ left: 0, right: 0 }, [Effect.map(counter_boot({}), |m| Right(m))])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Left(m) => ({ ..model, left: counter_update(model.left, m) }, [])
		Right(m) => ({ ..model, right: counter_update(model.right, m) }, [])
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			h2([], [text("left")]),
			Html.map(counter_view(model.left), |m| Left(m)),
			h2([], [text("right")]),
			Html.map(counter_view(model.right), |m| Right(m)),
		],
	)
