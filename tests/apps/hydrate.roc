app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [button, div, input, li, span, text, ul]
import html.Attribute exposing [attribute, checked, class, on_check, on_click, on_input, type, value]
import pf.Console
import pf.Effect

# The hydration fixture: its view holds everything SSR serializes lossily or
# hydration must claim carefully, in one small tree.
#
#   * adjacent text nodes ("count: " + the number), which SSR merges into one
#     DOM text node that hydration has to split back apart
#   * an empty text node, which SSR drops and hydration has to reinsert
#   * an input whose `value` and a checkbox whose `checked` come from the
#     model, the form-state claims
#   * on_click / on_input / on_check handlers, which SSR skips and hydration
#     must attach
#   * a list rendered from the model, so the harness can grow it after
#     hydration and exercise structural patches on claimed nodes
#   * an event handler attribute on the list, which the runtime refuses, so
#     markup that carries one can be claimed against it
#
# The flags set the whole initial model, so a harness can stage any
# server-rendered markup and boot the app to match (or mismatch) it.
Model : { count : I64, draft : Str, items : List(Str), on : Bool }

Msg : [Inc, Typed(Str), Toggled(Bool), Add]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |flags|
	match Json.parse(flags) {
		Ok({ count, draft, items, on }) => ({ count, draft, items, on }, [])
		Err(e) => (
			{ count: 0, draft: "", items: [], on: Bool.False },
			[Console.log("hydrate fixture: could not parse the flags: ${Str.inspect(e)}")],
		)
	}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Inc => ({ ..model, count: model.count + 1 }, [])
		Typed(draft) => ({ ..model, draft }, [])
		Toggled(on) => ({ ..model, on }, [])
		Add => ({ ..model, items: model.items.append(model.draft), draft: "" }, [])
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			button([class("inc"), on_click(Inc)], [text("+")]),
			# Three adjacent text nodes, one of them empty: SSR emits them as
			# the single run "count: N".
			span([class("greet")], [text("count: "), text(model.count.to_str()), text("")]),
			input([class("draft"), value(model.draft), on_input(|s| Typed(s))]),
			input([class("chk"), type("checkbox"), checked(model.on), on_check(|now| Toggled(now))]),
			button([class("add"), on_click(Add)], [text("add")]),
			ul([attribute("onmouseover", "steal()")], model.items.map(|item| li([], [text(item)]))),
		],
	)
