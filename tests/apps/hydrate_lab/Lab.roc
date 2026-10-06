import html.Html exposing [button, div, element, input, meta, option, select, span, table, tbody, td, text, textarea, tr]
import html.Attribute exposing [attribute, checked, class, disabled, id, name, on_change, on_check, on_click, on_input, selected, type, value]

## The hydration lab's view, shared by the client (app.roc) and the page
## generator (ssr.roc), so the server and the client render one view and the
## browser's own parser decides whether they agree. It holds what HTML
## serializes lossily or a parser rewrites: SVG and MathML with names the
## parser adjusts, form controls whose state HTML expresses differently than
## a view declares it, a <pre> starting with a newline, elements with a DOM
## property named `content` (a template's fragment, a meta's string), and the
## switches the generator flips to make the server's page disagree on
## purpose.
Lab := [].{
	Model : {
		name : Str,
		bio : Str,
		size : Str,
		color : Str,
		agree : Bool,
		code : Str,
		square : Bool,
		icons : List(Str),
		next : U64,
		math : Bool,
		count : U64,
		locked : Bool,
		stale : Bool,
		bare_rows : Bool,
		contents : Bool,
		nudges : U64,
	}

	Msg : [Named(Str), Bio(Str), Sized(Str), Colored(Str), Agreed(Bool), Count, ToggleShape, AddIcon, Rotate, ToggleMath, Nudged]

	default : Model
	default = {
		name: "Ann",
		bio: "First line\nsecond line",
		size: "m",
		color: "blue",
		agree: Bool.True,
		code: "\nindented()",
		square: Bool.False,
		icons: ["a", "b"],
		next: 0,
		math: Bool.False,
		count: 0,
		locked: Bool.False,
		stale: Bool.False,
		bare_rows: Bool.False,
		contents: Bool.False,
		nudges: 0,
	}

	decode : Str -> Try(Model, _)
	decode = |flags| {
		parsed : Try(Model, _)
		parsed = Json.parse(flags)
		parsed
	}

	encode : Model -> Str
	encode = |model| Json.to_str(model)

	update : Model, Msg -> Model
	update = |model, msg|
		match msg {
			# Refuses "!", so a value typed before boot can be refused too.
			Named(n) => if n.contains("!") { model } else { { ..model, name: n } }
			Bio(bio) => { ..model, bio }
			Sized(size) => { ..model, size }
			Colored(color) => { ..model, color }
			Agreed(agree) => { ..model, agree }
			Count => { ..model, count: model.count + 1 }
			ToggleShape => { ..model, square: !model.square }
			AddIcon => { ..model, icons: model.icons.append("n${model.next.to_str()}"), next: model.next + 1 }
			Rotate => { ..model, icons: model.icons.drop_first(1).concat(model.icons.take_first(1)) }
			ToggleMath => { ..model, math: !model.math }
			Nudged => { ..model, nudges: model.nudges + 1 }
		}

	view : Model -> Html(Msg)
	view = |model|
		div(
			[class("lab")],
			[
				forms(model),
				element("pre", [class("code")], [text(model.code)]),
				button(
					if model.stale {
						[class("count stale-class"), attribute("data-stale", "1"), disabled(model.locked), on_click(Count)]
					} else {
						[class("count"), disabled(model.locked), on_click(Count)]
					},
					[text("count")],
				),
				button([class("shape"), on_click(ToggleShape)], [text("shape")]),
				button([class("add"), on_click(AddIcon)], [text("add")]),
				button([class("rotate"), on_click(Rotate)], [text("rotate")]),
				button([class("math"), on_click(ToggleMath)], [text("math")]),
				drawing(model),
				if model.math {
					formula
				} else {
					text("")
				},
				rows(model),
			].concat(if model.contents contents_view else []),
		)
}

forms : Lab.Model -> Html(Lab.Msg)
forms = |model|
	div(
		[class("forms")],
		[
			input([class("name"), value(model.name), on_input(|s| Named(s))]),
			textarea([class("bio"), value(model.bio), on_input(|s| Bio(s))], []),
			select([class("size"), on_change(|s| Sized(s))], ["s", "m", "l"].map(|v| option([value(v), selected(model.size == v)], [text(v)]))),
			input([class("red"), type("radio"), name("color"), value("red"), checked(model.color == "red"), on_change(|s| Colored(s))]),
			input([class("blue"), type("radio"), name("color"), value("blue"), checked(model.color == "blue"), on_change(|s| Colored(s))]),
			input([class("agree"), type("checkbox"), checked(model.agree), on_check(|now| Agreed(now))]),
			# Untouched controls whose value the browser makes up, since the
			# markup has none: a range sits at its midpoint, a color reads
			# #000000. Neither is something the visitor typed ahead.
			input([class("slider"), type("range"), on_input(|_| Nudged)]),
			input([class("tint"), type("color"), on_input(|_| Nudged)]),
			span([class("nudges")], [text("nudges ${model.nudges.to_str()}")]),
			span(
				[class("echo")],
				[text("${model.name}|${model.bio}|${model.size}|${model.color}|${if model.agree "yes" else "no"}|${model.count.to_str()}")],
			),
		],
	)

drawing : Lab.Model -> Html(Lab.Msg)
drawing = |model|
	element(
		"svg",
		[class("canvas"), attribute("viewbox", "0 0 100 100"), attribute("width", "200"), attribute("height", "200")],
		[
			element(
				"defs",
				[],
				[
					element("lineargradient", [id("grad")], [element("stop", [attribute("offset", "0"), attribute("stop-color", "red")], [])]),
					element("symbol", [id("dot"), attribute("viewbox", "0 0 10 10")], [element("circle", [attribute("cx", "5"), attribute("cy", "5"), attribute("r", "5")], [])]),
				],
			),
			if model.square {
				element("rect", [class("shape"), attribute("x", "10"), attribute("y", "10"), attribute("width", "30"), attribute("height", "30")], [])
			} else {
				element("circle", [class("shape"), attribute("cx", "25"), attribute("cy", "25"), attribute("r", "15"), attribute("fill", "url(#grad)")], [])
			},
			element("use", [class("sprite"), attribute("xlink:href", "#dot"), attribute("x", "50"), attribute("y", "5"), attribute("width", "10"), attribute("height", "10")], []),
			element(
				"foreignobject",
				[attribute("x", "0"), attribute("y", "60"), attribute("width", "100"), attribute("height", "40")],
				[div([class("inside-fo")], [text("html again")])],
			),
			element("desc", [], [span([class("in-desc")], [text("described")])]),
			element("g", [class("icons")], model.icons.map(|n| Html.keyed(n, icon(n)))),
		],
	)

icon : Str -> Html(Lab.Msg)
icon = |n|
	element(
		"g",
		[class("icon"), attribute("data-name", n)],
		[
			element("title", [], [text(n)]),
			element("use", [attribute("href", "#dot"), attribute("x", "80"), attribute("y", "80"), attribute("width", "8"), attribute("height", "8")], []),
		],
	)

formula : Html(Lab.Msg)
formula =
	element(
		"math",
		[class("formula")],
		[
			element("mi", [], [text("x"), span([class("in-mi")], [text("html")]), element("mglyph", [], [])]),
			element("mrow", [], [element("mo", [], [text("+")]), element("mn", [], [text("1")])]),
			element("annotation-xml", [attribute("encoding", "text/html")], [div([class("in-annotation")], [text("html")])]),
			element("annotation-xml", [], [element("svg", [class("svg-in-math")], [])]),
		],
	)

# Two elements with a DOM property named `content`: a template, whose
# children the parser moves into that fragment, and microdata's <meta>,
# whose `content` is its attribute as a string.
contents_view : List(Html(Lab.Msg))
contents_view = [
	element("template", [class("stamp")], [div([class("in-template")], [text("stamped")])]),
	div([attribute("itemscope", "")], [meta([attribute("itemprop", "lab"), attribute("content", "claimed")])]),
]

rows : Lab.Model -> Html(Lab.Msg)
rows = |model| {
	cells = [tr([], [td([], [text("one")])]), tr([], [td([], [text("two")])])]
	if model.bare_rows {
		# Rows straight in the table, which the parser wraps in a tbody.
		table([class("rows")], cells)
	} else {
		table([class("rows")], [tbody([], cells)])
	}
}
