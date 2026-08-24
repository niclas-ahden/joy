#!/usr/bin/env roc
# Run:
#
#   ./build.roc
#
# To build app.roc into `www/app.wasm`. Run from the repo root, or let
# ./watch.roc run it once at startup, for Joy's runtime.js.
#
# joy-html arrives as a release bundle through the URL in app.roc's header.
# The Joy platform is whatever app.roc's header names: a release bundle by
# URL, or a Joy checkout by path (as in the Joy repo itself, where the
# checkout's wasm host must exist: run ./build.roc at the repo root once).
# Either way there is nothing to compile but the app itself.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.Path
import pf.Stderr

out_path = "www/app.wasm"

main! = |_args| {
	# roc can exit 0 without writing anything, so drop the wasm up front and
	# check that it came back. Something stale must never reach the page
	# ./watch.roc serves.
	#
	# runtime.js is left alone: copy_runtime! overwrites it below anyway, and
	# dropping it took index.html's `import { mount } from './runtime.js'`
	# down with any failed build, blanking the page at module load.
	drop!(out_path)?

	build_app!()?

	copy_runtime!()
}

drop! = |file| {
	path = Path.utf8(file)
	if path.is_file!()? {
		path.delete!()
	} else {
		Ok({})
	}
}

# The page's ./runtime.js is Joy's client runtime, shipped beside the
# platform so it always matches it. A bundle platform (by URL, https or the
# localhost http Joy's release gate serves drafts over) sits in roc's
# package cache after the build, so the runtime is copied out of there. A
# path platform is a Joy checkout, where the runtime lives in the checkout's
# www/. Nothing to commit, exactly like the wasm itself.
copy_runtime! = || {
	url = platform_url!()?
	src = if url.starts_with("https://") or url.starts_with("http://") {
		hash = match url.split_last("/") {
			Ok(at_slash) => at_slash.after.drop_suffix(".tar.zst")
			Err(_) => url.drop_suffix(".tar.zst")
		}
		home = Env.var_str!("HOME") ?? ""
		cache = Env.var_str!("XDG_CACHE_HOME") ?? "${home}/.cache"
		"${cache}/roc/packages/${hash}/www/runtime.js"
	} else {
		"${url.drop_suffix("platform/main.roc")}www/runtime.js"
	}
	if Path.utf8(src).is_file!()? {
		run!("cp", [src, "www/runtime.js"])
	} else {
		fail!("no runtime.js at ${src}. Is app.roc's platform a Joy bundle or checkout?")
	}
}

# The platform bundle URL out of app.roc's header.
platform_url! = || {
	source = Str.from_utf8_lossy(Path.utf8("app.roc").read_bytes!()?)
	match source.split_first("platform \"") {
		Ok(at_platform) =>
			match at_platform.after.split_first("\"") {
				Ok(at_quote) => Ok(at_quote.before)
				Err(_) => fail!("could not read the platform URL out of app.roc")
			}

		Err(_) => fail!("could not read the platform URL out of app.roc")
	}
}

# roc exits 2 when it emits warnings but 0 even when it reports errors, so the
# summary line decides, not the exit code. Any warning, an error, or a module
# that never got written fails the build.
build_app! = || {
	output = capture!(
		Cmd.new_str("roc")
			.args_str(["build", "--target=wasm32", "--no-cache", "--output=${out_path}", "app.roc"]),
	)?
	clean = match output.split_on("\n").keep_oks(summary_counts).last() {
		Ok(counts) => counts.errors == 0 and counts.warnings == 0
		Err(_) => Bool.False
	}

	if clean and Path.utf8(out_path).is_file!()? {
		Ok({})
	} else {
		Stderr.line!(output)?
		fail!("roc build failed for app.roc")
	}
}

# Read the counts out of a line like "0 errors and 1 warning found in 704ms".
# Lines that are not a summary fail to parse and are skipped by the caller.
summary_counts = |line| {
	at_error = line.split_first(" error")?
	at_and = at_error.after.split_first(" and ")?
	at_warning = at_and.after.split_first(" warning")?
	errors = U64.from_str(at_error.before.trim()).map_err(|_| NotFound)?
	warnings = U64.from_str(at_warning.before.trim()).map_err(|_| NotFound)?
	Ok({ errors, warnings })
}

# roc spreads its diagnostics across stdout and stderr, and a run that reports
# errors can exit 0, so gather both streams whatever the exit code was.
capture! = |cmd| {
	match cmd.exec_output_bytes!() {
		Ok(streams) => Ok(Str.from_utf8_lossy(streams.stdout_bytes.concat(streams.stderr_bytes)))
		Err(NonZeroExitCodeB(streams)) =>
			Ok(Str.from_utf8_lossy(streams.stdout_bytes.concat(streams.stderr_bytes)))

		Err(FailedToGetExitCodeB(_)) => fail!("could not run ${Cmd.to_str(cmd)}")
	}
}

# Run a command with inherited stdio, exiting with the child's code when it
# fails.
run! = |program, args| {
	match Cmd.new_str(program).args_str(args).exec_exit_code!() {
		Ok(0) => Ok({})
		Ok(code) => Err(Exit(code))
		Err(_) => Err(Exit(1))
	}
}

# Report a message on stderr and exit non-zero.
fail! = |message| {
	Stderr.line!("error: ${message}") ?? {}
	Err(Exit(1))
}
