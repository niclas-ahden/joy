import html.Html exposing [button, code, div, h3, li, ol, p, pre, span, text]
import html.Attribute exposing [aria, class, data, type]
import /Highlight

## A walk-through: code that stays on screen while the reader goes through
## what it does, a step at a time. The page's script follows
## the scroll and shows what each step leaves behind. Without the script it
## reads as the code and then the steps.
Walk := [].{

	## A step: its title, its text, and what else it shows, like the lines it
	## is about (see `excerpt`).
	Step : { title : List(Html([])), body : List(Html([])), more : List(Html([])) }

	## Something the steps change, like the model, and what it is at each (see `at`).
	Value : { name : Str, states : List(Html([])) }

	## Lines of the code, lit during the steps `during` names, like "2 6".
	## They must appear in code the suite compiles (see tests/check_guide.mjs).
	lines : Str, Str -> Html([])
	lines = |during, src| span([class("walk-lines"), data("lit", during)], Highlight.source(Roc, src))

	## The space between two definitions.
	gap : Html([])
	gap = span([class("walk-gap")], [])

	## What is shown during the steps `during` names, counting from 0.
	at : Str, List(Html([])) -> Html([])
	at = |during, children| span([class("walk-at"), data("at", during)], children)

	## A few lines for a step. A narrow window has no room for the whole code,
	## so there each step shows its own. Roc in one must appear in code the
	## suite compiles, as with `lines`.
	excerpt : [Roc, Js, Sh, Html, Text], Str -> Html([])
	excerpt = |lang, src| {
		name = match lang {
			Roc => "roc"
			Js => "js"
			Sh => "sh"
			Html => "html"
			Text => ""
		}
		pre([class("walk-excerpt"), data("lang", name)], [code([], Highlight.source(lang, src))])
	}

	## The walk-through. `code` is made of `lines` and `gap`, and `screen` and each
	## value's states of `at`.
	view : { file : Str, code : List(Html([])), screen : List(Html([])), values : List(Value), steps : List(Step) } -> Html([])
	view = |walk| {
		numbered = walk.steps.fold(
			{ n: 0, out: [] },
			|acc, step| { n: acc.n + 1, out: acc.out.append(step_view(acc.n, step)) },
		)
		div(
			[class("walk"), data("walk", "")],
			[
				div(
					[class("walk-stage")],
					[
						div(
							[class("walk-code")],
							[
								div([class("code-head")], [span([class("file")], [text(walk.file)])]),
								pre([], [code([], walk.code)]),
							],
						),
						div(
							[class("walk-side")],
							[
								div(
									[class("walk-now"), aria("hidden", "true")],
									[
										div([class("walk-app")], [label("The app"), div([class("walk-screen")], walk.screen)]),
										div([class("walk-values")], walk.values.map(value_view)),
										div(
											[class("walk-progress")],
											[
												span(
													[class("walk-count")],
													[text("Step "), span([data("walk-n", "")], [text("1")]), text(" of ${walk.steps.len().to_str()}")],
												),
												span([class("walk-bars")], walk.steps.map(|_| span([], []))),
											],
										),
									],
								),
								ol([class("walk-steps")], numbered.out),
								div(
									[class("walk-nav")],
									[
										button([type("button"), data("walk-back", "")], [text("Back")]),
										button([type("button"), data("walk-next", "")], [text("Next")]),
									],
								),
							],
						),
					],
				),
			],
		)
	}
}

label : Str -> Html([])
label = |name| span([class("walk-label")], [text(name)])

value_view : Walk.Value -> Html([])
value_view = |value| div([class("walk-value")], [label(value.name), code([], value.states)])

step_view : U64, Walk.Step -> Html([])
step_view = |n, step|
	li([class("walk-step"), data("at", n.to_str())], [h3([], step.title), p([], step.body)].concat(step.more))
