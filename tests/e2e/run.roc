# roc-spec runner for the browser E2E tests: discovers tests/e2e/*_test.roc
# and runs each as a standalone app (each launches its own Chromium via
# roc-playwright). Invoked by e2e.roc, which builds the examples, serves the
# repo root and exports E2E_URL first.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.0/BGjQKbG9U3V8cH6mRbypUAFVqFoVEu6n9bsA3QmFL1f4.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stdout
import pf.Utc
import spec.Spec

hooks = {
	new: Cmd.new,
	os_str: OsStr.from_str,
	# Leashed, so a test killed on timeout takes its browser with it.
	spawn!: Cmd.Command.spawn_leashed!,
	poll!: Cmd.Child.poll!,
	wait!: Cmd.Child.wait!,
	kill!: Cmd.Child.kill!,
	close!: Cmd.Child.close!,
	path: Path.utf8,
	# tests/e2e/ itself, plus each directory example's own tests/
	# (examples/spa-todomvc/tests/): a directory example keeps its browser tests
	# next to its app, and this runner spawns them all the same way.
	list!: |dir| {
		base = Path.list!(dir)?
		if Path.display(dir) == "tests/e2e" {
			per_example = Path.utf8("examples").list!()?
				.map_try!(|entry| Ok(Path.utf8("${Path.display(entry)}/tests").list!() ?? []))?
			Ok(base.concat(per_example.join()))
		} else {
			Ok(base)
		}
	},
	print!: Stdout.line!,
	now!: Utc.now!,
	sleep!: Sleep.millis!,
}

main! = |_args| {
	results = Spec.run!(
		hooks,
		"tests/e2e",
		{
			# WORKAROUND: roc-lang/roc#12693 and #12701. A shared roc cache can crash
			# the compile of each test. Drop `--no-cache` when fixed.
			test_command: ["roc", "--opt=speed", "--no-cache"],
			# Each test runs its own browser; two in flight keeps memory sane.
			max_workers: 2,
			worker_envs: |_index| [],
			before_each!: |_index| Ok({}),
			per_test_timeout_ms: 120_000,
			quiet: Bool.False,
			fail_fast: Bool.False,
		},
	)?

	passed = results.count_if(|r| r.passed)
	total = results.len()

	Stdout.line!("${passed.to_str()}/${total.to_str()} browser tests passed")?

	if total > 0 and passed == total {
		Ok({})
	} else {
		Err(BrowserTestsFailed)
	}
}
