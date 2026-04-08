app [Model, init!, update!, render] {
    pf: platform "../../../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.11.0/7rgWAa6Gu3IGfdGl1JKxHQyCBVK9IUbZXbDui0jIZSQ.tar.br",
}

import html.Html exposing [Html, div, text, button, dialog]
import html.Attribute exposing [id]
import html.Event
import pf.Action exposing [Action]
import pf.DOM

Model : { status : Str }

init! : Str => Model
init! = |_flags|
    { status: "" }

Ev : [ShowModal, CloseModal]

update! : Model, Str, List U8 => Action Model
update! = |model, raw, _payload|
    when decode_ev(raw) is
        ShowModal ->
            DOM.show_modal!("#test-dialog")
            { model & status: "opened" } |> Action.update

        CloseModal ->
            DOM.close_modal!("#test-dialog")
            { model & status: "closed" } |> Action.update

render : Model -> Html Model
render = |model|
    div([], [
        div([id("controls")], [
            button([id("btn-show"), Event.on_click(encode_ev(ShowModal))], [text("Show modal")]),
            button([id("btn-close"), Event.on_click(encode_ev(CloseModal))], [text("Close modal")]),
        ]),
        dialog([id("test-dialog")], [
            div([id("dialog-content")], [text("Dialog is open")]),
            button([id("btn-close-inside"), Event.on_click(encode_ev(CloseModal))], [text("Close")]),
        ]),
        div([id("status")], [text(model.status)]),
    ])

encode_ev : Ev -> Str
encode_ev = |ev| Inspect.to_str(ev)

decode_ev : Str -> Ev
decode_ev = |raw|
    when raw is
        "ShowModal" -> ShowModal
        "CloseModal" -> CloseModal
        _ -> crash("Unsupported event: ${raw}")
