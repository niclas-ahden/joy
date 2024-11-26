platform ""
    requires { Model } {
        init : {} -> Model,
        render : Model -> Html.Html Model,
    }
    exposes [Html, Action]
    packages {}
    imports []
    provides [initForHost, updateForHost, renderForHost]

import Html
import InnerHtml
import Action

PlatformState model : {
    boxedModel : Box model,
    handlers : List (InnerHtml.EventForApp model),
    htmlHandlerIds : InnerHtml.HtmlForHost,
}

initForHost : I32 -> PlatformState Model
initForHost = \_ -> {
    boxedModel: Box.box (init {}),
    handlers: [],
    htmlHandlerIds: None,
}

updateForHost : PlatformState Model, U64 -> Action.Action (Box Model)
updateForHost = \{ boxedModel, handlers }, eventId ->

    model = Box.unbox boxedModel

    when List.get handlers eventId is
        Err OutOfBounds -> crash "unreachable, got a bad event id from host"
        Ok { handler } -> handler model |> Action.map Box.box

renderForHost : Box Model -> PlatformState Model
renderForHost = \boxedModel ->

    htmlHandlerFns = render (Box.unbox boxedModel)

    (htmlHandlerIds, handlers) = InnerHtml.prepareForHost htmlHandlerFns 0 []

    { boxedModel, handlers, htmlHandlerIds }
