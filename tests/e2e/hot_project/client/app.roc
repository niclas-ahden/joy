# What tests/e2e/hot_dev_test.roc runs ./joy dev on: a bundle on a page its
# server renders, with a count, a typed value, a dialog, a GET and a POST.
app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
	shared: "../shared/main.roc",
}

import html.Html exposing [button, dialog, div, h1, input, span, text]
import html.Attribute exposing [id, value, on_click, on_input]
import pf.DOM
import pf.Effect
import pf.Http
import shared.Greeting
import shared.Label

Model : { greeting : Str, count : I64, name : Str, data : Str, saved : Str }

Msg : [
	Inc,
	Typed(Str),
	Open,
	Load,
	Loaded(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
	Save,
	Saved(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |flags| ({ greeting: flags, count: 0, name: "", data: "", saved: "" }, [])

body_of = |result|
	match result {
		Ok(response) => Str.from_utf8_lossy(response.body)
		Err(_) => "failed"
	}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Inc => ({ ..model, count: model.count + 1 }, [])
		Typed(name) => ({ ..model, name }, [])
		Open => (model, [DOM.show_modal("#dlg")])
		Load => (model, [Http.get("/api/data", |r| Loaded(r))])
		Loaded(result) => ({ ..model, data: body_of(result) }, [])
		Save => (model, [Http.post("/api/save", [], |r| Saved(r))])
		Saved(result) => ({ ..model, saved: body_of(result) }, [])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[id("page")],
		[
			h1([id("title")], [text(model.greeting)]),
			span([id("shared")], [text(Greeting.text)]),
			span([id("view")], [text(if (model.count == 0) "" else Label.text)]),
			span([id("label")], [text(if (model.count == 0) "" else "client one")]),
			button([id("inc"), on_click(Inc)], [text("+")]),
			span([id("count")], [text(model.count.to_str())]),
			input([id("name"), value(model.name), on_input(|s| Typed(s))]),
			button([id("open"), on_click(Open)], [text("open")]),
			dialog([id("dlg")], [text("hello")]),
			button([id("load"), on_click(Load)], [text("load")]),
			span([id("data")], [text(model.data)]),
			button([id("save"), on_click(Save)], [text("save")]),
			span([id("saved")], [text(model.saved)]),
		],
	)
