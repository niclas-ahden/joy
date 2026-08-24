app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
	random: "https://github.com/niclas-ahden/roc-prng/releases/download/0.3.0/C8MfdSF4ZCt7RahWC8PCBaj1NB6Y6L6vtiHdeHB1EVnv.tar.zst",
}

import html.Html exposing [Html, div, h1, button, table, tbody, tr, td, a, span, text]
import html.Attribute exposing [id, class, attribute, on_click]
import pf.Effect exposing [Effect]
import random.Random

# Joy entry for the js-framework-benchmark "table" app, keyed bracket: every
# row carries a `key`, so the differ moves DOM nodes by identity instead of
# patching positions. jsbench_nonkeyed.roc is the same app with the key
# dropped. The two brackets are separate apps rather than one app branching on
# a flag, so neither binary carries the other's code or tests a flag per row.
# The rendered DOM mirrors the vanillajs reference (button ids, table classes,
# tbody#tbody, aria-hidden) so the benchmark driver's selectors find everything.

# The row shape is the reference implementation's, an id and a label. The id
# is formatted on every render, as the Elm entry does with `String.fromInt`,
# rather than cached as a string in the model, so the two pay the same cost.
Row : { id : U64, label : Str }

Model : {
	rows : List(Row),
	# The id of the selected row, or 0 for "none" (ids start at 1).
	selected : U64,
	# Monotonically increasing id source, never reset, matching the reference
	# implementation so the first row after run N has id N*1000+1.
	next_id : U64,
	# PRNG state for label generation, advanced on every draw. A label depends
	# on how many draws came before it, not on the row id.
	seed : Random.Seed,
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

# The seed is a fixed constant so labels are reproducible across runs.
init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ rows: [], selected: 0, next_id: 1, seed: Random.seed(42) }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedRun => (create(model, 1000), [])
		UserClickedRunLots => (create(model, 10000), [])
		UserClickedAdd => {
			(new_rows, next_seed) = build(1000, model.next_id, model.seed)
			({ ..model, rows: model.rows.concat(new_rows), next_id: model.next_id + 1000, seed: next_seed }, [])
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
create = |model, count| {
	(new_rows, next_seed) = build(count, model.next_id, model.seed)
	{ ..model, rows: new_rows, next_id: model.next_id + count, selected: 0, seed: next_seed }
}

build : U64, U64, Random.Seed -> (List(Row), Random.Seed)
build = |count, start_id, seed0|
	(0..<count).iter().fold(
		([], seed0),
		|(rows, s), i| {
			(row, s1) = make_row(start_id + i, s)
			(rows.append(row), s1)
		},
	)

make_row : U64, Random.Seed -> (Row, Random.Seed)
make_row = |row_id, seed0| {
	(label, seed1) = make_label(seed0)
	({ id: row_id, label: label }, seed1)
}

# "adjective colour noun" from three PRNG draws, one per word, matching the
# reference implementation's three Math.random calls per row.
make_label : Random.Seed -> (Str, Random.Seed)
make_label = |seed0| {
	(adjective, seed1) = pick(adjectives, seed0)
	(colour, seed2) = pick(colours, seed1)
	(noun, seed3) = pick(nouns, seed2)
	("${adjective} ${colour} ${noun}", seed3)
}

pick : List(Str), Random.Seed -> (Str, Random.Seed)
pick = |words, seed0| {
	(index, seed1) = seed0.u64_below(words.len())
	(words.get(index) ?? "", seed1)
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
							tbody([id("tbody")], model.rows.map(|row| render_row(row, model.selected))),
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

# Per-row memoization, aligned with the Elm entry's `lazy` on every row: the
# whole tr is one lazy region whose inputs are the row and its selected flag,
# so an unchanged row skips render and diff at the cost of one thunk. `keyed`
# wraps the region, and the differ reads its key without forcing the thunk.
render_row : Row, U64 -> Html(Msg)
render_row = |row, selected|
	Html.keyed(row.id.to_str(), Html.lazy2(row_view, row, selected == row.id))

row_view : Row, Bool -> Html(Msg)
row_view = |row, is_selected| {
	row_attrs = if is_selected {
		[class("danger")]
	} else {
		[]
	}

	tr(
		row_attrs,
		[
			td([class("col-md-1")], [text(row.id.to_str())]),
			td(
				[class("col-md-4")],
				[
					a([class("lbl"), on_click(UserSelectedRow(row.id))], [text(row.label)]),
				],
			),
			td(
				[class("col-md-1")],
				[
					a(
						[class("remove"), on_click(UserRemovedRow(row.id))],
						[
							span([class("remove glyphicon glyphicon-remove"), attribute("aria-hidden", "true")], []),
						],
					),
				],
			),
			td([class("col-md-6")], []),
		],
	)
}
