# Rows that are selected by a click, each with a button that deletes it, in
# a plain list and in a keyed one. A click on the button passes the button's
# handler and then its row's, and the first removes the row the second was
# written for. `flip` is a click that changes what the row above it says.
# The flags can ask for more rows, as a number, for a view of some size.
app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [button, div, li, p, text, ul]
import html.Attribute exposing [id, on_click]
import pf.Effect
import pf.Time

Model : { plain : List(Str), keyed : List(Str), log : List(Str), flipped : Bool, ticks : U64 }

Msg : [UserSelected(Str), UserDeleted([Plain, Keyed], Str), UserFlipped, UserSaw(Str), ClockTicked]

init : Str -> (Model, List(Effect(Msg)))
init = |flags| {
	rows =
		match U64.from_str(flags) {
			Ok(count) => List.from_iter((1..=count).iter().map(|n| "row${n.to_str()}"))
			Err(_) => names
		}
	({ plain: rows, keyed: rows, log: [], flipped: Bool.False, ticks: 0 }, [])
}

names = ["alpha", "beta", "gamma", "delta"]

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserSelected(name) => ({ ..model, log: said(model, "selected ${name}") }, [])
		UserDeleted(Plain, name) => ({ ..model, plain: model.plain.drop_if(|row| row == name), log: said(model, "deleted ${name}") }, [])
		UserDeleted(Keyed, name) => ({ ..model, keyed: model.keyed.drop_if(|row| row == name), log: said(model, "deleted ${name}") }, [])
		UserFlipped => ({ ..model, flipped: !model.flipped, log: said(model, "flipped") }, [])
		UserSaw(what) => ({ ..model, log: said(model, "saw ${what}") }, [])
		ClockTicked => ({ ..model, ticks: model.ticks + 1 }, [])
	}

## The log with one more line. It keeps its last lines, so a long session
## leaves a model, and a view, of the size it started with.
said : Model, Str -> List(Str)
said = |model, line| model.log.append(line).take_last(20)

subscriptions = |_model| [Time.every(1000, |_| ClockTicked)]

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			ul([id("plain")], model.plain.map(|name| row("plain", Plain, name))),
			ul([id("keyed")], model.keyed.map(|name| Html.keyed(name, row("keyed", Keyed, name)))),
			# The outer handler says what the view showed when it was written.
			div(
				[id("outer"), on_click(UserSaw(if model.flipped "flipped" else "plain"))],
				[button([id("flip"), on_click(UserFlipped)], [text("flip")])],
			),
			p([id("log")], [text(Str.join_with(model.log, ", "))]),
			p([id("ticks")], [text(model.ticks.to_str())]),
		],
	)

row : Str, [Plain, Keyed], Str -> Html(Msg)
row = |list, which, name|
	li(
		[id("${list}-${name}"), on_click(UserSelected(name))],
		[text(name), button([id("${list}-del-${name}"), on_click(UserDeleted(which, name))], [text("x")])],
	)
