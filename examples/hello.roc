app [Model, init, render] { web: platform "../platform/main.roc" }

import web.Elem exposing [Elem]

Model : I64

init : {} -> Model
init = \{} -> 42

render : Model -> Elem
render = \_ ->
    Div (Text "Hello World")
