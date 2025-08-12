app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/v0.7.0/HRdu6jPerN3MsUjXXeDjQtbBgnqUMVaKaI7yyrcVHa8.tar.br",
}

import html.Html exposing [Html, div, textarea, p, h1, text]
import html.Attribute exposing [rows, cols]
import pf.Action exposing [Action]
import pf.Console

Model : Str

Event : [
    UserTypedSomething Str,
]

init! : Str => Model
init! = |_flags| ""

update! : Model, Str, List U8 => Action Model
update! = |_model, raw, payload|
    when decode_event(raw, payload) is
        UserTypedSomething(message) ->
            Console.log!("User typed: ${message}")
            message |> Action.update

render : Model -> Html Model
render = |model|
    div(
        [],
        [
            h1([], [text("Dear diary")]),
            textarea(
                [rows("10"), cols("30")],
                [{ name: "oninput", handler: encode_event(UserTypedSomething) }],
                [],
            ),
            p([], [text(model)]),
        ],
    )

## `encodeEvent` does not take an `Event` because `Event`s may have payloads that don't make sense
## to pass in when encoding. In this example we want the event `UserTypedSomething` to trigger
## on input in the textarea. The event will be triggered with the content of the texarea as its
## payload. If `encodeEvent` took `Event` we would have to pass in some nonsense payload above.
##
## Regrettably, this means that the tag `UserTypedSomething` _looks_ like an `Event` but it's
## not. It's just a tag that happens to look similar to the `Event` `UserTypedSomething Str`.
## Therefore, Roc cannot guarantee that we have written a decoder for every tag that we have an
## encoder for.
encode_event : _ -> Str
encode_event = |event| Inspect.to_str(event)

decode_event : Str, List U8 -> Event
decode_event = |raw, payload|
    when raw is
        "UserTypedSomething" -> UserTypedSomething(Str.from_utf8_lossy(payload))
        _ -> crash("Unsupported event type \"${raw}\", payload \"${Inspect.to_str(payload)}\"")
