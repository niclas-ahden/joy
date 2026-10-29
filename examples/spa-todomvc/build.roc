#!/usr/bin/env roc
# Run:
#
#   ./build.roc
#   ./build.roc --release
#
# To build app.roc into `www/app.wasm`. Run from the repo root, or let
# ./watch.roc run it once at startup, for Joy's runtime.js.
#
# The plain build is for development: its runtime.js holds every browser
# feature, so it stays good while ./watch.roc rebuilds the wasm. `--release`
# builds what you deploy, optimized for size and with a runtime.js holding
# only the features the app calls.
#
# joy-html arrives as a release bundle through the URL in app.roc's header.
# The Joy platform is whatever app.roc's header names: a release bundle by
# URL, or a Joy checkout by path (as in the Joy repo itself, where the
# checkout's wasm host must exist: run ./build.roc at the repo root once).
# Either way there is nothing to compile but the app itself.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	joy_runtime: "../../tools/runtime/main.roc",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stderr
import pf.System
import joy_runtime.JoyRuntime

out_path = "www/app.wasm"

main! = |args| {
	release = args.any(|arg| OsStr.to_str_try(arg) == Ok("--release"))

	# roc can exit 0 without writing anything, so drop the wasm up front and
	# check that it came back. Something stale must never reach the page
	# ./watch.roc serves.
	#
	# runtime.js is left alone: write_runtime! overwrites it below anyway, and
	# dropping it took index.html's `import { mount } from './runtime.js'`
	# down with any failed build, blanking the page at module load.
	drop!(out_path)?

	build_app!(release)?

	write_runtime!(release)
}

drop! = |file| {
	path = Path.utf8(file)
	if path.is_file!()? {
		path.delete!()
	} else {
		Ok({})
	}
}

# The page's ./runtime.js is Joy's client runtime with the code of every
# browser feature, or for a release only of those the app calls (see Joy's
# tools/runtime), made from the www/ that ships beside the platform so it
# always matches it. A bundle platform (by URL, https or the localhost http
# Joy's release gate serves drafts over) sits in roc's package cache after
# the build, so its www/ is read there. A path platform is a Joy checkout,
# with www/ in the checkout. Nothing to commit, exactly like the wasm itself.
write_runtime! = |release| {
	url = platform_url!()?
	joy_www = if url.starts_with("https://") or url.starts_with("http://") {
		hash = match url.split_last("/") {
			Ok(at_slash) => at_slash.after.drop_suffix(".tar.zst")
			Err(_) => url.drop_suffix(".tar.zst")
		}
		"${package_cache!()}/${hash}/www"
	} else {
		"${url.drop_suffix("platform/main.roc")}www"
	}
	core = match Path.utf8("${joy_www}/runtime.js").read_utf8!() {
		Ok(js) => js
		Err(_) => return fail!("no runtime.js in ${joy_www}. Is app.roc's platform a Joy bundle or checkout?")
	}
	features = (Path.utf8("${joy_www}/features").list!() ?? [])
		.keep_if(|entry| Path.display(entry).ends_with(".js"))
		.map_try!(|entry| entry.read_utf8!())?
	runtime = if release {
		wasm = Path.utf8(out_path).read_bytes!()?
		JoyRuntime.generate({ core, features, wasm })
	} else {
		JoyRuntime.full({ core, features })
	}
	match runtime {
		Ok(js) => Path.utf8("www/runtime.js").write_utf8!(js)
		Err(problem) => fail!("could not make www/runtime.js: ${Str.inspect(problem)}")
	}
}

# Where roc keeps the packages it downloads, found the way roc finds it:
# XDG_CACHE_HOME when set, else %LOCALAPPDATA% (Windows), else ~/.cache.
package_cache! = || {
	base = match Env.var_str!("XDG_CACHE_HOME") {
		Ok(xdg) => xdg
		Err(_) =>
			match (System.target!().os(), Env.var_str!("LOCALAPPDATA")) {
				(Windows(_), Ok(local)) => local
				_ => {
					home = Env.var_str!("HOME") ?? ""
					"${home}/.cache"
				}
			}
	}
	"${base}/roc/packages"
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
build_app! = |release| {
	opt = if release ["--opt=size"] else []
	output = capture!(
		Cmd.new(OsStr.from_str("roc"))
			.args(["build", "--target=wasm32", "--no-cache", "--output=${out_path}"].concat(opt).append("app.roc").map(OsStr.from_str)),
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
# WORKAROUND: roc-lang/roc#12707. Without this annotation roc can panic with
# `guarded list invalidated` while building. Drop the annotation when fixed.
summary_counts : Str -> Try({ errors : U64, warnings : U64 }, [NotFound])
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
	match cmd.run!() {
		Ok(output) => Ok(Str.from_utf8_lossy(output.stdout_bytes.concat(output.stderr_bytes)))
		Err(_) => fail!("could not run ${cmd.to_str()}")
	}
}

# Report a message on stderr and exit non-zero.
fail! = |message| {
	Stderr.line!("error: ${message}") ?? {}
	Err(Exit(1))
}
