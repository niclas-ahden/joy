module [Html]

Html state : [
    None,
    Text Str,
    Element
        {
            tag : Str,
            attrs : List Attribute,
        }
        (List (Html state)),
    VoidElement
        {
            tag : Str,
            attrs : List Attribute,
        },
]

Attribute : [
    Boolean { key : Str, value : Bool },
    String { key : Str, value : Str },
    Event { name : Str, handler : Str, stop_propagation : Bool, prevent_default : Bool },
    Visibility { on_visible : Str, rearm_key : Str, root_margin : Str },
    # NOTE: Perhaps we want `Enumerated` attributes in the future?
    # https://developer.mozilla.org/en-US/docs/Glossary/Enumerated
]
