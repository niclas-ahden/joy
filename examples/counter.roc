app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/v0.7.0/HRdu6jPerN3MsUjXXeDjQtbBgnqUMVaKaI7yyrcVHa8.tar.br",
}

import html.Html exposing [Html, div, button, text]
import pf.Action exposing [Action]

Model : I64

init! : Str => Model
init! = |_flags| 0

Event : [
    UserClickedDecrement,
    UserClickedIncrement,
]

update! : Model, Str, List U8 => Action Model
update! = |model, raw, _payload|
    when decode_event(raw) is
        UserClickedDecrement -> Num.sub_wrap(model, 1) |> Action.update
        UserClickedIncrement -> Num.add_wrap(model, 1) |> Action.update

render : Model -> Html Model
render = |model|
    div(
        [],
        [
            button([], [{ name: "onclick", handler: encode_event(UserClickedIncrement) }], [text("+")]),
            text(Inspect.to_str(model)),
            button([], [{ name: "onclick", handler: encode_event(UserClickedDecrement) }], [text("-")]),
        ],
    )

encode_event : Event -> Str
encode_event = |event| Inspect.to_str(event)

decode_event : Str -> Event
decode_event = |raw|
    when raw is
        "UserClickedIncrement" -> UserClickedIncrement
        "UserClickedDecrement" -> UserClickedDecrement
        _ -> crash("Unsupported event type \"${raw}\"")

