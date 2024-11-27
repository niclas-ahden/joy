app [Model, init, update, render] { web: platform "../platform/main.roc" }

import web.Html exposing [Html, div, text]
import web.Action exposing [Action]

Model : Str

init : {} -> Model
init = \{} -> "Roc"

update : Model, List U8 -> Action Model
update = \_, _ -> Action.none

render : Model -> Html Model
render = \model ->
    div [] [
        text "Hello from $(model)"
    ]
