import html.Html exposing [a, code, h1, h2, li, p, text, ul]
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
				text("Use the "),
				a([href("https://www.roc-lang.org/install")], [text("roc-lang.org installation guide")]),
				text(" and add Roc to your "),
				code([], [text("PATH")]),
				text("."),
			],
		),
		p([], [text("Check that you've got Roc ${Doc.roc_release} or later:")]),
		Doc.code(
			Sh,
			"",
			\\roc version
		),
		h2([], [text("Start a project")]),
		p([], [text("Run the starter which guides you through starting a project:")]),
		Doc.command("roc run ${Doc.cli_url} init"),
		p(
			[],
			[
				text("You then have a directory with your new project and a command called "),
				code([], [text("./joy")]),
				text(" inside. From now on you can use "),
				code([], [text("./joy")]),
				text(" to run, build, and upgrade your project to new Joy releases!"),
			],
		),
		p(
			[],
			[
				text("Have a look at the "),
				code([], [text("README.md")]),
				text(" in your new project to learn more about it."),
			],
		),
		h2([], [text("Run it")]),
		p(
			[],
			[
				text("Step into your project and use "),
				code([], [text("./joy dev")]),
				text(" to run and serve it:"),
			],
		),
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
				text("Now try the hot-reloading by changing some text in a "),
				code([], [text("view")]),
				text(" and see the change on the page right away :) Likewise if you make a mistake you'll see the compilation error in your browser, and it goes away when you fix it."),
			],
		),
		h2([], [text("Ship it")]),
		Doc.code(
			Sh,
			"",
			\\./joy build
		),
		p([], [text("That writes everything you deploy into "), code([], [text("dist/")]), text(":")]),
		ul(
			[],
			[
				li([], [text("Your app, compiled to WebAssembly, and the JavaScript files Joy needs to run it.")]),
				li([], [text("Your files in "), code([], [text("public/")]), text(", as they are.")]),
				li(
					[],
					[
						text("Your files in "),
						code([], [text("assets/")]),
						text(", with a hash in each name so browsers can cache them for good and still get the new version after a deploy. The build updates the links in your "),
						code([], [text("index.html")]),
						text(" and stylesheets to match."),
					],
				),
				li([], [text("Your server, if your project has one. More about this in Joy 0.36.0 ;)")]),
			],
		),
		p([], [text("There's more about both commands in "), code([], [text("./joy --help")]), text(".")]),
	]
}
