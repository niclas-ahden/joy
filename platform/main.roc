platform ""
    requires { Model } {
        init! : {} => Model,
        update! : Model, Str, Str => Action.Action Model,
        render : Model -> Html.Html Model,
    }
    exposes [Html, Action]
    packages {}
    imports []
    provides [init_for_host!, update_for_host!, render_for_host]

import Html
import Action

init_for_host! : I32 => Box Model
init_for_host! = |_| Box.box(init!({}))

update_for_host! : Box Model, Str, Str => Action.Action (Box Model)
update_for_host! = |boxed_model, raw_event, event_payload|
    Action.map(update!(Box.unbox(boxed_model), raw_event, event_payload), Box.box)

render_for_host : Box Model -> Html.Html Model
render_for_host = |boxed_model| render(Box.unbox(boxed_model))
