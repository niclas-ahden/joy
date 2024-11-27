module [
    Html,
    translate,
    text,
    div,
]

Html state : [
    None,
    Text Str,
    Element
        {
            tag : Str,
            attrs : List { key: Str, value: Str },
            events : List { name : Str, handler : List U8 },
        }
        (List (Html state)),
]

translate : Html child, (parent -> child), (parent, child -> parent) -> Html parent
translate = \elem, parentToChild, childToParent ->
    when elem is
        None ->
            None

        Text str ->
            Text str

        Element { tag, attrs, events } children ->
            Element
                { tag, attrs, events }
                (List.map children \c -> translate c parentToChild childToParent)

text : Str -> Html state
text = \str -> Text str

div : List { key: Str, value: Str },, List { name : Str, handler : List U8 }, List (Html state) -> Html state
div = \attrs, events, children ->
    Element { tag: "div", attrs, events } children
