app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [div, h1, p, span, button, input, details, summary, dialog, text]
import html.Attribute exposing [id, class, title, on_click, on_input, on_visible]
import pf.Effect
import pf.DOM

# The first of two builds of one view that tests/check_hot_view.mjs reloads
# between, to see which elements of the page a reload keeps. hot_view_v2.roc
# puts a heading in before the field and a div in before the sentinels,
# changes the Bump button's class and drops its title, turns the span into a
# strong, drops the footer, changes when the second sentinel re-arms, and has
# the Open button send another message.

Model : { typed : Str, count : I64, seen : I64, later : I64 }

Msg : [Typed(Str), Bump, Open, Close, Seen, SeenLater]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ typed: "", count: 0, seen: 0, later: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Typed(s) => ({ ..model, typed: s }, [])
		Bump => ({ ..model, count: model.count + 1 }, [])
		Open => (model, [DOM.show_modal("#confirm")])
		Close => (model, [DOM.close_modal("#confirm")])
		Seen => ({ ..model, seen: model.seen + 1 }, [])
		SeenLater => ({ ..model, later: model.later + 1 }, [])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			h1([], [text("View")]),
			input([id("name"), on_input(|s| Typed(s))]),
			p([id("typed")], [text(model.typed)]),
			button([id("bump"), class("plain"), title("Add one"), on_click(Bump)], [text("Bump")]),
			p([id("count")], [text(model.count.to_str())]),
			span([id("kind")], [text("span")]),
			details([id("more")], [summary([], [text("More")]), p([], [text("Hidden")])]),
			button([id("open"), on_click(Open)], [text("Open")]),
			dialog([id("confirm")], [button([id("close"), on_click(Close)], [text("Close")])]),
			div([id("sentinel"), on_visible(Seen, { root_margin: "0px", rearm_key: "" })], [text(model.seen.to_str())]),
			div([id("later"), on_visible(SeenLater, { root_margin: "0px", rearm_key: "1" })], [text(model.later.to_str())]),
			p([id("footer")], [text("Footer")]),
		],
	)
