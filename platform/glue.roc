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

Return : {
    model : I64,
    elem : Elem,
}

mainForHost : Return
mainForHost = main {}
