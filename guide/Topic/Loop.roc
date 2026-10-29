import html.Html exposing [code, element, h1, h2, li, ol, p, strong, svg, text, ul]
import html.Attribute exposing [aria, attribute, class, id, role]
import /Doc

## The topic "Enough to be dangerous", a recap of the loop every app runs.
Loop := [].{
	body : Doc.Body
	body = [
		p([class("eyebrow")], [text("Start here")]),
		h1([], [text("Enough to be dangerous")]),
		p(
			[class("lead")],
			[
				text("You now know enough Joy to be dangerous! Here's all of it in brief. Every Joy app runs this same loop:"),
			],
		),
		loop_diagram,
		p(
			[class("loop-caption")],
			[
				text("The violet boxes are the functions you write. Joy does everything else. The arrows show what is handed on."),
			],
		),
		ol(
			[],
			[
				li(
					[],
					[
						code([], [text("init")]),
						text(" returns the first model. The model is the whole state of your app."),
					],
				),
				li(
					[],
					[
						text("Joy calls "),
						code([], [text("view")]),
						text(" with the model and puts the HTML on the page. After the first time it changes only what differs."),
					],
				),
				li(
					[],
					[
						text("Something happens: the user clicks or types, or a request is answered. Each of these is a message, like "),
						code([], [text("UserClickedIncrement")]),
						text("."),
					],
				),
				li(
					[],
					[
						text("Joy calls "),
						code([], [text("update")]),
						text(" with the model and the message. You return the next model and a list of effects."),
					],
				),
				li(
					[],
					[
						text("Joy runs the effects and goes back to step 2 with the next model. The result of an effect comes back as a message, in step 3."),
					],
				),
			],
		),
		h2([], [text("What follows from it")]),
		ul(
			[],
			[
				li(
					[],
					[
						strong([], [text("One source of truth.")]),
						text(" The page is always "),
						code([], [text("view(model)")]),
						text(". There is no hidden state in the DOM that the model does not know about."),
					],
				),
				li(
					[],
					[
						strong([], [text("Effects are data.")]),
						text(" "),
						code([], [text("update")]),
						text(" describes what should happen, it never actually DOES anything itself. That makes "),
						code([], [text("update")]),
						text(" easy to test: call it and look at what it returns."),
					],
				),
				li(
					[],
					[
						strong([], [text("Your messages are the complete history.")]),
						text(" Every change to the model came from a message, so a list of messages explains how the app got where it is."),
					],
				),
			],
		),
	]
}

## The loop as a drawing. Boxes are who acts, arrows carry what is handed on.
## The main loop runs view, the page, update and back to view. Effects hang
## below update. www/style.css colours it.
loop_diagram : Html([])
loop_diagram =
	svg(
		[
			class("loop"),
			attribute("viewBox", "0 14 460 372"),
			role("img"),
			aria("label", "The loop. init returns the first model. view turns the model into Html. Joy puts it on the page. A click or a key press becomes a message. update takes the message and returns the next model, which goes back to view, and effects. Joy runs the effects, and their results come back to update as messages."),
		],
		[
			element(
				"defs",
				[],
				[
					element(
						"marker",
						[
							id("loop-head"),
							attribute("viewBox", "0 0 10 10"),
							attribute("refX", "9"),
							attribute("refY", "5"),
							attribute("markerWidth", "7"),
							attribute("markerHeight", "7"),
							attribute("orient", "auto"),
						],
						[element("path", [attribute("d", "M0 0 L10 5 L0 10 z")], [])],
					),
				],
			),
			# init to view
			flow("M78 56 H145"),
			words("data", "middle", 111, 44, "Model"),
			# view to the page
			flow("M225 56 H288"),
			words("data", "middle", 256, 44, "Html"),
			# the page to update
			flow("M350 82 V186"),
			words("data", "end", 340, 126, "Msg"),
			words("note", "end", 340, 144, "a click, a key press"),
			# update back to view
			flow("M302 206 H185 V76"),
			words("data", "middle", 243, 194, "next Model"),
			# update to the effects and back
			flow("M332 226 V320"),
			words("data", "end", 322, 273, "effects"),
			flow("M368 320 V226"),
			words("data", "start", 378, 265, "Msg"),
			words("note", "start", 378, 283, "the result"),
			box("you", 45, 56, 33, 20),
			words("name", "middle", 45, 56, "init"),
			box("you", 185, 56, 40, 20),
			words("name", "middle", 185, 56, "view"),
			box("joy", 350, 56, 62, 26),
			words("title", "middle", 350, 47, "The page"),
			words("note", "middle", 350, 66, "Joy updates it"),
			box("you", 350, 206, 48, 20),
			words("name", "middle", 350, 206, "update"),
			box("joy", 350, 346, 62, 26),
			words("title", "middle", 350, 337, "Effects"),
			words("note", "middle", 350, 356, "Joy runs them"),
		],
	)

## A box centred on a point, given half its width and half its height.
box : Str, I64, I64, I64, I64 -> Html([])
box = |kind, cx, cy, half_width, half_height|
	element(
		"rect",
		[
			class(kind),
			attribute("x", (cx - half_width).to_str()),
			attribute("y", (cy - half_height).to_str()),
			attribute("width", (half_width * 2).to_str()),
			attribute("height", (half_height * 2).to_str()),
		],
		[],
	)

## Words at a point. `anchor` is start, middle or end.
words : Str, Str, I64, I64, Str -> Html([])
words = |kind, anchor, x, y, says|
	element(
		"text",
		[
			class(kind),
			attribute("text-anchor", anchor),
			attribute("x", x.to_str()),
			attribute("y", y.to_str()),
		],
		[text(says)],
	)

## An arrow along a path.
flow : Str -> Html([])
flow = |d| element("path", [class("flow"), attribute("d", d), attribute("marker-end", "url(#loop-head)")], [])
