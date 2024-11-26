app [Model, init, render] { web: platform "../platform/main.roc" }

import web.Html exposing [Html, div, text]
import web.Action

Model : Str

init : {} -> Model
init = \{} -> "Roc"

render : Model -> Html Model
render = \model ->
    div [] [
        { name : "onclick", handler : \_prev -> Action.none }
    ] [
        text "Hello from $(model)"
    ]
