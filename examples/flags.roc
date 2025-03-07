app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/v0.1.0/g0btWTwHYXQ6ZTCsMRHnCxYuu73bZ5lharzD_p1s5lE.tar.br",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
}

import html.Html exposing [Html, div, p, pre, text]
import pf.Action exposing [Action]
import json.Json
import pf.Console

Model : [
    Human {
            name : Str,
            karma : I32,
        },
    FailedToParseFlags {
            flags : Str,
            error : [
                Leftover (List U8),
                TooShort,
            ],
        },
]

init! : Str => Model
init! = |flags|
    when Decode.from_bytes(Str.to_utf8(flags), Json.utf8) is
        Ok({ name, karma }) -> Human({ name, karma })
        Err(e) ->
            Console.log!("Failed to decode flags into model.\nFlags: ${flags}\n\nCause: ${Inspect.to_str(e)}")
            FailedToParseFlags(
                {
                    flags,
                    error: e,
                },
            )

update! : Model, Str, Str => Action Model
update! = |_, _, _| Action.none

render : Model -> Html Model
render = |model|
    when model is
        Human({ name, karma }) -> judgement_view(name, karma)
        FailedToParseFlags(rec) -> error_view(rec)

judgement_view : Str, I32 -> Html Model
judgement_view = |name, karma|
    judgement =
        if karma > 0 then
            "You're alright!"
        else
            "Karma isn't real, anyway! Right?"

    div(
        [],
        [
            p([], [text(judgement)]),
            p([], [text("Name: ${name}")]),
            p([], [text("Karma: ${Num.to_str(karma)}")]),
        ],
    )

error_view : { flags : Str, error : _ } -> _
error_view = |{ flags, error }|
    when flags is
        "" ->
            div(
                [],
                [
                    p([], [text("Let's set some flags! Open up `www/index.html` and find the call to `run(\"\");` and replace it with this:")]),
                    pre(
                        [],
                        [
                            text(
                                """
                                run(`{
                                  "name": "Brödil",
                                  "karma": 99
                                }`);
                                """,
                            ),
                        ],
                    ),
                ],
            )

        _ ->
            div(
                [],
                [
                    p(
                        [],
                        [
                            text("Oh, no, we couldn't parse the given flags! Open up `www/index.html` and make sure that the argument to `run` is a valid JSON string (not an object). Here's an example that will parse correctly:"),
                        ],
                    ),
                    pre(
                        [],
                        [
                            text(
                                """
                                run(`{
                                  "name": "Brödil",
                                  "karma": 99
                                }`);
                                """,
                            ),
                        ],
                    ),
                    p([], [text("Here's som info about the error:")]),
                    pre(
                        [],
                        [
                            text("Failed to decode flags into model.\n\nFlags: ${flags}\n\nError: ${Inspect.to_str(error)}"),
                        ],
                    ),
                ],
            )
