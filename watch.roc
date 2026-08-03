#!/usr/bin/env roc
# Run:
#
#   ./watch.roc examples/counter.roc
#
# To serve the given example at http://localhost:8000. You can then edit
# the example and it'll rebuild automatically. Refresh the page to see
# your changes. Run from the repo root.
#
# Set the environment variable `JOY_WATCH_PORT` to change the port (default 8000).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Stdout
import Util exposing [example_name]

main! = |args| {
	port = Env.var_str!("JOY_WATCH_PORT") ?? "8000"

	arg = args.get(1) ? MissingExampleName
	full_name = OsStr.display(arg)
	name = example_name(full_name)

	server =
		Cmd.new_str("node")
			.args_str(["www/serve.mjs", port, name])
			.spawn_grouped!()?

	Stdout.line!("=> Serving '${full_name}' at http://localhost:${port}")?

	watchexec =
		Cmd.new_str("watchexec")
			.args_str(["--no-global-ignore", "--restart", "--print-events", "--debounce", "500ms", "--exts", "roc,rs,html,css,js,mjs,toml", "--", "./build.roc", full_name])
			.exec_exit_code!()
			.ok_or(1)

	server.kill!() ?? {}

	if watchexec == 0 {
		Ok({})
	} else {
		Err(Exit(watchexec))
	}
}
