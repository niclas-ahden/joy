app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.13.0/D8dlKh8s_ZJeGZt5U_aeAx9b3KOBSady2jIGX_9of2Q.tar.br",
}

import html.Html exposing [Html, div, text]
import pf.Action exposing [Action]

Model : Str

init! : Str => Model
init! = |_flags| "Roc"

update! : Model, Str, List U8 => Action Model
update! = |_, _, _| Action.none

render : Model -> Html Model
render = |model|
    div([], [text("Hello, ${model}!")])
