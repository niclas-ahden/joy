#!/usr/bin/env roc
# Run:
#
#   ./watch.roc examples/counter.roc               at --opt=speed, the default
#   ./watch.roc --opt=dev examples/counter.roc  at another level
#
# To build the given example at that optimization level and serve it at
# http://localhost:8000. You can then edit the example and it'll rebuild
# automatically. Refresh the page to see your changes. Run from the repo
# root.
#
# `--opt` defaults to speed here: the dev loop wants the same code the
# examples ship with. Flags need roc's `--` separator in front of them,
# otherwise roc claims --opt and --help for itself instead of passing them
# on. Plain arguments, like the app name above, need no separator.
#
# Set the environment variable `JOY_WATCH_PORT` to change the port (default 8000).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Sleep
import pf.Stdout
import weaver.Cli
import weaver.Param
import Args
import Util exposing [example_name, fail!]

main! = |args| {
	port = Env.var_str!("JOY_WATCH_PORT") ?? "8000"

	config = Args.parse!(parser, args, "--opt=dev examples/counter.roc")?
	opt = Args.check_opt!(config.opt)?
	full_name = config.app_name
	name = example_name(full_name)

	check_watchexec!(Cmd.new(OsStr.from_str("watchexec")).arg(OsStr.from_str("--version")))?

	server = start_server!(port, opt, name)?

	Stdout.line!("=> Serving '${full_name}' (--opt=${opt}) at http://localhost:${port}")?

	# check_watchexec! has already ruled out the usual failure, a missing
	# binary, so an error here is something rarer and worth naming.
	exit_code = match watchexec_cmd(opt, full_name).inherit_stdio().run!() {
		Ok(output) =>
			match output.status {
				Exited(code) => code
				Signaled(_) => 1
			}

		Err(problem) => fail!("watchexec: ${Str.inspect(problem)}")?
	}

	server.close!() ?? {}

	if exit_code == 0 {
		Ok({})
	} else {
		Err(Exit(exit_code))
	}
}

# The rebuild loop: watchexec reruns build.roc whenever a source file changes.
# WORKAROUND: roc-lang/roc#12693 and #12701. A shared roc cache can crash the
# build.roc compile. Drop `--no-cache` when fixed.
watchexec_cmd = |opt, full_name|
	Cmd.new(OsStr.from_str("watchexec"))
		.args(["--no-global-ignore", "--restart", "--print-events", "--debounce", "500ms", "--exts", "roc,rs,html,css,js,mjs,toml", "--", "roc", "--no-cache", "./build.roc", "--opt=${opt}", full_name].map(OsStr.from_str))

# Check that watchexec is installed
check_watchexec! = |probe|
	# Any exit status will do: the only thing this check is for is whether
	# watchexec is there at all, not whether it liked being asked.
	match probe.run!() {
		Ok(_) => Ok({})

		Err(err) =>
			fail!(
				Str.join_with(
					[
						"Could not run watchexec: ${Str.inspect(err)}",
						"",
						"The watch loop needs watchexec to rebuild on change. Please install it ",
						"using `brew install watchexec`, `cargo install watchexec-cli`, or see",
						"https://github.com/watchexec/watchexec, and make sure it is on your PATH.",
					],
					"\n",
				),
			)
		}

# Start the dev server, and confirm it is still alive before printing a URL and
# claiming it works. spawn_leashed! ties the server to this process, so it goes
# down with us.
start_server! = |port, opt, name| {
	server =
		match Cmd.new(OsStr.from_str("node")).args(["www/serve.mjs", port, opt, name].map(OsStr.from_str)).stdout(Capture).stderr(Capture).spawn_leashed!() {
			Ok(child) => child
			Err(err) =>
				fail!(
					Str.join_with(
						[
							"Could not run node: ${Str.inspect(err)}",
							"",
							"Joy's dev server is a node script. Install node (v22) and make sure",
							"it is on your PATH.",
						],
						"\n",
					),
				)?
			}

	Sleep.millis!(300)?

	match poll!(server) {
		Ok(Running) => Ok(server)

		Ok(Finished(exit)) => {
			said = Str.from_utf8_lossy(exit.stdout_bytes.concat(exit.stderr_bytes)).trim()
			code = match exit.status {
				Exited(c) => c.to_str()
				Signaled(signal) => "signal ${signal.to_str()}"
			}

			fail!(
				Str.join_with(
					[
						"The dev server exited straight away (code ${code}).",
						"",
						"Port ${port} is most likely already taken, often by an earlier",
						"./watch.roc whose dev server outlived the terminal it ran in. Stop that",
						"process, or pick another port:",
						"",
						"    JOY_WATCH_PORT=8001 ./watch.roc --opt=${opt} ${name}",
					],
					"\n",
				)
					.concat(if said.is_empty() "" else "\n\nnode said:\n${said}"),
			)
		}

		Err(problem) => fail!("Could not check on the dev server: ${Str.inspect(problem)}")
	}
}

parser : Cli.CliParser({ opt : Str, app_name : Str })
parser = Cli.assert_valid(
	Cli.finish(
		{
			opt: Args.opt_option_with_default("speed"),
			app_name: Param.str({
				name: "app",
				help: "The app to serve, e.g. counter or examples/counter.roc.",
				default: NoDefault,
			}),
		}.Cli,
		{
			name: "watch",
			version: "",
			authors: [],
			description: "Build the given app on every change and serve it.",
			text_style: Plain,
		},
	),
)

# WORKAROUND: roc-lang/roc#12692. A dev build frees a Child whose method a
# `match` with an early return called, which kills the child. Call
# `child.poll!()` directly when fixed.
poll! = |child| child.poll!()
