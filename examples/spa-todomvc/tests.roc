#!/usr/bin/env roc
# Run:
#
#   roc tests.roc
#
# Builds what ships with ./joy build into .joy/test/build/, apart from dist/
# and from what ./joy dev serves, then hands every argument through to
# e2e/run.roc, which serves that build from one static file server per
# worker and runs every e2e/*_test.roc through roc-spec, driving a real
# browser with roc-playwright. Accepts a filename pattern (substring) and
# --fail-fast, e.g. `roc tests.roc edit`.
#
# A full run (no arguments) ends with a smoke pass over ./joy dev: start
# it, wait until it says the page is ready, then drive one browser test
# against it. That covers the loop you work in, not just the build.
#
# Run from the example's folder, with ./joy installed there (see the
# README) and inside `nix develop` (for roc, caddy and playwright).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import http.Request
import pf.Cmd
import pf.Duration
import pf.Http
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stderr
import pf.Stdout
import pf.Tcp

main! : List(OsStr) => Try({}, _)
main! = |forwarded| {
	if !(Path.utf8("joy").is_file!() ?? Bool.False) {
		Stderr.line!("There is no ./joy in this folder. The README says how to install it.")?
		Err(NoJoy)?
	}
	# A fresh build before any server starts serving it.
	build!("./joy", ["build", "--out-dir", ".joy/test/build"])?

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
		smoke_dev!({})
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
	runner_args = [OsStr.utf8("e2e/run.roc")].concat(forwarded)
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

# The loop you work in: ./joy dev must come up and serve a working app. One
# real browser test against it proves the whole chain (its first build, the
# page in public/, the loader and the hot runtime). It does not edit a
# file, as Joy's own suite covers what a save does.
smoke_dev! : {} => Try({}, _)
smoke_dev! = |{}| {
	ports = free_ports!(1)?
	smoke_port = (ports.first() ? |_| NoFreePort("the operating system gave no port")).to_str()
	Stdout.line!("Smoke testing ./joy dev on port ${smoke_port}...")?

	dev = Cmd.new(OsStr.from_str("./joy")).args(["dev", "--port", smoke_port].map(OsStr.from_str))
		.stdout(Pipe)
		.stderr(MergeWithStdout)
		.spawn_leashed!() ? |e| CouldNotStartDev(Str.inspect(e))

	# It says the page is ready once its first build has landed.
	wait_for_output!(dev, "Ready on", "", 600)?

	url = "http://localhost:${smoke_port}"
	wait_for_server!("${url}/", 150)?

	code = Cmd.new(OsStr.from_str("roc"))
		.args([OsStr.from_str("e2e/add_test.roc")])
		.env(OsStr.from_str("E2E_URL"), OsStr.from_str(url))
		.inherit_stdio()
		.run!()
		.map_ok(|output| exit_code(output.status))
		.ok_or(1)

	dev.kill!() ?? {}

	if code == 0 {
		Stdout.line!("./joy dev serves a working app")
	} else {
		Stderr.line!("The browser test against ./joy dev failed with exit code ${code.to_str()}")?
		Err(DevSmokeFailed(code))
	}
}

# Echo what ./joy dev prints until it has printed `part`. Bounded like
# wait_for_server!, at 200 ms a read.
wait_for_output! : Cmd.Child, Str, Str, U64 => Try({}, [DevNeverReady, Interrupted, ..e])
wait_for_output! = |child, part, seen, attempts_left| {
	if seen.contains(part) {
		Ok({})
	} else if attempts_left == 0 {
		Err(DevNeverReady)
	} else {
		match child.read!(Duration.millis(200)) {
			Ok(Stdout(bytes)) | Ok(Stderr(bytes)) => {
				text = Str.from_utf8_lossy(bytes)
				Stdout.write!(text) ?? {}
				wait_for_output!(child, part, Str.concat(seen, text), attempts_left - 1)
			}
			Err(EndOfInput) => Err(DevNeverReady)
			Err(_) => wait_for_output!(child, part, seen, attempts_left - 1)
		}
	}
}

# Any successful response means the server is up. Bounded, so a ./joy dev
# that never serves fails the smoke instead of hanging it.
wait_for_server! : Str, U64 => Try({}, [DevNeverServed, Interrupted, ..e])
wait_for_server! = |url, attempts_left| {
	if Http.send!(Request.from_method(GET).with_uri(url), {}).is_ok() {
		Ok({})
	} else if attempts_left == 0 {
		Err(DevNeverServed)
	} else {
		Sleep.millis!(200)?
		wait_for_server!(url, attempts_left - 1)
	}
}

## `count` ports that are free now. The operating system picks them, so the
## suite never collides with another server on this machine. Every probe
## stays open until all are picked, so no two ports are the same.
free_ports! : U64 => Try(List(U64), [NoFreePort(Str)])
free_ports! = |count| {
	var $probes = []
	var $ports = []
	while $ports.len() < count {
		probe = Tcp.listen!("127.0.0.1", 0, Duration.seconds(5)) ? |e| NoFreePort(Str.inspect(e))
		port = probe.local_port!() ? |e| NoFreePort(Str.inspect(e))
		$probes = $probes.append(probe)
		$ports = $ports.append(port.to_u64())
	}
	for probe in $probes {
		probe.close!() ? |e| NoFreePort(Str.inspect(e))
	}
	Ok($ports)
}
