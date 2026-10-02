## The counter page. A page is a plain module that owns its own Model, Msg,
## init, update, view and subscriptions, exactly like an app does, only the
## app in app.roc calls them instead of the platform. Nothing here knows that
## other pages exist, so the page can be written, read and tested on its own.
import html.Html exposing [button, div, h2, input, label, p, text]
import html.Attribute exposing [id, on_click, on_input, type, value]
import pf.Effect
import pf.Sub

Counter := [].{
	## The count, how far one click moves it, and the clicks so far, so the
	## page has state of its own to keep across visits to the other pages.
	Model : { count : I64, step : I64, clicks : U64 }

	Msg : [
		UserClickedIncrement,
		UserClickedDecrement,
		UserChangedStep(Str),
		UserClickedReset,
	]

	init : {} -> (Model, List(Effect(Msg)))
	init = |_| ({ count: 0, step: 1, clicks: 0 }, [])

	update : Model, Msg -> (Model, List(Effect(Msg)))
	update = |model, msg|
		match msg {
			UserClickedIncrement =>
				({ ..model, count: model.count + model.step, clicks: model.clicks + 1 }, [])

			UserClickedDecrement =>
				({ ..model, count: model.count - model.step, clicks: model.clicks + 1 }, [])

			# The step field is a controlled input: the model holds the number
			# and the view prints it back, so anything that isn't a number is
			# dropped on the floor and the field snaps back to the last step.
			UserChangedStep(raw) =>
				match I64.from_str(raw) {
					Ok(step) => ({ ..model, step }, [])
					Err(_) => (model, [])
				}

			UserClickedReset => ({ ..model, count: 0, clicks: 0 }, [])
		}

	subscriptions : Model -> List(Sub(Msg))
	subscriptions = |_model| []

	view : Model -> Html(Msg)
	view = |model|
		div(
			[id("counter")],
			[
				h2([], [text("Counter")]),
				p([id("count")], [text(model.count.to_str())]),
				button([id("decrement"), on_click(UserClickedDecrement)], [text("-")]),
				button([id("increment"), on_click(UserClickedIncrement)], [text("+")]),
				button([id("reset"), on_click(UserClickedReset)], [text("Reset")]),
				p(
					[],
					[
						label([], [text("Step ")]),
						input([id("step"), type("number"), value(model.step.to_str()), on_input(|s| UserChangedStep(s))]),
					],
				),
				p([id("clicks")], [text("${model.clicks.to_str()} clicks so far")]),
			],
		)
}
