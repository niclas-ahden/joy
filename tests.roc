#!/usr/bin/env roc
# Run:
#
#   ./tests.roc              at --opt=dev, the quick one for while you work
#   ./tests.roc --opt=speed  what an app ships with, which CI runs as well
#
# To build everything at that optimization level (see build.roc) and run the
# node harness checks against it. The level is handed explicitly to build.roc
# and, as JOY_OPT, to the harnesses, so every stage of one run agrees on the
# build/<opt>/ tree. Run from the repo root.
#
# Flags need roc's `--` separator in front of them. Without it roc claims
# --opt and --help for itself instead of passing them on.
#
# Environment variables pass straight through to build.roc, so
# `SMALL_BUFFERS=1 ./tests.roc --opt=speed` runs the whole suite with tiny
# initial outbound buffers, exercising the buffer growth path on every render.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.10.2/7CdYzjBAJmprmnK45oTpmH6BXt76ZASN2Ck5uZQEoWsK.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Stdout
import pf.System
import weaver.Cli
import Args
import Util exposing [run!, run_env!]

main! = |args| {
	opt = Args.check_opt!(Args.parse!(parser, args, "--opt=dev")?)?

	# Roc-level unit tests: top-level `expect`s in the platform modules (pure
	# code: the Cmd/Sub/Attribute/Html `map` plumbing, WebCrypto.to_hex, ...).
	# `roc test` on main.roc runs the expects of every module it imports.
	Stdout.line!("== roc test platform/main.roc")?
	run!("roc", ["test", "platform/main.roc"])?

	# ./joy has no Windows host yet.
	match System.target!().os() {
		Windows(_) => {}
		_ => {
			Stdout.line!("== roc test cli/main.roc")?
			run!("roc", ["test", "cli/main.roc"])?
		}
	}

	# The guide's Roc samples live in these apps (see tests/check_guide.mjs), and its
	# links are read from the page it builds.
	Stdout.line!("== roc check guide/samples")?
	samples = sample_apps!("guide/samples")?
	_ = samples.map_try!(|file| run!("roc", ["check", file]))?
	Stdout.line!("== building the guide")?
	built = Cmd.new(OsStr.from_str("roc")).args(["./build.roc"].map(OsStr.from_str)).cwd(Path.utf8("guide")).inherit_stdio().run!()?
	Util.exit_of(built.status)?

	Stdout.line!("== building and testing with --opt=${opt}")?
	run!("roc", ["./build.roc", "--opt=${opt}"])?

	# The hot reload harnesses (tests/check_hot*.mjs) reload between builds of
	# one app, which need hot reload compiled in, so those are built again
	# with JOY_HOT, and so is TodoMVC, for the differential harness.
	run_env!("roc", ["./build.roc", "--opt=${opt}", Str.join_with(hot_apps, ",")], "JOY_HOT", "1")?

	# node:test runs each harness in its own child process (concurrently) and
	# keeps going past a failing file, so one broken harness can't hide the
	# rest.
	harnesses = Path.utf8("tests").list!()?
		.keep_if(|entry| is_harness(Path.display(Path.filename(entry).ok_or(entry))))
		.map(Path.display)
	run_env!("node", ["--test"].concat(harnesses), "JOY_OPT", opt)?

	Ok({})
}

## Each app below `dir`, whose modules checking it checks too.
sample_apps! : Str => Try(List(Str), _)
sample_apps! = |dir| {
	entries = Path.utf8(dir).list!()?
	entries.fold_try!(
		[],
		|found, entry| {
			if entry.is_dir!()? {
				Ok(found.concat(sample_apps!(Path.display(entry))?))
			} else if Path.display(entry).ends_with(".roc") and entry.read_utf8!()?.starts_with("app [") {
				Ok(found.append(Path.display(entry)))
			} else {
				Ok(found)
			}
		},
	)
}

hot_apps = [
	"hot_v1",
	"hot_v2",
	"hot_v3",
	"hot_v4",
	"hot_fn_v1",
	"hot_fn_v2",
	"hot_fx_v1",
	"hot_fx_v2",
	"hot_view_v1",
	"hot_view_v2",
	"hot_src_v1",
	"hot_src_v2",
	"hot_handle",
	"many_apps",
	"hot_init_crash",
	"hot_page_v1",
	"hot_page_v2",
	"hot_page_v3",
	"rows",
	"port_answer",
	"hot_told_v1",
	"hot_told_v2",
	"jsbench_keyed",
	"spa-todomvc",
]

is_harness = |name| name.starts_with("check_") and name.ends_with(".mjs")

parser : Cli.CliParser(Str)
parser = Cli.assert_valid(
	Cli.finish(
		Args.opt_option_with_default("dev"),
		{
			name: "tests",
			version: "",
			authors: [],
			description: "Build every app at the given optimization level and run the node harness checks against it.",
			text_style: Plain,
		},
	),
)
