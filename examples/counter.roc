app [Model, init!, update!, render] { web: platform "../platform/main.roc" }

import web.Html exposing [Html, div, button, text]
import web.Action exposing [Action]

Model : I64

init! : {} => Model
init! = \{} -> 0

Event : [
    UserClickedDecrement,
    UserClickedIncrement,
]

update! : Model, Str, Str => Action Model
update! = \model, raw, _payload ->
    when decodeEvent raw is
        UserClickedDecrement -> Num.subWrap model 1 |> Action.update
        UserClickedIncrement -> Num.addWrap model 1 |> Action.update

render : Model -> Html Model
render = \model ->
    div [] [
        button [] [{ name: "onclick", handler: encodeEvent UserClickedIncrement }] [text "+"],
        text (Inspect.toStr model),
        button [] [{ name: "onclick", handler: encodeEvent UserClickedDecrement }] [text "-"],
    ]

encodeEvent : Event -> Str
encodeEvent = \event -> Inspect.toStr event

decodeEvent : Str -> Event
decodeEvent = \raw ->
    when raw is
        "UserClickedIncrement" -> UserClickedIncrement
        "UserClickedDecrement" -> UserClickedDecrement
        _ -> crash "Unsupported event type \"$(raw)\""

