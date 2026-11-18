#!/usr/bin/env roc
# Compare this checkout with an earlier version of Joy on js-framework-benchmark:
# a release tag, or any commit. Run from the repo root:
#
#   benchmarks/jsframework/compare.roc 0.34.0          # three runs, pooled
#   RUNS=1 benchmarks/jsframework/compare.roc 0.34.0   # one run, about half an hour
#
# The earlier version is unpacked into build/compare/<commit>/ and built there
# with its own compiler, the one its flake pins, so each side is what that
# version ships. Its two benchmark apps then stand in for the released entries
# of the js-framework-benchmark clone while run.roc measures, which is the
# comparison run.roc always makes: this checkout against a release, both in one
# session, the arms in reverse order every other round. The released entries
# are put back afterwards, also when a run fails.
#
# Every run is a row in the history like any other. On top of them this writes
# one report that pools the rounds of all the runs, under
# runs/<timestamp>_vs_<version>/, and prints its comparison.
#
# What a number means, how to keep the machine fair, and how to look into a
# difference with profile.mjs is in README.md here.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Env
import pf.Stderr
import pf.Stdout

here = "benchmarks/jsframework"

## Where the released entries wait while another build stands in for them.
keep = "build/compare/keep"

main! = |args| {
	ref =
		match args.map(OsStr.display) {
			[given, ..] if !given.starts_with("-") => given
			_ => return fail!("name the version to compare with, a tag or a commit: ${here}/compare.roc 0.34.0")
		}
	fork = Env.var_str!("JS_FRAMEWORK_BENCHMARK_DIR") ?? ""
	if fork.is_empty() {
		return fail!("JS_FRAMEWORK_BENCHMARK_DIR is not set. Point it at your js-framework-benchmark clone (see ${here}/README.md).")
	}
	runs =
		match U64.from_str(Env.var_str!("RUNS") ?? "3") {
			Ok(count) if count > 0 => count
			_ => return fail!("RUNS takes a number of runs, 1 or more")
		}
	commit =
		match capture_line!("git", ["rev-parse", "--short=10", "${ref}^{commit}"]) {
			Ok(found) => found
			Err(_) => return fail!("git knows no commit by the name ${ref}")
		}
	# render.mjs finds an entry's results by `<name>-v<version>-<bracket>`, so a
	# version has no dashes or underscores in it.
	version = sh_capture!("printf '%s' '${ref}' | tr -cd 'A-Za-z0-9.'") ?? commit
	tree = "build/compare/${commit}"

	# A run stops without the governor, and by then the entries would be swapped.
	check_governor!()?
	# Entries a comparison that was cut short left swapped go back first.
	restore!(fork)?

	Stdout.line!("== building ${ref} (${commit}) with its own compiler ==")?
	build_earlier!(ref, tree, fork)?

	started_server = !(sh_ok!("curl -sf -o /dev/null http://localhost:8080/ls"))
	before = sh_capture!("ls ${here}/runs 2>/dev/null | tr '\\n' ' '") ?? ""
	swap_in!(tree, fork, version)?

	var $done = 0
	var $failed = Bool.False
	while $done < runs and !$failed {
		Stdout.line!("")?
		Stdout.line!("== run ${($done + 1).to_str()} of ${runs.to_str()}: this checkout against ${ref} ==")?
		match run!("${here}/run.roc", []) {
			Ok({}) => {
				$done = $done + 1
			}
			Err(_) => {
				$failed = Bool.True
			}
		}
	}

	restore!(fork)?
	if started_server {
		stop_server!(fork)?
	}
	if $done == 0 {
		return fail!("no run finished, so there is nothing to compare")
	}

	stamp = capture_line!("date", ["+%Y-%m-%d_%H%M"])?
	label = capture_line!("date", ["+%Y-%m-%d %H:%M %Z"])?
	head = capture_line!("git", ["rev-parse", "--short", "HEAD"]) ?? "unknown"
	dirty = !(capture_line!("git", ["status", "--porcelain"]) ?? "").is_empty()
	out = "${here}/runs/${stamp}_vs_${version}"
	pool!({ fork, before, out, label, commit: if (dirty) "${head}-dirty" else head, subject: "This checkout against ${ref}, ${$done.to_str()} run(s) pooled" })?

	Stdout.line!("")?
	sh!("awk '/^## Dev vs released/,/^## Instruction counts/' '${out}/report.md' | sed '$d'")?
	Stdout.line!("The whole report: ${out}/report.md")?
	Stdout.line!("")?
	Stdout.line!("To see where a difference comes from, profile the two builds in the browser (see ${here}/README.md):")?
	Stdout.line!("  node ${here}/profile.mjs dev=${fork}/frameworks/keyed/joy-dev earlier=${tree}/entries/keyed")?
	if $failed {
		fail!("a run failed after ${$done.to_str()} finished, and the report pools those")
	} else {
		Ok({})
	}
}

# The earlier version's benchmark apps, built in its own tree by its own dev
# shell and prepared like the local entry: `wasm-opt -Oz` as run.roc runs it,
# and the runtime through uglify as build-local.sh does. They land in
# <tree>/entries/<bracket>/ with the local entry's page, which is all an entry
# is, so profile.mjs can serve them later.
build_earlier! = |ref, tree, fork|
	sh_lines!([
		"set -eo pipefail",
		"tree='${tree}'",
		"fork='${fork}'",
		"if [ ! -f \"$tree/src/platform/main.roc\" ]; then",
		"  mkdir -p \"$tree/src\"",
		"  git archive '${ref}' | tar -x -C \"$tree/src\"",
		"fi",
		"if [ ! -f \"$tree/src/tests/apps/jsbench_keyed.roc\" ]; then",
		"  echo 'error: ${ref} has no tests/apps/jsbench_keyed.roc, so it is from before the benchmark apps this compares.' >&2",
		"  exit 1",
		"fi",
		"if ! command -v nix >/dev/null; then",
		"  echo 'error: an earlier version is built with the compiler its flake pins, which takes nix.' >&2",
		"  exit 1",
		"fi",
		"for tool in wasm-opt npx; do",
		"  command -v $tool >/dev/null || { echo \"error: $tool not found. Run this from the dev shell (nix develop, or direnv allow).\" >&2; exit 1; }",
		"done",
		"src=$(cd \"$tree/src\" && pwd)",
		"# A build.roc takes its flags after `--` or without one, depending on the roc it was written for, and its own header says which.",
		"dashes=''",
		"if grep -q 'build.roc -- --opt' \"$src/build.roc\"; then dashes='--'; fi",
		"for bracket in keyed non-keyed; do",
		"  app=jsbench_keyed",
		"  if [ \"$bracket\" = non-keyed ]; then app=jsbench_nonkeyed; fi",
		"  (cd \"$src\" && nix develop \"path:$src\" -c ./build.roc $dashes --opt=size \"tests/apps/$app.roc\")",
		"  if [ ! -f \"$src/build/size/$app.wasm\" ]; then",
		"    echo \"error: the build of ${ref} produced no build/size/$app.wasm\" >&2",
		"    exit 1",
		"  fi",
		"  mkdir -p \"$tree/entries/$bracket/dist\"",
		"  entry=$(cd \"$tree/entries/$bracket\" && pwd)",
		"  cp \"$fork/frameworks/$bracket/joy-dev/index.html\" \"$entry/index.html\"",
		"  cp \"$src/build/size/$app.wasm\" \"$entry/dist/app.wasm\"",
		"  wasm-opt --enable-bulk-memory --enable-simd --enable-sign-ext --enable-mutable-globals --enable-nontrapping-float-to-int -Oz \"$entry/dist/app.wasm\" -o \"$entry/dist/app.wasm\"",
		"  (cd \"$fork/frameworks/$bracket/joy-dev\" && npx uglifyjs \"$src/www/runtime.js\" --compress --mangle --module -o \"$entry/dist/runtime.js\")",
		"done",
	])

# Put the earlier version's build where the released entries are, under its
# own version, and keep what was there. The mark says that it has to go back.
swap_in! = |tree, fork, version|
	sh_lines!([
		"set -eo pipefail",
		"for bracket in keyed non-keyed; do",
		"  entry='${fork}'/frameworks/$bracket/joy",
		"  mkdir -p '${keep}'/$bracket \"$entry/dist\"",
		"  cp \"$entry/package.json\" '${keep}'/$bracket/package.json",
		"  for file in app.wasm runtime.js; do",
		"    if [ -f \"$entry/dist/$file\" ]; then cp \"$entry/dist/$file\" '${keep}'/$bracket/$file; fi",
		"  done",
		"done",
		": > '${keep}'/swapped",
		"for bracket in keyed non-keyed; do",
		"  entry='${fork}'/frameworks/$bracket/joy",
		"  cp '${tree}'/entries/$bracket/dist/app.wasm '${tree}'/entries/$bracket/dist/runtime.js \"$entry/dist/\"",
		"  sed -i 's/\"frameworkVersion\": \"[^\"]*\"/\"frameworkVersion\": \"${version}\"/' \"$entry/package.json\"",
		"done",
	])

# Put the released entries back as swap_in! found them. Nothing to do when
# they are not swapped.
restore! = |fork|
	sh_lines!([
		"set -eo pipefail",
		"[ -f '${keep}'/swapped ] || exit 0",
		"for bracket in keyed non-keyed; do",
		"  entry='${fork}'/frameworks/$bracket/joy",
		"  cp '${keep}'/$bracket/package.json \"$entry/package.json\"",
		"  for file in app.wasm runtime.js; do",
		"    if [ -f '${keep}'/$bracket/$file ]; then cp '${keep}'/$bracket/$file \"$entry/dist/$file\"; fi",
		"  done",
		"done",
		"rm -f '${keep}'/swapped",
		"echo 'The released entries are back as they were.'",
	])

# run.roc starts the clone's benchmark server when none answers and leaves it
# running. The one this comparison started is stopped: the process that
# listens on its port, when its working directory is the clone's server.
stop_server! = |fork|
	sh_lines!([
		"command -v ss >/dev/null || exit 0",
		"pid=$(ss -ltnp 2>/dev/null | sed -n 's/.*:8080 .*pid=\\([0-9]*\\).*/\\1/p' | head -1)",
		"[ -n \"$pid\" ] || exit 0",
		"if [ \"$(readlink /proc/$pid/cwd 2>/dev/null)\" = \"$(cd '${fork}'/server && pwd -P)\" ]; then kill \"$pid\"; fi",
		"true",
	])

# One report over the rounds of every run this comparison made: the runs that
# are under runs/ now and were not there `before`. The pooled report is no run
# of its own, so it adds nothing to the history.
pool! = |{ fork, before, out, label, commit, subject }|
	sh_lines!([
		"set -eo pipefail",
		"n=0",
		"last=''",
		"for run in $(ls ${here}/runs); do",
		"  case ' ${before} ' in *\" $run \"*) continue ;; esac",
		"  # A pooled report of an earlier comparison is no run.",
		"  case \"$run\" in *_vs_*) continue ;; esac",
		"  [ -d \"${here}/runs/$run/rounds\" ] || continue",
		"  mkdir -p '${out}/rounds'",
		"  for round in \"${here}/runs/$run\"/rounds/*/; do",
		"    n=$((n + 1))",
		"    cp -r \"$round\" '${out}/rounds/'$n",
		"  done",
		"  last=$run",
		"done",
		"[ -n \"$last\" ] || { echo 'error: the runs left no rounds to pool' >&2; exit 1; }",
		"chromium=$(sed -n 's/^- \\*\\*Browser:\\*\\* chromium \\([^ ]*\\).*/\\1/p' \"${here}/runs/$last/report.md\" | head -1)",
		"roc=$(sed -n 's/^- \\*\\*Roc:\\*\\* //p' \"${here}/runs/$last/report.md\" | head -1)",
		"node ${here}/render.mjs --results '${fork}/webdriver-ts/results' --rounds '${out}/rounds' --icount \"${here}/runs/$last/icount\" --out '${out}' --label '${label}' --commit '${commit}' --subject '${subject}' --chromium \"$chromium\" --roc \"$roc\" --note \"$n rounds pooled\" --history no",
	])

# The same check as run.roc makes, made before anything is swapped.
check_governor! = ||
	sh_lines!([
		"govs=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u | tr '\\n' ' ')",
		"[ -n \"$govs\" ] || exit 0",
		"if [ \"$govs\" != 'performance ' ]; then",
		"  echo \"error: the CPU governor is $govs, not performance. Pin it for the runs:\" >&2",
		"  echo '  sudo cpupower frequency-set -g performance' >&2",
		"  echo 'and set it back afterwards.' >&2",
		"  exit 1",
		"fi",
	])

sh! = |script| run!("bash", ["-c", script])

sh_lines! = |lines| sh!(Str.join_with(lines, "\n"))

sh_capture! = |script| capture_line!("bash", ["-c", script])

## Whether a script exits 0, with nothing of it shown.
sh_ok! = |script|
	match Cmd.new(OsStr.from_str("bash")).args(["-c", script].map(OsStr.from_str)).run!() {
		Ok(output) => output.status == Exited(0)
		Err(_) => Bool.False
	}

# Run a command with inherited stdio, exiting with the child's code when it
# fails.
run! = |program, args| {
	match Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).inherit_stdio().run!() {
		Ok(output) =>
			match output.status {
				Exited(0) => Ok({})
				Exited(code) => Err(Exit(code))
				Signaled(_) => Err(Exit(1))
			}

		Err(_) => {
			Stderr.line!("error: could not run ${program}") ?? {}
			Err(Exit(1))
		}
	}
}

# A command's first line of output, trimmed.
capture_line! = |program, args| {
	match Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).run!() {
		Ok(output) if output.status == Exited(0) => {
			line = Str.from_utf8_lossy(output.stdout_bytes).split_on("\n").first() ?? ""
			Ok(line.trim())
		}
		_ => Err(CaptureFailed)
	}
}

# Report a message on stderr and exit non-zero.
fail! = |message| {
	Stderr.line!("error: ${message}") ?? {}
	Err(Exit(1))
}
