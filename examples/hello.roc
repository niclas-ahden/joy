app [Model, init, render] { web: platform "../platform/main.roc" }

import web.Html exposing [Html, div, text]

Model : Str

init : {} -> Model
init = \{} -> "Roc"

render : Model -> Html Model
render = \model ->
    div [] [] [
        text "Hello from $(model)"
    ]
