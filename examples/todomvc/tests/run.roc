# Test-suite runner (invoked by ./tests.roc from the repo root): starts one
# caddy per worker serving www/, waits until they all answer, then runs every
# tests/*_test.roc through roc-spec.
#
# Optional args: a filename pattern (substring) and --fail-fast.
# Optional env: ROC_SPEC_MAX_WORKERS (default 4).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.1/55UFmX5Ye5dNxWYzbzxQfsE54KTNwaoHNmYan163HbzB.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.Http
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stderr
import pf.Stdout
import pf.Url
import pf.Utc
import spec.Spec
import spec.TestEnvironment

effects = {
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
	list_dir!: |dir| Path.list!(Path.utf8(dir)).map_ok(|entries| entries.map(Path.display)),
	print!: Stdout.line!,
	utc_now!: Utc.now!,
	sleep_millis!: Sleep.millis!,
}

# ./watch.roc serves on 8000, so the test servers start above it and a dev
# server can keep running while the suite does. The server hooks below take
# U16 worker indexes and worker_envs takes U64, so the base appears once per
# width.
base_port : U16
base_port = 9000

## Environment for each test process: its own server's URL, in the same
## variable Joy's own e2e runner sets, so these tests run unchanged under
## either runner.
worker_envs : U64 -> List((Str, Str))
worker_envs = |index| [
	("JOY_E2E_URL", "http://localhost:${(9000 + index).to_str()}"),
]

max_workers! : {} => U16
max_workers! = |{}|
	match Env.var_str!("ROC_SPEC_MAX_WORKERS") {
		Ok(val) => U16.from_str(val).ok_or(4)
		Err(_) => 4
	}

## Parse command line args into pattern and flags
parse_args : List(Str) -> { pattern : Str, fail_fast : Bool }
parse_args = |args| {
	pattern = args.keep_if(|a| !a.starts_with("--")).first().ok_or("")
	fail_fast = args.contains("--fail-fast")
	{ pattern, fail_fast }
}

## The first tests/<name>_test.roc on disk. Every test file carries the same
## dependency header, so whichever one comes back stands in for all of them.
first_test_file! : Str => Try(Str, [NoTestFiles])
first_test_file! = |test_dir| {
	entries = Path.list!(Path.utf8(test_dir)) ? |_| NoTestFiles
	entries
		.map(Path.display)
		.keep_if(|name| name.ends_with("_test.roc"))
		.first()
		.map_err(|_| NoTestFiles)
}

## Download and extract every package the tests depend on, in one process,
## before any worker starts.
##
## The compiler does not lock the package cache: the first `roc` to want a
## missing package creates its cache directory and starts extracting into it,
## while every other `roc` sees that directory, takes it for a finished
## download, and dies with "PACKAGE DOWNLOAD FAILED ... FileNotFound". On a
## cold cache that wipes out every test that loses the race.
warm_package_cache! : Str => Try({}, _)
warm_package_cache! = |test_dir|
	match first_test_file!(test_dir) {
		Err(_) => Ok({})
		Ok(file) => {
			Stdout.line!("Warming the package cache...")?
			# Whatever this reports about the file itself is the test run's
			# business, so the output and the exit code are both dropped here.
			_ = Cmd.new(OsStr.utf8("roc")).args_str(["check", file]).exec_output!()
			Ok({})
		}
	}

## Start one static file server for the given worker index. The same
## Caddyfile that ./watch.roc uses, so the tests serve www/ exactly like
## the dev server does.
spawn_worker! : U16 => Try(Cmd.Child, _)
spawn_worker! = |index| {
	port = base_port + index
	cmd =
		Cmd.new_str("caddy")
			.args_str(["run", "--config", "Caddyfile", "--adapter", "caddyfile"])
			.env_str("JOY_WATCH_PORT", port.to_str())
			.stdout(Null)
			.stderr(Null)
	Cmd.spawn_leashed!(cmd).map_err(|e| ServerSpawnFailed(index, CaddyErr(e)))
}

## One readiness probe against a worker's server: any HTTP response means it
## is up
check_worker! : U16 => Bool
check_worker! = |port|
	match Url.parse("http://localhost:${port.to_str()}") {
		Err(_) => Bool.False
		Ok(u) => Http.get_utf8!(u).is_ok()
	}

main! : List(OsStr) => Try({}, _)
main! = |os_args| {
	args = os_args.map(|a| OsStr.display(a))
	{ pattern, fail_fast } = parse_args(args)
	workers = max_workers!({})

	warm_package_cache!("tests")?

	Stdout.line!("Starting ${workers.to_str()} test servers...")?

	# Spawn all test servers first (spawn_leashed! so they die with the
	# runner), then poll them all until every one answers (up to ~30s).
	servers = TestEnvironment.start!({ sleep!: Sleep.millis! }, {
		count: workers,
		spawn!: spawn_worker!,
		ready!: |index| check_worker!(base_port + index),
		max_attempts: 150,
		delay_ms: 200,
	})?

	Stdout.line!("All ${workers.to_str()} test servers ready")?

	results = Spec.run_filtered!(effects, "tests", {
		max_workers: workers,
		worker_envs,
		before_each!: |_index| Ok({}),
		per_test_timeout_ms: 120_000,
		quiet: Bool.True,
		fail_fast,
	}, pattern)?

	# Holding the handles until here kept the servers up for the run. A child
	# is terminated when its last reference is released, so close them only
	# now that the run is over.
	for server in servers {
		_ = Cmd.Child.close!(server)
	}

	passed = results.count_if(|r| r.passed)
	total = results.len()

	Stdout.line!("")?
	Stdout.line!("${passed.to_str()}/${total.to_str()} tests passed")?

	# A pattern that matches nothing is a failure: a typo'd filter must not
	# produce a green "0/0 passed" run.
	if total == 0 {
		Stderr.line!("No tests matched the pattern '${pattern}'")?
		Err(NoTestsMatched)
	} else if passed == total {
		Ok({})
	} else {
		Err(TestsFailed)
	}
}
