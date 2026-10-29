#!/usr/bin/env roc
# Run:
#
#   ./tests.roc
#
# Builds the app, then hands every argument through to tests/run.roc, which
# starts one static file server per worker and runs every tests/*_test.roc
# through roc-spec, driving a real browser with roc-playwright. Accepts a
# filename pattern (substring) and --fail-fast, e.g. `./tests.roc edit`.
#
# A full run (no arguments) ends with a smoke pass over ./watch.roc: start
# it, wait for its first build and its server, then drive one browser test
# against it. That covers the dev loop the scripts and Caddyfile promise, not
# just the app.
#
# Run from the repo root, inside `nix develop` (for roc, caddy and
# playwright).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import http.Request
import pf.Cmd
import pf.Duration
import pf.Http
import pf.OsStr
import pf.Sleep
import pf.Stderr
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |forwarded| {
	# Fresh wasm before any server starts serving www/.
	# WORKAROUND: roc-lang/roc#12693 and #12701. A shared roc cache can crash
	# this compile. Drop `--no-cache` when fixed.
	build!("roc", ["--no-cache", "./build.roc"])?

	# systemd scope when available (ensures all descendant processes die with
	# the run, browsers included). Fall back to a plain spawn in CI where no
	# user session exists.
	use_systemd =
		match Cmd.new(OsStr.utf8("systemctl")).args([OsStr.utf8("--user"), OsStr.utf8("show-environment")]).run!() {
			Ok(output) => output.status == Exited(0)
			Err(_) => Bool.False
		}

	Stdout.line!("Running the browser tests in parallel...")?

	code = run_suite!(use_systemd, forwarded)?

	if code != 0 {
		Stderr.line!("The browser tests failed with exit code ${code.to_str()}")?
		Err(TestsFailed(code))?
	} else {
		{}
	}

	# The smoke only belongs to a full run: filtered runs are someone
	# iterating on one test, and the smoke would tax every iteration.
	if forwarded.is_empty() {
		smoke_watch!({})
	} else {
		Ok({})
	}
}

# Run the build script with inherited stdio, so its diagnostics land in the
# terminal. A failed build means there is nothing to test.
build! : Str, List(Str) => Try({}, [BuildFailed, ..e])
build! = |program, args|
	match Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).inherit_stdio().run!() {
		Ok(output) if output.status == Exited(0) => Ok({})
		_ => Err(BuildFailed)
	}

run_suite! : Bool, List(OsStr) => Try(I32, _)
run_suite! = |use_systemd, forwarded| {
	runner_args = [OsStr.utf8("tests/run.roc")].concat(forwarded)
	if use_systemd {
		Cmd.new(OsStr.utf8("systemd-run"))
			.args([OsStr.utf8("--scope"), OsStr.utf8("--user"), OsStr.utf8("roc")].concat(runner_args))
			.inherit_stdio()
			.run!()
			.map_ok(|output| exit_code(output.status))
	} else {
		Cmd.new(OsStr.utf8("roc"))
			.args(runner_args)
			.inherit_stdio()
			.run!()
			.map_ok(|output| exit_code(output.status))
	}
}

# A child's exit code, 1 for one killed by a signal.
exit_code : Cmd.ExitStatus -> I32
exit_code = |status|
	match status {
		Exited(code) => code
		Signaled(_) => 1
	}

# The dev loop: ./watch.roc must come up and serve a working app. One real
# browser test against it proves the whole chain (caddy, the build it runs,
# runtime.js, the /spa-todomvc/ alias). It does not edit app.roc, so the
# rebuild-on-change half of the loop is roc's own --watch to keep honest.
# Clear of the worker servers at 9000+ and the dev default 8000.
smoke_port = "8123"

smoke_watch! : {} => Try({}, _)
smoke_watch! = |{}| {
	Stdout.line!("Smoke testing ./watch.roc on port ${smoke_port}...")?

	watch = Cmd.new(OsStr.from_str("roc")).args([OsStr.from_str("./watch.roc")])
		.env(OsStr.from_str("JOY_WATCH_PORT"), OsStr.from_str(smoke_port))
		.stdout(Pipe)
		.stderr(MergeWithStdout)
		.spawn_leashed!() ? |e| CouldNotStartWatch(Str.inspect(e))

	# The server comes up before roc's --watch build rewrites www/app.wasm, and
	# a page loaded meanwhile can get half a file, so wait for that build.
	wait_for_output!(watch, "successfully building", "", 600)?

	url = "http://localhost:${smoke_port}"
	wait_for_server!("${url}/", 150)?

	code = Cmd.new(OsStr.from_str("roc"))
		.args([OsStr.from_str("tests/add_test.roc")])
		.env(OsStr.from_str("E2E_URL"), OsStr.from_str(url))
		.inherit_stdio()
		.run!()
		.map_ok(|output| exit_code(output.status))
		.ok_or(1)

	watch.kill!() ?? {}

	if code == 0 {
		Stdout.line!("./watch.roc serves a working app")
	} else {
		Stderr.line!("The browser test against ./watch.roc failed with exit code ${code.to_str()}")?
		Err(WatchSmokeFailed(code))
	}
}

# Echo what ./watch.roc prints until it has printed `part`. Bounded like
# wait_for_server!, at 200 ms a read.
wait_for_output! : Cmd.Child, Str, Str, U64 => Try({}, [WatchNeverBuilt, Interrupted, ..e])
wait_for_output! = |child, part, seen, attempts_left| {
	if seen.contains(part) {
		Ok({})
	} else if attempts_left == 0 {
		Err(WatchNeverBuilt)
	} else {
		match read_child!(child, Duration.millis(200)) {
			Ok(Stdout(bytes)) | Ok(Stderr(bytes)) => {
				text = Str.from_utf8_lossy(bytes)
				Stdout.write!(text) ?? {}
				wait_for_output!(child, part, Str.concat(seen, text), attempts_left - 1)
			}
			Err(EndOfInput) => Err(WatchNeverBuilt)
			Err(_) => wait_for_output!(child, part, seen, attempts_left - 1)
		}
	}
}

# WORKAROUND: roc-lang/roc#12692. A dev build frees a Child whose method a
# `match` with an early return called, which kills the child. Call
# `child.read!(timeout)` directly when fixed.
read_child! = |child, timeout| child.read!(timeout)

# Any successful response means the server is up. Bounded, so a watch.roc
# that never serves fails the smoke instead of hanging it.
wait_for_server! : Str, U64 => Try({}, [WatchNeverServed, Interrupted, ..e])
wait_for_server! = |url, attempts_left| {
	if Http.send!(Request.from_method(GET).with_uri(url), {}).is_ok() {
		Ok({})
	} else if attempts_left == 0 {
		Err(WatchNeverServed)
	} else {
		Sleep.millis!(200)?
		wait_for_server!(url, attempts_left - 1)
	}
}
