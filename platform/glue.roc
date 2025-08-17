platform ""
    requires {} { main : _ }
    exposes []
    packages {}
    imports []
    provides [main_for_host]

# The types used in here are placeholders, and usually swapped out as a workaround
# for limitations in the current RustGlue.roc implementation.
# The generated `*.rs` glue code is still helpful to copy and past and then fixup manually.

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
]

Action : [
    None,
    Update Str,
]

main_for_host : Html Action
main_for_host = main({})
