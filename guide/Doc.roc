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

	## A name from the API in code, linked to its docs. "Sub.map" and
	## "Time.after(ms, to_msg)" link to the value, "Media" and "pf.Media" to
	## the module. Html names link to joy-html's docs.
	api : Str -> Html([])
	api = |shown| {
		name = (shown.split_first("(").map_ok(|{ before, .. }| before) ?? shown).drop_prefix("pf.")
		home : Str
		home =
			match name.split_first(".") {
				Ok({ before, .. }) => before
				Err(_) => name
			}
		anchor : Str
		anchor = if (home == name) "" else "#${name}"
		docs = if (home == "Html") "https://niclas-ahden.github.io/joy-html/main/" else Doc.api_docs
		Html.a([Attribute.href("${docs}${home}/${anchor}")], [Html.code([], [text(shown)])])
	}

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

	## One of the examples, whole, to edit and run.
	example : Str, Str -> Html([])
	example = |file, roc| Doc.editor(Doc.code(Roc, file, roc))

	## How a sample names Joy's platform. The Deploy docs workflow writes the
	## release's own URL in its place.
	platform_line : Str
	platform_line = "pf: platform \"https://github.com/niclas-ahden/joy/releases/download/VERSION/HASH.tar.zst\""

	## Joy's command line in a release, as `roc run` takes it. The Deploy docs
	## workflow writes the release's own URL in its place.
	cli_url : Str
	cli_url = "https://github.com/niclas-ahden/joy/releases/download/VERSION/CLI.tar.zst"

	## A command line whose text is put together in Roc. One written out is a
	## Doc.code.
	command : Str -> Html([])
	command = |line| Doc.code(Sh, "", line)

	## The Roc nightly the latest Joy release is tested with. The Test latest
	## Joy release on latest nightly Roc workflow moves it forward, so it
	## spells out the whole tag.
	roc_nightly : Str
	roc_nightly = "nightly-2026-11-18-a520eed"

	## A whole app with the page it is on, for an app whose page matters:
	## its flags, its stylesheet or its own JavaScript. `file` and `roc` are
	## the app, `page` its index.html, which the editor shows beside it.
	with_page : Str, Str, Str -> Html([])
	with_page = |file, roc, page|
		div([class("editor"), data("editor", "")], [Doc.code(Roc, file, roc), Doc.code(Html, "index.html", page)])

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
