app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/v0.10.0/VM_GLBCvmmdZAxFHzkRqOX2YHYxt4qPVrs5Omm2L374.tar.br",
}

import html.Html exposing [Html, div, h1, small, p, pre, text]
import pf.Action exposing [Action]
import pf.Console

Model : I32

Event : [Tick]

init! : Str => Model
init! = |_flags| 0

update! : Model, Str, List U8 => Action Model
update! = |model, raw, _|
    when decode_event(raw) is
        Tick ->
            Console.log!("Time passes slowly now... ${Num.to_str(model)}")
            Num.add_wrap(model, 1) |> Action.update

render : Model -> Html Model
render = |model|
    when model is
        0 ->
            div(
                [],
                [
                    p([], [text("Open ./www/index.html and uncomment the line that says:")]),
                    pre([], [text("setInterval(port, 1000, \"Tick\");")]),
                    p([], [text("Then refresh the page to see the magic.")]),
                ],
            )

        _ ->
            div(
                [],
                [
                    h1([], [text("Your excitement level for Roc: ${Num.to_str(model)}")]),
                    small([], [text("(you don't ever have to close this page if you don't want to)")]),
                ],
            )

# We haven't defined `encodeEvent` here because this example doesn't need it.

# `decodeEvent` takes two arguments in some other examples, but only one here. That's because this
# example doesn't include an `Event` with a `payload`.
decode_event : Str -> Event
decode_event = |raw|
    when raw is
        "Tick" -> Tick
        _ -> crash("Unsupported event type \"${raw}\"")

