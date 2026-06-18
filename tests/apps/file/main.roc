app [Model, init!, update!, render] {
    pf: platform "../../../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.11.0/7rgWAa6Gu3IGfdGl1JKxHQyCBVK9IUbZXbDui0jIZSQ.tar.br",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
}

import html.Html exposing [Html, div, text, input, button]
import html.Attribute exposing [id]
import html.Event
import pf.Action exposing [Action]
import pf.File
import json.Json

# `start` and `len` are supplied as query params by index.html so a single app
# can exercise reads at any offset/length.
Config : { start : U64, len : U64 }

Model : {
    config : Config,
    # Raw event payload, so tests can assert on the error shape.
    result : Str,
    # The returned bytes rendered as comma-joined decimals, e.g. "80,75,3,4".
    bytes_csv : Str,
    byte_count : U64,
    error : Str,
}

init! : Str => Model
init! = |flags|
    { config: parse_config(flags), result: "", bytes_csv: "", byte_count: 0, error: "" }

parse_config : Str -> Config
parse_config = |flags|
    parsed : Result { start : U64, len : U64 } _
    parsed = Decode.from_bytes_partial(Str.to_utf8(flags), Json.utf8).result
    when parsed is
        Ok(c) -> c
        Err(_) -> { start: 0, len: 12 }

Ev : [UserSelectedFile, ReadInvalidId, BytesRead]

update! : Model, Str, List U8 => Action Model
update! = |model, raw, payload|
    when decode_ev(raw) is
        UserSelectedFile ->
            meta : Result { file_id : I64 } _
            meta = Decode.from_bytes_partial(payload, Json.utf8).result
            when meta is
                Ok({ file_id }) ->
                    fid : U32
                    fid = Num.to_u32(file_id)
                    File.read_bytes_at!(fid, model.config.start, model.config.len, encode_ev(BytesRead))
                    { model & result: "", bytes_csv: "", byte_count: 0, error: "" }
                    |> Action.update

                Err(_) ->
                    { model & error: "Failed to decode file metadata" }
                    |> Action.update

        ReadInvalidId ->
            File.read_bytes_at!(999, 0, 4, encode_ev(BytesRead))
            { model & result: "", bytes_csv: "", byte_count: 0, error: "" }
            |> Action.update

        BytesRead ->
            result_str = payload |> Str.from_utf8 |> Result.with_default("decode error")
            decoded : Result { bytes : List U8 } _
            decoded = Decode.from_bytes_partial(payload, Json.utf8).result
            when decoded is
                Ok({ bytes }) ->
                    csv = bytes |> List.map(Num.to_str) |> Str.join_with(",")
                    { model & result: result_str, bytes_csv: csv, byte_count: List.len(bytes) }
                    |> Action.update

                Err(_) ->
                    { model & result: result_str }
                    |> Action.update

render : Model -> Html Model
render = |model|
    div([], [
        div([id("controls")], [
            input([Attribute.type("file"), id("file-input"), Event.on_change(encode_ev(UserSelectedFile))]),
            button([id("btn-read-invalid"), Event.on_click(encode_ev(ReadInvalidId))], [text("Read invalid ID")]),
        ]),
        div([id("error")], [text(model.error)]),
        div([id("result")], [text(model.result)]),
        div([id("byte-count")], [text(Num.to_str(model.byte_count))]),
        div([id("bytes")], [text(model.bytes_csv)]),
    ])

encode_ev : Ev -> Str
encode_ev = |ev| Inspect.to_str(ev)

decode_ev : Str -> Ev
decode_ev = |raw|
    when raw is
        "UserSelectedFile" -> UserSelectedFile
        "ReadInvalidId" -> ReadInvalidId
        "BytesRead" -> BytesRead
        _ -> crash("Unsupported event: ${raw}")
