platform ""
    requires { Model } {
        init! : Str => Model,
        update! : Model, Str, List U8 => Action.Action Model,
        render : Model -> Html.Html Model,
    }
    exposes [Html, Action, Keyboard]
    packages {}
    imports []
    provides [init_for_host!, update_for_host!, render_for_host]

import Html
import Action
import Keyboard

init_for_host! : Str => Box Model
init_for_host! = |flags| Box.box(init!(flags))

update_for_host! : Box Model, Str, List U8 => Action.Action (Box Model)
update_for_host! = |boxed_model, raw_event, event_payload|
    Action.map(update!(Box.unbox(boxed_model), raw_event, event_payload), Box.box)

render_for_host : Box Model -> Html.Html Model
render_for_host = |boxed_model| render(Box.unbox(boxed_model))
