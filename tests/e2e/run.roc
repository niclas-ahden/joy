# roc-spec runner for the browser E2E tests: discovers tests/e2e/*_test.roc
# and runs each as a standalone app (each launches its own Chromium via
# roc-playwright). Invoked by e2e.roc, which builds the examples, serves the
# repo root and exports JOY_E2E_URL first.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stdout
import pf.Utc
import spec.Spec

hooks = {
	spawn_test!: |file, envs|
		Cmd.new(OsStr.utf8("roc"))
			.args_str(["--opt=speed", file])
			.envs_str(envs)
			.spawn_leashed!(),
	poll!: Cmd.Child.poll!,
	kill_wait!: Cmd.Child.kill_wait!,
	list_dir!: |dir| Path.list!(Path.utf8(dir)).map_ok(|entries| entries.map(Path.display)),
	print!: Stdout.line!,
	utc_now!: Utc.now!,
	sleep_millis!: Sleep.millis!,
}

main! = |_args| {
	results = Spec.run!(
		hooks,
		"tests/e2e",
		{
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
