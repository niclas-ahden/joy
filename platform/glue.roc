platform ""
    requires {} { main : _ }
    exposes []
    packages {}
    imports []
    provides [mainForHost]

# the types used in here are placeholders, and usually swapped out as a workaround
# for limitations in the current RustGlue.roc implementation
# the generated `*.rs` glue code is still helpful to copy and past and then fixup manually

Html : [
    None,
    Text Str,
    Element
        {
            tag : Str,
            attrs : List { key : Str, value : Str },
            events : List { name : Str, handler : Str },
        }
        (List Html),
]

# Action : [
#    None,
#    Update Str,
# ]

mainForHost : Html
mainForHost = main {}
