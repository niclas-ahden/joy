# Test-suite runner (invoked by tests.roc from the example's folder): starts
# one caddy per worker serving the build in .joy/test/build/client, waits
# until they all answer, then runs every e2e/*_test.roc through roc-spec.
#
# Optional args: a filename pattern (substring) and --fail-fast.
# Optional env: ROC_SPEC_MAX_WORKERS (default 4).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.1/GXr8UJ7VDaJ8HYykmVYtTjLs7X4bZeE9YDTzAHoVXFJ9.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import http.Request
import pf.Cmd
import pf.Duration
import pf.Env
import pf.Http
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stderr
import pf.Stdout
import pf.Tcp
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

## The port of worker `index`. `ports` holds one per worker, so the lookup
## always finds it.
port_of : List(U64), U64 -> U64
port_of = |ports, index| ports.get(index) ?? 0

## Environment for each test process: its own server's URL.
worker_env : U64 -> List((Str, Str))
worker_env = |port| [
	("E2E_URL", "http://localhost:${port.to_str()}"),
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

## The first e2e/<name>_test.roc on disk. Every test file carries the same
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

## Start one static file server for the given worker index, on the files
## ./joy build wrote: what a static host would serve.
spawn_worker! : U16, U64 => Try(Cmd.Child, _)
spawn_worker! = |index, port| {
	Cmd.new(OsStr.from_str("caddy"))
		.args(["file-server", "--root", ".joy/test/build/client", "--listen", ":${port.to_str()}"].map(OsStr.from_str))
		.stdout(Null)
		.stderr(Null)
		.spawn_leashed!()
		.map_err(|e| ServerSpawnFailed(index, CaddyErr(e)))
}

## One readiness probe against a worker's server: any HTTP response means it
## is up
check_worker! : U64 => Bool
check_worker! = |port| {
	request = Request.from_method(GET).with_uri("http://localhost:${port.to_str()}")
	Http.send!(request, {}).is_ok()
}

main! : List(OsStr) => Try({}, _)
main! = |os_args| {
	args = os_args.map(|a| OsStr.display(a))
	{ pattern, fail_fast } = parse_args(args)
	workers = max_workers!({})
	# Each test server gets a port the operating system picks, so the suite
	# runs beside a dev server or anything else listening on this machine.
	ports = free_ports!(workers.to_u64())?

	warm_package_cache!("e2e")?

	Stdout.line!("Starting ${workers.to_str()} test servers...")?

	# Spawn all test servers first (spawn_leashed! so they die with the
	# runner), then poll them all until every one answers (up to ~30s).
	servers = TestEnvironment.start!(hooks, {
		count: workers,
		spawn!: |index| spawn_worker!(index, port_of(ports, index.to_u64())),
		ready!: |index| check_worker!(port_of(ports, index.to_u64())),
		max_attempts: 150,
		delay_ms: 200,
	})?

	Stdout.line!("All ${workers.to_str()} test servers ready")?

	results = Spec.run_filtered!(hooks, "e2e", {
		test_command: ["roc", "--opt=speed"],
		max_workers: workers,
		worker_envs: |index| worker_env(port_of(ports, index)),
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

## `count` ports that are free now. The operating system picks them, so the
## suite never collides with another server on this machine. Every probe
## stays open until all are picked, so no two ports are the same.
free_ports! : U64 => Try(List(U64), [NoFreePort(Str)])
free_ports! = |count| {
	var $probes = []
	var $ports = []
	while $ports.len() < count {
		probe = Tcp.listen!("127.0.0.1", 0, Duration.seconds(5)) ? |e| NoFreePort(Str.inspect(e))
		port = probe.local_port!() ? |e| NoFreePort(Str.inspect(e))
		$probes = $probes.append(probe)
		$ports = $ports.append(port.to_u64())
	}
	for probe in $probes {
		probe.close!() ? |e| NoFreePort(Str.inspect(e))
	}
	Ok($ports)
}
