app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [div, p, button, input, text]
import html.Attribute exposing [id, value, on_click, on_input]
import pf.Effect
import pf.Http
import pf.Port
import pf.Sub
import pf.Time

# The first of three builds of one app that tests/check_hot.mjs hot reloads
# from one to the next, each picking up in the state the last one reached:
# hot_v2.roc only rearranges the view, hot_v3.roc changes the model, the
# messages and update. Messages here reach update from every kind of source
# a replay has to find again in the next build: buttons, an input's value,
# a button per list item, an HTTP response, a timer and a port.

Model : {
	count : I64,
	draft : Str,
	items : List(Str),
	quote : Str,
	fired : I64,
	pinged : Str,
}

Msg : [
	Increment,
	Decrement,
	Typed(Str),
	Add,
	Remove(Str),
	Fetch,
	Got(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
	Later,
	Fired(I64),
	Pinged(Str),
]

subscriptions : Model -> List(Sub(Msg))
subscriptions = |_model| [Port.listen("ping", |word| Pinged(word))]

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ count: 0, draft: "", items: [], quote: "", fired: 0, pinged: "" }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Increment => ({ ..model, count: model.count + 1 }, [])
		Decrement => ({ ..model, count: model.count - 1 }, [])
		Typed(draft) => ({ ..model, draft }, [])
		Add => ({ ..model, items: model.items.append(model.draft), draft: "" }, [])
		Remove(item) => ({ ..model, items: model.items.drop_if(|other| other == item) }, [])
		Fetch => ({ ..model, quote: "loading" }, [Http.get("/quote", |result| Got(result))])
		Got(Ok(resp)) => ({ ..model, quote: Str.from_utf8_lossy(resp.body) }, [])
		Got(Err(_)) => ({ ..model, quote: "failed" }, [])
		Later => (model, [Time.after(5, |now| Fired(now))])
		Fired(_) => ({ ..model, fired: model.fired + 1 }, [])
		Pinged(word) => ({ ..model, pinged: word }, [])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			button([id("inc"), on_click(Increment)], [text("+")]),
			p([id("count")], [text(model.count.to_str())]),
			button([id("dec"), on_click(Decrement)], [text("-")]),
			input([id("draft"), value(model.draft), on_input(|draft| Typed(draft))]),
			button([id("add"), on_click(Add)], [text("Add")]),
			div([id("items")], model.items.map(|item| button([on_click(Remove(item))], [text(item)]))),
			button([id("fetch"), on_click(Fetch)], [text("Fetch")]),
			p([id("quote")], [text(model.quote)]),
			button([id("later"), on_click(Later)], [text("Later")]),
			p([id("fired")], [text(model.fired.to_str())]),
			p([id("pinged")], [text(model.pinged)]),
		],
	)
