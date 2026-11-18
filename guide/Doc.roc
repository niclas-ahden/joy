import html.Html exposing [button, div, pre, span, text]
import html.Attribute exposing [class, data, type]
import /Highlight

## What the topics are built from beyond plain joy-html: a code block with
## its file's name, highlighting and a Copy button. The topics are rendered
## into the page when it is built (see Page), and the page's script makes
## the button copy the block.
Doc := [].{

	## A topic's text. Nothing in it sends a message.
	Body : List(Html([]))

	Lang : [Roc, Js, Sh, Html, Text]

	## The address of the API docs for the release the guide is about. The
	## Deploy docs workflow writes that release in place of LATESTVERSION.
	api_docs : Str
	api_docs = "./LATESTVERSION/"

	## A code block. `file` labels it, and an empty one falls back to the
	## language's name. Roc in one must appear in code the suite compiles (see
	## tests/check_guide.mjs).
	code : Lang, Str, Str -> Html([])
	code = |lang, file, src| {
		label = if (file == "") short_name(lang) else file
		div(
			[class("code"), data("lang", short_name(lang))],
			[
				div([class("code-head")], [span([class("file")], [text(label)]), button([type("button"), class("copy")], [text("Copy")])]),
				pre([], [Html.code([], Highlight.source(lang, src))]),
			],
		)
	}

	## A whole app to edit and run in the page. `block` is its code, a
	## Doc.code, which the page's script turns into an editor beside the
	## running app (see www/editor.js). Without the script it stays an
	## ordinary code block.
	editor : Html([]) -> Html([])
	editor = |block| div([class("editor"), data("editor", "")], [block])

	## The same with the app's header folded away, for a first look at an app.
	## The reader can open it.
	editor_folded : Html([]) -> Html([])
	editor_folded = |block| div([class("editor"), data("editor", "folded")], [block])

	## A code block whose Roc cannot compile, like two rival definitions shown side
	## by side, so tests/check_guide.mjs leaves it alone.
	sketch : Lang, Str, Str -> Html([])
	sketch = |lang, file, src| Doc.code(lang, file, src)
}

short_name : Doc.Lang -> Str
short_name = |lang|
	match lang {
		Roc => "roc"
		Js => "js"
		Sh => "sh"
		Html => "html"
		Text => ""
	}
