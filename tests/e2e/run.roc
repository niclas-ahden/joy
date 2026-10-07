# roc-spec runner for the browser E2E tests: discovers tests/e2e/*_test.roc
# and runs each as a standalone app (each launches its own Chromium via
# roc-playwright). Invoked by e2e.roc, which builds the examples, serves the
# repo root and exports JOY_E2E_URL first.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.1/55UFmX5Ye5dNxWYzbzxQfsE54KTNwaoHNmYan163HbzB.tar.zst",
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
		# WORKAROUND: roc-lang/roc#11442. With a warm module cache,
		# `--opt=speed` builds fail to link with `undefined symbol:
		# roc__static_const_N`. Drop `--no-cache` when fixed.
		Cmd.new(OsStr.utf8("roc"))
			.args_str(["--opt=speed", "--no-cache", file])
			.envs_str(envs)
			.stdout(Capture)
			.stderr(Capture)
			.spawn_leashed!(),
	try_wait!: Cmd.Child.try_wait!,
	kill!: Cmd.Child.kill!,
	wait!: Cmd.Child.wait!,
	# tests/e2e/ itself, plus each directory example's own tests/
	# (examples/todomvc/tests/): a directory example keeps its browser tests
	# next to its app, and this runner spawns them all the same way.
	list_dir!: |dir| {
		base = Path.utf8(dir).list!()?.map(Path.display)
		per_example = Path.utf8("examples").list!()?
			.map_try!(|entry| Ok((Path.utf8("${Path.display(entry)}/tests").list!() ?? []).map(Path.display)))?
		Ok(base.concat(per_example.join()))
	},
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
