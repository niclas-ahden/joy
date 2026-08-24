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
# `examples/counter.roc`, `tests/apps/vdom.roc` and `examples/todomvc` all
# work: the argument's directory is dropped and only the name is looked up,
# so watch.roc can pass whatever the user typed. A flat app is
# <dir>/<name>.roc, a directory app is <dir>/<name>/app.roc.
find_source! = |name| {
	found = app_dirs
		.map(|dir| [Path.utf8("${dir}/${name}.roc"), Path.utf8("${dir}/${name}/app.roc")])
		.join()
		.map_try!(|path| path.is_file!().map_ok(|exists| { path, exists }))?
		.keep_if(|candidate| candidate.exists)

	match found.first() {
		Ok(candidate) => Ok(candidate.path)
		Err(_) => fail!("no such app: ${name}.roc or ${name}/app.roc (looked in ${Str.join_with(app_dirs, ", ")})")
	}
}

# Every app in every source directory. A flat app is one <dir>/<name>.roc
# file; an app that brings a page, styles or tests of its own is a directory,
# <dir>/<name>/, built from its app.roc (see examples/todomvc/).
list_sources! = ||
	app_dirs
		.map_try!(|dir| sources_in!(dir))
		.map_ok(|per_dir| per_dir.join())

sources_in! = |dir| {
	entries = Path.utf8(dir).list!()?
	entries
		.map_try!(
			|entry| {
				display = Path.display(entry)
				if display.ends_with(".roc") {
					Ok([entry])
				} else {
					nested = Path.utf8("${display}/app.roc")
					nested.is_file!().map_ok(|exists| if exists [nested] else [])
				}
			},
		)
		.map_ok(|per_entry| per_entry.join())
}

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

	## Memory size
	# `--wasm-memory=0` makes both `wasm-ld` and Roc's built-in linker
	# automatically determine the necessary memory size. That'll roughly be the
	# data section of the app (constants etc. from the user's app) plus the
	# stack size. Since the data section is app-dependent we don't want to
	# have to specify a fixed memory size.
	#
	## Stack size
	# We are using a fixed stack size of 1 MiB, which by testing corresponds to
	# roughly 10 000 levels of HTML nesting. Ergo, it _should_ not overflow, but
	# if we learn we're wrong we can always increase it or make it user-definable.
	#
	# We can't use `--stack-first`, because Roc does not currently expose that to
	# us, which means that if we overflow the stack we'll be corrupting the app's
	# static data section.
	#
	# To manage that danger we have two countermeasures:
	#
	# a) A canary memory band at the stack floor. The host scans it after every
	#    dispatch and fails loudly if any word was overwritten. Nothing fires at
	#    write time, so detection waits for the dispatch boundary, and a single
	#    frame larger than the band can step over it unseen.
	#
	# b) A stack pointer check in `roc_alloc` which traps as soon as the pointer
	#    is below the floor. Every allocation goes through the host allocator, also
	#    the ones Roc code makes, and render recursion allocates on nearly every
	#    level, so this fires mid-dispatch and catches frames of any size. Its
	#    blind spot is recursion that never allocates, which is covered by a).
	#
	# Both checks need the hardcoded stack size kept in
	# sync in two spots: the `--wasm-stack-size` flag here and `STACK_SIZE` in
	# host/host.rs.
	#
	# The engine's native call stack is a separate limit that backstops both.
	#
	# These checks _should_ give us loud errors on every stack overflow. They
	# would also make `wasm-opt`'s `--low-memory-unused` optimization safe,
	# should we ever run wasm-opt (nothing does today). We should probably
	# switch to `--stack-first` if that becomes available in the future.
	output = capture!(
		Cmd.new_str("roc")
			.args_str(["build", "--opt=${opt}", "--target=wasm32", "--wasm-memory=0", "--wasm-stack-size=1048576", "--no-cache", "--output=${out}", src]),
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
