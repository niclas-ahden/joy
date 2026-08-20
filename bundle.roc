#!/usr/bin/env roc
# Run:
#
#   ./bundle.roc
#
# To build the host and bundle the platform into dist/, ready to attach to a
# release. Run from the repo root.
#
# The platform names joy-html by its release URL, so the archive is
# self-contained and needs no base URL at bundle time: wherever it ends up
# served, the app's `pf` is that URL and nothing inside has to change.
#
# The Release workflow does this when a release tag is pushed. Running it by
# hand is for checking the archive before tagging one.
#
# Archive names are the blake3 hash of their contents, so re-bundling
# unchanged sources yields the same name.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
}

import pf.Cmd
import pf.Path
import pf.Stdout
import Util exposing [fail!, run!]

main! = |_args| {
	# The host ships inside the platform bundle, so it must be fresh.
	# Naming an example is the cheapest way through build.roc.
	run!("./build.roc", ["--", "--opt=speed", "hello"])?

	# Start from an empty dist/ so it holds exactly one archive. A leftover
	# from an earlier run would make `dist/*.tar.zst` ambiguous, and the
	# release workflow picks the archive to upload that way.
	run!("rm", ["-rf", "dist"])?
	Path.utf8("dist").create_all!()?

	# An app must name the same joy-html the platform was built against, or
	# its Html is a different nominal type than the one `render` returns, so
	# read the URL out of the header instead of repeating it here.
	html_url = html_url!({})?

	# Bundle a scratch copy of the platform so the runtime can be dropped in
	# without touching the checkout. The copy includes
	# targets/wasm32/host.wasm because build.roc just wrote it.
	run!("rm", ["-rf", "dist/.platform"])?
	run!("cp", ["-r", "platform", "dist/.platform"])?

	# The client runtime ships inside the bundle so an app always serves the
	# runtime its platform was built with. It lands in roc's package cache
	# next to the platform sources, where an app's build script copies it
	# from (see joy-frontend-example's build.roc).
	run!("mkdir", ["-p", "dist/.platform/www"])?
	run!("cp", ["www/runtime.js", "dist/.platform/www/runtime.js"])?

	platform_archive = bundle!("cd dist/.platform && roc bundle main.roc targets/wasm32/host.wasm www/runtime.js --output-dir ..")?

	run!("rm", ["-rf", "dist/.platform"])?

	Stdout.line!("")?
	Stdout.line!("Bundled into dist/${platform_archive}")?
	Stdout.line!("")?
	Stdout.line!("Attach it to a release and an app's `pf` is that download URL,")?
	Stdout.line!("paired with the joy-html this platform was built against:")?
	Stdout.line!("")?
	Stdout.line!("    html: \"${html_url}\",")
}

# Run a `roc bundle` command line via bash (Cmd cannot set a working
# directory), returning the created archive's file name. roc bundle prints
# "Created: <path>" on success, so a missing line means it failed, whatever
# the exit code was.
bundle! = |command| {
	output = match Cmd.new_str("bash").args_str(["-c", command]).exec_output_bytes!() {
		Ok(streams) => Str.from_utf8_lossy(streams.stdout_bytes.concat(streams.stderr_bytes))
		Err(NonZeroExitCodeB(streams)) =>
			Str.from_utf8_lossy(streams.stdout_bytes.concat(streams.stderr_bytes))

		Err(FailedToGetExitCodeB(_)) => fail!("could not run: ${command}")?
	}

	created = output.split_on("\n").keep_oks(|line| line.split_first("Created: ")).first()
	match created {
		Ok(split) =>
			match split.after.trim().split_last("/") {
				Ok(at_slash) => Ok(at_slash.after)
				Err(_) => Ok(split.after.trim())
			}

		Err(_) => {
			Stdout.line!(output)?
			fail!("no archive came out of: ${command}")
		}
	}
}

# The joy-html URL out of the platform header, so the printed instructions
# cannot drift from what the platform was built against.
html_url! = |{}| {
	source = Path.utf8("platform/main.roc").read_utf8!() ?? fail!("could not read platform/main.roc")?

	match source.split_first("html: \"") {
		Ok(split) =>
			match split.after.split_first("\"") {
				Ok(quoted) => Ok(quoted.before)
				Err(_) => fail!("unterminated html URL in platform/main.roc")
			}

		Err(_) => fail!("no html dependency in platform/main.roc")
	}
}
