app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [button, dialog, div, input, p, text]
import html.Attribute exposing [id, on_click, on_file, on_input, on_key, on_pointer_down, type, value]
import pf.DOM
import pf.Effect
import pf.Http
import pf.Time

# hot_page_v1.roc crashing on the second Inc.

Model : { count : I64, name : Str, data : Str, saved : Str, fired : I64, key : Str, x : F64, file : Str, boots : Str }

Response : Try(Http.Response, [HttpErr([Timeout, NetworkError])])

Msg : [
	Inc,
	Typed(Str),
	Load,
	Loaded(Response),
	Save,
	Saved(Response),
	Later,
	Fired(I64),
	Key(Str),
	Pointed(F64),
	Picked(Str),
	Open,
	Move,
	Moved(Response),
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |flags| ({ count: 0, name: "", data: "", saved: "", fired: 0, key: "", x: 0, file: "", boots: flags }, [])

body_of : Response -> Str
body_of = |result|
	match result {
		Ok(response) => Str.from_utf8_lossy(response.body)
		Err(_) => "failed"
	}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Inc => if (model.count == 1) crash "the second Inc" else ({ ..model, count: model.count + 1 }, [])
		Typed(name) => ({ ..model, name }, [])
		Load => (model, [Http.get("/load", |r| Loaded(r))])
		Loaded(result) => ({ ..model, data: body_of(result) }, [])
		Save => (model, [Http.post("/save", Str.to_utf8("draft"), |r| Saved(r))])
		Saved(result) => ({ ..model, saved: body_of(result) }, [])
		Later => (model, [Time.after(5, |now| Fired(now))])
		Fired(_) => ({ ..model, fired: model.fired + 1 }, [])
		Key(key) => ({ ..model, key }, [])
		Pointed(x) => ({ ..model, x }, [])
		Picked(file) => ({ ..model, file }, [])
		Open => (model, [DOM.show_modal("#dlg")])
		Move => (model, [DOM.push_url("/moved")])
		Moved(_) => (model, [])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			button([id("inc"), on_click(Inc)], [text("+")]),
			input([id("name"), value(model.name), on_input(|s| Typed(s))]),
			button([id("load"), on_click(Load)], [text("load")]),
			button([id("save"), on_click(Save)], [text("save")]),
			button([id("later"), on_click(Later)], [text("later")]),
			input([id("field"), on_key("keydown", ["Enter"], |e| Key(e.key))]),
			div([id("pad"), on_pointer_down(|e| Pointed(e.client_x))], [text("pad")]),
			input([id("upload"), type("file"), on_file(|f| Picked(f.name))]),
			button([id("open"), on_click(Open)], [text("open")]),
			button([id("move"), on_click(Move)], [text("move")]),
			dialog([id("dlg")], [text("hello")]),
			p([id("count")], [text(model.count.to_str())]),
			p([id("data")], [text(model.data)]),
			p([id("saved")], [text(model.saved)]),
			p([id("fired")], [text(model.fired.to_str())]),
			p([id("key")], [text(model.key)]),
			p([id("x")], [text(model.x.to_str())]),
			p([id("file")], [text(model.file)]),
			p([id("boots")], [text(model.boots)]),
		],
	)
