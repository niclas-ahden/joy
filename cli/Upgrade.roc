import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.Param
import weaver.SubCmd
import Args
import Build
import Init
import Project
import Prompt
import Release
import Releases

## `./joy upgrade`: move a project to another Joy release. It changes the
## addresses of Joy's platform and of joy-html in the headers of the
## project's .roc files, and installs that release's ./joy. The project's own
## code stays as it is.
##
## The release the project moves to does the rewriting, since only its ./joy
## knows where that release keeps its addresses. This ./joy builds that one
## and runs `upgrade <tag> --no-input` with it, and $JOY_UPGRADE_TO set to
## the tag tells it that it is the one to do the work. Every ./joy from
## 0.35.0 on keeps to that.
Upgrade :: [].{
	Options : { no_input : Bool, version : Try(Str, [NoValue]) }

	## `./joy upgrade` as a weaver subcommand, which also writes its --help.
	command : (Upgrade.Options -> command) -> SubCmd.SubcommandParserConfig(command)
	command = |wrap|
		SubCmd.finish(
			{
				no_input: Opt.flag({ short: "", long: "no-input", help: "Never ask. Fail instead, and list the releases to name." }),
				version: Param.maybe_str({ name: "version", help: "The release to move to. Without it, upgrade asks." }),
			}.Cli,
			{
				name: "upgrade",
				description: "Move the project to another Joy release: its platform, joy-html and ./joy.",
				mapper: wrap,
			},
		)

	run! : Upgrade.Options => Try({}, _)
	run! = |options| {
		found = scan!()?
		match found.checkouts {
			[{ file, url }, ..] => return Build.fail!("${file} builds against the Joy checkout at ${url}. ./joy upgrade moves a project that is on a release.")
			[] => {}
		}
		tags = found.joy.keep_oks(|{ url, .. }| Releases.tag_of_url(url))
		current =
			match tags.first() {
				Ok(first) => tags.fold(first, |newest, tag| if (Releases.is_newer(tag, newest)) tag else newest)
				Err(_) => return Build.fail!("No .roc file here names a Joy release. Run ./joy upgrade in the project's root.")
			}
		repo =
			match found.joy.keep_oks(|{ url, .. }| Releases.repo_of_url(url)).first() {
				Ok(known) => known
				Err(_) => "niclas-ahden/joy"
			}
		releases = Releases.read!(repo)?
		target =
			match Args.given(options.version) {
				Some(named) => named!(named, releases, repo)?
				None => chosen!(current, releases, repo, options.no_input)?
			}
		handed = Env.var_str!(OsStr.from_str("JOY_UPGRADE_TO")) ?? ""
		if handed == target.tag or Release.version == target.tag {
			apply!(found, current, target, releases, repo)
		} else {
			hand_off!(target)
		}
	}
}

## A string in a header, and the file it is in.
Named : { file : Str, url : Str }

## The project's .roc files with a header, and what their headers name:
## Joy's platform and joy-html by release, any other package by URL, and
## Joy's platform in a checkout by path.
Found : { files : List({ file : Str, source : Str }), joy : List(Named), html : List(Named), others : List(Named), checkouts : List(Named) }

scan! : () => Try(Found, _)
scan! = || {
	var $found = { files: [], joy: [], html: [], others: [], checkouts: [] }
	for file in Project.project_roc_files!()? {
		source = Path.utf8(file).read_utf8!() ?? ""
		match header_strings(source) {
			Ok(strings) => {
				$found = { ..$found, files: $found.files.append({ file, source }) }
				for { value, by_platform, .. } in strings {
					named = { file, url: value }
					if is_joy(value) {
						$found = { ..$found, joy: $found.joy.append(named) }
					} else if is_html(value) {
						$found = { ..$found, html: $found.html.append(named) }
					} else if value.starts_with("https://") or value.starts_with("http://") {
						$found = { ..$found, others: $found.others.append(named) }
					} else if by_platform and Project.is_joy!(file, value) {
						$found = { ..$found, checkouts: $found.checkouts.append(named) }
					}
				}
			}

			Err(_) => {}
		}
	}
	Ok($found)
}

is_joy : Str -> Bool
is_joy = |url| url.contains("/joy/releases/download/")

is_html : Str -> Bool
is_html = |url| url.contains("/joy-html/releases/download/")

## The release a project is moved to when it is named.
named! : Str, List(Releases.Entry), Str => Try(Releases.Entry, _)
named! = |tag, releases, repo|
	match releases.find_first(|entry| entry.tag == tag) {
		Ok(entry) => Ok(entry)
		Err(_) => Build.fail!("There is no Joy release called ${tag}. The releases are at https://github.com/${repo}/releases")
	}

## The release a project is moved to when none is named: the one picked from
## a short list, or, where nobody can be asked, none, with the list printed.
chosen! : Str, List(Releases.Entry), Str, Bool => Try(Releases.Entry, _)
chosen! = |current, releases, repo, no_input| {
	offered = Releases.offers(current, releases)
	latest =
		match offered.last() {
			Ok(offer) => offer.tag
			Err(_) => {
				Stdout.line!("This project is on Joy ${current}, the latest release.")?
				return Err(Exit(0))
			}
		}
	stay = { name: "Stay on ${current}", description: "", link: "" }
	items = [One(stay)].concat(list(offered, repo))
	if !Prompt.asks!(no_input) {
		return Build.fail!("This project is on Joy ${current}. Name the release to upgrade to:\n${Prompt.listing(list(offered, repo))}\n\n    ./joy upgrade ${latest}")
	}
	Stdout.line!("This project is on Joy ${current}.\n")?
	picked =
		match Prompt.pick!("Upgrade to which release?", items) {
			Ok(choice) => choice
			Err(_) => return Err(Exit(130))
		}
	if picked == stay {
		return Err(Exit(0))
	}
	match releases.find_first(|entry| entry.tag == picked.name) {
		Ok(entry) => Ok(entry)
		Err(_) => Build.fail!("There is no Joy release called ${picked.name}.")
	}
}

## The releases a project can move to, as the lines of a list: a fix of its
## own line, the next line, the latest one, and a gap for the lines between.
list : List(Releases.Offer), Str -> List(Prompt.Item)
list = |offered, repo| {
	fixes = offered.keep_if(|offer| offer.kind != Breaking)
	lines = offered.keep_if(|offer| offer.kind == Breaking)
	count = lines.len()
	labelled =
		lines.map_with_index(
			|offer, index| {
				label = if (index + 1 == count) "Latest" else if (index == 0) "Next step" else ""
				(offer, label)
			},
		)
	own =
		fixes.map(
			|offer| {
				label = if (offer.kind == Fixes) "Fixes only" else "No breaking changes"
				One(choice(offer, label, repo))
			},
		)
	rows =
		if count <= 3 {
			labelled.map(|(offer, label)| One(choice(offer, label, repo)))
		} else {
			middle = labelled.drop_first(1).drop_last(1)
			first_line =
				match middle.first() {
					Ok((offer, _)) => line_of(offer.tag)
					Err(_) => ""
				}
			last_line =
				match middle.last() {
					Ok((offer, _)) => line_of(offer.tag)
					Err(_) => ""
				}
			gap = Gap("... ${middle.len().to_str()} more, ${first_line} to ${last_line}", middle.map(|(offer, label)| choice(offer, label, repo)))
			labelled.take_first(1).map(|(offer, label)| One(choice(offer, label, repo))).append(gap).concat(labelled.take_last(1).map(|(offer, label)| One(choice(offer, label, repo))))
		}
	own.concat(rows)
}

choice : Releases.Offer, Str, Str -> Prompt.Choice
choice = |offer, label, repo| { name: offer.tag, description: label, link: Releases.notes_url(repo, offer.notes) }

line_of : Str -> Str
line_of = |tag|
	match Releases.version(tag) {
		Ok(v) => Releases.line_name(Releases.line_of(v))
		Err(_) => tag
	}

## Build the ./joy of `target` and let it do the upgrade.
hand_off! : Releases.Entry => Try({}, _)
hand_off! = |target| {
	dir = ".joy/upgrade"
	program = "${dir}/${Build.executable!("joy")}"
	_ = Path.utf8(dir).delete_all!()
	if Path.utf8(dir).create_all!().is_err() {
		return Build.fail!("Could not make the folder ${dir}.")
	}
	Stdout.line!("Building ./joy for Joy ${target.tag}, which does the upgrade.")?
	built = Cmd.new(OsStr.from_str("roc")).args(["build", "--opt=dev", "--output=${program}", target.cli_url].map(OsStr.from_str)).run!()
	if !(Path.utf8(program).is_file!() ?? False) {
		said =
			match built {
				Ok(output) => Str.from_utf8_lossy(output.stdout_bytes.concat(output.stderr_bytes))
				Err(err) => Str.inspect(err)
			}
		needed = roc_needed(target)
		needs = if (needed.is_empty()) "" else "\n${needed}"
		_ = Path.utf8(dir).delete_all!()
		return Build.fail!("Could not build ./joy for Joy ${target.tag}, so nothing changed. roc said:\n${said}${needs}")
	}
	ran =
		Cmd.new(OsStr.from_str(program))
			.args(["upgrade", target.tag, "--no-input"].map(OsStr.from_str))
			.env(OsStr.from_str("JOY_UPGRADE_TO"), OsStr.from_str(target.tag))
			.call!()
	_ = Path.utf8(dir).delete_all!()
	match ran {
		Ok({}) => Ok({})
		Err(BadExitStatus(output)) =>
			match output.status {
				Exited(code) => Err(Exit(code))
				Signaled(signal) => Err(Exit(128 + signal))
			}
		Err(err) => Build.fail!("Could not run ./joy for Joy ${target.tag}: ${Str.inspect(err)}")
	}
}

## Move the project's headers to `target`, install this program as ./joy,
## and say what changed and what did not.
apply! : Found, Str, Releases.Entry, List(Releases.Entry), Str => Try({}, _)
apply! = |found, current, target, releases, repo| {
	moves = found.files.keep_oks(
		|{ file, source }| {
			moved = with_release(source, target)
			if (moved == source) Err(Unchanged) else Ok((file, moved))
		},
	)
	# Each file is written to a copy beside it first, which keeps its mode,
	# and moved into place only once every copy is written. A file that
	# cannot be written then leaves the project as it was.
	for (file, moved) in moves {
		staged = Path.utf8("${file}.upgrade")
		if Path.utf8(file).copy!(staged).is_err() or staged.write_utf8!(moved).is_err() {
			for (other, _) in moves {
				_ = Path.utf8("${other}.upgrade").delete!()
			}
			return Build.fail!("Could not write ${file}, so nothing changed.")
		}
	}
	for (file, _) in moves {
		if Path.utf8("${file}.upgrade").rename!(Path.utf8(file)).is_err() {
			return Build.fail!("Could not move ${file}.upgrade to ${file}. Move it there by hand to finish the upgrade.")
		}
	}
	changed = moves.map(|(file, _)| (file, changes(file, found, target)))
	old_joy = joy_version!()
	Init.install_self!()?
	joy_line = if (old_joy == Release.version) [] else [("./joy", if (old_joy.is_empty()) "installed" else "${old_joy} -> ${target.tag}")]
	rows = List.sort_with(changed, |(a, _), (b, _)| Project.order(a, b)).concat(joy_line)
	if rows.is_empty() {
		return Stdout.line!("This project is on Joy ${target.tag} already.")
	}
	width = rows.map(|(name, _)| name.count_utf8_bytes()).max() ?? 0
	if Releases.is_newer(current, target.tag) {
		Stdout.line!("Moved back to Joy ${target.tag}, from the newer ${current}.")?
	} else {
		Stdout.line!("Upgraded to Joy ${target.tag}.")?
	}
	for (name, what) in rows {
		Stdout.line!("  ${name}${Str.repeat(" ", width - name.count_utf8_bytes())}  ${what}")?
	}
	touched = changed.map(|(file, _)| file)
	left = found.others.keep_if(|{ file, .. }| touched.contains(file))
	if !left.is_empty() {
		Stdout.line!("\nLeft as they are:")?
		names = left.map(|{ file, url }| (package_name(url), file))
		name_width = names.map(|(name, _)| name.count_utf8_bytes()).max() ?? 0
		for (name, file) in names {
			Stdout.line!("  ${name}${Str.repeat(" ", name_width - name.count_utf8_bytes())}  ${file}")?
		}
	}
	Stdout.line!("")?
	needed = roc_needed(target)
	if !needed.is_empty() {
		Stdout.line!(needed)?
	}
	match Releases.crossed(current, target.tag, releases) {
		[] => Stdout.line!("Notes: ${Releases.notes_url(repo, target.tag)}")
		[one] => Stdout.line!("Run ./joy dev to see what needs changing. Notes: ${Releases.notes_url(repo, one)}")
		[first, .., last] => Stdout.line!("Run ./joy dev to see what needs changing. Read the notes from ${first} to ${last}: https://github.com/${repo}/releases")
	}
}

## What a release says about the Roc it needs, empty when its notes say
## nothing. Releases from before Roc made releases name a nightly.
roc_needed : Releases.Entry -> Str
roc_needed = |target|
	if !target.roc_minimum.is_empty() {
		"Joy ${target.tag} needs Roc ${target.roc_minimum} or later."
	} else if !target.roc_nightly.is_empty() {
		"Joy ${target.tag} is tested with roc ${target.roc_nightly}."
	} else {
		""
	}

## What moved in `file`: Joy's platform and joy-html, from the releases it
## named to the ones of `target`.
changes : Str, Found, Releases.Entry -> Str
changes = |file, found, target| {
	from = |named| {
		tags = named.keep_if(|n| n.file == file).keep_oks(|n| Releases.tag_of_url(n.url))
		tags.fold([], |seen, tag| if (seen.contains(tag)) seen else seen.append(tag))
	}
	step = |what, old, new|
		match Releases.tag_of_url(new) {
			Ok(tag) => old.drop_if(|o| o == tag).map(|o| "${what} ${o} -> ${tag}")
			Err(_) => []
		}
	Str.join_with(step("platform", from(found.joy), target.platform_url).concat(step("joy-html", from(found.html), target.html_url)), ", ")
}

## A package by its repository and release, joy-carousel 0.3.0, or its URL.
package_name : Str -> Str
package_name = |url|
	match (Releases.repo_of_url(url), Releases.tag_of_url(url)) {
		(Ok(repo), Ok(tag)) =>
			match repo.split_last("/") {
				Ok({ after, .. }) => "${after} ${tag}"
				Err(_) => "${repo} ${tag}"
			}

		_ => url
	}

## The release the installed ./joy says it belongs to, empty without one.
joy_version! : () => Str
joy_version! = || {
	program = Build.executable!("joy")
	if !(Path.utf8(program).is_file!() ?? False) {
		return ""
	}
	match Cmd.new(OsStr.from_str("./${program}")).args([OsStr.from_str("--version")]).run!() {
		Ok(output) => Str.from_utf8_lossy(output.stdout_bytes).trim().split_on(" ").last() ?? ""
		Err(_) => ""
	}
}

## A string in a header: its text, where the text starts and ends in the
## source, in bytes, and whether it names the platform.
HeaderString : { value : Str, start : U64, end : U64, by_platform : Bool }

## A source with its header on `target`: every Joy platform release in it
## swapped for the target's, and every joy-html release for the one the
## target was built with. Nothing outside the header changes.
with_release : Str, Releases.Entry -> Str
with_release = |source, target| {
	bytes = Str.to_utf8(source)
	var $out = []
	var $at = 0
	for string in header_strings(source) ?? [] {
		swapped =
			if is_joy(string.value) {
				Some(target.platform_url)
			} else if is_html(string.value) {
				Some(target.html_url)
			} else {
				None
			}
		match swapped {
			Some(url) => {
				$out = $out.concat(bytes.sublist({ start: $at, len: string.start - $at })).concat(Str.to_utf8(url))
				$at = string.end
			}
			None => {}
		}
	}
	Str.from_utf8($out.concat(bytes.drop_first($at))) ?? source
}

## The strings in the header of an app or a package. Any other file has no
## header here. The header is read the way Roc reads it, so a `#` comment
## or an escaped quote never starts or ends a string, and a `}` in either
## never ends the header.
header_strings : Str -> Try(List(HeaderString), [NoHeader])
header_strings = |source| {
	bytes = Str.to_utf8(source)
	count = bytes.len()
	byte = |at| bytes.get(at) ?? 0
	# The comments and blank lines above the header.
	var $at = 0
	var $above = True
	while $above and $at < count {
		if byte($at) == '#' {
			$at = line_end(bytes, $at)
		} else if is_space(byte($at)) {
			$at = $at + 1
		} else {
			$above = False
		}
	}
	keyword = word_at(bytes, $at)
	if keyword != "app" and keyword != "package" {
		return Err(NoHeader)
	}
	var $strings = []
	var $depth = 0
	var $last_word = ""
	while $at < count {
		current = byte($at)
		if current == '#' {
			$at = line_end(bytes, $at)
		} else if current == '"' {
			start = $at + 1
			var $end = start
			while $end < count and byte($end) != '"' {
				$end = if (byte($end) == '\\') $end + 2 else $end + 1
			}
			if $end >= count {
				return Err(NoHeader)
			}
			if $depth > 0 {
				value = Str.from_utf8(bytes.sublist({ start, len: $end - start })) ?? ""
				$strings = $strings.append({ value, start, end: $end, by_platform: $last_word == "platform" })
			}
			$last_word = ""
			$at = $end + 1
		} else if current == '{' {
			$depth = $depth + 1
			$last_word = ""
			$at = $at + 1
		} else if current == '}' {
			if $depth <= 1 {
				return if ($depth == 1) Ok($strings) else Err(NoHeader)
			}
			$depth = $depth - 1
			$last_word = ""
			$at = $at + 1
		} else if is_word(current) {
			word = word_at(bytes, $at)
			$last_word = word
			$at = $at + word.count_utf8_bytes()
		} else {
			if !is_space(current) {
				$last_word = ""
			}
			$at = $at + 1
		}
	}
	Err(NoHeader)
}

## Where the line that `at` is on ends: at its newline, or the end.
line_end : List(U8), U64 -> U64
line_end = |bytes, at| {
	var $end = at
	while $end < bytes.len() and (bytes.get($end) ?? 0) != '\n' {
		$end = $end + 1
	}
	$end
}

## The name or keyword that starts at `at`, empty when none does.
word_at : List(U8), U64 -> Str
word_at = |bytes, at| {
	var $end = at
	while $end < bytes.len() and is_word(bytes.get($end) ?? 0) {
		$end = $end + 1
	}
	Str.from_utf8(bytes.sublist({ start: at, len: $end - at })) ?? ""
}

is_word : U8 -> Bool
is_word = |b| (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '_'

is_space : U8 -> Bool
is_space = |b| b == ' ' or b == '\t' or b == '\n' or b == '\r'

old_pf = "https://github.com/niclas-ahden/joy/releases/download/0.35.0/Old.tar.zst"

old_html = "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/OldHtml.tar.zst"

carousel = "https://github.com/niclas-ahden/joy-carousel/releases/download/0.3.0/Car.tar.zst"

target_entry = { tag: "0.36.1", date: "", platform_url: "https://github.com/niclas-ahden/joy/releases/download/0.36.1/New.tar.zst", cli_url: "c", html_url: "https://github.com/niclas-ahden/joy-html/releases/download/0.19.0/NewHtml.tar.zst", roc_nightly: "", roc_minimum: "" }

app_file = |pf, html| "#!/usr/bin/env roc\n# My app\napp [main] {\n\tpf: platform \"${pf}\",\n\thtml: \"${html}\",\n\tcar: \"${carousel}\",\n}\n\nimport html.Html\n\nlink = \"${pf}\"\n"

values = |source| (header_strings(source) ?? []).map(|string| (string.value, string.by_platform))

expect with_release(app_file(old_pf, old_html), target_entry) == app_file(target_entry.platform_url, target_entry.html_url).replace_first("link = \"${target_entry.platform_url}\"", "link = \"${old_pf}\"")
expect with_release("package [Share] { pf: platform \"${old_pf}\" }\n", target_entry) == "package [Share] { pf: platform \"${target_entry.platform_url}\" }\n"
expect with_release("Share :: [].{\n\turl = \"${old_pf}\"\n}\n", target_entry) == "Share :: [].{\n\turl = \"${old_pf}\"\n}\n"
expect values("app [main] {\n\tpf: platform \"../joy/platform/main.roc\",\n\thtml: \"h\",\n}") == [("../joy/platform/main.roc", True), ("h", False)]

# A quote, a brace or the word app in a comment, and an escaped quote in a
# string, are what a simpler reading gets wrong.
expect values("# the \"app\" {\napp [main] {\n\t# it's \"old\" }\n\tpf: platform \"p\",\n\tx: \"a\\\"b\",\n}\n\ny = \"after\"") == [("p", True), ("a\\\"b", False)]
expect with_release("app [main] {\n\t# was \"${old_pf}\"\n\tpf: platform \"${old_pf}\",\n}\n", target_entry) == "app [main] {\n\t# was \"${old_pf}\"\n\tpf: platform \"${target_entry.platform_url}\",\n}\n"
expect header_strings("app [main] {\n\tpf: platform \"p\",\n") == Err(NoHeader)
expect header_strings("module [x]\n\nx = \"app {\"") == Err(NoHeader)
expect package_name(carousel) == "joy-carousel 0.3.0"

expect {
	offered = [
		{ tag: "0.30.4", kind: Fixes, notes: "0.30.4" },
		{ tag: "0.31.2", kind: Breaking, notes: "0.31.0" },
		{ tag: "0.32.0", kind: Breaking, notes: "0.32.0" },
		{ tag: "0.44.0", kind: Breaking, notes: "0.44.0" },
		{ tag: "0.45.0", kind: Breaking, notes: "0.45.0" },
	]
	Prompt.listing(list(offered, "niclas-ahden/joy"))
		== "  0.30.4  Fixes only  https://github.com/niclas-ahden/joy/releases/tag/0.30.4\n  0.31.2  Next step   https://github.com/niclas-ahden/joy/releases/tag/0.31.0\n  ... 2 more, 0.32 to 0.44\n  0.45.0  Latest      https://github.com/niclas-ahden/joy/releases/tag/0.45.0"
}

expect roc_needed({ ..target_entry, roc_minimum: "0.1.0-rc1" }) == "Joy 0.36.1 needs Roc 0.1.0-rc1 or later."
expect roc_needed({ ..target_entry, roc_nightly: "nightly-2026-11-01-abc1234" }) == "Joy 0.36.1 is tested with roc nightly-2026-11-01-abc1234."
expect roc_needed(target_entry) == ""
