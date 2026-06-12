app [Model, init!, update!, render] {
    pf: platform "../../../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.11.0/7rgWAa6Gu3IGfdGl1JKxHQyCBVK9IUbZXbDui0jIZSQ.tar.br",
}

# Test app for Joy's virtual-DOM contract (render -> diff -> patch), driven by a test
# harness rather than a user. The harness pushes an arbitrary list state via the `set:`
# event (injected through the exposed wasm `port`, see index.html), so it can fuzz the
# diff by transitioning between random states and asserting the resulting DOM. Each row
# also carries an `onclick`, so event listener add/remove is exercised whenever rows are
# inserted/removed during a diff.
#
# Event encodings (the harness builds these; labels must not contain ',' or ';'):
#   "set:<id>,<label>,<sel>;<id>,<label>,<sel>;..."   replace the whole model ("set:" = empty)
#   "toggle:<id>"                                      flip one row's selected flag (the onclick)

import html.Html exposing [Html, table, tbody, tr, td, a, text]
import html.Attribute exposing [id, class]
import html.Event
import pf.Action exposing [Action]

Row : { id : U64, label : Str, sel : Bool }

Model : List Row

init! : Str => Model
init! = |_flags| []

Ev : [Set (List Row), Toggle U64]

update! : Model, Str, List U8 => Action Model
update! = |model, raw, _payload|
    when decode_ev(raw) is
        Set(rows) -> Action.update(rows)
        Toggle(tid) ->
            model
            |> List.map(|row| if row.id == tid then { row & sel: !row.sel } else row)
            |> Action.update

render : Model -> Html Model
render = |model|
    table([id("tbl")], [tbody([id("tbody")], List.map(model, render_row))])

render_row : Row -> Html Model
render_row = |{ id: row_id, label, sel }|
    row_attrs = if sel then [class("row selected")] else [class("row")]
    id_str = Num.to_str(row_id)
    tr(row_attrs, [
        td([class("id")], [text(id_str)]),
        td([class("label")], [
            a([class("lbl"), Event.on_click("toggle:${id_str}")], [text(label)]),
        ]),
    ])

decode_ev : Str -> Ev
decode_ev = |raw|
    when Str.split_first(raw, ":") is
        Ok({ before: "set", after }) -> Set(parse_rows(after))
        Ok({ before: "toggle", after }) -> Toggle(Str.to_u64(after) |> Result.with_default(0))
        _ -> crash("Unsupported event: ${raw}")

parse_rows : Str -> List Row
parse_rows = |s|
    if Str.is_empty(s) then
        []
    else
        Str.split_on(s, ";")
        |> List.keep_if(|chunk| !Str.is_empty(chunk))
        |> List.map(parse_row)

parse_row : Str -> Row
parse_row = |chunk|
    parts = Str.split_on(chunk, ",")
    row_id = List.get(parts, 0) |> Result.try(Str.to_u64) |> Result.with_default(0)
    label = List.get(parts, 1) |> Result.with_default("")
    sel = (List.get(parts, 2) |> Result.with_default("0")) == "1"
    { id: row_id, label, sel }
