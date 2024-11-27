platform ""
    requires { Model } {
        init : {} -> Model,
        update : Model, List U8 -> Action.Action Model,
        render : Model -> Html.Html Model,
    }
    exposes [Html, Action]
    packages {}
    imports []
    provides [initForHost, updateForHost, renderForHost]

import Html
import Html
import Action

initForHost : I32 -> Box Model
initForHost = \_ -> Box.box (init {})

updateForHost : Box Model, List U8 -> Action.Action (Box Model)
updateForHost = \boxedModel, payload ->
    Action.map (update (Box.unbox boxedModel) payload) Box.box

renderForHost : Box Model -> Html.Html Model
renderForHost = \boxedModel -> render (Box.unbox boxedModel)
