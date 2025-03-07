app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/v0.1.0/g0btWTwHYXQ6ZTCsMRHnCxYuu73bZ5lharzD_p1s5lE.tar.br",
}

import html.Html exposing [Html, div, text]
import pf.Action exposing [Action]

Model : Str

init! : {} => Model
init! = |{}| "Roc"

update! : Model, Str, Str => Action Model
update! = |_, _, _| Action.none

render : Model -> Html Model
render = |model|
    div([], [text("Hello, ${model}!")])
