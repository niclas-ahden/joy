app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.0/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
}

import html.Html exposing [button, div, element, input, li, p, span, text, ul]
import html.Attribute exposing [class, on_click, on_input, value]
import pf.Effect

# A page others write to as well: a browser extension puts a control next to
# a video, a password manager an icon next to an input, a map draws into a
# container the app leaves empty. tests/check_others.mjs puts such nodes
# among the app's and then drives every patch that changes the tree's shape:
#
#   * Rotate moves the last item to the front, a REORDER that inserts in
#     front of the items that stay. Add appends one, Drop removes the
#     first and Fresh replaces them all, a REORDER that keeps nothing
#   * Swap turns the clip and every item's mark into other elements
#     (REPLACEs) and flips every item's tags (a REORDER inside each item)
#   * Spin does Rotate and Swap at once, so REPLACEs and REORDERs land
#     inside the items a REORDER moves, all in one paint
#   * Open fills and empties a panel, REORDERs from and to no children,
#     with a custom element among what it fills it with
#   * Count only changes text

Model : { items : List(Str), next : U64, fancy : Bool, open : Bool, count : U64, name : Str }

Msg : [Rotate, Add, Drop, Fresh, Swap, Spin, Open, Count, Named(Str)]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_flags| ({ items: ["a", "b", "c", "d"], next: 0, fancy: Bool.False, open: Bool.False, count: 0, name: "" }, [])

# The last item first.
rotate : List(Str) -> List(Str)
rotate = |items| items.take_last(1).concat(items.drop_last(1))

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		Rotate => ({ ..model, items: rotate(model.items) }, [])
		Add => ({ ..model, items: model.items.append("n${model.next.to_str()}"), next: model.next + 1 }, [])
		Drop => ({ ..model, items: model.items.drop_first(1) }, [])
		Fresh => ({ ..model, items: model.items.map(|item| "${item}${model.next.to_str()}"), next: model.next + 1 }, [])
		Swap => ({ ..model, fancy: !model.fancy }, [])
		Spin => ({ ..model, items: rotate(model.items), fancy: !model.fancy }, [])
		Open => ({ ..model, open: !model.open }, [])
		Count => ({ ..model, count: model.count + 1 }, [])
		Named(name) => ({ ..model, name }, [])
	}

item : Str, Bool -> Html(Msg)
item = |name, fancy| {
	mark = if fancy element("em", [class("mark")], [text("*")]) else span([class("mark")], [text("-")])
	tags = if fancy ["x", "y"] else ["y", "x"]
	Html.keyed(
		name,
		li(
			[class("item")],
			[
				text(name),
				mark,
				ul([class("tags")], tags.map(|tag| Html.keyed(tag, li([class("tag")], [text(tag)])))),
			],
		),
	)
}

render : Model -> Html(Msg)
render = |model|
	div(
		[class("others")],
		[
			div(
				[class("controls")],
				[
					button([class("rotate"), on_click(Rotate)], [text("rotate")]),
					button([class("add"), on_click(Add)], [text("add")]),
					button([class("drop"), on_click(Drop)], [text("drop")]),
					button([class("fresh"), on_click(Fresh)], [text("fresh")]),
					button([class("swap"), on_click(Swap)], [text("swap")]),
					button([class("spin"), on_click(Spin)], [text("spin")]),
					button([class("open"), on_click(Open)], [text("open")]),
					button([class("count"), on_click(Count)], [text("count")]),
				],
			),
			input([class("name"), value(model.name), on_input(|s| Named(s))]),
			div(
				[class("media")],
				[if model.fancy element("video", [class("clip")], []) else element("img", [class("clip")], [])],
			),
			ul([class("items")], model.items.map(|name| item(name, model.fancy))),
			# x-note is a custom element: the browser test defines it with a
			# connectedCallback that inserts next to it inside the runtime's insert.
			div([class("panel")], if model.open [element("x-note", [], [text("one")]), p([], [text("two")])] else []),
			element("figure", [class("map")], []),
			span([class("total")], [text("count ${model.count.to_str()}")]),
			span([class("echo")], [text("name ${model.name}")]),
		],
	)
