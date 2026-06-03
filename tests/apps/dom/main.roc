app [Model, init!, update!, render] {
    pf: platform "../../../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.11.0/7rgWAa6Gu3IGfdGl1JKxHQyCBVK9IUbZXbDui0jIZSQ.tar.br",
}

import html.Html exposing [Html, div, text, button, dialog]
import html.Attribute exposing [id]
import html.Event
import pf.Action exposing [Action]
import pf.DOM

Model : { status : Str, path : Str }

init! : Str => Model
init! = |flags|
    # `flags` is `location.pathname` (see index.html), so the app renders the
    # URL it booted at. The navigate test reads this to confirm it moved.
    { status: "", path: flags }

Ev : [ShowModal, CloseModal, Navigate, NavigateMissing, ReplaceUrl, PushUrl]

update! : Model, Str, List U8 => Action Model
update! = |model, raw, _payload|
    when decode_ev(raw) is
        ShowModal ->
            DOM.show_modal!("#test-dialog")
            { model & status: "opened" } |> Action.update

        CloseModal ->
            DOM.close_modal!("#test-dialog")
            { model & status: "closed" } |> Action.update

        Navigate ->
            # Full-page navigation to the same app at a distinct path. The
            # destination reboots and renders its new `location.pathname`.
            DOM.navigate!("/dom/index.html")
            Action.none

        NavigateMissing ->
            # navigate! is fire-and-forget: it doesn't validate the target, so
            # the browser still moves here even though the server 404s.
            DOM.navigate!("/dom/nope")
            Action.none

        ReplaceUrl ->
            # No reload and no new history entry, just syncs the address bar.
            DOM.replace_url!("/dom?replaced=1")
            Action.none

        PushUrl ->
            # No reload, but adds a history entry.
            DOM.push_url!("/dom?pushed=1")
            Action.none

render : Model -> Html Model
render = |model|
    div([], [
        div([id("controls")], [
            button([id("btn-show"), Event.on_click(encode_ev(ShowModal))], [text("Show modal")]),
            button([id("btn-close"), Event.on_click(encode_ev(CloseModal))], [text("Close modal")]),
            button([id("btn-navigate"), Event.on_click(encode_ev(Navigate))], [text("Navigate")]),
            button([id("btn-navigate-missing"), Event.on_click(encode_ev(NavigateMissing))], [text("Navigate to missing")]),
            button([id("btn-replace-url"), Event.on_click(encode_ev(ReplaceUrl))], [text("Replace URL")]),
            button([id("btn-push-url"), Event.on_click(encode_ev(PushUrl))], [text("Push URL")]),
        ]),
        dialog([id("test-dialog")], [
            div([id("dialog-content")], [text("Dialog is open")]),
            button([id("btn-close-inside"), Event.on_click(encode_ev(CloseModal))], [text("Close")]),
        ]),
        div([id("status")], [text(model.status)]),
        div([id("path")], [text(model.path)]),
    ])

encode_ev : Ev -> Str
encode_ev = |ev| Inspect.to_str(ev)

decode_ev : Str -> Ev
decode_ev = |raw|
    when raw is
        "ShowModal" -> ShowModal
        "CloseModal" -> CloseModal
        "Navigate" -> Navigate
        "NavigateMissing" -> NavigateMissing
        "ReplaceUrl" -> ReplaceUrl
        "PushUrl" -> PushUrl
        _ -> crash("Unsupported event: ${raw}")
