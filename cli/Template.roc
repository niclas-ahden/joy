import "../examples/templates/spa-minimal/README.md" as minimal_readme : Str
import "../examples/templates/spa-minimal/assets/css/style.css" as minimal_style : Str
import "../examples/templates/spa-minimal/client/app.roc" as minimal_app : Str
import "../examples/templates/spa-minimal/public/index.html" as minimal_index : Str
import "../examples/templates/spa-pages/README.md" as pages_readme : Str
import "../examples/templates/spa-pages/assets/css/style.css" as pages_style : Str
import "../examples/templates/spa-pages/client/Page/About.roc" as pages_page_about : Str
import "../examples/templates/spa-pages/client/Page/Home.roc" as pages_page_home : Str
import "../examples/templates/spa-pages/client/Page/Quote.roc" as pages_page_quote : Str
import "../examples/templates/spa-pages/client/Route.roc" as pages_route : Str
import "../examples/templates/spa-pages/client/app.roc" as pages_app : Str
import "../examples/templates/spa-pages/public/index.html" as pages_index : Str
import "../examples/templates/spa-pages-expanded/README.md" as expanded_readme : Str
import "../examples/templates/spa-pages-expanded/assets/css/style.css" as expanded_style : Str
import "../examples/templates/spa-pages-expanded/client/Notebook.roc" as expanded_notebook : Str
import "../examples/templates/spa-pages-expanded/client/Page.roc" as expanded_page : Str
import "../examples/templates/spa-pages-expanded/client/Page/About.roc" as expanded_page_about : Str
import "../examples/templates/spa-pages-expanded/client/Page/Note.roc" as expanded_page_note : Str
import "../examples/templates/spa-pages-expanded/client/Page/Notes.roc" as expanded_page_notes : Str
import "../examples/templates/spa-pages-expanded/client/Page/Quote.roc" as expanded_page_quote : Str
import "../examples/templates/spa-pages-expanded/client/Route.roc" as expanded_route : Str
import "../examples/templates/spa-pages-expanded/client/app.roc" as expanded_app : Str
import "../examples/templates/spa-pages-expanded/public/index.html" as expanded_index : Str

## The projects `./joy init` starts from. Each is a folder under
## examples/templates/ and a Joy project of its own, whose bundles name
## this checkout's platform, so it builds where it is. Its files are built
## into ./joy.
## A description shares the name's line in the prompt of ./joy init, so it
## is kept short enough for a terminal 80 columns wide.
Template :: [].{

	## `ignored` is what the project keeps out of git besides ./joy's own
	## files, as lines of its .gitignore.
	Template : { name : Str, description : Str, files : List((Str, Str)), ignored : List(Str) }

	all : List(Template.Template)
	all = [
		{
			name: "spa-minimal",
			description: "A single file with a counter example.",
			files: [
				("README.md", minimal_readme),
				("assets/css/style.css", minimal_style),
				("client/app.roc", minimal_app),
				("public/index.html", minimal_index),
			],
			ignored: [],
		},
		{
			name: "spa-pages",
			description: "Routing and pages, with one state for the whole app.",
			files: [
				("README.md", pages_readme),
				("assets/css/style.css", pages_style),
				("client/Page/About.roc", pages_page_about),
				("client/Page/Home.roc", pages_page_home),
				("client/Page/Quote.roc", pages_page_quote),
				("client/Route.roc", pages_route),
				("client/app.roc", pages_app),
				("public/index.html", pages_index),
			],
			ignored: [],
		},
		{
			name: "spa-pages-expanded",
			description: "Like spa-pages, with state and messages per page.",
			files: [
				("README.md", expanded_readme),
				("assets/css/style.css", expanded_style),
				("client/Notebook.roc", expanded_notebook),
				("client/Page.roc", expanded_page),
				("client/Page/About.roc", expanded_page_about),
				("client/Page/Note.roc", expanded_page_note),
				("client/Page/Notes.roc", expanded_page_notes),
				("client/Page/Quote.roc", expanded_page_quote),
				("client/Route.roc", expanded_route),
				("client/app.roc", expanded_app),
				("public/index.html", expanded_index),
			],
			ignored: [],
		},
	]

	## How a template's bundles name the platform. Init puts the project's own
	## platform in its place.
	platform_line : Str
	platform_line = "platform \"../../../../platform/main.roc\""

	## Where a template's README shows the command that installs ./joy in a
	## fresh clone. Init writes the command there.
	install_command : Str
	install_command = "<INSERT JOY INSTALL COMMAND HERE>"
}
