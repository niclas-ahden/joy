# roc-spec runner for the browser E2E tests: discovers tests/e2e/*_test.roc
# and runs each as a standalone app (each launches its own browser via
# roc-playwright). Invoked by e2e.roc, which builds the examples, compiles the
# tests (see compile.roc), serves the repo root and exports E2E_URL first.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.1/GXr8UJ7VDaJ8HYykmVYtTjLs7X4bZeE9YDTzAHoVXFJ9.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stdout
import pf.Utc
import spec.Spec
import Compiled

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
	list!: Path.list!,
	print!: Stdout.line!,
	now!: Utc.now!,
	sleep!: Sleep.millis!,
}

main! = |_args| {
	results = Spec.run!(
		hooks,
		"tests/e2e",
		{
			test_command: [Compiled.binary!(Compiled.launcher_source)],
			# Each test runs its own browser, on a port and in a folder of its own.
			max_workers: 6,
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
