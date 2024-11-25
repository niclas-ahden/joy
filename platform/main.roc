platform ""
    requires {} { main! : {} => Str }
    exposes []
    packages {}
    imports []
    provides [mainForHost!]

mainForHost! : I32 => Str
mainForHost! = \_ -> main! {}
