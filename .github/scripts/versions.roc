#!/usr/bin/env roc
# Run:
#
#   roc .github/scripts/versions.roc <owner/repo> <output file>
#
# To write versions.json: every published release with the URLs a project
# needs and the Roc nightly it recommends. It is attached to the latest
# release, so ./joy reads it from releases/latest/download/versions.json, a
# plain download, instead of from GitHub's rate-limited API.
#
# The file is written from the releases every time, never edited, so a
# deleted release drops out and a hand edit to the notes shows up on the
# next run. Reads the releases with `gh api`, which needs GH_TOKEN.
#
# The format, newest release first:
#
#   { "schema": 1, "releases": [{ "tag", "date", "platform_url", "cli_url", "html_url", "roc_nightly" }] }
#
# Every field is a string, "" when the release has none (no CLI bundle
# before ./joy existed, no nightly line in the oldest notes). ./joy reads
# this from releases it was built long before, so fields are only ever
# added. A change it could not read gets a new file name instead.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout

main! = |args| {
	(repo, out) =
		match args.map(|arg| OsStr.to_str_try(arg) ?? "") {
			[r, o] => (r, o)
			_ => return fail!("usage: roc .github/scripts/versions.roc <owner/repo> <output file>")
		}

	releases = published!(repo)?.map(entry)
	json = Json.to_str_try({ schema: 1.U32, releases }) ? |_| Exit(1)
	Path.utf8(out).write_utf8!(json)?
	Stdout.line!("${out}: ${releases.len().to_str()} releases")
}

# One release as `gh api` prints it below.
Release : {
	tag : Str,
	date : Str,
	body : Str,
	assets : List({ name : Str, label : Str, url : Str }),
}

# The published releases, newest first. Drafts and prereleases are left out
# here, in jq, along with the nulls Roc's JSON decoding has no string for.
published! = |repo| {
	query = ".[] | select(.draft | not) | select(.prerelease | not) | {tag: .tag_name, date: (.published_at // \"\"), body: (.body // \"\"), assets: [.assets[] | {name, label: (.label // \"\"), url: .browser_download_url}]}"
	output = capture!(Cmd.new(OsStr.from_str("gh")).args(["api", "--paginate", "repos/${repo}/releases?per_page=100", "--jq", query].map(OsStr.from_str)))?
	output.split_on("\n").drop_if(|line| line.trim().is_empty()).map_try(|line| {
		release : Try(Release, _)
		release = Json.parse(line)
		release.map_err(|_| Exit(1))
	})
}

entry = |{ tag, date, body, assets }| {
	bundles = assets.keep_if(|asset| asset.name.ends_with(".tar.zst"))
	{
		tag,
		date,
		platform_url: bundle_url(bundles, "platform"),
		cli_url: bundle_url(bundles, "cli"),
		html_url: joy_html_url(body),
		roc_nightly: roc_nightly(body),
	}
}

# A bundle by its label. Releases from before the CLI bundle carry the
# platform alone, unlabelled.
bundle_url = |bundles, label|
	match (bundles.find_first(|b| b.label == label), bundles) {
		(Ok(bundle), _) => bundle.url
		(Err(_), [only]) if label == "platform" and only.label == "" => only.url
		_ => ""
	}

# The joy-html URL from the notes' "Using this release" block.
joy_html_url = |body| quoted_after(body, "html: \"")

# The nightly the "Compatible with:" line names, the line
# .github/scripts/name-nightly.sh moves forward.
roc_nightly = |body| {
	line = body.split_on("\n").find_first(|l| l.starts_with("Compatible with: [`roc ")) ?? ""
	match line.split_first("[`roc ") {
		Ok({ after, .. }) => after.split_first("`").map_ok(|parts| parts.before) ?? ""
		Err(_) => ""
	}
}

# What sits between `prefix` and the next double quote, on the first line
# that starts with `prefix` once indented.
quoted_after = |body, prefix| {
	line = body.split_on("\n").find_first(|l| l.trim().starts_with(prefix)) ?? ""
	match line.trim().split_first(prefix) {
		Ok({ after, .. }) => after.split_first("\"").map_ok(|parts| parts.before) ?? ""
		Err(_) => ""
	}
}

# Stdout of a command that must succeed.
capture! = |cmd| {
	match cmd.run!() {
		Ok(output) =>
			if output.status == Exited(0) {
				Ok(Str.from_utf8_lossy(output.stdout_bytes))
			} else {
				fail!("${cmd.to_str()} failed: ${Str.from_utf8_lossy(output.stderr_bytes)}")
			}

		Err(_) => fail!("could not run ${cmd.to_str()}")
	}
}

fail! = |message| {
	Stderr.line!("error: ${message}") ?? {}
	Err(Exit(1))
}
