app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, button, text]
import html.Attribute exposing [on_click]
import pf.Effect exposing [Effect]

# Renders a chain of nested divs whose depth comes from the flags, so the
# stack canary harness can drive nesting past the shadow stack budget (see
# check_stack_canary.mjs). Mounts shallow, one click jumps to the flagged
# depth.
Model : { depth : I64, target : I64 }

Msg : [Go]

# No recurring event sources.
subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |flags| ({ depth: 1, target: I64.from_str(flags) ?? 1 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Go => ({ ..model, depth: model.target }, [])
	}

nest : I64 -> Html(Msg)
nest = |n| if n <= 1 text("bottom") else div([], [nest(n - 1)])

render : Model -> Html(Msg)
render = |model| div([], [button([on_click(Go)], [text("go")]), nest(model.depth)])
