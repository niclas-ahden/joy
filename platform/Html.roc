module [Html]

Html state : [
    None,
    Text Str,
    Element
        {
            tag : Str,
            attrs : List Attribute,
            events : List { name : Str, handler : Str },
        }
        (List (Html state)),
    VoidElement
        {
            tag : Str,
            attrs : List Attribute,
            events : List { name : Str, handler : Str },
        },
]

Attribute : [
    Boolean { key : Str, value : Bool },
    String { key : Str, value : Str },
    # NOTE: Perhaps we want `Enumerated` attributes in the future?
    # https://developer.mozilla.org/en-US/docs/Glossary/Enumerated
]
