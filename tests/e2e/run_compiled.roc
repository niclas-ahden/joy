# What roc-spec runs for each browser test: it hands over the test's Roc file, and
# this runs the binary tests/e2e/compile.roc made of it. The test is leashed to
# this, so roc-spec killing this on a timeout takes the test and its browser too.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Stderr
import Compiled

main! = |args| {
	source =
		match args.map(OsStr.display) {
			[given, ..] => given
			[] => ""
		}
	binary = Compiled.binary!(source)
	match Cmd.new(OsStr.from_str(binary)).inherit_stdio().spawn_leashed!() {
		Ok(child) =>
			match child.wait!()?.status {
				Exited(0) => Ok({})
				Exited(code) => Err(Exit(code))
				Signaled(_) => Err(Exit(1))
			}

		Err(err) => {
			Stderr.line!("Could not run ${binary}, the compiled form of ${source}: ${Str.inspect(err)}. tests/e2e/compile.roc only compiles the files directly in tests/e2e and in each example's tests/.")?
			Err(Exit(1))
		}
	}
}
