app [Model, init!, update!, render] {
    pf: platform "../../../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.11.0/7rgWAa6Gu3IGfdGl1JKxHQyCBVK9IUbZXbDui0jIZSQ.tar.br",
}

import html.Html exposing [Html, div, text]
import html.Attribute exposing [id]
import pf.Action exposing [Action]
import pf.Keyboard

Model : {
    key_events : List Str,
    last_key : Str,
}

init! : Str => Model
init! = |_flags|
    # Listen for all keys
    Keyboard.add_global_listener!("AnyKey", [])
    # Listen for specific keys only
    Keyboard.add_global_listener!("EscapeOnly", ["Escape"])
    { key_events: [], last_key: "" }

Ev : [AnyKey, EscapeOnly]

update! : Model, Str, List U8 => Action Model
update! = |model, raw, payload|
    key = payload |> Str.from_utf8 |> Result.with_default("")
    when decode_ev(raw) is
        AnyKey ->
            { model &
                key_events: model.key_events |> List.append("any:$(key)"),
                last_key: key,
            }
            |> Action.update

        EscapeOnly ->
            { model &
                key_events: model.key_events |> List.append("escape:$(key)"),
            }
            |> Action.update

render : Model -> Html Model
render = |model|
    div([], [
        div([id("last-key")], [text(model.last_key)]),
        div([id("event-count")], [text(Num.to_str(List.len(model.key_events)))]),
        div([id("events")], [text(model.key_events |> Str.join_with(","))]),
    ])

encode_ev : Ev -> Str
encode_ev = |ev| Inspect.to_str(ev)

decode_ev : Str -> Ev
decode_ev = |raw|
    when raw is
        "AnyKey" -> AnyKey
        "EscapeOnly" -> EscapeOnly
        _ -> crash("Unsupported event: ${raw}")
