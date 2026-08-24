app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, button, text]
import html.Attribute exposing [id, on_click]
import pf.Effect exposing [Effect]

# Click propagation. The outer div counts every click that reaches it, so the
# two buttons inside it tell the flag apart: "bubbles" carries a plain
# `on_click` and its click travels on to the div, moving both counters, while
# "stops" chains `.stop_propagation()` and the div never hears about it.

Model : { outer : I64, inner : I64 }

Msg : [OuterClicked, InnerClicked]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ outer: 0, inner: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		OuterClicked => ({ ..model, outer: model.outer + 1 }, [])
		InnerClicked => ({ ..model, inner: model.inner + 1 }, [])
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[id("outer"), on_click(OuterClicked)],
		[
			button([id("bubbles"), on_click(InnerClicked)], [text("bubbles")]),
			button(
				[id("stops"), on_click(InnerClicked).stop_propagation()],
				[text("stops")],
			),
			div(
				[id("counts")],
				[text("outer ${model.outer.to_str()}, inner ${model.inner.to_str()}")],
			),
		],
	)
