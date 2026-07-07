app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.14.0/IVK93mBqjterEFSYijs67Dkl1rYfu0qGl4PAhSPGET0.tar.br",
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
