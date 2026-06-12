app [Model, init!, update!, render] {
    pf: platform "../../../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.11.0/7rgWAa6Gu3IGfdGl1JKxHQyCBVK9IUbZXbDui0jIZSQ.tar.br",
}

# Benchmark app for Joy's end-to-end update cycle (render -> convert -> diff+patch).
#
# It renders a fixed-size list and, on each `Step` event, advances a counter. Row
# labels are derived from the counter so that a sparse-but-nonzero fraction of rows
# change every step -- the realistic case that exercises diffing without degenerating
# into "rebuild everything". The driver (tests/bench/driver.roc) dispatches many Step
# events and reads the per-update timings emitted by the `joy_bench` feature.

import html.Html exposing [Html, div, button, ul, li, span, text]
import html.Attribute exposing [id, class]
import html.Event
import pf.Action exposing [Action]

# Number of rows in the list. Large enough to produce a measurable diff, small enough
# to keep a full bench run quick. Mirrors the order of magnitude of the percy benches.
rows : U64
rows = 1000

Model : U64

init! : Str => Model
init! = |_flags| 0

Ev : [Step]

update! : Model, Str, List U8 => Action Model
update! = |model, raw, _payload|
    when decode_ev(raw) is
        Step -> Num.add_wrap(model, 1) |> Action.update

render : Model -> Html Model
render = |model|
    items =
        List.range({ start: At(0), end: Before(rows) })
        |> List.map(|i| render_row(i, model))

    div([], [
        button([id("step"), Event.on_click(encode_ev(Step))], [text("step")]),
        div([id("count")], [text(Num.to_str(model))]),
        ul([id("rows")], items),
    ])

render_row : U64, Model -> Html Model
render_row = |i, model|
    # Mirror js-framework-benchmark's "select row": exactly one row is marked (a class
    # toggle), labels are stable. So each Step changes the class on 2 rows (old + new
    # selected) -- an O(1) logical change -- while `render` still rebuilds the whole tree
    # and percy still diffs all `rows` nodes. That isolates the whole-tree re-render cost.
    is_selected = i == Num.rem(model, rows)
    label = "item ${Num.to_str(i)}"
    row_class = if is_selected then "row selected" else "row"

    li([class(row_class)], [
        span([class("id")], [text(Num.to_str(i))]),
        span([class("label")], [text(label)]),
    ])

encode_ev : Ev -> Str
encode_ev = |ev| Inspect.to_str(ev)

decode_ev : Str -> Ev
decode_ev = |raw|
    when raw is
        "Step" -> Step
        _ -> crash("Unsupported event: ${raw}")
