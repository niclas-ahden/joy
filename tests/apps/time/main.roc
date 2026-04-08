app [Model, init!, update!, render] {
    pf: platform "../../../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.11.0/7rgWAa6Gu3IGfdGl1JKxHQyCBVK9IUbZXbDui0jIZSQ.tar.br",
}

import html.Html exposing [Html, div, text, button]
import html.Attribute exposing [id]
import html.Event
import pf.Action exposing [Action]
import pf.Time

Model : {
    timer_id : I32,
    event_count : I64,
    last_event : Str,
}

init! : Str => Model
init! = |_flags|
    { timer_id: 0, event_count: 0, last_event: "" }

Ev : [
    StartAfter,
    StartEvery,
    StartDebounce,
    DebounceAgain,
    CancelTimer,
    TimerFired,
    IntervalFired,
    DebounceFired,
]

update! : Model, Str, List U8 => Action Model
update! = |model, raw, _payload|
    when decode_ev(raw) is
        StartAfter ->
            timer_id = Time.after!(100, encode_ev(TimerFired))
            { model & timer_id, event_count: 0, last_event: "" } |> Action.update

        StartEvery ->
            timer_id = Time.every!(100, encode_ev(IntervalFired))
            { model & timer_id, event_count: 0, last_event: "" } |> Action.update

        StartDebounce ->
            Time.debounce!("test-key", 150, encode_ev(DebounceFired))
            { model & event_count: 0, last_event: "" } |> Action.update

        DebounceAgain ->
            Time.debounce!("test-key", 150, encode_ev(DebounceFired))
            model |> Action.update

        CancelTimer ->
            Time.cancel!(model.timer_id)
            { model & last_event: "cancelled" } |> Action.update

        TimerFired ->
            { model & event_count: model.event_count + 1, last_event: "after" } |> Action.update

        IntervalFired ->
            { model & event_count: model.event_count + 1, last_event: "every" } |> Action.update

        DebounceFired ->
            { model & event_count: model.event_count + 1, last_event: "debounce" } |> Action.update

render : Model -> Html Model
render = |model|
    div([], [
        div([id("controls")], [
            button([id("btn-after"), Event.on_click(encode_ev(StartAfter))], [text("after!")]),
            button([id("btn-every"), Event.on_click(encode_ev(StartEvery))], [text("every!")]),
            button([id("btn-debounce"), Event.on_click(encode_ev(StartDebounce))], [text("debounce!")]),
            button([id("btn-debounce-again"), Event.on_click(encode_ev(DebounceAgain))], [text("debounce again")]),
            button([id("btn-cancel"), Event.on_click(encode_ev(CancelTimer))], [text("cancel!")]),
        ]),
        div([id("event-count")], [text(Num.to_str(model.event_count))]),
        div([id("last-event")], [text(model.last_event)]),
    ])

encode_ev : Ev -> Str
encode_ev = |ev| Inspect.to_str(ev)

decode_ev : Str -> Ev
decode_ev = |raw|
    when raw is
        "StartAfter" -> StartAfter
        "StartEvery" -> StartEvery
        "StartDebounce" -> StartDebounce
        "DebounceAgain" -> DebounceAgain
        "CancelTimer" -> CancelTimer
        "TimerFired" -> TimerFired
        "IntervalFired" -> IntervalFired
        "DebounceFired" -> DebounceFired
        _ -> crash("Unsupported event: ${raw}")
