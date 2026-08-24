app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, text]
import pf.Effect exposing [Effect]

Model : Str

Msg : []

# No recurring event sources.
subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ("Roc", [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, _msg| (model, [])

render : Model -> Html(Msg)
render = |model|
	div([], [text("Hello, ${model}!")])
