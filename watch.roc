#!/usr/bin/env -S sh -c 'exec roc "$0" -- "$@"'
# Run:
#
#   ./watch.roc --opt=speed examples/counter.roc
#
# To build the given example at that optimization level (the shebang
# trampolines through sh so roc passes --opt through instead of claiming it)
# and serve it at http://localhost:8000. You can then edit the example and
# it'll rebuild automatically. Refresh the page to see your changes. Run from
# the repo root.
#
# Set the environment variable `JOY_WATCH_PORT` to change the port (default 8000).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.7.0/9PiT7ffE9m8BJyVv3LwE4rWWdcbpxEMUADMpiLBfY8jJ.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.Stdout
import weaver.Cli
import weaver.Param
import Args
import Util exposing [example_name]

main! = |args| {
	port = Env.var_str!("JOY_WATCH_PORT") ?? "8000"

	config = Args.parse!(parser, args)?
	opt = Args.check_opt!(config.opt)?
	full_name = config.app_name
	name = example_name(full_name)

	server =
		Cmd.new_str("node")
			.args_str(["www/serve.mjs", port, opt, name])
			.spawn!()?

	Stdout.line!("=> Serving '${full_name}' (--opt=${opt}) at http://localhost:${port}")?

	watchexec =
		Cmd.new_str("watchexec")
			.args_str(["--no-global-ignore", "--restart", "--print-events", "--debounce", "500ms", "--exts", "roc,rs,html,css,js,mjs,toml", "--", "./build.roc", "--opt=${opt}", full_name])
			.exec_exit_code!()
			.ok_or(1)

	server.kill!() ?? {}

	if watchexec == 0 {
		Ok({})
	} else {
		Err(Exit(watchexec))
	}
}

parser : Cli.CliParser({ opt : Str, app_name : Str })
parser = Cli.assert_valid(
	Cli.finish(
		{
			opt: Args.opt_option,
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
