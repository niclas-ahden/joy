app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
	pf: platform "../../../../platform/main.roc",
}

import html.Html exposing [button, div, h1, p, text]
import html.Attribute exposing [aria, on_click]
import pf.Effect
import pf.Sub

Model : { count : I64 }

Msg : [UserClickedDecrement, UserClickedIncrement]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ count: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedDecrement => ({ count: model.count - 1 }, [])
		UserClickedIncrement => ({ count: model.count + 1 }, [])
	}

subscriptions : Model -> List(Sub(Msg))
subscriptions = |_model| []

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			h1([], [text("A Joy app")]),
			p([], [text("Edit client/app.roc and save. The page takes the change, and the count stays.")]),
			p(
				[],
				[
					button([on_click(UserClickedDecrement), aria("label", "One less")], [text("-")]),
					text(" ${model.count.to_str()} "),
					button([on_click(UserClickedIncrement), aria("label", "One more")], [text("+")]),
				],
			),
		],
	)
