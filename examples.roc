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
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
}

import pf.Cmd
import pf.OsStr
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
				ran = Cmd.new(OsStr.from_str("roc"))
					.args([OsStr.from_str("./tests.roc")])
					.cwd(Path.utf8(dir))
					.inherit_stdio()
					.run!()
				passed =
					match ran {
						Ok(output) => output.status == Exited(0)
						Err(_) => Bool.False
					}
				Ok(if passed [] else [dir])
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
