app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/v0.10.0/VM_GLBCvmmdZAxFHzkRqOX2YHYxt4qPVrs5Omm2L374.tar.br",
}

import pf.Action exposing [Action]
import html.Html exposing [Html, div, button, ul, li, text]
import html.Attribute exposing [style]
import html.Event

Model : {
    left : I64,
    middle : I64,
    right : I64,
}

init! : _ => Model
init! = |_flags| {
    left: -10,
    middle: 0,
    right: 10,
}

Event : [
    UserClickedDecrement [Left, Middle, Right],
    UserClickedIncrement [Left, Middle, Right],
]

update! : Model, Str, List U8 => Action Model
update! = |model, raw, _payload|
    when decode_event(raw) is
        UserClickedDecrement(Left) -> model |> &left(Num.sub_wrap(model.left, 1)) |> Action.update
        UserClickedDecrement(Middle) -> model |> &middle(Num.sub_wrap(model.middle, 1)) |> Action.update
        UserClickedDecrement(Right) -> model |> &right(Num.sub_wrap(model.right, 1)) |> Action.update
        UserClickedIncrement(Left) -> model |> &left(Num.add_wrap(model.left, 1)) |> Action.update
        UserClickedIncrement(Middle) -> model |> &middle(Num.add_wrap(model.middle, 1)) |> Action.update
        UserClickedIncrement(Right) -> model |> &right(Num.add_wrap(model.right, 1)) |> Action.update

render : Model -> Html Model
render = |model|
    div(
        [
            style(
                [
                    ("display", "flex"),
                    ("justify-content", "space-around"),
                    ("padding", "20px"),
                ],
            ),
        ],
        [
            counter(Left, model.left),
            counter(Middle, model.middle),
            counter(Right, model.right),
        ],
    )

counter : [Left, Middle, Right], I64 -> _
counter = |variant, value|
    ul(
        [
            style(
                [
                    ("list-style", "none"),
                    ("padding", "0"),
                    ("text-align", "center"),
                ],
            ),
        ],
        [
            li(
                [],
                [
                    button(
                        [
                            style(
                                [
                                    ("background-color", "red"),
                                    ("color", "white"),
                                    ("padding", "10px 20px"),
                                    ("border", "none"),
                                    ("border-radius", "5px"),
                                    ("cursor", "pointer"),
                                    ("margin", "5px"),
                                    ("font-size", "16px"),
                                ],
                            ),
                            Event.on_click(encode_event(UserClickedDecrement(variant))),
                        ],
                        [text("-")],
                    ),
                ],
            ),
            li(
                [
                    style(
                        [
                            ("font-size", "24px"),
                            ("margin", "15px 0"),
                            ("font-weight", "bold"),
                        ],
                    ),
                ],
                [text(Inspect.to_str(value))],
            ),
            li(
                [],
                [
                    button(
                        [
                            style(
                                [
                                    ("background-color", "blue"),
                                    ("color", "white"),
                                    ("padding", "10px 20px"),
                                    ("border", "none"),
                                    ("border-radius", "5px"),
                                    ("cursor", "pointer"),
                                    ("margin", "5px"),
                                    ("font-size", "16px"),
                                ],
                            ),
                            Event.on_click(encode_event(UserClickedIncrement(variant))),
                        ],
                        [text("+")],
                    ),
                ],
            ),
        ],
    )

encode_event : Event -> Str
encode_event = |event| Inspect.to_str(event)

decode_event : Str -> Event
decode_event = |raw|
    when raw is
        "(UserClickedIncrement Left)" -> UserClickedIncrement(Left)
        "(UserClickedIncrement Right)" -> UserClickedIncrement(Right)
        "(UserClickedIncrement Middle)" -> UserClickedIncrement(Middle)
        "(UserClickedDecrement Left)" -> UserClickedDecrement(Left)
        "(UserClickedDecrement Right)" -> UserClickedDecrement(Right)
        "(UserClickedDecrement Middle)" -> UserClickedDecrement(Middle)
        _ -> crash("Unsupported event type \"${raw}\"")

