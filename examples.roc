#!/usr/bin/env roc
# Run:
#
#   ./examples.roc
#   ./examples.roc --browser=all
#
# To run the own suite of every Joy project in the repo that has one: a
# directory example (examples/<name>/tests.roc) and a template ./joy init
# starts from (cli/templates/<name>/tests.roc), each from its own folder, the
# way someone working on it would run it. A project builds with ./joy, so
# each gets one first, built from this checkout's cli/main.roc. A new
# example or template with a tests.roc is picked up without a change here.
# Every suite runs even when an earlier one fails, and the run fails if any
# of them did. The browser tests run in Chromium, or in the engine
# `--browser` names (chromium, firefox, webkit, or all for each in turn),
# which every suite reads from JOY_BROWSER. Run from the repo root, inside the
# nix devShell (it provides playwright, its browsers and caddy).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Stdout
import Util exposing [fail!, run!]

# Where the projects are.
project_dirs = ["examples", "cli/templates"]

main! = |args| {
	asked = args.map(OsStr.display).find_first(|arg| arg.starts_with("--browser=")).map_ok(|arg| arg.drop_prefix("--browser=")) ?? "chromium"
	engines =
		match asked {
			"all" => ["chromium", "firefox", "webkit"]
			"chromium" | "firefox" | "webkit" => [asked]
			other => fail!("unknown --browser ${other}, expected chromium, firefox, webkit or all")?
		}
	suites = project_dirs
		.map_try!(|dir| Path.utf8(dir).list!())?
		.join()
		.map(Path.display)
		.map_try!(|entry| if Path.utf8(entry).is_dir!()? has_suite!(entry) else Ok([]))?
		.join()
	if suites.is_empty() {
		fail!("no tests.roc found in a folder of ${Str.join_with(project_dirs, " or ")}")?
	}

	runs = engines.map(|engine| suites.map(|dir| (dir, engine))).join()
	failed = runs
		.map_try!(
			|(dir, engine)| {
				Stdout.line!("== ${dir} in ${engine}")?
				# Built for each, as `roc build` takes under a second at --opt=dev.
				run!("roc", ["build", "--opt=dev", "--output=${dir}/joy", "cli/main.roc"])?
				ran = Cmd.new(OsStr.from_str("roc"))
					.args([OsStr.from_str("./tests.roc")])
					.env(OsStr.from_str("JOY_BROWSER"), OsStr.from_str(engine))
					.cwd(Path.utf8(dir))
					.inherit_stdio()
					.run!()
				passed =
					match ran {
						Ok(output) => output.status == Exited(0)
						Err(_) => Bool.False
					}
				Ok(if passed [] else ["${dir} in ${engine}"])
			},
		)?
		.join()

	if failed.is_empty() {
		Ok({})
	} else {
		fail!("these suites failed: ${Str.join_with(failed, ", ")}")
	}
}

# The directory, in a list, when it has a suite of its own.
has_suite! = |dir| Path.utf8("${dir}/tests.roc").is_file!().map_ok(|exists| if exists [dir] else [])
