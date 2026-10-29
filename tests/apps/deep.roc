app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.1/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [div, button, text]
import html.Attribute exposing [on_click]
import pf.Effect

# Renders a chain of nested divs whose depth comes from the flags, so the
# stack overflow harness can drive nesting past the shadow stack budget (see
# check_stack_overflow.mjs). Mounts shallow, one click jumps to the flagged
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

view : Model -> Html(Msg)
view = |model| div([], [button([on_click(Go)], [text("go")]), nest(model.depth)])
