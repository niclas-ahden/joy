app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.12.0/YuDkYcO06nJ7XHn3vR0vGETvUp1PGiE8LDJVJV15yZo.tar.br",
    url: "https://github.com/niclas-ahden/roc-url/releases/download/v0.4.0/iznLM3TyHqI5VtPBwGY1rRhyVtW7i6we85HfBVRHKfQ.tar.br",
}

import html.Html exposing [Html, div, h1, h2, p, input, button, text]
import html.Attribute exposing [placeholder]
import html.Event
import pf.Action exposing [Action]
import pf.DOM
import url.Url

# This example shows the three ways to change the URL from a Joy app:
#
#   DOM.replace_url!  rewrite the URL in place, no reload, no history entry
#   DOM.push_url!     change the URL, no reload, adds a history entry
#   DOM.navigate!     a full page load (leaves the current page)
#
# Type in the search box and watch the address bar: the `?q=...` follows what
# you type, but Back does not step through every keystroke. That is the job
# replace_url! is built for. The buttons below show how push_url! and navigate!
# differ.

Model : Str

init! : Str => Model
init! = |flags|
    # `flags` is expected to be the URL search string, e.g. "?q=hats%20on". Wire
    # www/index.html with `run(location.search)` so a shared or refreshed link
    # starts with the box filled in.
    query_from_search(flags)

## Pull the `q` parameter out of a URL search string and percent-decode it back
## to plain text, so "?q=hats%20on" becomes "hats on". query_params leaves the
## value percent-encoded, so we decode it ourselves.
query_from_search : Str -> Str
query_from_search = |search|
    params = Url.query_params(Url.from_str(search))
    when Dict.get(params, "q") is
        Ok(encoded) -> Url.percent_decode(encoded) |> Result.with_default("")
        Err(_) -> ""

Event : [
    UserTypedQuery Str,
    UserClickedPush,
    UserClickedReload,
]

update! : Model, Str, List U8 => Action Model
update! = |_model, raw, payload|
    when decode_event(raw, payload) is
        UserTypedQuery(query) ->
            # Percent-encode the query so spaces and special characters are safe
            # in the URL, then sync it into the address bar without growing
            # history.
            encoded = Url.percent_encode(query)
            DOM.replace_url!("?q=${encoded}")
            query |> Action.update

        UserClickedPush ->
            # Adds a history entry, so Back returns to where you were.
            DOM.push_url!("?demo=push")
            Action.none

        UserClickedReload ->
            # A full page load. The query you typed is lost because init! runs
            # again, unlike the two effects above which keep the Model intact.
            DOM.navigate!("?reloaded=1")
            Action.none

render : Model -> Html Model
render = |model|
    div(
        [],
        [
            h1([], [text("Navigation")]),
            h2([], [text("replace_url!: search as you type")]),
            input([placeholder("Search..."), Event.on_input(encode_event(UserTypedQuery))]),
            p([], [text("Current query: ${model}")]),
            p([], [text("The address bar shows ?q=... as you type, but Back does not record every keystroke.")]),
            h2([], [text("push_url!: adds a history entry")]),
            button([Event.on_click(encode_event(UserClickedPush))], [text("Push ?demo=push")]),
            p([], [text("Changes the URL without reloading and lets Back return here. Joy has no router, so the view does not react to Back/Forward on its own.")]),
            h2([], [text("navigate!: full page load")]),
            button([Event.on_click(encode_event(UserClickedReload))], [text("Reload with ?reloaded=1")]),
            p([], [text("Leaves the current page. Notice the query above resets, because the app re-initialises.")]),
        ],
    )

# See examples/events_input.roc for why encode_event takes a bare tag rather
# than an Event: the typed text arrives as the event payload, so we must not
# supply a payload when encoding.
encode_event : _ -> Str
encode_event = |event| Inspect.to_str(event)

decode_event : Str, List U8 -> Event
decode_event = |raw, payload|
    when raw is
        "UserTypedQuery" -> UserTypedQuery(Str.from_utf8_lossy(payload))
        "UserClickedPush" -> UserClickedPush
        "UserClickedReload" -> UserClickedReload
        _ -> crash("Unsupported event type \"${raw}\"")
