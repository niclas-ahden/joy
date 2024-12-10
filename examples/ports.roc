app [Model, init!, update!, render] { web: platform "../platform/main.roc" }

import web.Html exposing [Html, div, h1, small, p, pre, text]
import web.Action exposing [Action]
import web.Console

Model : I32

Event : [Tick]

init! : {} => Model
init! = \{} -> 0

update! : Model, Str, Str => Action Model
update! = \model, raw, _ ->
    when decodeEvent raw is
        Tick ->
            Console.log! "Time passes slowly now... $(Num.toStr model)"
            Num.addWrap model 1 |> Action.update

render : Model -> Html Model
render = \model ->
    when model is
        0 ->
            div [] [
                p [] [text "Open ./www/index.html and uncomment the line that says:"],
                pre [] [text "setInterval(port, 1000, \"Tick\");"],
                p [] [text "Then refresh the page to see the magic."],
            ]

        _ ->
            div [] [
                h1 [] [text "Your excitement level for Roc: $(Num.toStr model)"],
                small [] [text "(you don't have to close this page if you don't want to)"],
            ]

# We haven't defined `encodeEvent` here because this example doesn't need it.

# `decodeEvent` takes two arguments in some other examples, but only one here. That's because this
# example doesn't include an `Event` with a `payload`.
decodeEvent : Str -> Event
decodeEvent = \raw ->
    when raw is
        "Tick" -> Tick
        _ -> crash "Unsupported event type \"$(raw)\""

