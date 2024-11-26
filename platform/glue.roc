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
            attrs : List U64,
            events : List { name : Str, handler : List U8 },
        }
        (List Html),
]

#Action : [
#    None,
#    Update (List U8),
#]

#PlatformState : {
#    boxedModel : List U64,
#    handlers : List U64,
#    htmlHandlerIds : HtmlForHost,
#}

mainForHost : Html
mainForHost = main {}
