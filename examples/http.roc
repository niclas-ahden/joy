app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/v0.7.0/HRdu6jPerN3MsUjXXeDjQtbBgnqUMVaKaI7yyrcVHa8.tar.br",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
}

import Decode exposing [from_bytes_partial]
import html.Attribute exposing [style]
import html.Html exposing [Html, div, pre, button, text]
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
    ClientReceivedQuote (List U8),
]

init! : Str => Model
init! = |_flags|
    # `init!` is effectful, so we can run effects and trigger Events when the app starts. We could
    # for example get a quote right away, without the user having to request one:
    #
    #     Http.get!(
    #       "https://ron-swanson-quotes.herokuapp.com/v2/quotes",
    #       encodeEvent(ClientReceivedQuote),
    #     )
    { quote: NotRequestedYet }

update! : Model, Str, List U8 => Action Model
update! = |model, raw, payload|
    when decode_event(raw, payload) is
        UserRequestedQuote ->
            Console.log!("Requesting a quote...")

            # Make an HTTP request and then trigger the `ClientReceivedQuote` event. The event will
            # have a `payload` of bytes which is either the body of a succesful request or a UTF-8
            # string with an error message.
            Http.get!(
                "https://ron-swanson-quotes.herokuapp.com/v2/quotes",
                encode_event(ClientReceivedQuote),
            )

            model |> &quote(Loading) |> Action.update

        ClientReceivedQuote(json) ->
            decoded : DecodeResult Quote
            decoded = from_bytes_partial(json, Json.utf8)

            when decoded.result is
                Ok(quote) ->
                    Console.log!("Successfully parsed JSON")

                    model
                    |> &quote(Loaded(quote))
                    |> Action.update

                Err(e) ->
                    error = "ERROR: Failed to decode JSON. Cause: ${Inspect.to_str(e)}"
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
        [style([("display", "block")])],
        [{ name: "onclick", handler: encode_event(UserRequestedQuote) }],
        [text("Treat Yo Self")],
    )

## `encodeEvent` does not take an `Event` because `Event`s may have payloads that don't make sense
## to pass in when encoding. In this example we're making HTTP requests and the
## `ClientReceivedQuote` has a payload which is the body of a successful request or an error.
##
## We want to be able to make a request and say which `Event` we want to trigger like so:
##
##     Event : [ ClientReceivedQuote Str ]
##
##     Http.get! "https://www.example.com/get-quote" (encodeEvent ClientReceivedQuote)
##
## If `encodeEvent` took `Event` we would have to pass in some nonsense payload above.
##
## Regrettably, this means that the tag `ClientReceivedQuote` _looks_ like an `Event` but it's
## not. It's just a tag that happens to look similar to the `Event` `ClientReceivedQuote Str`.
## Therefore, Roc cannot guarantee that we have written a decoder for every tag that we have an
## encoder for.
encode_event : _ -> Str
encode_event = |event| Inspect.to_str(event)

decode_event : Str, List U8 -> Event
decode_event = |raw, payload|
    when raw is
        "UserRequestedQuote" -> UserRequestedQuote
        "ClientReceivedQuote" -> ClientReceivedQuote(payload)
        _ -> crash("Unsupported event type \"${raw}\", payload \"${Str.from_utf8_lossy(payload)}\"")
