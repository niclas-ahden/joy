app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.1/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [div, fieldset, legend, input, label, select, option, textarea, button, text, element]
import html.Attribute exposing [id, class, type, name, value, checked, selected, attribute, for_, on_input, on_check, on_change, on, on_click]
import pf.Effect

# Probe: a large form, every kind of control, and an update that refuses
# some changes. Flags carry the row count as JSON, `{"n":200}`. The harness
# asserts that a change to one control costs work proportional to that
# control, never to the form, and that a refused change snaps the control
# back to the model: text and textarea refuse "!", checkboxes refuse
# unchecking, the color radios refuse blue, the size select refuses XL, and
# the quantity refuses anything above 10. The code field normalizes instead
# of refusing: it keeps what the user typed uppercased and without spaces,
# so the model can differ from the DOM after an accepted keystroke.

Row : { id : U64, text : Str, on : Bool }

Model : { rows : List(Row), color : Str, size : Str, qty : Str, notes : Str, code : Str, ticks : U64 }

Msg : [RowTyped(U64, Str), RowChecked(U64, Bool), ColorPicked(Str), SizePicked(Str), QtyTyped(Str), NotesTyped(Str), CodeTyped(Str), Tick]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |flags| {
	decoded : Try({ n : U64 }, _)
	decoded = Json.parse(flags)
	n = match decoded {
		Ok(parsed) => parsed.n
		Err(_) => 200
	}
	rows = (0..<n).iter().map(|i| { id: i, text: "row ${i.to_str()}", on: Bool.False }).collect()
	({ rows, color: "red", size: "s", qty: "1", notes: "", code: "", ticks: 0 }, [])
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		RowTyped(row_id, s) =>
			if s.contains("!") {
				(model, [])
			} else {
				({ ..model, rows: model.rows.map(|r| if r.id == row_id { ..r, text: s } else r) }, [])
			}

		RowChecked(row_id, now) =>
			if now {
				({ ..model, rows: model.rows.map(|r| if r.id == row_id { ..r, on: Bool.True } else r) }, [])
			} else {
				(model, [])
			}

		ColorPicked(color) =>
			if color == "blue" {
				(model, [])
			} else {
				({ ..model, color }, [])
			}

		SizePicked(size) =>
			if size == "xl" {
				(model, [])
			} else {
				({ ..model, size }, [])
			}

		QtyTyped(qty) =>
			if qty.is_empty() {
				({ ..model, qty }, [])
			} else {
				match U64.from_str(qty) {
					Ok(q) => if q <= 10 ({ ..model, qty }, []) else (model, [])
					Err(_) => (model, [])
				}
			}

		NotesTyped(s) =>
			if s.contains("!") {
				(model, [])
			} else {
				({ ..model, notes: s }, [])
			}

		CodeTyped(s) => ({ ..model, code: normalize_code(s) }, [])

		Tick => ({ ..model, ticks: model.ticks + 1 }, [])
	}

# ASCII letters uppercased, spaces dropped, everything else kept.
normalize_code : Str -> Str
normalize_code = |s|
	Str.from_utf8_lossy(
		s.to_utf8()
			.keep_if(|b| b != 32)
			.map(|b| if b >= 97 and b <= 122 b - 32 else b),
	)

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			button([id("tick"), on_click(Tick)], [text(model.ticks.to_str())]),
			fieldset(
				[id("colors")],
				[legend([], [text("Color")])].concat(["red", "green", "blue"].map(|c| color_view(c, model.color))),
			),
			select(
				[id("size"), on_change(|v| SizePicked(v))],
				[
					element("optgroup", [attribute("label", "Small")], [option_view("s", "S", model.size), option_view("m", "M", model.size)]),
					element("optgroup", [attribute("label", "Large")], [option_view("l", "L", model.size), option_view("xl", "XL", model.size)]),
				],
			),
			input([id("qty"), type("number"), value(model.qty), on_input(|v| QtyTyped(v))]),
			textarea([id("notes"), value(model.notes), on_input(|v| NotesTyped(v))], []),
			input([id("code"), type("text"), value(model.code), on_input(|v| CodeTyped(v))]),
			div([id("rows")], model.rows.map(row_view)),
		],
	)

color_view : Str, Str -> Html(Msg)
color_view = |color, current|
	label(
		[for_("color-${color}")],
		[
			input([id("color-${color}"), type("radio"), name("color"), value(color), checked(current == color), on("change", ColorPicked(color))]),
			text(color),
		],
	)

option_view : Str, Str, Str -> Html(Msg)
option_view = |val, label_text, current|
	option([value(val), selected(current == val)], [text(label_text)])

row_view : Row -> Html(Msg)
row_view = |row|
	div(
		[class("row")],
		[
			input([id("t${row.id.to_str()}"), type("text"), value(row.text), on_input(|s| RowTyped(row.id, s))]),
			input([id("c${row.id.to_str()}"), type("checkbox"), checked(row.on), on_check(|now| RowChecked(row.id, now))]),
		],
	)
