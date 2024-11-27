app [
    Model,
    init,
    update,
    render,
] {
    web: platform "../platform/main.roc",
}

import web.Html exposing [Html, div, text]
import web.Action exposing [Action]

Model : Str

init : {} -> Model
init = \{} -> "CLICK ME"

update : Model, List U8 -> Action Model
update = \_, raw ->
    if raw == Str.toUtf8 "UserClickedText" then
        Action.update "ALREADY CLICKED!!!"
    else
        Action.none

render : Model -> Html Model
render = \model ->
    div [] [
        { name : "onclick", handler : Str.toUtf8 "UserClickedText" }
    ] [
        text "Click status: $(model)"
    ]
