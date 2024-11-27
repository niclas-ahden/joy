app [Model, init, update, render] {
    web: platform "../platform/main.roc",
}

import web.Html exposing [Html, div, text]
import web.Action exposing [Action]

Model : [
    NotClicked,
    Clicked,
]

init : {} -> Model
init = \{} -> NotClicked

update : Model, List U8 -> Action Model
update = \model, raw ->
    when model is
        NotClicked if raw == Str.toUtf8 "UserClickedText" -> Action.update Clicked
        _ -> Action.none

render : Model -> Html Model
render = \model ->
    when model is
        NotClicked ->
            div
                []
                [
                    { name: "onclick", handler: Str.toUtf8 "UserClickedText" },
                ]
                [
                    text "NOT CLICKED",
                ]

        Clicked ->
            div [] [] [text "BEEN CLICKED"]
