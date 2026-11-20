import pf.Env
import pf.Http
import pf.OsStr
import pf.Path
import pf.Sleep
import http.Request
import http.Response
import Build

## Joy's releases, from the versions.json attached to the latest one, which
## .github/scripts/versions.roc writes. It is a plain download rather than a
## call to GitHub's API, so reading it never meets a rate limit.
Releases :: [].{

	## One release as versions.json lists it. A field the release has no
	## value for is empty.
	Entry : { tag : Str, date : Str, platform_url : Str, cli_url : Str, html_url : Str, roc_nightly : Str }

	## A release ./joy upgrade can move a project to, what kind of step it
	## is, and the release whose notes describe the step: for a new line of
	## releases its first one, which has the breaking changes.
	Offer : { tag : Str, kind : [Fixes, Features, Breaking], notes : Str }

	## A tag taken apart: 0.35.0-rc9 is [0, 35, 0] and the candidate "rc9".
	## A release has no candidate.
	Version : { numbers : List(U64), candidate : Str }

	## Every release of the Joy at `repo`, such as niclas-ahden/joy, newest
	## first. $JOY_VERSIONS_URL reads another copy, from a URL or a file.
	read! : Str => Try(List(Releases.Entry), [Exit(I32)])
	read! = |repo| {
		url =
			match Env.var_str!(OsStr.from_str("JOY_VERSIONS_URL")) {
				Ok(given) if !given.is_empty() => given
				_ => "https://github.com/${repo}/releases/latest/download/versions.json"
			}
		body =
			if url.starts_with("https://") or url.starts_with("http://") {
				# A refresh deletes the file before uploading the new one, so
				# it can be missing for a few seconds. One retry covers that.
				match download!(url) {
					Ok(text) => text
					Err(_) => {
						Sleep.millis!(3000) ?? {}
						match download!(url) {
							Ok(text) => text
							Err(problem) => return Build.fail!("Could not download the list of Joy releases from ${url}: ${problem}")
						}
					}
				}
			} else {
				match Path.utf8(url).read_utf8!() {
					Ok(text) => text
					Err(_) => return Build.fail!("Could not read the list of Joy releases at ${url}.")
				}
			}
		# Fields this ./joy does not know are skipped, so newer files still
		# read. Only ever adding fields keeps old ./joy programs working.
		index : Try({ releases : List(Releases.Entry) }, _)
		index = Json.parse(body)
		match index {
			Ok({ releases }) => Ok(releases)
			Err(_) => Build.fail!("${url} is not a list of Joy releases that this ./joy can read.")
		}
	}

	version : Str -> Try(Releases.Version, [NotAVersion])
	version = |tag| {
		(main, candidate) =
			match tag.split_first("-") {
				Ok({ before, after }) => (before, after)
				Err(_) => (tag, "")
			}
		numbers = main.split_on(".").map_try(|part| U64.from_str(part)) ? |_| NotAVersion
		if numbers.is_empty() {
			Err(NotAVersion)
		} else {
			Ok({ numbers, candidate })
		}
	}

	## Whether tag `a` is a later release than tag `b`. A tag that is not a
	## version is never later.
	is_newer : Str, Str -> Bool
	is_newer = |a, b|
		match (Releases.version(a), Releases.version(b)) {
			(Ok(x), Ok(y)) => compare(x, y) == After
			_ => False
		}

	## The line a release belongs to, the releases between which there are
	## no breaking changes: 0.35 for 0.35.2, and 2 for 2.4.1.
	line_of : Releases.Version -> List(U64)
	line_of = |v|
		match v.numbers {
			[0, ..] => v.numbers.take_first(2)
			_ => v.numbers.take_first(1)
		}

	line_name : List(U64) -> Str
	line_name = |line| Str.join_with(line.map(|number| number.to_str()), ".")

	## What a project on `current` can move to, oldest first: the newest
	## release of its own line, then the newest of each newer line. Release
	## candidates are left out.
	offers : Str, List(Releases.Entry) -> List(Releases.Offer)
	offers = |current, entries| {
		now =
			match Releases.version(current) {
				Ok(v) => v
				Err(_) => return []
			}
		own_line = Releases.line_of(now)
		releases = finals(entries)
		movable = releases.keep_if(|(_, v)| compare(v, now) == After)
		var $offers = []
		for line in lines_of(movable) {
			in_line = movable.keep_if(|(_, v)| Releases.line_of(v) == line)
			newest = newest_of(in_line)
			match newest {
				Ok((entry, v)) =>
					if line == own_line {
						kind = if (v.numbers.take_first(2) == now.numbers.take_first(2)) Fixes else Features
						$offers = $offers.append({ tag: entry.tag, kind, notes: entry.tag })
					} else {
						notes = first_of_line(releases, line) ?? entry.tag
						$offers = $offers.append({ tag: entry.tag, kind: Breaking, notes })
					}

				Err(_) => {}
			}
		}
		$offers
	}

	## The first release of each line after the line of `from`, up to and
	## including the line of `to`: whose notes describe the breaking changes
	## a move from one to the other crosses.
	crossed : Str, Str, List(Releases.Entry) -> List(Str)
	crossed = |from, to, entries|
		match (Releases.version(from), Releases.version(to)) {
			(Ok(a), Ok(b)) => {
				releases = finals(entries)
				from_line = Releases.line_of(a)
				to_line = Releases.line_of(b)
				lines_of(releases)
					.keep_if(|line| compare_numbers(line, from_line) == After and compare_numbers(line, to_line) != After)
					.keep_oks(|line| first_of_line(releases, line))
			}

			_ => []
		}

	## The release tag in a release download URL: 0.35.0 in
	## https://github.com/niclas-ahden/joy/releases/download/0.35.0/<hash>.tar.zst.
	tag_of_url : Str -> Try(Str, [NotARelease])
	tag_of_url = |url|
		match url.split_first("/releases/download/") {
			Ok({ after, .. }) =>
				match after.split_first("/") {
					Ok({ before, .. }) if !before.is_empty() => Ok(before)
					_ => Err(NotARelease)
				}

			Err(_) => Err(NotARelease)
		}

	## The GitHub repository of a release download URL, niclas-ahden/joy.
	repo_of_url : Str -> Try(Str, [NotARelease])
	repo_of_url = |url|
		match (url.split_first("https://github.com/"), url.split_first("/releases/download/")) {
			(Ok({ after, .. }), Ok(_)) =>
				match after.split_first("/releases/download/") {
					Ok({ before, .. }) if before.contains("/") => Ok(before)
					_ => Err(NotARelease)
				}

			_ => Err(NotARelease)
		}

	## The page of a release's notes.
	notes_url : Str, Str -> Str
	notes_url = |repo, tag| "https://github.com/${repo}/releases/tag/${tag}"
}

## The releases of `entries` that are not candidates, with their versions.
finals : List(Releases.Entry) -> List((Releases.Entry, Releases.Version))
finals = |entries|
	entries.keep_oks(
		|entry|
			match Releases.version(entry.tag) {
				Ok(v) if v.candidate.is_empty() => Ok((entry, v))
				_ => Err(NotARelease)
			},
	)

## The lines `releases` belong to, each once, oldest first.
lines_of : List((Releases.Entry, Releases.Version)) -> List(List(U64))
lines_of = |releases| {
	var $lines = []
	for (_, v) in releases {
		line = Releases.line_of(v)
		if !$lines.contains(line) {
			$lines = $lines.append(line)
		}
	}
	List.sort_with($lines, compare_numbers)
}

newest_of : List((Releases.Entry, Releases.Version)) -> Try((Releases.Entry, Releases.Version), [Empty])
newest_of = |releases| {
	var $best = Err(Empty)
	for (entry, v) in releases {
		match $best {
			Ok((_, known)) if compare(known, v) != Before => {}
			_ => {
				$best = Ok((entry, v))
			}
		}
	}
	$best
}

## The tag of the oldest release of `line`.
first_of_line : List((Releases.Entry, Releases.Version)), List(U64) -> Try(Str, [Empty])
first_of_line = |releases, line| {
	var $best = Err(Empty)
	for (entry, v) in releases.keep_if(|(_, version)| Releases.line_of(version) == line) {
		match $best {
			Ok((_, known)) if compare(known, v) != After => {}
			_ => {
				$best = Ok((entry.tag, v))
			}
		}
	}
	match $best {
		Ok((tag, _)) => Ok(tag)
		Err(_) => Err(Empty)
	}
}

compare : Releases.Version, Releases.Version -> [Before, Same, After]
compare = |a, b|
	match compare_numbers(a.numbers, b.numbers) {
		Same =>
			match (a.candidate, b.candidate) {
				("", "") => Same
				("", _) => After
				(_, "") => Before
				_ => compare_candidates(a.candidate, b.candidate)
			}

		other => other
	}

## Numbers compared one by one, a missing one counting as 0, so 0.10.0 comes
## after 0.9.0 and 0.35 is 0.35.0.
compare_numbers : List(U64), List(U64) -> [Before, Same, After]
compare_numbers = |a, b|
	match (a, b) {
		([], []) => Same
		([x, .. as xs], []) => if (x > 0) After else compare_numbers(xs, [])
		([], [y, .. as ys]) => if (y > 0) Before else compare_numbers([], ys)
		([x, .. as xs], [y, .. as ys]) => if (x < y) Before else if (x > y) After else compare_numbers(xs, ys)
	}

## rc10 comes after rc9: by the number a candidate ends in, then by its text.
compare_candidates : Str, Str -> [Before, Same, After]
compare_candidates = |a, b| {
	ending = |text| U64.from_str(Str.from_utf8(Str.to_utf8(text).drop_if(|byte| byte < '0' or byte > '9')) ?? "") ?? 0
	x = ending(a)
	y = ending(b)
	if x < y {
		Before
	} else if x > y {
		After
	} else if a == b {
		Same
	} else if Str.to_utf8(a).len() < Str.to_utf8(b).len() {
		Before
	} else {
		After
	}
}

## The body at `url`, following the redirect a release download answers with.
download! : Str => Try(Str, Str)
download! = |url| {
	request = Request.from_method(GET).with_uri(url).add_header("User-Agent", "joy").with_timeout(TimeoutMilliseconds(30000))
	match Http.send!(request, { max_redirects: 5 }) {
		Ok(response) => {
			status = Response.status(response)
			if status == 200 {
				Ok(Str.from_utf8_lossy(Response.body(response)))
			} else {
				Err("HTTP ${status.to_str()}")
			}
		}

		Err(problem) => Err(Str.inspect(problem))
	}
}

entry : Str -> Releases.Entry
entry = |tag| {
	tag,
	date: "",
	platform_url: "https://github.com/niclas-ahden/joy/releases/download/${tag}/P.tar.zst",
	cli_url: "https://github.com/niclas-ahden/joy/releases/download/${tag}/C.tar.zst",
	html_url: "",
	roc_nightly: "",
}

many = ["0.45.0", "0.44.1", "0.44.0", "0.40.0", "0.36.1", "0.36.0", "0.35.2", "0.35.1", "0.35.0", "0.35.0-rc9"].map(entry)

expect Releases.is_newer("0.35.0", "0.35.0-rc9")
expect Releases.is_newer("0.35.0-rc10", "0.35.0-rc9")
expect Releases.is_newer("0.10.0", "0.9.0")
expect !Releases.is_newer("0.35.0", "0.35")
expect !Releases.is_newer("unreleased", "0.35.0")

expect Releases.offers("0.35.0", many) == [
	{ tag: "0.35.2", kind: Fixes, notes: "0.35.2" },
	{ tag: "0.36.1", kind: Breaking, notes: "0.36.0" },
	{ tag: "0.40.0", kind: Breaking, notes: "0.40.0" },
	{ tag: "0.44.1", kind: Breaking, notes: "0.44.0" },
	{ tag: "0.45.0", kind: Breaking, notes: "0.45.0" },
]

# A candidate's own final release counts as a fix.
expect Releases.offers("0.35.0-rc9", many).first() == Ok({ tag: "0.35.2", kind: Fixes, notes: "0.35.2" })
expect Releases.offers("0.45.0", many) == []
expect Releases.offers("2.1.0", ["2.3.0", "2.1.4"].map(entry)) == [{ tag: "2.3.0", kind: Features, notes: "2.3.0" }]

expect Releases.crossed("0.35.0", "0.44.1", many) == ["0.36.0", "0.40.0", "0.44.0"]
expect Releases.crossed("0.35.0", "0.35.2", many) == []

expect Releases.tag_of_url("https://github.com/growthagent/joy/releases/download/0.35.0-rc9/H.tar.zst") == Ok("0.35.0-rc9")
expect Releases.tag_of_url("../platform/main.roc") == Err(NotARelease)
expect Releases.repo_of_url("https://github.com/growthagent/joy/releases/download/0.35.0-rc9/H.tar.zst") == Ok("growthagent/joy")
expect Releases.repo_of_url("https://example.com/releases/download/1/H.tar.zst") == Err(NotARelease)
