#!/usr/bin/env roc
# Run:
#
#   ./e2e.roc
#
# To build the examples, serve the repo root, then let roc-spec run
# tests/e2e/*_test.roc. Each one drives a Joy example in a real Chromium via
# roc-playwright. Run from the repo root.
#
# Needs the nix devShell (playwright + browsers) and a local checkout of
# ../roc-playwright, a path dep until it is released (roc-spec and basic-cli
# come in by release URL). Not part of tests.roc/CI yet for exactly that
# reason.
#
# Set the environment variable `JOY_E2E_PORT` to change the port (default 8787).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.Http
import pf.Sleep
import spec.Wait
import Util exposing [fail!, run!]

main! = |_args| {
	match Cmd.new_str("playwright").args_str(["--version"]).exec_output_bytes!() {
		Ok(_) => {}
		Err(_) => fail!("playwright not found, run inside the nix devShell")?
	}

	run!("./build.roc", [])?

	port = Env.var_str!("JOY_E2E_PORT") ?? "8787"
	url = "http://127.0.0.1:${port}"

	# Spawned grouped, so the platform kills the server (and anything it
	# spawned) when this script exits, pass or fail.
	# The same dev server watch.roc uses, started without an app name so every
	# app is reachable under its own prefix and the tests can share one port.
	server = Cmd.new_str("node")
		.args_str(["www/serve.mjs", port])
		.env_str("JOY_E2E_URL", url)
		.spawn_grouped!()?

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
