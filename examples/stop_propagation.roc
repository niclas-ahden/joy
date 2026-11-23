app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../platform/main.roc",
}

import html.Html exposing [button, div, text]
import html.Attribute exposing [id, on_click]
import pf.Effect

# Click propagation. The outer div counts every click that reaches it, so the
# two buttons inside it tell the flag apart: "Bubbles" carries a plain
# `on_click` and its click travels on to the div, moving both counters, while
# "Doesn't bubble" chains `.stop_propagation()` and the div never hears about it.

Model : { outer : I64, inner : I64 }

Msg : [OuterClicked, InnerClicked]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ outer: 0, inner: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		OuterClicked => ({ ..model, outer: model.outer + 1 }, [])
		InnerClicked => ({ ..model, inner: model.inner + 1 }, [])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[id("outer"), on_click(OuterClicked)],
		[
			button([id("bubbles"), on_click(InnerClicked)], [text("Bubbles")]),
			button(
				[id("stops"), on_click(InnerClicked).stop_propagation()],
				[text("Doesn't bubble")],
			),
			div(
				[id("counts")],
				[text("Outer ${model.outer.to_str()}, inner ${model.inner.to_str()}")],
			),
		],
	)

# No subs needed for this example!
subscriptions = |_model| []
