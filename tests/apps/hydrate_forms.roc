app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [div, input, option, select, span, text, textarea]
import html.Attribute exposing [checked, class, name, on_change, on_check, on_input, selected, type, value]
import pf.Console
import pf.Effect

# The form-control hydration fixture: every control whose state HTML
# expresses differently than the view declares it, or that a user can change
# in the server-rendered page before the app boots.
#
#   * a text input, which refuses "!" so a pre-boot value can be refused
#   * a textarea whose value is an attribute (the server writes it as text)
#   * a textarea whose value is its text child
#   * a select driven by its options' `selected`, and one by a `value`
#     attribute, which HTML ignores on a select
#   * a radio group and a checkbox, the checkbox gone while the name is
#     "hide", so delivering a pre-boot name can re-render a later
#     pre-boot control away before its own delivery
#   * an echo of the whole model, so a harness can read what the app knows
#
# The flags set the whole initial model.
Model : { name : Str, bio : Str, notes : Str, size : Str, level : Str, color : Str, agree : Bool }

Msg : [Named(Str), Bio(Str), Notes(Str), Sized(Str), Leveled(Str), Colored(Str), Agreed(Bool)]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |flags|
	match Json.parse(flags) {
		Ok({ name: n, bio, notes, size, level, color, agree }) => ({ name: n, bio, notes, size, level, color, agree }, [])
		Err(e) => (
			{ name: "", bio: "", notes: "", size: "s", level: "low", color: "red", agree: Bool.False },
			[Console.log("hydrate_forms fixture: could not parse the flags: ${Str.inspect(e)}")],
		)
	}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Named(n) => if n.contains("!") { (model, []) } else { ({ ..model, name: n }, []) }
		Bio(bio) => ({ ..model, bio }, [])
		Notes(notes) => ({ ..model, notes }, [])
		Sized(size) => ({ ..model, size }, [])
		Leveled(level) => ({ ..model, level }, [])
		Colored(color) => ({ ..model, color }, [])
		Agreed(agree) => ({ ..model, agree }, [])
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			input([class("name"), value(model.name), on_input(|s| Named(s))]),
			textarea([class("bio"), value(model.bio), on_input(|s| Bio(s))], []),
			textarea([class("notes"), on_input(|s| Notes(s))], [text(model.notes)]),
			select([class("size"), on_change(|s| Sized(s))], ["s", "m", "l"].map(|v| option([value(v), selected(model.size == v)], [text(v)]))),
			select([class("level"), value(model.level), on_change(|s| Leveled(s))], ["low", "high"].map(|v| option([value(v)], [text(v)]))),
			input([class("red"), type("radio"), name("color"), value("red"), checked(model.color == "red"), on_change(|s| Colored(s))]),
			input([class("blue"), type("radio"), name("color"), value("blue"), checked(model.color == "blue"), on_change(|s| Colored(s))]),
			if model.name == "hide" {
				text("")
			} else {
				input([class("agree"), type("checkbox"), checked(model.agree), on_check(|now| Agreed(now))])
			},
			span(
				[class("echo")],
				[text("${model.name}|${model.bio}|${model.notes}|${model.size}|${model.level}|${model.color}|${if model.agree "yes" else "no"}")],
			),
		],
	)
