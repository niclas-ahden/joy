app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/v0.10.0/VM_GLBCvmmdZAxFHzkRqOX2YHYxt4qPVrs5Omm2L374.tar.br",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
}

import Decode exposing [from_bytes_partial]
import html.Attribute exposing [style]
import html.Html exposing [Html, div, pre, button, text]
import html.Event
import json.Json
import pf.Action exposing [Action]
import pf.Console
import pf.Http

Model : {
    quote : [
        NotRequestedYet,
        Loading,
        Loaded Quote,
        Error Str,
    ],
}

Quote : List Str

Event : [
    UserRequestedQuote,
    ClientReceivedQuote,
]

init! : Str => Model
init! = |_flags|
    # `init!` is effectful, so we can run effects and trigger Events when the app starts. We could
    # for example get a quote right away, without the user having to request one.
    { quote: NotRequestedYet }

update! : Model, Str, List U8 => Action Model
update! = |model, raw, payload|
    when decode_event(raw, payload) is
        UserRequestedQuote ->
            Console.log!("Requesting a quote...")

            # Make an HTTP request and then trigger the `ClientReceivedQuote` event.
            Http.get!(
                "https://ron-swanson-quotes.herokuapp.com/v2/quotes",
                encode_event(ClientReceivedQuote),
            )

            model |> &quote(Loading) |> Action.update

        ClientReceivedQuote ->
            # You might expect that we'd get ClientReceivedQuote(HttpReponse) or such because that's neat. However,
            # it's early days, and not everything's tip-top yet. We'll get everything sorted as we go, but for now,
            # here's how we handle HTTP:
            #
            # The `payload` of an event is always passed in to the `update!` function and it's a `List U8`. You then
            # decode those bytes into whatever makes sense for the type of effect you're running. For an HTTP effect
            # the `payload` will contain the bytes of a JSON string like:
            #
            #      {"ok": {"status": 200, "body": [...]}}
            #      or
            #      {"err": "..."}
            #
            # You can decode that into a neat type and voilà: you're where you wanted to be.
            #
            # The ergonomics of this will be improved after Roc v0.1.
            when decode_http_response(payload) is
                Ok({ status, body }) ->
                    Console.log!("Received HTTP response with status: ${Num.to_str(status)}")
                    # Now decode the actual quote JSON from the body
                    quote_decoded : DecodeResult Quote
                    quote_decoded = from_bytes_partial(body, Json.utf8)
                    when quote_decoded.result is
                        Ok(quote) ->
                            Console.log!("Successfully parsed quote JSON")
                            model
                            |> &quote(Loaded(quote))
                            |> Action.update

                        Err(e) ->
                            error = "Failed to decode quote JSON. Cause: ${Inspect.to_str(e)}, Response: ${Str.from_utf8_lossy(payload)}"
                            Console.log!(error)
                            model |> &quote(Error(error)) |> Action.update

                Err(HttpErr(msg)) ->
                    error = "HTTP request failed: ${msg}"
                    Console.log!(error)
                    model |> &quote(Error(error)) |> Action.update

                Err(DecodingFailed(e)) ->
                    response_text = Str.from_utf8_lossy(payload)
                    error = "Failed to decode HTTP response JSON. Cause: ${Inspect.to_str(e)}, Response: ${response_text}"
                    Console.log!(error)
                    model |> &quote(Error(error)) |> Action.update

render : Model -> Html Model
render = |model|
    when model.quote is
        NotRequestedYet ->
            div(
                [],
                [
                    text("Would you like a Ron Swanson quote?"),
                    request_quote_button_view,
                ],
            )

        Loading -> div([], [text("Getting a quote...")])
        Loaded(quote) ->
            div(
                [],
                [
                    text("Ron once said:"),
                    pre([], [Str.join_with(quote, "\n") |> text]),
                    request_quote_button_view,
                ],
            )

        Error(error) ->
            div(
                [],
                [
                    text("Couldn't get quote, cause: ${error}"),
                    request_quote_button_view,
                ],
            )

request_quote_button_view : Html Model
request_quote_button_view =
    button(
        [style([("display", "block")]), Event.on_click(encode_event(UserRequestedQuote))],
        [text("Treat Yo Self")],
    )

encode_event : Event -> Str
encode_event = |event| Inspect.to_str(event)

decode_event : Str, List U8 -> Event
decode_event = |raw, payload|
    when raw is
        "UserRequestedQuote" -> UserRequestedQuote
        "ClientReceivedQuote" -> ClientReceivedQuote
        _ -> crash("Unsupported event type \"${raw}\", payload \"${Str.from_utf8_lossy(payload)}\"")

decode_http_response : List U8 -> Result { status : U16, body : List U8 } [HttpErr Str, DecodingFailed _]
decode_http_response = |payload|
    when Decode.from_bytes_partial(payload, Json.utf8).result is
        Ok({ ok }) -> Ok(ok)
        Err(_) ->
            when Decode.from_bytes_partial(payload, Json.utf8).result is
                Ok({ err }) -> Err(HttpErr(err))
                Err(e) -> Err(DecodingFailed(e))
