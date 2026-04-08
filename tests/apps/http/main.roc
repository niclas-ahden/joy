app [Model, init!, update!, render] {
    pf: platform "../../../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.11.0/7rgWAa6Gu3IGfdGl1JKxHQyCBVK9IUbZXbDui0jIZSQ.tar.br",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
}

import html.Html exposing [Html, div, text, input, button]
import html.Attribute exposing [id, attribute]
import html.Event
import pf.Action exposing [Action]
import pf.Http
import json.Json

Model : {
    response : Str,
    error : Str,
    status : Str,
}

init! : Str => Model
init! = |_flags|
    { response: "", error: "", status: "" }

Ev : [
    UserSelectedFile,
    PostFile,
    PostFileSlice,
    PutFile,
    PutFileSlice,
    PostBody,
    PostEmptyBody,
    PutBody,
    GetRequest,
    GetError500,
    PostError500,
    Response,
]

update! : Model, Str, List U8 => Action Model
update! = |model, raw, payload|
    when decode_ev(raw) is
        UserSelectedFile ->
            Action.none

        PostFile ->
            Http.post_file!("/echo", File(1), [("X-Test-Header", "post-file-value")], encode_ev(Response))
            { model & response: "", error: "", status: "" } |> Action.update

        PostFileSlice ->
            Http.post_file!("/echo", Slice({ file: 1, start: 2, len: 5 }), [("X-Slice", "true")], encode_ev(Response))
            { model & response: "", error: "", status: "" } |> Action.update

        PutFile ->
            Http.put_file!("/echo", File(1), [("X-Test-Header", "put-file-value")], encode_ev(Response))
            { model & response: "", error: "", status: "" } |> Action.update

        PutFileSlice ->
            Http.put_file!("/echo", Slice({ file: 1, start: 0, len: 5 }), [("X-Slice", "true")], encode_ev(Response))
            { model & response: "", error: "", status: "" } |> Action.update

        PostBody ->
            Http.post!("/echo", Str.to_utf8("hello from post"), encode_ev(Response))
            { model & response: "", error: "", status: "" } |> Action.update

        PostEmptyBody ->
            Http.post!("/echo", [], encode_ev(Response))
            { model & response: "", error: "", status: "" } |> Action.update

        PutBody ->
            Http.put!("/echo", Str.to_utf8("hello from put"), encode_ev(Response))
            { model & response: "", error: "", status: "" } |> Action.update

        GetRequest ->
            Http.get!("/echo", encode_ev(Response))
            { model & response: "", error: "", status: "" } |> Action.update

        GetError500 ->
            Http.get!("/error-500", encode_ev(Response))
            { model & response: "", error: "", status: "" } |> Action.update

        PostError500 ->
            Http.post!("/error-500", Str.to_utf8("test"), encode_ev(Response))
            { model & response: "", error: "", status: "" } |> Action.update

        Response ->
            { body, status_code } = extract_response(payload)
            { model & response: body, status: Num.to_str(status_code) } |> Action.update

render : Model -> Html Model
render = |model|
    div([], [
        div([id("controls")], [
            input([Attribute.type("file"), id("file-input"), Event.on_change(encode_ev(UserSelectedFile))]),
            button([id("btn-post-file"), Event.on_click(encode_ev(PostFile))], [text("POST file")]),
            button([id("btn-post-file-slice"), Event.on_click(encode_ev(PostFileSlice))], [text("POST file slice")]),
            button([id("btn-put-file"), Event.on_click(encode_ev(PutFile))], [text("PUT file")]),
            button([id("btn-put-file-slice"), Event.on_click(encode_ev(PutFileSlice))], [text("PUT file slice")]),
            button([id("btn-post-body"), Event.on_click(encode_ev(PostBody))], [text("POST body")]),
            button([id("btn-post-empty"), Event.on_click(encode_ev(PostEmptyBody))], [text("POST empty")]),
            button([id("btn-put-body"), Event.on_click(encode_ev(PutBody))], [text("PUT body")]),
            button([id("btn-get"), Event.on_click(encode_ev(GetRequest))], [text("GET")]),
            button([id("btn-get-500"), Event.on_click(encode_ev(GetError500))], [text("GET 500")]),
            button([id("btn-post-500"), Event.on_click(encode_ev(PostError500))], [text("POST 500")]),
        ]),
        div([id("response")], [text(model.response)]),
        div([id("status")], [text(model.status)]),
        div([id("error")], [text(model.error)]),
    ])

## Extract body and status from Joy HTTP response event payload.
## Joy wraps responses as: {"ok":{"status":200,"body":[...]}} or {"err":"message"}
extract_response : List U8 -> { body : Str, status_code : U16 }
extract_response = |payload|
    ok_result : Result { ok : { status : U16, body : List U8 } } _
    ok_result = Decode.from_bytes_partial(payload, Json.utf8).result
    when ok_result is
        Ok({ ok }) ->
            body_str = ok.body |> Str.from_utf8 |> Result.with_default("body not utf8")
            { body: body_str, status_code: ok.status }

        Err(_) ->
            raw = payload |> Str.from_utf8 |> Result.with_default("decode error")
            { body: raw, status_code: 0 }

encode_ev : Ev -> Str
encode_ev = |ev| Inspect.to_str(ev)

decode_ev : Str -> Ev
decode_ev = |raw|
    when raw is
        "UserSelectedFile" -> UserSelectedFile
        "PostFile" -> PostFile
        "PostFileSlice" -> PostFileSlice
        "PutFile" -> PutFile
        "PutFileSlice" -> PutFileSlice
        "PostBody" -> PostBody
        "PostEmptyBody" -> PostEmptyBody
        "PutBody" -> PutBody
        "GetRequest" -> GetRequest
        "GetError500" -> GetError500
        "PostError500" -> PostError500
        "Response" -> Response
        _ -> crash("Unsupported event: ${raw}")
