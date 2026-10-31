# Compile each browser test once, for tests/e2e/run.roc to run in every browser,
# and stop with roc's report when one does not compile. e2e.roc runs this first.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout
import Compiled

# A compile takes about 600 MB and 10 s, and nothing else runs meanwhile.
at_a_time = 6

main! = |_args| {
	folder = Compiled.folder!({})
	# Nothing from an earlier run may stand in for a test that no longer compiles.
	Path.utf8(folder).delete_all!() ?? {}
	Path.utf8(folder).create_all!()?
	per_example = Path.utf8("examples").list!()?
		.map_try!(|entry| Ok(Path.utf8("${Path.display(entry)}/tests").list!() ?? []))?
	tests = Path.utf8("tests/e2e").list!()?
		.concat(per_example.join())
		.map(Path.display)
		.keep_if(|file| file.ends_with("_test.roc"))
	sources = tests.append(Compiled.launcher_source)
	Stdout.line!("Compiling ${sources.len().to_str()} programs, ${at_a_time.to_str()} at a time")?
	var $failed = 0
	var $start = 0
	while $start < sources.len() {
		batch = sources.sublist({ start: $start, len: at_a_time })
		running = batch.map_try!(|source| spawn_compile!(source))?
		for (source, child) in running {
			output = child.wait!()?
			if output.status != Exited(0) {
				report = Str.from_utf8_lossy(output.stdout_bytes.concat(output.stderr_bytes))
				Stderr.line!("${source} does not compile:\n${report}")?
				$failed = $failed + 1
			}
		}
		$start = $start + at_a_time
	}
	if $failed == 0 {
		Ok({})
	} else {
		Err(Exit(1))
	}
}

# WORKAROUND: roc-lang/roc#12693 and #12701. A shared roc cache can crash the
# compile of each test. Drop `--no-cache` when fixed.
spawn_compile! = |source| {
	args = ["build", "--no-cache", "--opt=speed", "--output=${Compiled.binary!(source)}", source]
	child = Cmd.new(OsStr.from_str("roc")).args(args.map(OsStr.from_str)).stdout(Capture).stderr(Capture).spawn_leashed!()?
	Ok((source, child))
}
