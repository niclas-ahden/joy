app [Model, init, update, render] {
    web: platform "../platform/main.roc",
}

import web.Html exposing [Html, div, button, ul, li, text]
import web.Action exposing [Action]

Model : {
    left : I64,
    middle : I64,
    right : I64,
}

init : {} -> Model
init = \{} -> {
    left: -10,
    middle: 0,
    right: 10,
}

Event : [
    UserClickedDecrement [Left, Middle, Right],
    UserClickedIncrement [Left, Middle, Right],
]

update : Model, List U8 -> Action Model
update = \model, raw ->
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
            { key: "style", value: "display: flex; justify-content: space-around; padding: 20px;" },
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
            { key: "style", value: "list-style: none; padding: 0; text-align: center;" },
        ]
        [
            li [] [
                button
                    [
                        {
                            key: "style",
                            value:
                            """
                            background-color: red;
                            color: white;
                            padding: 10px 20px;
                            border: none;
                            border-radius: 5px;
                            cursor: pointer;
                            margin: 5px;
                            font-size: 16px;
                            """,
                        },
                    ]
                    [
                        { name: "onclick", handler: encodeEvent (UserClickedDecrement variant) },
                    ]
                    [text "-"],
            ],
            li
                [
                    { key: "style", value: "font-size: 24px; margin: 15px 0; font-weight: bold;" },
                ]
                [
                    text (Inspect.toStr value),
                ],
            li [] [
                button
                    [
                        {
                            key: "style",
                            value:
                            """
                            background-color: blue;
                            color: white;
                            padding: 10px 20px;
                            border: none;
                            border-radius: 5px;
                            cursor: pointer;
                            margin: 5px;
                            font-size: 16px;
                            """,
                        },
                    ]
                    [
                        { name: "onclick", handler: encodeEvent (UserClickedIncrement variant) },
                    ]
                    [text "+"],
            ],
        ]

encodeEvent : Event -> List U8
encodeEvent = \event ->
    when event is
        UserClickedIncrement Left -> [1]
        UserClickedIncrement Right -> [2]
        UserClickedIncrement Middle -> [3]
        UserClickedDecrement Left -> [4]
        UserClickedDecrement Right -> [5]
        UserClickedDecrement Middle -> [6]

decodeEvent : List U8 -> Event
decodeEvent = \raw ->
    when raw is
        [1] -> UserClickedIncrement Left
        [2] -> UserClickedIncrement Right
        [3] -> UserClickedIncrement Middle
        [4] -> UserClickedDecrement Left
        [5] -> UserClickedDecrement Right
        [6] -> UserClickedDecrement Middle
        _ -> crash "unreachable - invalid event encoding"
