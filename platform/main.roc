platform ""
    requires {} { main! : {} => Result {} [Exit I32 Str]_ }
    exposes [Stdout]
    packages {}
    imports []
    provides [mainForHost!]

import Effect

mainForHost! : I32 => I32
mainForHost! = \_ ->
    when main! {} is
        Ok {} -> 0
        Err (Exit code str) ->
            if Str.isEmpty str then
                code
            else
                Effect.log! str
                code

        Err other ->
            Effect.log! "Program exited early with error: $(Inspect.toStr other)"
            1
