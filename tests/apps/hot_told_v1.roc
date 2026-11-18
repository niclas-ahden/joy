# An app that tells things outside itself, for what a hot reload does with
# them (tests/check_hot_told.mjs): its page's JavaScript through a port, the
# focus, the scroll, the URL, and the clipboard. hot_told_v2.roc is the same
# app with the clipboard's answer under another name, so the answer v1 got no
# longer replays.
app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [button, div, input, p, text]
import html.Attribute exposing [id, on_click]
import pf.Clipboard
import pf.DOM
import pf.Effect
import pf.Port
import pf.Sub

Model : { told : U64, path : Str, copied : U64 }

Msg : [
	UserClickedTell,
	UserClickedFocus,
	UserClickedScroll,
	UserClickedGo(Str),
	UserWentBackOrForward(Str),
	UserClickedCopy,
	ClipboardWrote(Try({}, Clipboard.Problem)),
]

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ told: 0, path: "/", copied: 0 }, [Port.send("page", "boot")])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedTell => ({ ..model, told: model.told + 1 }, [Port.send("page", "note ${model.told.to_str()}")])
		UserClickedFocus => (model, [DOM.focus("#field")])
		UserClickedScroll => (model, [DOM.scroll_to({ x: 0, y: 40 + model.told })])
		UserClickedGo(path) => ({ ..model, path }, [DOM.push_url(path)])
		UserWentBackOrForward(path) => ({ ..model, path }, [])
		UserClickedCopy => (model, [Clipboard.write_text("copied text", |wrote| ClipboardWrote(wrote))])
		ClipboardWrote(_) => ({ ..model, copied: model.copied + 1 }, [])
	}

subscriptions = |_model| [DOM.on_url_change(|path| UserWentBackOrForward(path))]

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			input([id("field")]),
			button([id("tell"), on_click(UserClickedTell)], [text("tell")]),
			button([id("focus"), on_click(UserClickedFocus)], [text("focus")]),
			button([id("scroll"), on_click(UserClickedScroll)], [text("scroll")]),
			button([id("go-a"), on_click(UserClickedGo("/a"))], [text("a")]),
			button([id("go-b"), on_click(UserClickedGo("/b"))], [text("b")]),
			button([id("copy"), on_click(UserClickedCopy)], [text("copy")]),
			p([id("state")], [text("told ${model.told.to_str()} at ${model.path} copied ${model.copied.to_str()}")]),
		],
	)
