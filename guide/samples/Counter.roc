import html.Html
import html.Attribute exposing [on_click]
import pf.Effect

Counter := [].{
	Model : { count : I64 }

	Msg : [Bump]

	update : Model, Msg -> (Model, List(Effect(Msg)))
	update = |model, Bump| ({ count: model.count + 1 }, [])

	view : Model -> Html(Msg)
	view = |model| Html.button([on_click(Bump)], [Html.text(model.count.to_str())])
}
