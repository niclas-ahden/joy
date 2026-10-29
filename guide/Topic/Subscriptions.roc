import html.Html exposing [code, h1, h2, p, text]
import html.Attribute exposing [class]
import /Doc

## The topic "Subscriptions".
Subscriptions := [].{
	body : Doc.Body
	body = [
		p([class("eyebrow")], [text("Start here")]),
		h1([], [text("Subscriptions")]),
		p(
			[class("lead")],
			[
				text("An effect happens once. A subscription keeps sending messages for as long as the app asks for it."),
			],
		),
		p(
			[],
			[
				text("After every update Joy calls "),
				code([], [text("subscriptions")]),
				text(" with the new model. Whatever list it returns is what the app listens to from then on. A subscription you stop returning is stopped."),
			],
		),
		p(
			[],
			[
				text("Have a look at this ticker 👇 "),
				code([], [text("Time.every")]),
				text(" sends a "),
				code([], [text("Tick")]),
				text(" every second, and each one raises your excitement level for Roc. Press "),
				code([], [text("Calm down")]),
				text(" and the ticking stops."),
			],
		),
		h2([], [text("Your turn:")]),
		p(
			[],
			[
				text("Edit the code below and get excited twice as fast. You can do it!"),
			],
		),
		Doc.playground_folded(
			Doc.code(
				Roc,
				"ticker.roc",
				\\app [Model, Msg, init, update, view, subscriptions] {
				\\    pf: platform "https://github.com/niclas-ahden/joy/releases/download/VERSION/HASH.tar.zst",
				\\    html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
				\\}
				\\
				\\import html.Html exposing [button, div, h1, text]
				\\import html.Attribute exposing [on_click]
				\\import pf.Effect
				\\import pf.Sub
				\\import pf.Time
				\\
				\\Model : { level : I64, paused : Bool }
				\\
				\\Msg : [Tick(I64), UserToggledPause]
				\\
				\\init : Str -> (Model, List(Effect(Msg)))
				\\init = |_flags| ({ level: 0, paused: False }, [])
				\\
				\\update : Model, Msg -> (Model, List(Effect(Msg)))
				\\update = |model, msg|
				\\    match msg {
				\\        Tick(_now) => ({ ..model, level: model.level + 1 }, [])
				\\        UserToggledPause => ({ ..model, paused: !model.paused }, [])
				\\    }
				\\
				\\subscriptions : Model -> List(Sub(Msg))
				\\subscriptions = |model|
				\\    if model.paused {
				\\        []
				\\    } else {
				\\        [Time.every(1000, |now| Tick(now))]
				\\    }
				\\
				\\view : Model -> Html(Msg)
				\\view = |model| {
				\\    label = if (model.paused) "Get excited!" else "Calm down"
				\\    div(
				\\        [],
				\\        [
				\\            h1([], [text("Your excitement level for Roc: \${model.level.to_str()}")]),
				\\            button([on_click(UserToggledPause)], [text(label)]),
				\\        ],
				\\    )
				\\}
			),
		),
		p(
			[],
			[
				text("The ticker ticks only while "),
				code([], [text("paused")]),
				text(" is false. Because subscriptions follow the model, they can never get out of step with it. The same holds for the microphone in "),
				code([], [text("pf.Media")]),
				text(": it is open exactly while the app subscribes to it."),
			],
		),
		p(
			[],
			[
				code([], [text("Sub.map")]),
				text(" wraps a subscription's messages, the same way "),
				code([], [text("Html.map")]),
				text(" and "),
				code([], [text("Effect.map")]),
				text(" do."),
			],
		),
	]
}
