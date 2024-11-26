module [
    Html,
    Event,
    translate,
    text,
    div,
]

import InnerHtml

Html state : InnerHtml.HtmlForApp state
Event state : InnerHtml.EventForApp state

translate = InnerHtml.translateHtmlForApp

text : Str -> Html state
text = \str -> Text str

div : List (Str, Str), List (Event state), List (Html state) -> Html state
div = \attrs, events, children ->
    Element { tag: "div", attrs, events } children
