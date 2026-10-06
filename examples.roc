#!/usr/bin/env roc
# Run:
#
#   ./examples.roc
#
# To run the own suite of every directory example that has one
# (examples/<name>/tests.roc), each from its own directory, the way someone
# who copied the example out would run it. A new example with a tests.roc is
# picked up without a change here. Every suite runs even when an earlier one
# fails, and the run fails if any of them did. Run from the repo root, inside
# the nix devShell (it provides playwright, its browsers and caddy).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
}

import pf.Cmd
import pf.Path
import pf.Stdout
import Util exposing [fail!]

main! = |_args| {
	suites = Path.utf8("examples").list!()?
		.map(Path.display)
		.map_try!(|entry| if Path.utf8(entry).is_dir!()? has_suite!(entry) else Ok([]))?
		.join()
	if suites.is_empty() {
		fail!("no examples/*/tests.roc found")?
	}

	failed = suites
		.map_try!(
			|dir| {
				Stdout.line!("== ${dir}")?
				code = Cmd.new_str("roc")
					.args_str(["./tests.roc"])
					.cwd(Path.utf8(dir))
					.exec_exit_code!()
					.ok_or(1)
				Ok(if code == 0 [] else [dir])
			},
		)?
		.join()

	if failed.is_empty() {
		Ok({})
	} else {
		fail!("these examples' suites failed: ${Str.join_with(failed, ", ")}")
	}
}

# The directory, in a list, when it has a suite of its own.
has_suite! = |dir| Path.utf8("${dir}/tests.roc").is_file!().map_ok(|exists| if exists [dir] else [])
