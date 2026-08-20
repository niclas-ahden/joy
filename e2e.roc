#!/usr/bin/env roc
# Run:
#
#   ./e2e.roc -- --opt=speed
#   ./e2e.roc -- --opt=dev
#
# To build the examples at that optimization level (flags need roc's `--`
# separator in front of them, otherwise roc claims --opt instead of passing
# it on), serve the repo root, then let roc-spec run
# tests/e2e/*_test.roc. Each one drives a Joy example in a real Chromium via
# roc-playwright. Run from the repo root, inside the nix devShell (it carries
# playwright and its browsers). CI runs this next to ./tests.roc: the fake-DOM
# harnesses there own the app logic, these tests own what only a real browser
# can prove (event dispatch and bubbling, <dialog>, History, WebCrypto, fetch,
# timers, real keyboard/mouse input).
#
# Set the environment variable `JOY_E2E_PORT` to change the port (default 8787).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.7.0/9PiT7ffE9m8BJyVv3LwE4rWWdcbpxEMUADMpiLBfY8jJ.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.Http
import pf.Sleep
import spec.Wait
import weaver.Cli
import Args
import Util exposing [fail!, run!]

main! = |args| {
	opt = Args.check_opt!(Args.parse!(parser, args, "--opt=speed")?)?

	if !(on_path!("playwright")) {
		fail!("playwright not found, run inside the nix devShell")?
	}

	run!("./build.roc", ["--", "--opt=${opt}"])?

	port = Env.var_str!("JOY_E2E_PORT") ?? "8787"
	url = "http://127.0.0.1:${port}"

	# Spawned leashed, so the platform kills the server (and anything it
	# spawned) when this script exits, pass or fail.
	# The same dev server watch.roc uses, started without an app name so every
	# app is reachable under its own prefix and the tests can share one port.
	server = Cmd.new_str("node")
		.args_str(["www/serve.mjs", port, opt])
		.env_str("JOY_E2E_URL", url)
		.spawn_leashed!()?

	# Any response means the port is live, so poll the page the tests open.
	# Bounded, so a server that never comes up fails the run instead of
	# hanging it.
	Wait.for_server!(
		{ http_send!: Http.send!, sleep!: Sleep.millis! },
		"${url}/counter/",
		{
			max_attempts: 100,
			delay_ms: 100,
			request_timeout_ms: 5_000,
			headers: [],
		},
	) ? |_| ServerNeverAnswered(url)

	# The runner is interpreted (default --opt=dev). It is only orchestration,
	# each test is spawned compiled (`roc --opt=speed`) by roc-spec.
	code = Cmd.new_str("roc")
		.args_str(["tests/e2e/run.roc"])
		.env_str("JOY_E2E_URL", url)
		.exec_exit_code!()
		.ok_or(1)

	server.kill!() ?? {}

	if code == 0 {
		Ok({})
	} else {
		Err(Exit(code))
	}
}

# Whether `program --version` runs at all. The program is a parameter rather
# than a literal because a command built from literals and matched in place is
# read as a compile-time constant, and the run warns "unconditional condition".
# A warning makes roc exit non-zero, which would fail this script for CI even
# when every test passed.
on_path! : Str => Bool
on_path! = |program|
	Cmd.new_str(program).args_str(["--version"]).exec_output_bytes!().is_ok()

parser : Cli.CliParser(Str)
parser = Cli.assert_valid(
	Cli.finish(
		Args.opt_option,
		{
			name: "e2e",
			version: "",
			authors: [],
			description: "Build the examples at the given optimization level and drive them in a real Chromium via tests/e2e/.",
			text_style: Plain,
		},
	),
)
