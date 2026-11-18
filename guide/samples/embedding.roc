app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../platform/main.roc",
}

import html.Html
import pf.Effect
import Counter

Model : { counter : Counter.Model }

Msg : [Counter(Counter.Msg)]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ counter: { count: 0 } }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, Counter(msg)| {
	(counter, effects) = Counter.update(model.counter, msg)
	wrapped =
		effects.map(|effect| Effect.map(effect, |m| Counter(m)))
	({ counter: counter }, wrapped)
}

view : Model -> Html(Msg)
view = |model|
	Html.map(Counter.view(model.counter), |m| Counter(m))
