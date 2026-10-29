import html.Html exposing [button, div, h1, p, text]
import html.Attribute exposing [on_click]
import pf.Effect
import pf.Sub

## The first page, with state of its own: a count. A page has the same parts
## as an app, and the app calls them.
Home := [].{
	Model : { count : I64 }

	Msg : [UserClickedIncrement, UserClickedDecrement]

	init : {} -> (Model, List(Effect(Msg)))
	init = |{}| ({ count: 0 }, [])

	update : Model, Msg -> (Model, List(Effect(Msg)))
	update = |model, msg|
		match msg {
			UserClickedIncrement => ({ count: model.count + 1 }, [])
			UserClickedDecrement => ({ count: model.count - 1 }, [])
		}

	subscriptions : Model -> List(Sub(Msg))
	subscriptions = |_model| []

	view : Model -> Html(Msg)
	view = |model|
		div(
			[],
			[
				h1([], [text("Home")]),
				p([], [text("Edit client/Page/Home.roc and save. The page takes the change.")]),
				button([on_click(UserClickedDecrement)], [text("-")]),
				text(" ${model.count.to_str()} "),
				button([on_click(UserClickedIncrement)], [text("+")]),
			],
		)
}
