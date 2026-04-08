app [Model, init!, update!, render] {
    pf: platform "../../../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.11.0/7rgWAa6Gu3IGfdGl1JKxHQyCBVK9IUbZXbDui0jIZSQ.tar.br",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
}

import html.Html exposing [Html, div, text, input, button, ul, li, span]
import html.Attribute exposing [id, class, attribute]
import html.Event
import pf.Action exposing [Action]
import pf.Crypto
import json.Json

Config : { chunk_size : U64, algorithm : Crypto.HashAlgorithm, parallelism : Crypto.Parallelism }

Model : {
    config : Config,
    chunk_events : List ChunkEvent,
    done_result : Str,
    error : Str,
}

ChunkEvent : { chunk_index : U64, starts_at_byte : U64, ends_at_byte : U64, hash : Str, total_chunks : U64 }

init! : Str => Model
init! = |flags|
    config = parse_config(flags)
    { config, chunk_events: [], done_result: "", error: "" }

parse_config : Str -> Config
parse_config = |flags|
    parsed : Result { chunk_size : U64, algorithm : Str, parallelism : I64 } _
    parsed = Decode.from_bytes_partial(Str.to_utf8(flags), Json.utf8).result

    when parsed is
        Ok({ chunk_size, algorithm, parallelism }) ->
            {
                chunk_size,
                algorithm: parse_algorithm(algorithm),
                parallelism: if parallelism <= 0 then UseAllCores else Exact(Num.to_u32(parallelism)),
            }

        Err(_) ->
            { chunk_size: 10, algorithm: Sha1, parallelism: Exact(2) }

parse_algorithm : Str -> Crypto.HashAlgorithm
parse_algorithm = |s|
    when s is
        "SHA-1" -> Sha1
        "SHA-256" -> Sha256
        "SHA-384" -> Sha384
        "SHA-512" -> Sha512
        _ -> Sha1

Ev : [UserSelectedFile, HashInvalidId, ChunkHashed, AllChunksHashed]

update! : Model, Str, List U8 => Action Model
update! = |model, raw, payload|
    when decode_ev(raw) is
        UserSelectedFile ->
            file_meta_result : Result { file_id : I64 } _
            file_meta_result = Decode.from_bytes_partial(payload, Json.utf8).result

            when file_meta_result is
                Ok({ file_id }) ->
                    fid : U32
                    fid = Num.to_u32(file_id)
                    Crypto.hash_file_chunks!(fid, {
                        algorithm: model.config.algorithm,
                        chunk_size_bytes: model.config.chunk_size,
                        parallelism: model.config.parallelism,
                        chunk_event: encode_ev(ChunkHashed),
                        done_event: encode_ev(AllChunksHashed),
                    })
                    { model & chunk_events: [], done_result: "", error: "" }
                    |> Action.update

                Err(_) ->
                    { model & error: "Failed to decode file metadata" }
                    |> Action.update

        HashInvalidId ->
            Crypto.hash_file_chunks!(999, {
                algorithm: Sha1,
                chunk_size_bytes: 10,
                parallelism: Exact(1),
                chunk_event: encode_ev(ChunkHashed),
                done_event: encode_ev(AllChunksHashed),
            })
            { model & chunk_events: [], done_result: "", error: "" }
            |> Action.update

        ChunkHashed ->
            chunk_result : Result { total_chunks : U64, chunk : { index : U64, starts_at_byte : U64, ends_at_byte : U64, hash : Str } } _
            chunk_result = Decode.from_bytes_partial(payload, Json.utf8).result

            when chunk_result is
                Ok({ total_chunks, chunk }) ->
                    event : ChunkEvent
                    event = {
                        chunk_index: chunk.index,
                        starts_at_byte: chunk.starts_at_byte,
                        ends_at_byte: chunk.ends_at_byte,
                        hash: chunk.hash,
                        total_chunks,
                    }
                    { model & chunk_events: model.chunk_events |> List.append(event) }
                    |> Action.update

                Err(_) ->
                    { model & error: "Failed to decode chunk event" }
                    |> Action.update

        AllChunksHashed ->
            done_str = payload |> Str.from_utf8 |> Result.with_default("decode error")
            { model & done_result: done_str }
            |> Action.update

render : Model -> Html Model
render = |model|
    div([], [
        div([id("controls")], [
            input([Attribute.type("file"), id("file-input"), Event.on_change(encode_ev(UserSelectedFile))]),
            button([id("btn-hash-invalid"), Event.on_click(encode_ev(HashInvalidId))], [text("Hash invalid ID")]),
        ]),
        div([id("error")], [text(model.error)]),
        div([id("done-result")], [text(model.done_result)]),
        div([id("chunk-count")], [text(Num.to_str(List.len(model.chunk_events)))]),
        ul(
            [id("chunk-events")],
            model.chunk_events
            |> List.sort_with(|a, b| Num.compare(a.chunk_index, b.chunk_index))
            |> List.map(|chunk|
                li([class("chunk"), attribute("data-index", Num.to_str(chunk.chunk_index))], [
                    span([class("hash")], [text(chunk.hash)]),
                    span([class("start")], [text(Num.to_str(chunk.starts_at_byte))]),
                    span([class("end")], [text(Num.to_str(chunk.ends_at_byte))]),
                    span([class("total")], [text(Num.to_str(chunk.total_chunks))]),
                ])
            ),
        ),
    ])

encode_ev : Ev -> Str
encode_ev = |ev| Inspect.to_str(ev)

decode_ev : Str -> Ev
decode_ev = |raw|
    when raw is
        "UserSelectedFile" -> UserSelectedFile
        "HashInvalidId" -> HashInvalidId
        "ChunkHashed" -> ChunkHashed
        "AllChunksHashed" -> AllChunksHashed
        _ -> crash("Unsupported event: ${raw}")
