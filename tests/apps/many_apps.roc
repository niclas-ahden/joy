app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [dialog, div, element, p, button, input, text]
import html.Attribute exposing [id, type, on_click, on_file]
import pf.Clipboard
import pf.DOM
import pf.Effect
import pf.Keyboard
import pf.Media
import pf.Time
import pf.WebCrypto

# What tests/check_many_apps.mjs and tests/e2e/many_apps_test.roc mount more than
# once on a page: every copy uses the same debounce key and selectors and gets the
# same file ids. The flags "grab" make a copy hold on to the space key.

Model : { grab : Bool, fired : I64, file : U32, url : Str, keys : I64, hashed : I64 }

Msg : [Arm, Cancel, Fired, Picked(U32), Ask, Got(Str), Focus, Open, Shut, OpenPageDialog, Play, Copy, Ignored, Key, Hash, HashRepeated, Hashed]

subscriptions = |model|
	if model.grab [Keyboard.on_down_keys_prevent_default([" "], |_| Key)] else []

init : Str -> (Model, List(Effect(Msg)))
init = |flags| ({ grab: flags == "grab", fired: 0, file: 0, url: "", keys: 0, hashed: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Arm => (model, [Time.debounce("search", 80, |_| Fired)])
		Cancel => (model, [Time.cancel("search")])
		Fired => ({ ..model, fired: model.fired + 1 }, [])
		Picked(file) => ({ ..model, file }, [])
		Ask => (model, [Media.object_url(model.file, |answer| Got(answer ?? "failed"))])
		Got(url) => ({ ..model, url }, [])
		Focus => (model, [DOM.focus("#name")])
		Open => (model, [DOM.show_modal("#dialog")])
		Shut => (model, [DOM.close_modal("#dialog")])
		OpenPageDialog => (model, [DOM.show_modal("#page-dialog")])
		Play => (model, [Media.play("#player", |_| Ignored)])
		Copy => (model, [Clipboard.write_text_of("#quote", |_| Ignored)])
		Ignored => (model, [])
		Key => ({ ..model, keys: model.keys + 1 }, [])
		Hash => {
			chunk = |start| WebCrypto.digest_file_slice(Sha256, { file: model.file, start, len: 1 }, |_| Hashed)
			(model, [chunk(0), chunk(1), chunk(2), chunk(3), chunk(4), chunk(5)])
		}
		HashRepeated => (model, List.repeat(WebCrypto.digest_file(Sha256, model.file, |_| Hashed), 6))
		Hashed => ({ ..model, hashed: model.hashed + 1 }, [])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			button([id("arm"), on_click(Arm)], [text("Arm")]),
			button([id("cancel"), on_click(Cancel)], [text("Cancel")]),
			p([id("fired")], [text(model.fired.to_str())]),
			input([id("upload"), type("file"), on_file(|f| Picked(f.id))]),
			button([id("ask"), on_click(Ask)], [text("Ask")]),
			p([id("url")], [text(model.url)]),
			input([id("name")]),
			button([id("focus"), on_click(Focus)], [text("Focus")]),
			dialog([id("dialog")], [text("Dialog")]),
			button([id("open"), on_click(Open)], [text("Open")]),
			button([id("shut"), on_click(Shut)], [text("Shut")]),
			button([id("open-page-dialog"), on_click(OpenPageDialog)], [text("Open the page's")]),
			element("audio", [id("player")], []),
			button([id("play"), on_click(Play)], [text("Play")]),
			p([id("quote")], [text("quote")]),
			button([id("copy"), on_click(Copy)], [text("Copy")]),
			p([id("keys")], [text(model.keys.to_str())]),
			button([id("hash"), on_click(Hash)], [text("Hash")]),
			button([id("hash-repeated"), on_click(HashRepeated)], [text("Hash repeated")]),
			p([id("hashed")], [text(model.hashed.to_str())]),
		],
	)
