app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../platform/main.roc",
}

import html.Html exposing [button, div, input, li, p, text, ul]
import html.Attribute exposing [disabled, on_click, on_input, placeholder, value]
import pf.Effect

Model : { new_guest : Str, guests : List(Str) }

Msg : [
	UserTypedNewGuest(Str),
	UserClickedInvite,
	UserClickedRemove(Str),
]

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ new_guest: "", guests: ["Ada", "Grace"] }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserTypedNewGuest(typed) =>
			({ ..model, new_guest: typed }, [])

		UserClickedInvite =>
			({ new_guest: "", guests: List.append(model.guests, model.new_guest) }, [])

		UserClickedRemove(guest) =>
			({ ..model, guests: List.drop_if(model.guests, |g| g == guest) }, [])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			input([
				placeholder("Who's coming?"),
				value(model.new_guest),
				on_input(|typed| UserTypedNewGuest(typed)),
			]),
			button(
				[on_click(UserClickedInvite), disabled(model.new_guest == "")],
				[text("Invite")],
			),
			ul([], List.map(model.guests, guest_row)),
			p([], [text("${model.guests.len().to_str()} coming")]),
		],
	)

guest_row : Str -> Html(Msg)
guest_row = |guest|
	li(
		[],
		[
			text(guest),
			button([on_click(UserClickedRemove(guest))], [text("Remove")]),
		],
	)

subscriptions = |_model| []
