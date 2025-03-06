app [Model, init!, update!, render] { web: platform "../platform/main.roc" }

import web.Html exposing [Html, div, button, text]
import web.Action exposing [Action]

Model : I64

init! : {} => Model
init! = |{}| 0

Event : [
    UserClickedDecrement,
    UserClickedIncrement,
]

update! : Model, Str, Str => Action Model
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

