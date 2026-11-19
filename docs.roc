#!/usr/bin/env roc
# Run:
#
#   ./docs.roc
#   ./docs.roc --output=site/main
#
# To write the platform's API docs into generated-docs/, or the folder
# `--output` names, and make two changes to what `roc docs` writes:
#
# - A few words of welcome on the first page. `roc docs` leaves that page
#   empty for a package of several modules and has no place to take an intro
#   from.
# - No `:= []` under the name of a module that is only a place for its
#   functions, like Http. It is how such a module is written, and says
#   nothing to someone reading its docs.
#
# Run from the repo root.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
}

import pf.OsStr
import pf.Path
import pf.Stdout
import Util exposing [fail!, run!]

# Where the intro goes: right above the drawing roc docs fills the page with.
marker = "        <div class=\"index-decoration\">"

# The classes are the ones a module's page has, so the intro reads like the
# top of one. The guide is one folder up from the docs of any release.
intro =
	\\        <div class="main-content">
	\\        <h1 class="module-name">Joy API Documentation</h1>
	\\        <div class="module-doc">
	\\        <p>Hi there! Check out each module in the menu and please <a href="https://github.com/niclas-ahden/joy/issues">report an issue</a> or <a href="https://github.com/niclas-ahden/joy/pulls">open a pull request</a> if you see potential for improvements.</p>
	\\        <p>Want an introduction to Joy? See <a href="../">the Joy guide</a>, that's the best place to get started!</p>
	\\        </div>
	\\        </div>
	\\

# What `roc docs` writes under a module's name when the module is a type with
# no values, there to hold functions.
empty_type = "        <pre class=\"entry-type-def\"><code class=\"entry-type-def-code\">:= []</code></pre>\n"

main! = |args| {
	dir = args.map(OsStr.display).find_first(|arg| arg.starts_with("--output=")).map_ok(|arg| arg.drop_prefix("--output=")) ?? "generated-docs"
	run!("roc", ["docs", "platform/main.roc", "--output=${dir}"])?

	index = Path.utf8("${dir}/index.html")
	page =
		match index.read_utf8!() {
			Ok(text) => text
			Err(_) => fail!("roc docs wrote no ${dir}/index.html")?
		}
	match page.split_first(marker) {
		Ok({ before, after }) => index.write_utf8!("${before}${intro}${marker}${after}")?
		Err(_) => fail!("The first page of the docs no longer has the place where docs.roc puts Joy's intro. Look at what roc docs writes in ${dir}/index.html now, and change `marker` in docs.roc.")?
	}
	pages = Path.utf8(dir).list!()?.map(|entry| Path.utf8("${Path.display(entry)}/index.html"))
	var $tidied = 0.U64
	for module_page in pages {
		match module_page.read_utf8!() {
			Ok(html) =>
				if html.contains(empty_type) {
					module_page.write_utf8!(html.replace_each(empty_type, ""))?
					$tidied = $tidied + 1
				} else {
					{}
				}

			# Not a module's folder.
			Err(_) => {}
		}
	}
	Stdout.line!("The API docs are in ${dir}, with Joy's intro on their first page and ${$tidied.to_str()} modules without an empty type under their name.")
}
