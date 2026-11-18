import pf.Path
import joy_runtime.JoyRuntime
import Project

## The check that every effect an app uses has its JavaScript. An effect has
## two halves that only share an id: a call in Roc (`Effect.call`,
## `Effect.send` or `Sub.listen`) and a section of a JavaScript file, Joy's
## own or, for a custom effect, the file beside the Roc module. roc knows
## nothing of the second, so a misspelt id, or a module without its
## JavaScript, would build and then fail in the browser.
##
## The ids an app uses are in its wasm. The platform takes an id only as a
## string literal and marks each one (see Effect.Id), and roc drops the ones
## in code the app never reaches. So nothing is guessed from the source: the
## wasm says what is used, the JavaScript says what is defined, and the
## source is read only to point at the place.
##
## A problem is reported the way roc reports its own: where it is, the line
## with the place marked, what is wrong, and what to do about it.
CustomEffects := [].{

	## An id and what it is the id of.
	Defined : { id : Str, kind : [Effect, Subscription] }

	## A place an id is written in a Roc file. `shown` is its line and
	## `under` the part of that line to mark. `home` is the file the
	## JavaScript of the module's effects belongs in.
	Site : { file : Str, line : U64, column : U64, shown : Str, under : { at : U64, len : U64 }, home : Str }

	## The places `id` is written as a string in `source`, the text of `file`.
	## Comments do not count.
	sites : { file : Str, source : Str, home : Str }, Str -> List(Site)
	sites = |{ file, source, home }, id| {
		quoted = "\"${id}\""
		source
			.split_on("\n")
			.map_with_index(|shown, index| (shown, index + 1))
			.keep_if(|(shown, _)| !shown.trim_start().starts_with("#"))
			.map(
				|(shown, line)| {
					parts = shown.split_on(quoted)
					# What is before each place the id is written.
					parts.drop_last(1).map_with_index(
						|_, nth| {
							at = Str.join_with(parts.take_first(nth + 1), quoted).count_utf8_bytes() + 1
							{ file, line, column: at + 1, shown, under: { at, len: id.count_utf8_bytes() }, home }
						},
					)
				},
			)
			.join()
	}

	## What the JavaScript files in `sources` define.
	defined : List(Str) -> List(Defined)
	defined = |sources|
		sources
			.map(|source| JoyRuntime.sections(source) ?? [])
			.join()
			.keep_oks(
				|section|
					match section.kind {
						Effect => Ok({ id: section.name, kind: Effect })
						Subscription => Ok({ id: section.name, kind: Subscription })
						Helper => Err(Helper)
					},
			)

	## A report for each id among `used`, the ones in the app's wasm, that
	## has no JavaScript of its kind among `defined`. `written` says where an
	## id is in the source, and `scripts` are the files of JavaScript that
	## are there.
	problems : { used : List(Defined), defined : List(Defined), written : (Str -> List(Site)), scripts : List(Str) } -> List(Str)
	problems = |given|
		given.used
			.keep_if(|one| !given.defined.contains(one))
			.map(
				|one| {
					places = (given.written)(one.id)
					if given.defined.any(|other| other.id == one.id) {
						other_kind(one, places)
					} else {
						undefined(one, places, given.defined.keep_if(|other| other.kind == one.kind).map(|other| other.id), given.scripts)
					}
				},
			)

	## A report for each thing wrong in the JavaScript files a project and its
	## packages bring, whatever the app uses of them: a `////` line that
	## starts no section, an `import` line, an id that is Joy's or is defined
	## twice, and a section whose code does not define the id its line names.
	## `joys` are the ids of Joy's own.
	malformed : List({ file : Str, source : Str }), List(Str) -> List(Str)
	malformed = |scripts, joys| {
		lines_wrong =
			scripts
				.map(
					|{ file, source }| {
						numbered = source.split_on("\n").map_with_index(|line, index| (line, index + 1))
						unread =
							match JoyRuntime.sections(source) {
								Err(BadSection(header)) =>
									numbered.keep_if(|(line, _)| line == "//// ${header}").take_first(1).map(|(line, at)| not_a_section("${file}:${at.to_str()}", line))

								_ => []
							}
						brought_in = numbered.keep_if(|(line, _)| line.trim_start().starts_with("import ") or line.trim_start().starts_with("import{")).take_first(1).map(|(line, at)| import_line("${file}:${at.to_str()}", line))
						unread.concat(brought_in)
					},
				)
				.join()
		defines = scripts.map(|{ file, source }| CustomEffects.defined([source]).map(|one| { id: one.id, file })).join()
		reserved = defines.keep_if(|one| one.id.starts_with("joy/")).map(|one| joys_own(one.file, one.id))
		twice =
			defines
				.map_with_index(|one, index| (one, index))
				.keep_oks(
					|(one, index)|
						match defines.take_first(index).find_first(|other| other.id == one.id) {
							Ok(first) => Ok(defined_twice(one.id, first.file, one.file))
							Err(_) => if (joys.contains(one.id)) Ok(defined_twice(one.id, "Joy itself", one.file)) else Err(Once)
						},
				)
		drifted = CustomEffects.mismatched(scripts)
		# Code that defines an id under no line of its own is in no section.
		# Where a line and its code disagree, that report says it already.
		lost =
			if drifted.is_empty() {
				scripts
					.map(
						|{ file, source }|
							match JoyRuntime.sections(source) {
								Ok(sections) => {
									named = sections.map(|section| section.name)
									defines_in(source).drop_if(|one| named.contains(one.id)).map(|one| no_line(file, one.define, one.id))
								}
								Err(_) => []
							},
					)
					.join()
			} else {
				[]
			}
		lines_wrong.concat(reserved).concat(twice).concat(drifted).concat(lost)
	}

	## A report for each section in `scripts` whose code does not define the
	## id its `////` line names, so that the two cannot drift apart.
	mismatched : List({ file : Str, source : Str }) -> List(Str)
	mismatched = |scripts|
		scripts
			.map(
				|{ file, source }|
					(JoyRuntime.sections(source) ?? []).keep_oks(
						|section| {
							(word, define) =
								match section.kind {
									Effect => ("effect", "defineEffect")
									Subscription => ("subscription", "defineSubscription")
									Helper => return Err(Fine)
								}
							# A line that is commented out defines nothing.
							code = Str.join_with(section.code.split_on("\n").drop_if(|line| line.trim_start().starts_with("//")), "\n")
							if ["'", "\"", "`"].any(|quote| code.contains("${define}(${quote}${section.name}${quote}")) {
								Err(Fine)
							} else {
								Ok(unmatched(file, word, define, section.name))
							}
						},
					),
			)
			.join()

	## The files of JavaScript a project and its packages bring, by the paths
	## to say them by. Their code runs in the app's pages, so a build names
	## them.
	brought! : List(Project.Bundle) => List(Str)
	brought! = |bundles| Project.feature_files!(bundles).map(tidy)

	## Check the effects the app whose builds are `wasms` uses against the
	## JavaScript of Joy, of the project and of its packages.
	check! : List(Project.Bundle), List(List(U8)) => Try({}, [Problems(Str)])
	check! = |bundles, wasms| {
		first =
			match bundles {
				[bundle, ..] => bundle
				[] => return Ok({})
			}
		joys = read_all!((Path.utf8("${Project.www!(first)}/features").list!() ?? []).map(Path.display).keep_if(|file| file.ends_with(".js")))
		theirs = read_all!(Project.feature_files!(bundles))
		scripts = joys.concat(theirs)
		known = CustomEffects.defined(scripts.map(|script| script.source))
		marked =
			match wasms.map_try(JoyRuntime.ids_in) {
				Ok(found) => found.join()
				Err(problem) => return Err(Problems("Could not read the ids of the app's effects out of its wasm: ${Str.inspect(problem)}"))
			}
		used = marked.fold([], |seen, one| if (seen.contains(one)) seen else seen.append(one))
		# roc keeps each id in the wasm as the platform's id types mark it.
		# The text of one without a single mark means this roc does not.
		if used.is_empty() {
			long = known.map(|one| one.id).keep_if(|id| id.count_utf8_bytes() >= 12)
			bare = wasms.map(|wasm| JoyRuntime.texts_in(wasm, long) ?? []).join()
			match bare.first() {
				Ok(id) => return Err(Problems(unmarked(id)))
				Err(_) => {}
			}
		}
		drifted = CustomEffects.malformed(theirs, CustomEffects.defined(joys.map(|script| script.source)).map(|one| one.id))
		if drifted.is_empty() and used.all(|one| known.contains(one)) {
			return Ok({})
		}
		# Something is wrong, so the source is read to say where.
		sources =
			Project.bundle_sources!(bundles)
				.map_try!(|{ file, home }| Ok({ file: tidy(file), source: Path.utf8(file).read_utf8!() ?? "", home: tidy(home) }))
				?? []
		written = |id| sources.map(|source| CustomEffects.sites(source, id)).join()
		wrong = drifted.concat(CustomEffects.problems({ used, defined: known, written, scripts: scripts.map(|script| script.file) }))
		Err(Problems(Str.join_with(wrong, "\n\n")))
	}
}

read_all! : List(Str) => List({ file : Str, source : Str })
read_all! = |files| files.map_try!(|file| Ok({ file: tidy(file), source: Path.utf8(file).read_utf8!() ?? "" })) ?? []

## The word a section of JavaScript starts with, for this kind.
word_of : [Effect, Subscription] -> Str
word_of = |kind|
	match kind {
		Effect => "effect"
		Subscription => "subscription"
	}

## Where a report is about and what it shows of it: the first place the id is
## written, and the others in a line. An id that is in the wasm is in the
## source, so no place at all only stands for a source that could not be read.
shown_at : List(CustomEffects.Site), Str -> { at : Str, lines : List(Str), home : [Beside(Str), Unknown] }
shown_at = |places, id|
	match places {
		[first, .. as more] => {
			# The call before a test of it, when the id is in both.
			in_code = places.drop_if(|one| one.shown.trim_start().starts_with("expect"))
			(site, others) =
				match in_code {
					[code, ..] => (code, places.drop_if(|one| one == code))
					[] => (first, more)
				}
			also =
				if others.is_empty() {
					[]
				} else {
					["", "The id is also written at ${Str.join_with(others.map(place), " and ")}."]
				}
			{ at: place(site), lines: [excerpt(site)].concat(also), home: Beside(site.home) }
		}

		[] => { at: "in the app", lines: ["    \"${id}\""], home: Unknown }
	}

## The report of an id nothing defines. Ids that start the same way are the
## likely right spellings: the ones a slip of the hand away, or else all of
## them. Without any, what is missing is the JavaScript, so the report says
## where it goes and how it starts.
undefined : CustomEffects.Defined, List(CustomEffects.Site), List(Str), List(Str) -> Str
undefined = |{ id, kind }, places, known, scripts| {
	start =
		match id.split_first("/") {
			Ok({ before, .. }) => "${before}/"
			Err(_) => id
		}
	alike = closest(id, known.keep_if(|other| other.starts_with(start)).fold([], |seen, other| if (seen.contains(other)) seen else seen.append(other)))
	nearest =
		match alike.first() {
			Ok((steps, _)) => steps
			Err(_) => 0
		}
	slips = alike.keep_if(|(steps, _)| nearest <= 3 and steps <= nearest + 1).map(|(_, other)| other)
	shown = shown_at(places, id)
	(where_to, there) =
		match shown.home {
			Beside(home) => (home, scripts.contains(home))
			Unknown => ("the .js file beside the module that uses it", Bool.True)
		}
	released = where_to.contains("/roc/packages/")
	advice =
		if released and alike.is_empty() {
			[
				"The module is part of a released package, which came without its JavaScript,",
				"${file_name(where_to)}. That is for the package to put right: whoever releases",
				"it gives `roc bundle` the .js files along with the Roc files.",
			]
		} else if alike.is_empty() {
			[
				"No ${word_of(kind)} has an id that starts with ${start} yet, so the JavaScript",
				if (there) "of this one is still to be written. It goes in the module's JavaScript file," else "of this one is still to be written. It goes in a new file beside the module,",
				"${where_to}, and starts like this:",
				"",
				sketch(kind, id),
			]
		} else {
			(
				if slips.is_empty() {
					["These are the ones that start with ${start}:", ""].concat(alike.take_first(8).map(|(_, other)| "    ${other}"))
				} else {
					[if (slips.len() == 1) "Did you mean this one?" else "Did you mean one of these?", ""].concat(slips.take_first(4).map(|other| "    ${other}"))
				}
			).concat([
				"",
				"If the id is the one you meant, then its JavaScript is what is missing:",
				"a section that starts with `//// ${word_of(kind)} ${id}`",
				if (there) "in ${where_to}." else "in ${where_to}, a file to make beside the module.",
			])
		}
	Str.join_with(
		[heading("custom effect without javascript", shown.at), "", "No JavaScript defines the custom effect with this id:", ""]
			.concat(shown.lines)
			.concat([""])
			.concat(advice)
			.concat([
				"",
				"Hint: A custom effect is a call in Roc and JavaScript for the browser, joined",
				"by an id. roc cannot see the JavaScript, so ./joy checks that it is there.",
				"",
				read_more,
			]),
		"\n",
	)
}

## The report of an id that is defined, for the other of the two kinds.
other_kind : CustomEffects.Defined, List(CustomEffects.Site) -> Str
other_kind = |{ id, kind }, places| {
	(defines, uses, wants) =
		match kind {
			Effect => ("a subscription", "Effect.call or Effect.send", "`//// effect ${id}` and `defineEffect`")
			Subscription => ("an effect", "Sub.listen", "`//// subscription ${id}` and `defineSubscription`")
		}
	shown = shown_at(places, id)
	Str.join_with(
		[heading("custom effect of the other kind", shown.at), "", "The JavaScript with this id defines ${defines}, and the app uses it with ${uses}:", ""]
			.concat(shown.lines)
			.concat([
				"",
				"${uses} needs a section that starts with",
				"${wants}.",
				"",
				"Hint: Effect.call and Effect.send run an effect once. Sub.listen hears",
				"the events of a subscription until it is taken out of the app's list.",
				"",
				read_more,
			]),
		"\n",
	)
}

## The report of a `////` line that starts no section.
not_a_section : Str, Str -> Str
not_a_section = |at, line|
	Str.join_with(
		[
			heading("custom effect line not understood", at),
			"",
			"This line does not start a section:",
			"",
			"    ${line}",
			"",
			"A section starts with one of these, and its code follows:",
			"",
			"    //// effect <id>",
			"    //// subscription <id>",
			"    //// helper <name>",
			"",
			"After the id or the name can come `needs <helper> ...`, for the helpers",
			"the section uses.",
			"",
			read_more,
		],
		"\n",
	)

## The report of an `import` line in a file of custom effects.
import_line : Str, Str -> Str
import_line = |at, line|
	Str.join_with(
		[
			heading("custom effect file with an import line", at),
			"",
			"This line cannot stand where the file's code ends up:",
			"",
			"    ${line.trim()}",
			"",
			"./joy puts the code of this file into Joy's runtime, inside a block, and",
			"an import line is only allowed at the top of a file. Load the library",
			"where it is used instead, inside the effect:",
			"",
			"    const library = await import('https://example.com/library.js');",
			"",
			read_more,
		],
		"\n",
	)

## The ids a file's code defines, each with the function that does it. A line
## that is commented out defines nothing.
defines_in : Str -> List({ define : Str, id : Str })
defines_in = |source| {
	code = Str.join_with(source.split_on("\n").drop_if(|line| line.trim_start().starts_with("//")), "\n")
	["defineEffect", "defineSubscription"]
		.map(
			|define|
				code.split_on("${define}(").drop_first(1).keep_oks(
					|after| {
						quote = Str.from_utf8_lossy(Str.to_utf8(after).take_first(1))
						if ["'", "\"", "`"].contains(quote) {
							after.drop_prefix(quote).split_first(quote).map_ok(|parts| { define, id: parts.before })
						} else {
							Err(NotFound)
						}
					},
				),
		)
		.join()
}

## The report of code that defines an id no `////` line names.
no_line : Str, Str, Str -> Str
no_line = |file, define, id| {
	word = if (define == "defineSubscription") "subscription" else "effect"
	Str.join_with(
		[
			heading("custom effect code without its line", file),
			"",
			"This file defines an id that no `////` line names:",
			"",
			"    ${define}('${id}', ...",
			"",
			"A build takes a file apart by those lines, and code under none of them is",
			"in no custom effect. Put the line that says what it is above the code:",
			"",
			"    //// ${word} ${id}",
			"    ${define}('${id}', ...",
			"",
			read_more,
		],
		"\n",
	)
}

## The report of an id that starts like Joy's own.
joys_own : Str, Str -> Str
joys_own = |file, id|
	Str.join_with(
		[
			heading("custom effect with an id of joy's", file),
			"",
			"This id starts with joy/, which is for Joy's own effects:",
			"",
			"    ${id}",
			"",
			"Start it with a name of your own, like my_app/${id.drop_prefix("joy/")}, in the JavaScript",
			"and in the Roc that uses it.",
			"",
			read_more,
		],
		"\n",
	)

## The report of an id two sections define.
defined_twice : Str, Str, Str -> Str
defined_twice = |id, first, second|
	Str.join_with(
		[
			heading("custom effect defined twice", second),
			"",
			"Two sections define this id, and an app can have only one of them:",
			"",
			"    ${id}",
			"",
			"The other one is in ${first}. Ids are shared by everything",
			"on a page, so each starts with a name of its own: an app's with the app's,",
			"a package's with the package's.",
			"",
			read_more,
		],
		"\n",
	)

## The report of ids that are in the wasm without their marks.
unmarked : Str -> Str
unmarked = |id|
	Str.join_with(
		[
			heading("custom effects not found in the wasm", "in the app"),
			"",
			"The app uses this id, and it is not in the wasm the way ./joy reads it:",
			"",
			"    ${id}",
			"",
			"roc works out each id while it compiles and keeps it in the wasm with a mark",
			"around it, which is where ./joy sees what an app uses. This roc has not",
			"done that, so ./joy cannot tell what to ship. Build with the version of roc",
			"this release of Joy names.",
		],
		"\n",
	)

file_name : Str -> Str
file_name = |path|
	match path.split_last("/") {
		Ok({ after, .. }) => after
		Err(_) => path
	}

## The report of a section whose code does not define the id it names.
unmatched : Str, Str, Str, Str -> Str
unmatched = |file, word, define, id|
	Str.join_with(
		[
			heading("custom effect section without its code", file),
			"",
			"The code under this line does not define the id the line names:",
			"",
			"    //// ${word} ${id}",
			"",
			"The line says what the code below it defines, up to the next such line,",
			"so the two have the same id:",
			"",
			"    //// ${word} ${id}",
			"    ${define}('${id}', ...",
			"",
			"Hint: A build keeps the sections whose ids an app uses and leaves the",
			"rest out, so it has to know what each section defines.",
			"",
			read_more,
		],
		"\n",
	)

## Where the guide explains all of this. The guide is the one of Joy's own
## repository, whichever one a release comes from.
read_more : Str
read_more = "The guide has more on this: https://niclas-ahden.github.io/joy/#custom-effects"

place : CustomEffects.Site -> Str
place = |site| "${site.file}:${site.line.to_str()}:${site.column.to_str()}"

## The first line of a report, as roc writes its own: what is wrong on the
## left, where on the right, 80 columns across.
heading : Str, Str -> Str
heading = |title, at| {
	taken = title.count_utf8_bytes() + at.count_utf8_bytes() + 7
	"── ✗ ${title} ${Str.repeat("─", if (taken < 77) 80 - taken else 3)} ${at}"
}

## The line an id is on, indented, with the id marked below.
excerpt : CustomEffects.Site -> Str
excerpt = |site| {
	code = site.shown.trim_start()
	lead = site.shown.count_utf8_bytes() - code.count_utf8_bytes()
	before = if (site.under.at > lead) site.under.at - lead else 0
	"    ${code.trim_end()}\n    ${Str.repeat(" ", before)}${Str.repeat("^", site.under.len)}"
}

## How the JavaScript of a custom effect starts.
sketch : [Effect, Subscription], Str -> Str
sketch = |kind, id|
	match kind {
		Subscription =>
			Str.join_with(
				[
					"    //// subscription ${id}",
					"    defineSubscription('${id}', (args, host, emit) => {",
					"      // start listening, and emit(...) each event",
					"      return () => {",
					"        // stop listening",
					"      };",
					"    });",
				],
				"\n",
			)

		Effect =>
			Str.join_with(
				[
					"    //// effect ${id}",
					"    defineEffect('${id}', (args) => {",
					"      // what the browser does",
					"    });",
				],
				"\n",
			)
	}

## `ids`, the nearest to `id` first, each with how far it is.
closest : Str, List(Str) -> List((U64, Str))
closest = |id, ids|
	ids
		.map(|other| (distance(id, other), other))
		.sort_with(|(a, _), (b, _)| if (a < b) Before else if (a > b) After else Same)

## How many letters have to be changed, added or taken out to turn one text
## into the other.
distance : Str, Str -> U64
distance = |from, to| {
	ys = Str.to_utf8(to)
	var $row = [0].concat(ys.map_with_index(|_, j| j + 1))
	for (x, i) in Str.to_utf8(from).map_with_index(|x, i| (x, i)) {
		var $next = [i + 1]
		for (y, j) in ys.map_with_index(|y, j| (y, j)) {
			changed = ($row.get(j) ?? 0) + (if (x == y) 0 else 1)
			added = ($next.get(j) ?? 0) + 1
			taken = ($row.get(j + 1) ?? 0) + 1
			$next = $next.append(least(changed, least(added, taken)))
		}
		$row = $next
	}
	$row.last() ?? 0
}

least : U64, U64 -> U64
least = |a, b| if (a < b) a else b

## A path without the folders it enters only to leave again:
## `client/../../pkg/A.roc` is `../pkg/A.roc`.
tidy : Str -> Str
tidy = |path|
	Str.join_with(
		path.split_on("/").fold(
			[],
			|kept, part|
				match kept.last() {
					Ok(last) if part == ".." and last != ".." and last != "" => kept.drop_last(1)
					_ => if (part == "." and !kept.is_empty()) kept else kept.append(part)
				},
		),
		"/",
	)

found : Str, Str -> List((U64, U64))
found = |source, id| CustomEffects.sites({ file: "A.roc", source, home: "A.js" }, id).map(|site| (site.line, site.column))

expect found("get = |key| Effect.call(\"store/get_one\", args, done)", "store/get_one") == [(1, 26)]
expect found("a = 1\nset =\n\tFx.send(\n\t\t\"store/set_one\",\n\t\targs,\n\t)\n", "store/set_one") == [(4, 4)]
expect found("# Like Effect.call(\"store/get_one\", args, done).\nx = 1", "store/get_one") == []
expect found("two = [send(\"store/one\", []), send(\"store/one\", [])]\nid : Effect.Id\nid = \"store/one\"", "store/one") == [(1, 14), (1, 37), (3, 7)]
expect found("other = Effect.send(\"store/one_more\", [])", "store/one") == []

expect CustomEffects.defined(["//// helper store\nconst a = 1;\n//// effect store/get_one needs store\ndefineEffect('store/get_one', () => {});\n//// subscription store/changes\ndefineSubscription('store/changes', () => {});\n"]) == [{ id: "store/get_one", kind: Effect }, { id: "store/changes", kind: Subscription }]

expect distance("store/get_on", "store/get_one") == 1
expect distance("gte", "get") == 2
expect distance("", "abc") == 3
expect closest("store/gte_one", ["store/set_one", "store/changes", "store/get_one"]) == [(2, "store/get_one"), (3, "store/set_one"), (7, "store/changes")]

expect tidy("client/../../pkg/A.roc") == "../pkg/A.roc"
expect tidy("client/../../../joy/platform/../www/features") == "../../joy/www/features"
expect tidy("/home/me/app/./client/A.roc") == "/home/me/app/client/A.roc"
expect tidy("client/Page/Home.roc") == "client/Page/Home.roc"

effects : List(Str) -> List(CustomEffects.Defined)
effects = |ids| ids.map(|id| { id, kind: Effect })

## Where an id is in one file, as check! has it for a whole project.
in_file : Str, Str -> (Str -> List(CustomEffects.Site))
in_file = |file, source| |id| CustomEffects.sites({ file, source, home: "${file.drop_suffix(".roc")}.js" }, id)

# A misspelt id: the place, the line, and the ids it could have been.
expect {
	written = in_file("pkg/Store.roc", "import pf.Effect\n\nStore := [].{\n\tget = |done|\n\t\tEffect.call(\"store/gte_one\", [], done)\n}")
	CustomEffects.problems({ used: effects(["store/gte_one", "store/set_one"]), defined: effects(["store/set_one", "store/get_one", "other/thing_here"]), written, scripts: ["pkg/Store.js"] })
	== [
		Str.join_with(
			[
				"── ✗ custom effect without javascript ─────────────────────── pkg/Store.roc:5:16",
				"",
				"No JavaScript defines the custom effect with this id:",
				"",
				"    Effect.call(\"store/gte_one\", [], done)",
				"                 ^^^^^^^^^^^^^",
				"",
				"Did you mean one of these?",
				"",
				"    store/get_one",
				"    store/set_one",
				"",
				"If the id is the one you meant, then its JavaScript is what is missing:",
				"a section that starts with `//// effect store/gte_one`",
				"in pkg/Store.js.",
				"",
				"Hint: A custom effect is a call in Roc and JavaScript for the browser, joined",
				"by an id. roc cannot see the JavaScript, so ./joy checks that it is there.",
				"",
				"The guide has more on this: https://niclas-ahden.github.io/joy/#custom-effects",
			],
			"\n",
		),
	]
}

# An id that is like none of its package: all of them, as none stands out.
expect {
	written = in_file("pkg/Store.roc", "empty = Effect.send(\"store/clear_all\", [])")
	report = CustomEffects.problems({ used: effects(["store/clear_all"]), defined: effects(["store/get_one", "store/set_one"]), written, scripts: [] }).first() ?? ""
	report.contains("\n\nThese are the ones that start with store/:\n\n    store/get_one\n    store/set_one\n\nIf the id is the one you meant,") and report.contains("\nin pkg/Store.js, a file to make beside the module.\n")
}

# No JavaScript at all: where it goes, and how it starts.
expect {
	written = in_file("pkg/Store.roc", "watch = |heard| Sub.listen(\"store/changes\", [], heard)")
	CustomEffects.problems({ used: [{ id: "store/changes", kind: Subscription }], defined: effects(["store/get_one"]), written, scripts: ["joy/www/features/time.js"] })
	== [
		Str.join_with(
			[
				"── ✗ custom effect without javascript ─────────────────────── pkg/Store.roc:1:29",
				"",
				"No JavaScript defines the custom effect with this id:",
				"",
				"    watch = |heard| Sub.listen(\"store/changes\", [], heard)",
				"                                ^^^^^^^^^^^^^",
				"",
				"No subscription has an id that starts with store/ yet, so the JavaScript",
				"of this one is still to be written. It goes in a new file beside the module,",
				"pkg/Store.js, and starts like this:",
				"",
				"    //// subscription store/changes",
				"    defineSubscription('store/changes', (args, host, emit) => {",
				"      // start listening, and emit(...) each event",
				"      return () => {",
				"        // stop listening",
				"      };",
				"    });",
				"",
				"Hint: A custom effect is a call in Roc and JavaScript for the browser, joined",
				"by an id. roc cannot see the JavaScript, so ./joy checks that it is there.",
				"",
				"The guide has more on this: https://niclas-ahden.github.io/joy/#custom-effects",
			],
			"\n",
		),
	]
}

# An id that is a named value: the report is about where it is written, and
# says where else it is.
expect {
	written = in_file("pkg/Store.roc", "remove_id : Effect.Id\nremove_id = \"store/remove_it\"\n\nagain = Effect.send(\"store/remove_it\", [])")
	report = CustomEffects.problems({ used: effects(["store/remove_it"]), defined: [], written, scripts: [] }).first() ?? ""
	report.contains(" pkg/Store.roc:2:14\n")
	and report.contains("    remove_id = \"store/remove_it\"\n                 ^^^^^^^^^^^^^^^\n\nThe id is also written at pkg/Store.roc:4:22.\n")
}

# An effect's call on a subscription's id.
expect {
	written = in_file("pkg/Store.roc", "watch = Effect.call(\"store/changes\", [], heard)")
	report = CustomEffects.problems({ used: effects(["store/changes"]), defined: [{ id: "store/changes", kind: Subscription }], written, scripts: [] }).first() ?? ""
	report.contains("── ✗ custom effect of the other kind ")
	and report.contains("The JavaScript with this id defines a subscription, and the app uses it with Effect.call or Effect.send:")
	and report.contains("Effect.call or Effect.send needs a section that starts with\n`//// effect store/changes` and `defineEffect`.")
}

expect CustomEffects.problems({ used: effects(["store/set_one"]), defined: effects(["store/set_one"]), written: |_| [], scripts: [] }) == []

# A section's line and its code name the same id.
expect CustomEffects.mismatched([{ file: "pkg/Store.js", source: "//// helper store\nconst a = 1;\n//// effect store/get_one needs store\ndefineEffect('store/get_one', () => a);\n//// subscription store/changes\ndefineSubscription(\"store/changes\", () => {});\n" }]) == []
expect {
	CustomEffects.mismatched([{ file: "pkg/Store.js", source: "//// effect store/get_one\ndefineEffect('store/get_once', () => 1);\n" }])
	== [
		Str.join_with(
			[
				"── ✗ custom effect section without its code ─────────────────────── pkg/Store.js",
				"",
				"The code under this line does not define the id the line names:",
				"",
				"    //// effect store/get_one",
				"",
				"The line says what the code below it defines, up to the next such line,",
				"so the two have the same id:",
				"",
				"    //// effect store/get_one",
				"    defineEffect('store/get_one', ...",
				"",
				"Hint: A build keeps the sections whose ids an app uses and leaves the",
				"rest out, so it has to know what each section defines.",
				"",
				"The guide has more on this: https://niclas-ahden.github.io/joy/#custom-effects",
			],
			"\n",
		),
	]
}
expect CustomEffects.mismatched([{ file: "pkg/Store.js", source: "//// subscription store/changes\ndefineEffect('store/changes', () => 1);\n" }]).len() == 1
expect CustomEffects.mismatched([{ file: "pkg/Store.js", source: "//// effect store/get_one\n// defineEffect('store/get_one', () => 1);\n" }]).len() == 1

titles : List(Str) -> List(Str)
titles = |reports| reports.map(|report| (report.split_on(" ─").first() ?? "").drop_prefix("── ✗ "))

# What is wrong in a file, whatever an app uses of it.
expect titles(CustomEffects.malformed([{ file: "pkg/Store.js", source: "//// efect store/get_one\ndefineEffect('store/get_one', () => 1);\n" }], [])) == ["custom effect line not understood"]
expect CustomEffects.malformed([{ file: "pkg/Store.js", source: "// about\n\n//// efect store/get_one\nx\n" }], []).first().map_ok(|report| report.contains(" pkg/Store.js:3\n") and report.contains("    //// efect store/get_one\n")) == Ok(Bool.True)
expect titles(CustomEffects.malformed([{ file: "pkg/Store.js", source: "import x from 'x';\n//// effect store/get_one\ndefineEffect('store/get_one', () => x);\n" }], [])) == ["custom effect file with an import line"]
expect CustomEffects.malformed([{ file: "pkg/Store.js", source: "//// effect store/get_one\ndefineEffect('store/get_one', async () => (await import('./x.js')).default);\n" }], []) == []
expect titles(CustomEffects.malformed([{ file: "pkg/Store.js", source: "//// effect joy/http/request\ndefineEffect('joy/http/request', () => 1);\n" }], ["joy/http/request"])) == ["custom effect with an id of joy's", "custom effect defined twice"]
expect {
	one = { file: "pkg/A.js", source: "//// effect store/get_one\ndefineEffect('store/get_one', () => 1);\n" }
	other = { file: "pkg/B.js", source: "//// effect store/get_one\ndefineEffect('store/get_one', () => 2);\n" }
	reports = CustomEffects.malformed([one, other], [])
	titles(reports) == ["custom effect defined twice"] and (reports.first() ?? "").contains("The other one is in pkg/A.js.")
}

expect titles(CustomEffects.malformed([{ file: "pkg/Store.js", source: "defineSubscription('store/changes', () => () => {});\n" }], [])) == ["custom effect code without its line"]
expect titles(CustomEffects.malformed([{ file: "pkg/Store.js", source: "const each = (id) => defineEffect(id, () => 1);\n//// effect store/get_one\n// defineEffect('store/get_old', 0)\ndefineEffect('store/get_one', () => 1);\n" }], [])) == []

# A module of a released package without its JavaScript is the package's to put right.
expect {
	written = |id| CustomEffects.sites({ file: "/home/me/.cache/roc/packages/abc/Store.roc", source: "get = Effect.send(\"store/get_one\", [])", home: "/home/me/.cache/roc/packages/abc/Store.js" }, id)
	report = CustomEffects.problems({ used: effects(["store/get_one"]), defined: [], written, scripts: [] }).first() ?? ""
	report.contains("The module is part of a released package, which came without its JavaScript,\nStore.js.")
}

# The call is shown before a test of it.
expect {
	written = in_file("pkg/Store.roc", "expect Store.get.identity().id == \"store/get_one\"\nget = Effect.send(\"store/get_one\", [])")
	report = CustomEffects.problems({ used: effects(["store/get_one"]), defined: [], written, scripts: [] }).first() ?? ""
	report.contains(" pkg/Store.roc:2:20\n") and report.contains("The id is also written at pkg/Store.roc:1:36.")
}
