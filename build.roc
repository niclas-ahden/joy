#!/usr/bin/env roc
# Run:
#
#   ./build.roc -- --opt=speed                       every app, what tests.roc and CI want
#   ./build.roc -- --opt=speed examples/counter.roc  just that one, what watch.roc wants
#
# To build the Rust host and link each app into `build/<opt>/<name>.wasm`.
# Run from the repo root.
#
# Flags need roc's `--` separator in front of them. Without it roc claims
# --opt and --help for itself instead of passing them on. Plain arguments,
# like the app name above, need no separator.
#
# `--opt` mirrors roc's own flag and is passed straight to `roc build`. It is
# required, there is no default: every caller says which level it wants, and
# each level builds into its own tree, `build/<opt>/<name>.wasm`, so a dev
# pass and a speed pass can never hand each other stale output.
#
# Set the environment variable `RUSTC` to pick another rustc, `SMALL_BUFFERS`
# to shrink the host's outbound buffers to a few words so every render
# exercises their growth path, and `JOY_BENCH` to compile in the host's phase
# instrumentation (see tests/bench/).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.7.0/9PiT7ffE9m8BJyVv3LwE4rWWdcbpxEMUADMpiLBfY8jJ.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.Path
import pf.Stderr
import weaver.Cli
import weaver.Param
import Args
import Util exposing [example_name, fail!, run!]

main! = |args| {
	config = Args.parse!(parser, args, "--opt=speed examples/counter.roc")?
	opt = Args.check_opt!(config.opt)?

	Path.utf8("platform/targets/wasm32").create_all!()?
	Path.utf8("build/${opt}").create_all!()?

	build_host!()?

	# One app when named, every app otherwise. watch.roc names one: rebuilding
	# two dozen modules for an edit that touches a single app costs seconds on
	# every save. tests.roc and CI name none and get all.
	sources = match config.app_name {
		Ok(name) => [find_source!(example_name(name))?]
		Err(NoValue) => list_sources!()?
	}

	# roc can exit 0 without writing anything, so drop each module up front and
	# check that it came back in build_example!. A stale wasm must never reach
	# the tests, or the page watch.roc serves. Only the sources are dropped, so
	# working on one example leaves an earlier full build intact.
	_ = sources.map_try!(
		|src| {
			out = Path.utf8(wasm_path(src, opt))
			if out.is_file!()? {
				out.delete!()
			} else {
				Ok({})
			}
		},
	)?

	_ = sources.map_try!(|src| build_example!(src, opt))?

	Ok({})
}

# Apps live in two directories, both built the same way into
# build/<opt>/<name>.wasm: examples/ holds the user-facing ones the README
# points at,
# tests/apps/ the fixtures the harnesses in tests/ drive. Those fixtures assert
# on internals (which nodes the diff reused, how many listeners are bound,
# render cost as a grid grows) instead of demonstrating anything, so they are
# not examples. Names must stay unique across both, since the output is flat.
app_dirs = ["examples", "tests/apps"]

# The named app, in whichever directory holds it. `counter`,
# `examples/counter.roc` and `tests/apps/vdom.roc` all work: the argument's
# directory is dropped and only the name is looked up, so watch.roc can pass
# whatever the user typed.
find_source! = |name| {
	found = app_dirs
		.map(|dir| Path.utf8("${dir}/${name}.roc"))
		.map_try!(|path| path.is_file!().map_ok(|exists| { path, exists }))?
		.keep_if(|candidate| candidate.exists)

	match found.first() {
		Ok(candidate) => Ok(candidate.path)
		Err(_) => fail!("no such app: ${name}.roc (looked in ${Str.join_with(app_dirs, ", ")})")
	}
}

# Every app in every source directory.
list_sources! = ||
	app_dirs
		.map_try!(
			|dir|
				Path.utf8(dir).list!()
					.map_ok(|entries| entries.keep_if(|entry| Path.display(entry).ends_with(".roc"))),
		)
		.map_ok(|per_dir| per_dir.join())

# build/<opt>/<name>.wasm for examples/<name>.roc or tests/apps/<name>.roc.
wasm_path : Path.Path, Str -> Str
wasm_path = |src, opt| "build/${opt}/${example_name(Path.display(src))}.wasm"

# The Rust host becomes one relocatable wasm object (staticlib crate-type plus
# --emit obj). no_std and panic=abort keep it import-free. It defines the six
# roc_* runtime symbols and the compiler-rt intrinsics Roc's builtins call (see
# host.rs), and leaves roc_init/roc_update/roc_render to the compiled app.
#
# host.rs derives its offsets and strides from host/roc_platform_abi.rs, whose
# layout asserts turn ABI drift into a compile error. That file is committed
# and hand-maintained: `roc glue` overflows its stack on this platform, so
# there is nothing to regenerate it with.
build_host! = || {
	small_buffers = if (Env.var_str!("SMALL_BUFFERS") ?? "").is_empty() {
		[]
	} else {
		["--cfg", "small_buffers"]
	}
	joy_bench = if (Env.var_str!("JOY_BENCH") ?? "").is_empty() {
		[]
	} else {
		["--cfg", "joy_bench"]
	}
	run!(
		Env.var_str!("RUSTC") ?? "rustc",
		["--edition", "2021", "--target", "wasm32-unknown-unknown", "--crate-type", "staticlib"]
			.concat(["-C", "opt-level=2", "-C", "panic=abort", "--emit", "obj"])
			.concat(small_buffers)
			.concat(joy_bench)
			.concat(["host/host.rs", "-o", "platform/targets/wasm32/host.wasm"]),
	)
}

# roc exits 2 when it emits warnings but 0 even when it reports errors, so the
# summary line decides, not the exit code. One warning is expected:
# examples/logging.roc keeps a `dbg` on purpose to demonstrate the console.debug
# stream, and `dbg` in an optimized build warns by design. Any other warning, an
# error, or a module that never got written fails the build.
#
# The expected warning is recognised by its title, matched with the case folded
# away: roc titled its diagnostics in capitals until 2026-08, and a compiler
# from either side of that change must build this repo.
build_example! = |path, opt| {
	src = Path.display(path)
	out = wasm_path(path, opt)

	# The linker defaults to 64 MB of initial linear memory, which every page
	# then carries as its memory floor before the first render (the host heap
	# grows on demand past the initial region, so the default is pure waste).
	# 4 MB initial fits the data segments plus the 2 MB stack. The allocator
	# grows memory as the app actually needs it. The stack is not
	# overflow-protected on wasm (no --stack-first), so if a build ever
	# corrupts memory on deeply nested views, raise the stack first.
	output = capture!(
		Cmd.new_str("roc")
			.args_str(["build", "--opt=${opt}", "--target=wasm32", "--wasm-memory=4194304", "--wasm-stack-size=2097152", "--no-cache", "--output=${out}", src]),
	)?
	lines = output.split_on("\n")
	clean = match lines.keep_oks(summary_counts).last() {
		Ok(counts) =>
			counts.errors == 0
				and counts.warnings
					== lines.count_if(|line| line.with_ascii_lowercased().contains("in optimized build"))

		Err(_) => Bool.False
	}

	if clean and Path.utf8(out).is_file!()? {
		Ok({})
	} else {
		Stderr.line!(output)?
		fail!("roc build failed for ${src}")
	}
}

parser : Cli.CliParser({ opt : Str, app_name : Try(Str, [NoValue]) })
parser = Cli.assert_valid(
	Cli.finish(
		{
			opt: Args.opt_option,
			app_name: Param.maybe_str({
				name: "app",
				help: "Build only this app, e.g. counter or examples/counter.roc. Builds every app when omitted.",
			}),
		}.Cli,
		{
			name: "build",
			version: "",
			authors: [],
			description: "Build the Rust host and link each Joy app into build/<opt>/<name>.wasm.",
			text_style: Plain,
		},
	),
)

# Read the counts out of a line like "0 errors and 1 warning found in 704ms".
# Lines that are not a summary fail to parse and are skipped by the caller.
summary_counts = |line| {
	at_error = line.split_first(" error")?
	at_and = at_error.after.split_first(" and ")?
	at_warning = at_and.after.split_first(" warning")?
	errors = U64.from_str(at_error.before.trim()).map_err(|_| NotFound)?
	warnings = U64.from_str(at_warning.before.trim()).map_err(|_| NotFound)?
	Ok({ errors, warnings })
}

# roc spreads its diagnostics across stdout and stderr, and a run that reports
# errors can exit 0, so gather both streams whatever the exit code was.
capture! = |cmd| {
	match cmd.exec_output_bytes!() {
		Ok(streams) => Ok(Str.from_utf8_lossy(streams.stdout_bytes.concat(streams.stderr_bytes)))
		Err(NonZeroExitCodeB(streams)) =>
			Ok(Str.from_utf8_lossy(streams.stdout_bytes.concat(streams.stderr_bytes)))

		Err(FailedToGetExitCodeB(_)) => fail!("could not run ${Cmd.to_str(cmd)}")
	}
}
