#!/usr/bin/env roc
# Run:
#
#   ./watch.roc examples/counter.roc               at --opt=speed, the default
#   ./watch.roc -- --opt=dev examples/counter.roc  at another level
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
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.7.0/9PiT7ffE9m8BJyVv3LwE4rWWdcbpxEMUADMpiLBfY8jJ.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.IOErr
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

	check_watchexec!(Cmd.new_str("watchexec").arg_str("--version"))?

	server = start_server!(port, opt, name)?

	Stdout.line!("=> Serving '${full_name}' (--opt=${opt}) at http://localhost:${port}")?

	# check_watchexec! has already ruled out the usual failure, a missing
	# binary, so an error here is something rarer and worth naming.
	exit_code = match watchexec_cmd(opt, full_name).exec_exit_code!() {
		Ok(code) => code
		Err(FailedToGetExitCode(problem)) => fail!("watchexec: ${IOErr.to_str(problem.err)}")?
	}

	server.kill!() ?? {}

	if exit_code == 0 {
		Ok({})
	} else {
		Err(Exit(exit_code))
	}
}

# The rebuild loop: watchexec reruns build.roc whenever a source file changes.
watchexec_cmd = |opt, full_name|
	Cmd.new_str("watchexec")
		.args_str(["--no-global-ignore", "--restart", "--print-events", "--debounce", "500ms", "--exts", "roc,rs,html,css,js,mjs,toml", "--", "./build.roc", "--", "--opt=${opt}", full_name])

# Check that watchexec is installed
check_watchexec! = |probe|
	match probe.exec_output_bytes!() {
		Ok(_) => Ok({})

		# It is installed, it just did not like being asked. Good enough, the
		# only thing this check is for is whether it is there at all.
		Err(NonZeroExitCodeB(_)) => Ok({})

		Err(FailedToGetExitCodeB(err)) =>
			fail!(
				Str.join_with(
					[
						"Could not run watchexec: ${IOErr.to_str(err)}",
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
		match Cmd.new_str("node").args_str(["www/serve.mjs", port, opt, name]).spawn_leashed!() {
			Ok(child) => child
			Err(SpawnFailed(err)) =>
				fail!(
					Str.join_with(
						[
							"Could not run node: ${IOErr.to_str(err)}",
							"",
							"Joy's dev server is a node script. Install node (v22) and make sure",
							"it is on your PATH.",
						],
						"\n",
					),
				)?
			}

	Sleep.millis!(300)

	match server.poll!() {
		Ok(Running) => Ok(server)

		Ok(Exited(exit)) => {
			said = Str.from_utf8_lossy(exit.stdout.concat(exit.stderr)).trim()

			fail!(
				Str.join_with(
					[
						"The dev server exited straight away (code ${exit.exit_code.to_str()}).",
						"",
						"Port ${port} is most likely already taken, often by an earlier",
						"./watch.roc whose dev server outlived the terminal it ran in. Stop that",
						"process, or pick another port:",
						"",
						"    JOY_WATCH_PORT=8001 ./watch.roc -- --opt=${opt} ${name}",
					],
					"\n",
				)
					.concat(if said.is_empty() "" else "\n\nnode said:\n${said}"),
			)
		}

		Err(PollFailed(err)) => fail!("Could not check on the dev server: ${IOErr.to_str(err)}")
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
