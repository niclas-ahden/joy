#!/usr/bin/env -S sh -c 'exec roc "$0" -- "$@"'
# Run:
#
#   ./tests.roc --opt=speed
#   ./tests.roc --opt=dev
#
# To build everything at that optimization level (see build.roc) and run the
# node harness checks against it. `--opt` is required and is handed explicitly
# to build.roc and, as JOY_OPT, to the harnesses, so every stage of one run
# agrees on the build/<opt>/ tree. Run from the repo root.
#
# The shebang trampolines through sh to place roc's `--` separator between
# the script and its args. Without it roc claims --opt and --help for itself
# instead of passing them through.
#
# Environment variables pass straight through to build.roc, so
# `SMALL_BUFFERS=1 ./tests.roc --opt=speed` runs the whole suite with tiny
# initial outbound buffers, exercising the buffer growth path on every render.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.7.0/9PiT7ffE9m8BJyVv3LwE4rWWdcbpxEMUADMpiLBfY8jJ.tar.zst",
}

import pf.Path
import pf.Stdout
import weaver.Cli
import Args
import Util exposing [run!, run_env!]

main! = |args| {
	opt = Args.check_opt!(Args.parse!(parser, args)?)?

	# Roc-level unit tests: top-level `expect`s in the platform modules (pure
	# code: the Cmd/Sub/Attribute/Html `map` plumbing, WebCrypto.to_hex, ...).
	# `roc test` on main.roc runs the expects of every module it imports.
	Stdout.line!("== roc test platform/main.roc")?
	run!("roc", ["test", "platform/main.roc"])?

	Stdout.line!("== building and testing with --opt=${opt}")?
	run!("./build.roc", ["--opt=${opt}"])?

	# node:test runs each harness in its own child process (concurrently) and
	# keeps going past a failing file, so one broken harness can't hide the
	# rest.
	harnesses = Path.utf8("tests").list!()?
		.keep_if(|entry| is_harness(Path.display(Path.filename(entry).ok_or(entry))))
		.map(Path.display)
	run_env!("node", ["--test"].concat(harnesses), "JOY_OPT", opt)?

	Ok({})
}

is_harness = |name| name.starts_with("check_") and name.ends_with(".mjs")

parser : Cli.CliParser(Str)
parser = Cli.assert_valid(
	Cli.finish(
		Args.opt_option,
		{
			name: "tests",
			version: "",
			authors: [],
			description: "Build every app at the given optimization level and run the node harness checks against it.",
			text_style: Plain,
		},
	),
)
