platform ""
    requires { Model } {
        init! : {} => Model,
        update! : Model, Str, Str => Action.Action Model,
        render : Model -> Html.Html Model,
    }
    exposes [Html, Action]
    packages {}
    imports []
    provides [initForHost!, updateForHost!, renderForHost]

import Html
import Action

initForHost! : I32 => Box Model
initForHost! = \_ -> Box.box (init! {})

updateForHost! : Box Model, Str, Str => Action.Action (Box Model)
updateForHost! = \boxedModel, rawEvent, eventPayload ->
    Action.map (update! (Box.unbox boxedModel) rawEvent eventPayload) Box.box

renderForHost : Box Model -> Html.Html Model
renderForHost = \boxedModel -> render (Box.unbox boxedModel)
