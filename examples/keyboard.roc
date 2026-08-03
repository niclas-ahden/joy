app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, p, button, input, text]
import html.Attribute exposing [on_click, on_key, on_keydown, placeholder]
import pf.Effect exposing [Effect]
import pf.Sub exposing [Sub]
import pf.Keyboard

Model : {
	last_key : Str,
	keys_seen : U64,
	escapes : U64,
	input_key : Str,
	submits : U64,
	listening : Bool,
}

Msg : [
	UserPressed(Sub.KeyEvent),
	UserSawKey,
	UserPressedEscape,
	UserTypedInInput(Sub.KeyEvent),
	UserSubmitted,
	UserToggledListening,
]

init : Str -> (Model, List(Effect(Msg)))
init = |_|
	({ last_key: "", keys_seen: 0, escapes: 0, input_key: "", submits: 0, listening: Bool.True }, [])

# The whole KeyEvent record on one line, e.g. "s (KeyS) ctrl repeat".
describe : Sub.KeyEvent -> Str
describe = |e| {
	ctrl = if e.ctrl {
		" ctrl"
	} else {
		""
	}
	shift = if e.shift {
		" shift"
	} else {
		""
	}
	alt = if e.alt {
		" alt"
	} else {
		""
	}
	meta = if e.meta {
		" meta"
	} else {
		""
	}
	repeat = if e.repeat {
		" repeat"
	} else {
		""
	}
	composing = if e.is_composing {
		" composing"
	} else {
		""
	}
	"${e.key} (${e.code})${ctrl}${shift}${alt}${meta}${repeat}${composing}"
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserPressed(e) => ({ ..model, last_key: describe(e) }, [])
		UserSawKey => ({ ..model, keys_seen: model.keys_seen + 1 }, [])
		UserPressedEscape => ({ ..model, escapes: model.escapes + 1 }, [])
		UserTypedInInput(e) => ({ ..model, input_key: e.key }, [])
		UserSubmitted => ({ ..model, submits: model.submits + 1 }, [])
		UserToggledListening => ({ ..model, listening: !model.listening }, [])
	}

subscriptions : Model -> List(Sub(Msg))
subscriptions = |model|
	if model.listening {
		[
			Keyboard.on_down(|e| UserPressed(e)),
			# Same identity as the sub above: one shared document listener,
			# and every keydown delivers both messages.
			Keyboard.on_down(|_| UserSawKey),
			Keyboard.on_down_keys_prevent_default(["Escape"], |_| UserPressedEscape),
		]
	} else {
		[]
	}

render : Model -> Html(Msg)
render = |model| {
	listen_label = if model.listening {
		"Stop listening"
	} else {
		"Listen"
	}

	div(
		[],
		[
			p([], [text("Last key: ${model.last_key}")]),
			p([], [text("Keys seen: ${model.keys_seen.to_str()}")]),
			p([], [text("Escapes: ${model.escapes.to_str()}")]),
			p([], [text("Input key: ${model.input_key}")]),
			p([], [text("Submits: ${model.submits.to_str()}")]),
			input([placeholder("Type here"), on_keydown(|e| UserTypedInInput(e))]),
			input([placeholder("Enter submits"), on_key("keydown", ["Enter"], |_| UserSubmitted).prevent_default()]),
			button([on_click(UserToggledListening)], [text(listen_label)]),
		],
	)
}
