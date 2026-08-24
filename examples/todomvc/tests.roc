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
# it, wait for its server, then drive one browser test against it. That
# covers the dev loop the scripts and Caddyfile promise, not just the app.
#
# Run from the repo root, inside `nix develop` (for roc, caddy and
# playwright).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
}

import pf.Cmd
import pf.Http
import pf.OsStr exposing [OsStr]
import pf.Sleep
import pf.Stderr
import pf.Stdout
import pf.Url

main! : List(OsStr) => Try({}, _)
main! = |os_args| {
	forwarded = os_args.drop_first(1)

	# Fresh wasm before any server starts serving www/
	build!("./build.roc")?

	# systemd scope when available (ensures all descendant processes die with
	# the run, browsers included). Fall back to a plain spawn in CI where no
	# user session exists.
	use_systemd =
		Cmd.new(OsStr.utf8("systemctl"))
			.args([OsStr.utf8("--user"), OsStr.utf8("show-environment")])
			.exec_output!()
			.is_ok()

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
build! : Str => Try({}, [BuildFailed, ..e])
build! = |script|
	match Cmd.new_str(script).exec_exit_code!() {
		Ok(0) => Ok({})
		_ => Err(BuildFailed)
	}

run_suite! : Bool, List(OsStr) => Try(I32, _)
run_suite! = |use_systemd, forwarded| {
	runner_args = [OsStr.utf8("tests/run.roc"), OsStr.utf8("--")].concat(forwarded)
	if use_systemd {
		Cmd.new(OsStr.utf8("systemd-run"))
			.args([OsStr.utf8("--scope"), OsStr.utf8("--user"), OsStr.utf8("roc")].concat(runner_args))
			.exec_exit_code!()
	} else {
		Cmd.new(OsStr.utf8("roc"))
			.args(runner_args)
			.exec_exit_code!()
	}
}

# The dev loop: ./watch.roc must come up and serve a working app. One real
# browser test against it proves the whole chain (caddy, the build it runs,
# runtime.js, the /todomvc/ alias). It does not edit app.roc, so the
# rebuild-on-change half of the loop is roc's own --watch to keep honest.
# Clear of the worker servers at 9000+ and the dev default 8000.
smoke_port = "8123"

smoke_watch! : {} => Try({}, _)
smoke_watch! = |{}| {
	Stdout.line!("Smoke testing ./watch.roc on port ${smoke_port}...")?

	watch = Cmd.new_str("./watch.roc")
		.env_str("JOY_WATCH_PORT", smoke_port)
		.spawn_leashed!() ? |e| CouldNotStartWatch(Str.inspect(e))

	url = "http://localhost:${smoke_port}"
	wait_for_server!(Url.parse("${url}/") ? |_| BadSmokeUrl(url), 150)?

	code = Cmd.new_str("roc")
		.args_str(["tests/add_test.roc"])
		.env_str("JOY_E2E_URL", url)
		.exec_exit_code!()
		.ok_or(1)

	watch.kill!() ?? {}

	if code == 0 {
		Stdout.line!("./watch.roc serves a working app")
	} else {
		Stderr.line!("The browser test against ./watch.roc failed with exit code ${code.to_str()}")?
		Err(WatchSmokeFailed(code))
	}
}

# Any successful response means the server is up. Bounded, so a watch.roc
# that never serves fails the smoke instead of hanging it.
wait_for_server! : Url.Url, U64 => Try({}, [WatchNeverServed, ..e])
wait_for_server! = |url, attempts_left| {
	if Http.get_utf8!(url).is_ok() {
		Ok({})
	} else if attempts_left == 0 {
		Err(WatchNeverServed)
	} else {
		Sleep.millis!(200)
		wait_for_server!(url, attempts_left - 1)
	}
}
