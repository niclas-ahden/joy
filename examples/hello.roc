app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/v0.10.0/VM_GLBCvmmdZAxFHzkRqOX2YHYxt4qPVrs5Omm2L374.tar.br",
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
