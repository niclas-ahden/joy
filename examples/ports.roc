app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, h1, p, pre, small, text]
import html.Attribute exposing [id]
import pf.Effect exposing [Effect]
import pf.Port
import pf.Console

# Ports in both directions. Incoming: we subscribe to a named port and
# JavaScript drives it (here with a setInterval).
#
# This example caps its excitement at 3, after which the subscription is
# omitted and further sends are ignored. Outgoing: each tick sends the
# new level back out to whatever handler JavaScript registered with
# app.onPort("level", ...).

Model : I32

Msg : [Tick]

subscriptions = |model|
	if model < 3 [Port.listen("excitement", |_| Tick)] else []

init : Str -> (Model, List(Effect(Msg)))
init = |_|
	(0, [Port.send("status", "listening")])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Tick =>
			(
				model + 1,
				[
					Console.log("Time passes slowly now... ${model.to_str()}"),
					Port.send("level", (model + 1).to_str()),
				],
			)
		}

render : Model -> Html(Msg)
render = |model|
	match model {
		0 =>
			div(
				[],
				[
					p([], [text("Open the browser console and run:")]),
					pre([], [text("setInterval(() => app.sendPort(\"excitement\", \"\"), 1000)")]),
					p([], [text("(www/index.html exposes the mounted app as `app`.)")]),
				],
			)

		_ =>
			div(
				[],
				[
					h1([id("level")], [text("Your excitement level for Roc: ${model.to_str()}")]),
					if model >= 3 {
						p([id("capped")], [text("Whoah, let's calm down! I've stopped the ticker.")])
					} else {
						small([], [text("(you don't ever have to close this page if you don't want to)")])
					},
				],
			)
		}
