app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [div, text]
import pf.Effect
import pf.Sub
import pf.Time

# Makes Joy's heap grow after Roc's boxy runtime has grown memory for its own
# bookkeeping. Boxing a callback (as `Time.every` does) links the boxy runtime,
# which takes pages straight from `memory.grow`. The first tick then renders
# `target` rows (from the flags) at once, so the host allocator has to grow
# linear memory too. If it still assumes it is the only one growing, its new
# spans overlap the runtime's pages and the next render traps. Regression for
# issue #15.
Model : { rows : U64, target : U64 }

Msg : [Tick(I64)]

init : Str -> (Model, List(Effect(Msg)))
init = |flags| {
	target = U64.from_str(flags) ?? 0
	({ rows: 0, target: target }, [])
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, Tick(_)| ({ ..model, rows: model.target }, [])

subscriptions : Model -> List(Sub(Msg))
subscriptions = |_| [Time.every(100, |now| Tick(now))]

render : Model -> Html(Msg)
render = |model| div([], List.repeat(0, model.rows).map_with_index(|_, i| div([], [text(i.to_str())])))
