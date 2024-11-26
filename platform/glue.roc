platform ""
    requires {} { main : _ }
    exposes []
    packages {}
    imports []
    provides [mainForHost]

# the types used in here are placeholders, and usually swapped out as a workaround
# for limitations in the current RustGlue.roc implementation
# the generated `*.rs` glue code is still helpful to copy and past and then fixup manually

HtmlForHost : [
    None,
    Text Str,
    Element
        {
            tag : Str,
            attrs : List { key : Str, val : Str },
            events : List U64,
        }
        (List HtmlForHost),
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

mainForHost : HtmlForHost
mainForHost = main {}
