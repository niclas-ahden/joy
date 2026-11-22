import html.Html exposing [a, code, h1, h2, p, text]
import html.Attribute exposing [class, href]
import /Doc

## The topic "Joy on your machine".
Install := [].{
	body : Doc.Body
	body = [
		p([class("eyebrow")], [text("Installation")]),
		h1([], [text("Joy on your machine")]),
		p(
			[class("lead")],
			[
				text("So far everything has run right here in the browser. Now let's put Joy on your machine and start a project of your own. It takes a couple of minutes."),
			],
		),
		h2([], [text("Install Roc")]),
		p(
			[],
			[
				text("Install Roc ${Doc.roc_release} or later. You'll get that from the official "),
				a([href("https://www.roc-lang.org/install")], [text("roc-lang.org installation guide")]),
				text("."),
			],
		),
		p([], [text("Check that you've got the correct version:")]),
		Doc.code(
			Sh,
			"",
			\\roc version
		),
		h2([], [text("Start a project")]),
		Doc.command("roc run ${Doc.cli_url} init my-app"),
		p(
			[],
			[
				text("This runs Joy's command line straight from the release, which takes a few seconds the first time. You get to pick a template to start from."),
			],
		),
		p(
			[],
			[
				text("You now have a folder called "),
				code([], [text("my-app")]),
				text(" with an app in it, and a command called "),
				code([], [text("./joy")]),
				text(". That's the one you use from now on. See your new project's README for an explanation of what files are in it."),
			],
		),
		h2([], [text("Run it")]),
		Doc.code(
			Sh,
			"",
			\\cd my-app
			\\./joy dev
		),
		p(
			[],
			[
				text("Open "),
				a([href("http://localhost:8000")], [text("http://localhost:8000")]),
				text(" and there's your app!"),
			],
		),
		p(
			[],
			[
				text("Now change some text in its "),
				code([], [text("view")]),
				text(" and save. The page takes the change as you save, no refresh needed :) Make a mistake and the compiler's report shows up over the page until you fix it."),
			],
		),
		h2([], [text("Ship it")]),
		Doc.code(
			Sh,
			"",
			\\./joy build
		),
		p(
			[],
			[
				text("That writes everything you deploy into "),
				code([], [text("dist/")]),
				text(". There's more about both commands in "),
				code([], [text("./joy --help")]),
				text("."),
			],
		),
	]
}
