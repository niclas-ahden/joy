app [Model, init!, update!, render] { web: platform "../platform/main.roc" }

import web.Html exposing [Html, div, button, ul, li, text, styleAttr]
import web.Action exposing [Action]

Model : {
    left : I64,
    middle : I64,
    right : I64,
}

init! : {} => Model
init! = \{} -> {
    left: -10,
    middle: 0,
    right: 10,
}

Event : [
    UserClickedDecrement [Left, Middle, Right],
    UserClickedIncrement [Left, Middle, Right],
]

update! : Model, Str, Str => Action Model
update! = \model, raw, _payload ->
    when decodeEvent raw is
        UserClickedDecrement Left -> model |> &left (Num.subWrap model.left 1) |> Action.update
        UserClickedDecrement Middle -> model |> &middle (Num.subWrap model.middle 1) |> Action.update
        UserClickedDecrement Right -> model |> &right (Num.subWrap model.right 1) |> Action.update
        UserClickedIncrement Left -> model |> &left (Num.addWrap model.left 1) |> Action.update
        UserClickedIncrement Middle -> model |> &middle (Num.addWrap model.middle 1) |> Action.update
        UserClickedIncrement Right -> model |> &right (Num.addWrap model.right 1) |> Action.update

render : Model -> Html Model
render = \model ->
    div
        [
            styleAttr [
                ("display", "flex"),
                ("justify-content", "space-around"),
                ("padding", "20px"),
            ],
        ]
        [
            counter Left model.left,
            counter Middle model.middle,
            counter Right model.right,
        ]

counter : [Left, Middle, Right], I64 -> _
counter = \variant, value ->
    ul
        [
            styleAttr [
                ("list-style", "none"),
                ("padding", "0"),
                ("text-align", "center"),
            ],
        ]
        [
            li [] [
                button
                    [
                        styleAttr [
                            ("background-color", "red"),
                            ("color", "white"),
                            ("padding", "10px 20px"),
                            ("border", "none"),
                            ("border-radius", "5px"),
                            ("cursor", "pointer"),
                            ("margin", "5px"),
                            ("font-size", "16px"),
                        ],
                    ]
                    [
                        { name: "onclick", handler: encodeEvent (UserClickedDecrement variant) },
                    ]
                    [text "-"],
            ],
            li
                [
                    styleAttr [
                        ("font-size", "24px"),
                        ("margin", "15px 0"),
                        ("font-weight", "bold"),
                    ],
                ]
                [
                    text (Inspect.toStr value),
                ],
            li [] [
                button
                    [
                        styleAttr [
                            ("background-color", "blue"),
                            ("color", "white"),
                            ("padding", "10px 20px"),
                            ("border", "none"),
                            ("border-radius", "5px"),
                            ("cursor", "pointer"),
                            ("margin", "5px"),
                            ("font-size", "16px"),
                        ],
                    ]
                    [
                        { name: "onclick", handler: encodeEvent (UserClickedIncrement variant) },
                    ]
                    [text "+"],
            ],
        ]

encodeEvent : Event -> Str
encodeEvent = \event -> Inspect.toStr event

decodeEvent : Str -> Event
decodeEvent = \raw ->
    when raw is
        "(UserClickedIncrement Left)" -> UserClickedIncrement Left
        "(UserClickedIncrement Right)" -> UserClickedIncrement Right
        "(UserClickedIncrement Middle)" -> UserClickedIncrement Middle
        "(UserClickedDecrement Left)" -> UserClickedDecrement Left
        "(UserClickedDecrement Right)" -> UserClickedDecrement Right
        "(UserClickedDecrement Middle)" -> UserClickedDecrement Middle
        _ -> crash "Unsupported event type \"$(raw)\""

