#!/usr/bin/env roc
# Run:
#
#   ./e2e.roc -- --opt=speed
#   ./e2e.roc -- --opt=dev
#
# To build the examples at that optimization level (flags need roc's `--`
# separator in front of them, otherwise roc claims --opt instead of passing
# it on), serve the repo root, then let roc-spec run
# tests/e2e/*_test.roc. Each one drives a Joy example in a real browser via
# roc-playwright: Chromium by default, `--browser=firefox`, `webkit` or `all`
# for the other engines Playwright bundles. Run from the repo root with
# `playwright` on PATH: the nix devShell carries it and its browsers, CI's
# nightly-compiler legs install it with npm instead. CI runs this next to
# ./tests.roc: the fake-DOM harnesses there own the app logic, these tests own
# what only a real browser can prove (event dispatch and bubbling, <dialog>,
# History, WebCrypto, fetch, timers, real keyboard/mouse input).
#
# Set the environment variable `JOY_E2E_PORT` to change the port (default 8787).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.1/55UFmX5Ye5dNxWYzbzxQfsE54KTNwaoHNmYan163HbzB.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.Http
import pf.Sleep
import pf.Stdout
import spec.Wait
import weaver.Cli
import weaver.Opt
import Args
import Util exposing [fail!, run!]

main! = |args| {
	{ opt: opt_arg, browser } = Args.parse!(parser, args, "--opt=speed")?
	opt = Args.check_opt!(opt_arg)?
	browsers = match browser {
		"all" => ["chromium", "firefox", "webkit"]
		"chromium" | "firefox" | "webkit" => [browser]
		other => fail!("unknown --browser ${other}, expected chromium, firefox, webkit or all")?
	}

	if !(on_path!("playwright")) {
		fail!("playwright not found. The nix devShell provides it, or install it with `npm install -g playwright && playwright install chromium`.")?
	}

	run!("roc", ["./build.roc", "--", "--opt=${opt}"])?

	port = Env.var_str!("JOY_E2E_PORT") ?? "8787"
	url = "http://127.0.0.1:${port}"

	# Spawned leashed, so the platform kills the server (and anything it
	# spawned) when this script exits, pass or fail.
	# The same dev server watch.roc uses, started without an app name so every
	# app is reachable under its own prefix and the tests can share one port.
	server = Cmd.new_str("node")
		.args_str(["www/serve.mjs", port, opt])
		.env_str("JOY_E2E_URL", url)
		.stdout(Null)
		.stderr(Null)
		.spawn_leashed!() ? |e| SpawnFailed(e)

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
	# each test is spawned compiled (`roc --opt=speed`) by roc-spec. JOY_OPT
	# names the build under test (stack_canary_test gates its deep budget on
	# it), JOY_BROWSER the engine (see tests/e2e/Browser.roc). One runner
	# pass per engine, so a red engine shows next to the others instead of
	# hiding behind the first.
	codes = browsers.map_try!(
		|engine| {
			Stdout.line!("== ${engine}")?
			Ok(
				Cmd.new_str("roc")
					.args_str(["tests/e2e/run.roc"])
					.env_str("JOY_E2E_URL", url)
					.env_str("JOY_OPT", opt)
					.env_str("JOY_BROWSER", engine)
					.exec_exit_code!()
					.ok_or(1),
			)
		},
	)?
	# The first engine that failed decides the exit code. Not the largest: a
	# crash on Windows exits with a negative code, which another engine's 0
	# would hide.
	code = codes.find_first(|c| c != 0) ?? 0

	server.close!() ?? {}

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
	# npm installs the CLI as `<name>.cmd` on Windows, and a spawn's PATH
	# search there only ever appends `.exe`, so the bare name resolves on
	# Unix and nowhere else. Try the shim second.
		or Cmd.new_str("${program}.cmd").args_str(["--version"]).exec_output_bytes!().is_ok()

parser : Cli.CliParser({ opt : Str, browser : Str })
parser = Cli.assert_valid(
	Cli.finish(
		{
			opt: Args.opt_option,
			browser: Opt.str({
				short: "",
				long: "browser",
				help: "Engine to drive: chromium (default), firefox, webkit or all.",
				default: Value("chromium"),
			}),
		}.Cli,
		{
			name: "e2e",
			version: "",
			authors: [],
			description: "Build the examples at the given optimization level and drive them in a real browser via tests/e2e/.",
			text_style: Plain,
		},
	),
)
