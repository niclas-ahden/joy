platform ""
    requires {} { main : _ }
    exposes []
    packages {}
    imports []
    provides [mainForHost]

HtmlForHost : [
    Text Str,
    Element
        {
            tag : Str,
            attrs : List { key : Str, val : Str },
            events : List U64,
        }
        (List HtmlForHost),
]

Action : [
    None,
    Update (List U8),
]

mainForHost : Action
mainForHost = main {}
