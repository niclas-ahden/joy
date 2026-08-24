app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, button, text]
import html.Attribute exposing [id, on_click]
import pf.Effect exposing [Effect]

# Probe: do lazy captures with padding bytes (Bool in a tuple, Bool in a
# record, U8 mixed with U64) still compare equal across renders, so the
# region skips? Each item is captured through a differently shaped input.

Item : { n : U64, flag : Bool }

Model : { items : List(Item), tick : U64 }

Msg : [Tick]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| {
	items = [{ n: 1, flag: Bool.True }, { n: 2, flag: Bool.False }, { n: 3, flag: Bool.True }]
	({ items, tick: 0 }, [])
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Tick => ({ ..model, tick: model.tick + 1 }, [])
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			button([id("tick"), on_click(Tick)], [text("tick")]),
			text(model.tick.to_str()),
			div([id("tuple-bool")], model.items.map(|it| Html.lazy2(tuple_bool_view, it.n, it.flag))),
			div([id("record-bool")], model.items.map(|it| Html.lazy(record_bool_view, it))),
			div([id("u8-mix")], model.items.map(|it| Html.lazy2(u8_view, small(it), it.n))),
		],
	)

small : Item -> U8
small = |it| if it.flag { 1 } else { 0 }

tuple_bool_view : U64, Bool -> Html(Msg)
tuple_bool_view = |n, flag| div([], [text("t${n.to_str()}${if flag { "y" } else { "n" }}")])

record_bool_view : Item -> Html(Msg)
record_bool_view = |it| div([], [text("r${it.n.to_str()}${if it.flag { "y" } else { "n" }}")])

u8_view : U8, U64 -> Html(Msg)
u8_view = |s, n| div([], [text("u${n.to_str()}${s.to_str()}")])
