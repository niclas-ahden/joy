app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [div, p, input, text]
import html.Attribute exposing [id, type, on_key, on_pointer_down, on_file, on_visible]
import pf.Effect
import pf.Sub
import pf.Time
import pf.Keyboard
import pf.Port
import pf.DOM

# A message from each kind of source tests/check_hot.mjs does not get from
# hot_v1.roc: a key handler, a pointer handler, a file input, a visibility
# observer, and subscriptions to a timer, a key, a port and URL changes. Each
# message adds a line to the log. hot_src_v2.roc is this app with three
# sources that no longer hear what they heard here: the key handler hears Tab
# rather than Enter, the key subscription q rather than Escape, and the port
# is pong rather than ping.

Model : { log : List(Str) }

Msg : [Key(Str), Pointed(F64), Picked(Str), Seen, Ticked, Escaped(Str), Pinged(Str), Moved(Str)]

subscriptions : Model -> List(Sub(Msg))
subscriptions = |_model| [
	Time.every(1000, |_| Ticked),
	Keyboard.on_down_keys(["Escape"], |e| Escaped(e.key)),
	Port.listen("ping", |word| Pinged(word)),
	DOM.on_url_change(|url| Moved(url)),
]

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ log: [] }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg| {
	line = match msg {
		Key(key) => "key ${key}"
		Pointed(x) => "pointer ${x.to_str()}"
		Picked(name) => "file ${name}"
		Seen => "seen"
		Ticked => "tick"
		Escaped(key) => "escape ${key}"
		Pinged(word) => "ping ${word}"
		Moved(url) => "url ${url}"
	}
	({ log: model.log.append(line) }, [])
}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			input([id("field"), on_key("keydown", ["Enter"], |e| Key(e.key))]),
			div([id("pad"), on_pointer_down(|e| Pointed(e.client_x))], [text("pad")]),
			input([id("upload"), type("file"), on_file(|f| Picked(f.name))]),
			div([id("sentinel"), on_visible(Seen, { root_margin: "0px", rearm_key: "" })], [text("sentinel")]),
			p([id("log")], [text(Str.join_with(model.log, ","))]),
		],
	)
