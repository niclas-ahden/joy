app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [div, h1, p, button, input, text]
import html.Attribute exposing [id, value, on_click, on_input]
import pf.Effect
import pf.Http
import pf.Port
import pf.Sub
import pf.Time

# hot_v1.roc with only the view rearranged (see tests/check_hot.mjs): a
# heading and a wrapper shift every node, the buttons swap places, and the
# items list runs backwards, so no handler sits where it used to. The model,
# messages and update are v1's.

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
			h1([], [text("Version 2")]),
			div(
				[],
				[
					button([id("dec"), on_click(Decrement)], [text("minus")]),
					p([id("count")], [text(model.count.to_str())]),
					button([id("inc"), on_click(Increment)], [text("plus")]),
				],
			),
			div([id("items")], model.items.rev().map(|item| button([on_click(Remove(item))], [text(item)]))),
			input([id("draft"), value(model.draft), on_input(|draft| Typed(draft))]),
			button([id("add"), on_click(Add)], [text("Add")]),
			p([id("quote")], [text(model.quote)]),
			button([id("fetch"), on_click(Fetch)], [text("Fetch")]),
			p([id("fired")], [text(model.fired.to_str())]),
			button([id("later"), on_click(Later)], [text("Later")]),
			p([id("pinged")], [text(model.pinged)]),
		],
	)
