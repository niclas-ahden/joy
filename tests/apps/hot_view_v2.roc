app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [div, h1, h2, p, strong, button, input, details, summary, dialog, text]
import html.Attribute exposing [id, class, on_click, on_input, on_visible]
import pf.Effect
import pf.DOM

# The second build of the view in hot_view_v1.roc, which says what changed.

Model : { typed : Str, count : I64, seen : I64, later : I64 }

Msg : [Typed(Str), Bump, OpenConfirm, Close, Seen, SeenLater]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ typed: "", count: 0, seen: 0, later: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Typed(s) => ({ ..model, typed: s }, [])
		Bump => ({ ..model, count: model.count + 1 }, [])
		OpenConfirm => (model, [DOM.show_modal("#confirm")])
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
			h2([], [text("Added")]),
			input([id("name"), on_input(|s| Typed(s))]),
			p([id("typed")], [text(model.typed)]),
			button([id("bump"), class("loud"), on_click(Bump)], [text("Bump")]),
			p([id("count")], [text(model.count.to_str())]),
			strong([id("kind")], [text("strong")]),
			details([id("more")], [summary([], [text("More")]), p([], [text("Hidden")])]),
			button([id("open"), on_click(OpenConfirm)], [text("Open")]),
			dialog([id("confirm")], [button([id("close"), on_click(Close)], [text("Close")])]),
			div([], [text("New")]),
			div([id("sentinel"), on_visible(Seen, { root_margin: "0px", rearm_key: "" })], [text(model.seen.to_str())]),
			div([id("later"), on_visible(SeenLater, { root_margin: "0px", rearm_key: "2" })], [text(model.later.to_str())]),
		],
	)
