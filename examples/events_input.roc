app [Model, init!, update!, render] { web: platform "../platform/main.roc" }

import web.Html exposing [Html, div, textarea, p, h1, text, rows, cols]
import web.Action exposing [Action]
import web.Console

Model : Str

Event : [
    UserTypedSomething Str,
]

init! : {} => Model
init! = \{} -> ""

update! : Model, Str, Str => Action Model
update! = \_model, raw, payload ->
    when decodeEvent raw payload is
        UserTypedSomething message ->
            Console.log! "User typed: $(message)"

            message |> Action.update

render : Model -> Html Model
render = \model ->
    div [] [
        h1 [] [text "Dear diary"],
        textarea
            [rows "10", cols "30"]
            [{ name: "oninput", handler: encodeEvent UserTypedSomething }]
            [],
        p [] [text model],
    ]

## `encodeEvent` does not take an `Event` because `Event`s may have payloads that don't make sense
## to pass in when encoding. In this example we want the event `UserTypedSomething` to trigger
## on input in the textarea. The event will be triggered with the content of the texarea as its
## payload. If `encodeEvent` took `Event` we would have to pass in some nonsense payload above.
##
## Regrettably, this means that the tag `UserTypedSomething` _looks_ like an `Event` but it's
## not. It's just a tag that happens to look similar to the `Event` `UserTypedSomething Str`.
## Therefore, Roc cannot guarantee that we have written a decoder for every tag that we have an
## encoder for.
encodeEvent : _ -> Str
encodeEvent = \event -> Inspect.toStr event

decodeEvent : Str, Str -> Event
decodeEvent = \raw, payload ->
    when raw is
        "UserTypedSomething" -> UserTypedSomething payload
        _ -> crash "Unsupported event type \"$(raw)\", payload \"$(payload)\""

