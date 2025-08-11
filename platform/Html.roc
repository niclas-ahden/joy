module [Html]

Html state : [
    None,
    Text Str,
    Element
        {
            tag : Str,
            attrs : List { key : Str, value : Str },
            events : List { name : Str, handler : Str },
        }
        (List (Html state)),
    VoidElement
        {
            tag : Str,
            attrs : List { key : Str, value : Str },
            events : List { name : Str, handler : Str },
        },
]
