# Test-suite runner (invoked by ./tests.roc from the repo root): starts one
# caddy per worker serving www/, waits until they all answer, then runs every
# tests/*_test.roc through roc-spec.
#
# Optional args: a filename pattern (substring) and --fail-fast.
# Optional env: ROC_SPEC_MAX_WORKERS (default 4).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.0/BGjQKbG9U3V8cH6mRbypUAFVqFoVEu6n9bsA3QmFL1f4.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import http.Request
import pf.Cmd
import pf.Env
import pf.Http
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stderr
import pf.Stdout
import pf.Utc
import spec.Spec
import spec.TestEnvironment

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
	("E2E_URL", "http://localhost:${(9000 + index).to_str()}"),
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
			_ = Cmd.new(OsStr.from_str("roc")).args(["check", file].map(OsStr.from_str)).run!()
			Ok({})
		}
	}

## Start one static file server for the given worker index. The same
## Caddyfile that ./watch.roc uses, so the tests serve www/ exactly like
## the dev server does.
spawn_worker! : U16 => Try(Cmd.Child, _)
spawn_worker! = |index| {
	port = base_port + index
	Cmd.new(OsStr.from_str("caddy"))
		.args(["run", "--config", "Caddyfile", "--adapter", "caddyfile"].map(OsStr.from_str))
		.env(OsStr.from_str("JOY_WATCH_PORT"), OsStr.from_str(port.to_str()))
		.stdout(Null)
		.stderr(Null)
		.spawn_leashed!()
		.map_err(|e| ServerSpawnFailed(index, CaddyErr(e)))
}

## One readiness probe against a worker's server: any HTTP response means it
## is up
check_worker! : U16 => Bool
check_worker! = |port| {
	request = Request.from_method(GET).with_uri("http://localhost:${port.to_str()}")
	Http.send!(request, {}).is_ok()
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
	servers = TestEnvironment.start!(hooks, {
		count: workers,
		spawn!: spawn_worker!,
		ready!: |index| check_worker!(base_port + index),
		max_attempts: 150,
		delay_ms: 200,
	})?

	Stdout.line!("All ${workers.to_str()} test servers ready")?

	results = Spec.run_filtered!(hooks, "tests", {
		# WORKAROUND: roc-lang/roc#12693 and #12701. A shared roc cache can crash
		# the compile of each test. Drop `--no-cache` when fixed.
		test_command: ["roc", "--opt=speed", "--no-cache"],
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
