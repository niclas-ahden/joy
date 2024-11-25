platform ""
    requires {} { main! : {} => Str }
    exposes [
        Console
    ]
    packages {}
    imports []
    provides [mainForHost!]

mainForHost! : I32 => Str
mainForHost! = \_ -> main! {}
