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
				text("The notes of the "),
				a([href("https://github.com/niclas-ahden/joy/releases/latest")], [text("Joy release")]),
				text(" you're using say which Roc version you need, under \"Roc compiler version\". It looks like "),
				code([], [text("roc nightly-2026-11-15-f25da45")]),
				text(", and the last part, "),
				code([], [text("f25da45")]),
				text(", is what tells one version from another."),
			],
		),
		p(
			[],
			[
				text("The easiest way to get exactly that version is "),
				a([href("https://github.com/imclerran/rocup")], [text("rocup")]),
				text(". Install it the way its README says, then give it that last part:"),
			],
		),
		Doc.code(
			Sh,
			"",
			\\rocup <last part>
		),
		p(
			[],
			[
				text("You can also download it yourself. The version in the release notes is a link to its files: get the one for your system, unpack it, and put the "),
				code([], [text("roc")]),
				text(" in it on your "),
				code([], [text("PATH")]),
				text("."),
			],
		),
		p(
			[],
			[
				a([href("https://www.roc-lang.org/install")], [text("Roc's own installer")]),
				text(" installs a recent version, which is not always the one Joy names. Joy often works with it anyway. If something fails, get the one in the release notes."),
			],
		),
		p([], [text("Check which one you have:")]),
		Doc.code(
			Sh,
			"",
			\\roc version
		),
		h2([], [text("Start a project")]),
		Doc.code(
			Sh,
			"",
			\\roc run <cli url> init my-app
		),
		p(
			[],
			[
				text("Take "),
				code([], [text("<cli url>")]),
				text(" from the notes of the latest release too. This runs Joy's command line straight from the release, which takes a few seconds the first time. You get to pick a template, so pick the one you want."),
			],
		),
		p(
			[],
			[
				text("You now have a folder called "),
				code([], [text("my-app")]),
				text(" with an app in it, and a command called "),
				code([], [text("./joy")]),
				text(". That's the one you use from now on. The project's README says what the files in it are for."),
			],
		),
		p(
			[],
			[
				code([], [text("./joy")]),
				text(" is built for your machine, so it stays out of git. The "),
				code([], [text(".gitignore")]),
				text(" for that is written for you, and the README shows how to install "),
				code([], [text("./joy")]),
				text(" again after a fresh clone."),
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
				text(" and there's your app."),
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
