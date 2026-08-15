app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.15.0/5Yoz712P8ed4MBW74eddTEJdZ92ZDCUbVGFkt4XXSuj9.tar.zst",
}

import html.Html exposing [Html, div, h1, button, table, tbody, tr, td, a, span, text]
import html.Attribute exposing [id, class, key, attribute, on_click]
import pf.Effect exposing [Effect]

# Joy entry for the js-framework-benchmark "table" app. One wasm serves both
# brackets: {"keyed": true} flags put a `key` attribute on every row so the
# differ moves DOM nodes by identity, {"keyed": false} leaves rows unkeyed and
# they are patched positionally. The rendered DOM mirrors the vanillajs
# reference (button ids, table classes, tbody#tbody, aria-hidden) so the
# benchmark driver's selectors find everything.

Row : { id : U64, label : Str }

Model : {
	rows : List(Row),
	# The id of the selected row, or 0 for "none" (ids start at 1).
	selected : U64,
	# Monotonically increasing id source, never reset, matching the reference
	# implementation so the first row after run N has id N*1000+1.
	next_id : U64,
	keyed : Bool,
}

Msg : [
	UserClickedRun,
	UserClickedRunLots,
	UserClickedAdd,
	UserClickedUpdate,
	UserClickedClear,
	UserClickedSwap,
	UserSelectedRow(U64),
	UserRemovedRow(U64),
]

# No recurring event sources.
subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |flags| {
	decoded : Try({ keyed : Bool }, _)
	decoded = Json.parse(flags)
	keyed = match decoded {
		Ok(parsed) => parsed.keyed
		Err(_) => Bool.False
	}
	({ rows: [], selected: 0, next_id: 1, keyed }, [])
}

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedRun => (create(model, 1000), [])
		UserClickedRunLots => (create(model, 10000), [])
		UserClickedAdd => {
			appended = model.rows.concat(build(1000, model.next_id))
			({ ..model, rows: appended, next_id: model.next_id + 1000 }, [])
		}
		UserClickedUpdate => {
			bumped = model.rows.map_with_index(
				|row, i| {
					if i.rem_by(10) == 0 {
						{ ..row, label: "${row.label} !!!" }
					} else {
						row
					}
				},
			)
			({ ..model, rows: bumped }, [])
		}
		UserClickedClear => ({ ..model, rows: [], selected: 0 }, [])
		UserClickedSwap => ({ ..model, rows: model.rows.swap(1, 998) ?? model.rows }, [])
		UserSelectedRow(row_id) => ({ ..model, selected: row_id }, [])
		UserRemovedRow(row_id) => ({ ..model, rows: model.rows.keep_if(|row| row.id != row_id) }, [])
	}

create : Model, U64 -> Model
create = |model, count|
	{ ..model, rows: build(count, model.next_id), next_id: model.next_id + count, selected: 0 }

build : U64, U64 -> List(Row)
build = |count, start_id|
	(0..<count).iter()
		.map(|i| make_row(start_id + i))
		.collect()

make_row : U64 -> Row
make_row = |row_id| { id: row_id, label: make_label(row_id) }

# Deterministic "adjective colour noun" label. Content isn't validated by the
# benchmark (only row counts, ids, and that `update` appends " !!!"), so a
# cheap spread over the reference word lists is enough to mimic realistic,
# varied labels.
make_label : U64 -> Str
make_label = |seed|
	"${pick(adjectives, seed * 7)} ${pick(colours, seed * 13)} ${pick(nouns, seed * 17)}"

pick : List(Str), U64 -> Str
pick = |words, n|
	match words.get(n.rem_by(words.len())) {
		Ok(word) => word
		Err(_) => ""
	}

adjectives : List(Str)
adjectives = ["pretty", "large", "big", "small", "tall", "short", "long", "handsome", "plain", "quaint", "clean", "elegant", "easy", "angry", "crazy", "helpful", "mushy", "odd", "unsightly", "adorable", "important", "inexpensive", "cheap", "expensive", "fancy"]

colours : List(Str)
colours = ["red", "yellow", "blue", "green", "pink", "brown", "purple", "brown", "white", "black", "orange"]

nouns : List(Str)
nouns = ["table", "chair", "house", "bbq", "desk", "car", "pony", "cookie", "sandwich", "burger", "pizza", "mouse", "keyboard"]

render : Model -> Html(Msg)
render = |model|
	div(
		[id("main")],
		[
			div(
				[class("container")],
				[
					div(
						[class("jumbotron")],
						[
							div(
								[class("row")],
								[
									div([class("col-md-6")], [h1([], [text("Joy")])]),
									div(
										[class("col-md-6")],
										[
											div(
												[class("row")],
												[
													action_button("run", "Create 1,000 rows", UserClickedRun),
													action_button("runlots", "Create 10,000 rows", UserClickedRunLots),
													action_button("add", "Append 1,000 rows", UserClickedAdd),
													action_button("update", "Update every 10th row", UserClickedUpdate),
													action_button("clear", "Clear", UserClickedClear),
													action_button("swaprows", "Swap Rows", UserClickedSwap),
												],
											),
										],
									),
								],
							),
						],
					),
					table(
						[class("table table-hover table-striped test-data")],
						[
							tbody([id("tbody")], model.rows.map(|row| render_row(row, model.selected, model.keyed))),
						],
					),
					span([class("preloadicon glyphicon glyphicon-remove"), attribute("aria-hidden", "true")], []),
				],
			),
		],
	)

action_button : Str, Str, Msg -> Html(Msg)
action_button = |button_id, label, msg|
	div(
		[class("col-sm-6 smallpad")],
		[
			button(
				[attribute("type", "button"), class("btn btn-primary btn-block"), id(button_id), on_click(msg)],
				[text(label)],
			),
		],
	)

# Per-row memoization, aligned with the Elm entry's `lazy2` on every row:
# each cell is a lazy region keyed on the data it shows, so an unchanged
# row's cells skip render and diff entirely. The key and the selection class
# stay on the tr OUTSIDE the lazy regions, because the keyed differ matches
# by keys on real elements (a key inside a thunk is invisible without
# forcing it), and with selection outside, selecting a row forces nothing.
render_row : Row, U64, Bool -> Html(Msg)
render_row = |row, selected, keyed| {
	id_str = row.id.to_str()
	danger = if selected == row.id {
		[class("danger")]
	} else {
		[]
	}
	row_attrs = if keyed {
		danger.append(key(id_str))
	} else {
		danger
	}

	tr(
		row_attrs,
		[
			Html.lazy(id_cell, row.id),
			Html.lazy(label_cell, row),
			Html.lazy(remove_cell, row.id),
			td([class("col-md-6")], []),
		],
	)
}

id_cell : U64 -> Html(Msg)
id_cell = |row_id| td([class("col-md-1")], [text(row_id.to_str())])

label_cell : Row -> Html(Msg)
label_cell = |row|
	td(
		[class("col-md-4")],
		[
			a([class("lbl"), on_click(UserSelectedRow(row.id))], [text(row.label)]),
		],
	)

remove_cell : U64 -> Html(Msg)
remove_cell = |row_id|
	td(
		[class("col-md-1")],
		[
			a(
				[class("remove"), on_click(UserRemovedRow(row_id))],
				[
					span([class("remove glyphicon glyphicon-remove"), attribute("aria-hidden", "true")], []),
				],
			),
		],
	)
