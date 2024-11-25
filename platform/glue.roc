platform ""
    requires {} {  main : _}
    exposes []
    packages {}
    imports []
    provides [mainForHost]

Elem : [
    Text Str,
    Div Elem,
]

mainForHost : Elem
mainForHost = main {}
