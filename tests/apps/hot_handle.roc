app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [div, p, button, input, text]
import html.Attribute exposing [id, type, checked, on_click, on_input, on_check, on_file]
import pf.Effect
import pf.Port
import pf.WebCrypto

# What tests/check_hot_handle.mjs reaches through the handle mount returns, and
# what a rebuilt app takes over: outgoing ports, picked files and a checkbox that
# the view keeps unchecked.

Model : { count : I64, typed : Str, first_file : U32, hash_start : U8 }

Msg : [Bump, Typed(Str), Say, Refused(Bool), Picked(U32), Hash, Hashed(List(U8))]

subscriptions = |_model| [Port.listen("ping", |_| Bump)]

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ count: 0, typed: "", first_file: 0, hash_start: 0 }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Bump => ({ ..model, count: model.count + 1 }, [])
		Typed(s) => ({ ..model, typed: s }, [])
		Say => (model, [Port.send("said", model.count.to_str())])
		Refused(_) => (model, [])
		Picked(file) => ({ ..model, first_file: if (model.first_file == 0) file else model.first_file }, [])
		Hash => ({ ..model, hash_start: 0 }, [WebCrypto.digest_file(Sha256, model.first_file, |hash| Hashed(hash))])
		Hashed(hash) => ({ ..model, hash_start: hash.first() ?? 0 }, [])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			button([id("bump"), on_click(Bump)], [text("Bump")]),
			p([id("count")], [text(model.count.to_str())]),
			input([id("field"), on_input(|s| Typed(s))]),
			p([id("typed")], [text(model.typed)]),
			button([id("say"), on_click(Say)], [text("Say")]),
			input([id("agree"), type("checkbox"), checked(False), on_check(|on| Refused(on))]),
			input([id("upload"), type("file"), on_file(|f| Picked(f.id))]),
			button([id("hash"), on_click(Hash)], [text("Hash")]),
			p([id("hash-start")], [text(model.hash_start.to_str())]),
		],
	)
