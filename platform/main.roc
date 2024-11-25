platform ""
    requires { Model } {
        init : {} -> Model,
        render : Model -> Elem,
    }
    exposes [Elem]
    packages {}
    imports []
    provides [initForHost, renderForHost]

import Elem exposing [Elem]

initForHost : I32 -> Box Model
initForHost = \_ -> Box.box (init {})

Return : {
    model : Box Model,
    elem : Elem,
}

renderForHost : Box Model -> Return
renderForHost = \boxedModel ->
    {
        model : boxedModel,
        elem : render (Box.unbox boxedModel),
    }
