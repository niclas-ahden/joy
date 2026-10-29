#!/usr/bin/env roc
# Run the js-framework-benchmark suite for Joy (keyed + non-keyed) and the
# comparison frameworks, write a dated snapshot under runs/<timestamp>/, and
# append to history.jsonl / HISTORY.md.
#
# This is how we track Joy's cross-framework performance over time: make a
# change in this repo, then run this to see the new numbers next to the
# previous runs. Every run is the same procedure, so two runs differ only in
# the code and the machine: the CPU governor must be `performance` or the run
# stops, the suite runs twice with the arms in reverse order the second time,
# and the report pools both rounds and says which deltas are bigger than the
# noise. Next to the timings it counts each Joy arm's wasm instructions and
# DOM calls per benchmark, which do not move with machine noise at all. Run
# from the repo root:
#
#   benchmarks/jsframework/run.roc          # Joy only (reuses cached competitor results)
#   FULL=1 benchmarks/jsframework/run.roc   # also re-run Elm, Halogen, Leptos, Solid, React, vanilla
#   FAST=1 benchmarks/jsframework/run.roc   # Joy only, quick subset (create/swap/remove)
#   FRAMEWORKS="keyed/joy keyed/elm" benchmarks/jsframework/run.roc   # an explicit set
#
# JS_FRAMEWORK_BENCHMARK_DIR must point at a clone of js-framework-benchmark. See
# README.md here for the one-time setup. A standard setup needs node/npm on PATH
# and nothing else. On NixOS the clone carries a local flake dev shell
# (clone-setup/ here), and this script detects its .envrc and wraps the
# benchmark work in `direnv exec`.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Env
import pf.Sleep
import pf.Stderr
import pf.Stdout

here = "benchmarks/jsframework"

main! = |_args| {
	fork = Env.var_str!("JS_FRAMEWORK_BENCHMARK_DIR") ?? ""
	_ = if fork.is_empty() {
		fail!("JS_FRAMEWORK_BENCHMARK_DIR is not set. Point it at your js-framework-benchmark clone (see ${here}/README.md).")?
	} else {
		{}
	}

	check_governor!()?

	full = !(Env.var_str!("FULL") ?? "").is_empty()
	fast = !(Env.var_str!("FAST") ?? "").is_empty()

	# The clone only has an .envrc when it uses the NixOS dev shell from
	# clone-setup/. A standard setup has node and the Playwright chromium on
	# PATH already and needs no wrapping.
	use_direnv = match Cmd.new(OsStr.from_str("bash")).args(["-c", "test -f '${fork}/.envrc' && command -v direnv >/dev/null"].map(OsStr.from_str)).run!() {
		Ok(output) => output.status == Exited(0)
		Err(_) => Bool.False
	}
	in_fork = if use_direnv { "direnv exec ." } else { "" }

	# By default only Joy is re-benchmarked: the comparison frameworks don't
	# change between Joy edits, and their result JSONs from the last FULL run
	# stay in webdriver-ts/results/, which render.mjs reuses. The report is
	# still a full comparison table, just ~6x faster to produce. FRAMEWORKS
	# names an explicit set instead, for re-measuring one control next to Joy.
	frameworks = Env.var_str!("FRAMEWORKS") ?? (
		if full {
			"keyed/joy-dev non-keyed/joy-dev keyed/joy non-keyed/joy keyed/elm non-keyed/elm non-keyed/halogen keyed/leptos keyed/solid keyed/react-hooks non-keyed/vanillajs"
		} else {
			"keyed/joy-dev non-keyed/joy-dev keyed/joy non-keyed/joy"
		}
	)

	# 07_create10k is not in the main list. It gets its own unbatched pass in
	# run_round!, see there for why.
	benches = if fast {
		"01_ 05_ 06_"
	} else {
		"01_ 02_ 03_ 04_ 05_ 06_ 08_ 09_ 21_ 22_ 25_ 40_"
	}

	stamp = capture_line!("date", ["+%Y-%m-%d_%H%M"])?
	label = capture_line!("date", ["+%Y-%m-%d %H:%M %Z"])?
	head = capture_line!("git", ["rev-parse", "--short", "HEAD"]) ?? "unknown"
	# A run off uncommitted work is not reproducible from its commit, and the
	# history reads as a changelog keyed on that commit, so say when the tree
	# was dirty instead of quietly attributing the numbers to HEAD.
	dirty = !(capture_line!("git", ["status", "--porcelain"]) ?? "").is_empty()
	commit = if dirty { "${head}-dirty" } else { head }
	subject = capture_line!("git", ["log", "-1", "--format=%s"]) ?? ""
	# The compiler is the confounder a size delta is most often hiding: a
	# nightly bump moved the bundle 25% on 2026-08-25 with the source
	# unchanged. `roc --version` alone says "release-fast-no-git" for a
	# nix-built compiler, so name the store path too, which pins the rev.
	roc_ver = sh_capture!(
		"v=$(roc --version 2>/dev/null | head -1 | sed 's/^Roc compiler version //'); p=$(command -v roc 2>/dev/null); case \"$p\" in /nix/store/*) n=$(printf '%s' \"$p\" | cut -d/ -f4 | sed 's/^[a-z0-9]*-//');; *) n=;; esac; if [ -n \"$n\" ]; then echo \"$v ($n)\"; else echo \"$v\"; fi",
	) ?? "unknown"
	note = if full {
		""
	} else {
		"Re-measured this run: ${frameworks}. The other frameworks are reused from the last full run (FULL=1 to refresh them)."
	}
	out = "${here}/runs/${stamp}"

	# joy-dev is this checkout; joy is the published release, measured beside it
	# in the same session so a Joy-vs-Joy delta carries no machine drift. Label
	# the dev results with the commit that built them. No dashes or underscores:
	# render.mjs finds the entries by matching `<name>-v<version>-<bracket>`.
	entry_version = if dirty { "${head}.dirty" } else { head }
	set_entry_version!(fork, entry_version)?

	Stdout.line!("== rebuilding the Joy entries ==")?
	# Each build.sh rebuilds its bracket's app from this checkout and copies
	# it into that entry's dist/.
	sh!("joy_root=$PWD; cd '${fork}/frameworks/keyed/joy-dev' && JOY_ROOT=$joy_root ./build-local.sh")?
	sh!("joy_root=$PWD; cd '${fork}/frameworks/non-keyed/joy-dev' && JOY_ROOT=$joy_root ./build-local.sh")?

	Stdout.line!("== optimizing the entry wasm ==")?
	optimize_wasm!("${fork}/frameworks/keyed/joy-dev/dist/app.wasm")?
	optimize_wasm!("${fork}/frameworks/non-keyed/joy-dev/dist/app.wasm")?

	Stdout.line!("== counting instructions ==")?
	count_instructions!(fork, frameworks, "${out}/icount")?

	Stdout.line!("== ensuring the benchmark server ==")?
	sh_lines!([
		"if ! curl -sf -o /dev/null http://localhost:8080/ls; then",
		"  ( cd '${fork}' && ${in_fork} bash -c 'nohup npm start >/tmp/jsfb-server.log 2>&1 &' )",
		"  for _ in $(seq 1 50); do curl -sf -o /dev/null http://localhost:8080/ls && break; sleep 0.2; done",
		"fi",
		"curl -sf -o /dev/null http://localhost:8080/ls || { echo 'server did not come up (see /tmp/jsfb-server.log)' >&2; exit 1; }",
	])?

	Stdout.line!("== running benchmarks: ${benches} ==")?
	# Two rounds, the second walking the arms in reverse, pooled into one
	# median per arm. One round in a fixed order is not enough to read a few
	# percent off: on 2026-10-18 keyed replace 1k came out 5% slower in one
	# round and 4% faster in the next, with the same two binaries. Each round's
	# results are kept under rounds/<n>/, where render.mjs pools them and reads
	# the round to round spread for its noise band.
	arms = frameworks.split_on(" ")
	for round in ["1", "2"] {
		order = if round == "1" { arms } else { arms.fold([], |acc, arm| acc.prepend(arm)) }
		run_round!(fork, in_fork, order, benches, fast, "${out}/rounds/${round}")?
	}

	Stdout.line!("== rendering report ==")?
	# The browser lives under $PLAYWRIGHT_BROWSERS_PATH in the nix shell and in
	# Playwright's default cache otherwise. Take the first root that has one, in
	# the order bench! picks the binary: globbing every root into a single `ls`
	# sorts the paths together, so a stale $HOME cache outranks the shell's
	# chromium and the report names a browser the run never used.
	chromium_ver = sh_capture!("cd '${fork}' && ${in_fork} bash -c 'for root in \"$PLAYWRIGHT_BROWSERS_PATH\" \"$HOME/.cache/ms-playwright\" \"$HOME/Library/Caches/ms-playwright\"; do [ -n \"$root\" ] || continue; found=$(ls -d \"$root\"/chromium-* 2>/dev/null | head -1); if [ -n \"$found\" ]; then basename \"$found\"; exit 0; fi; done; echo unknown'") ?? "unknown"
	run!(
		"node",
		[
			"${here}/render.mjs",
			"--results",
			"${fork}/webdriver-ts/results",
			"--rounds",
			"${out}/rounds",
			"--icount",
			"${out}/icount",
			"--out",
			out,
			"--label",
			label,
			"--commit",
			commit,
			"--subject",
			subject,
			"--chromium",
			chromium_ver.drop_prefix("chromium-"),
			"--roc",
			roc_ver,
			"--note",
			note,
		],
	)?

	# Keep a copy of the raw result JSONs alongside the report for full
	# reproducibility.
	sh!("mkdir -p '${out}/results' && cp '${fork}'/webdriver-ts/results/*.json '${out}/results/' 2>/dev/null || true")?

	Stdout.line!("")?
	Stdout.line!("Snapshot written to ${out}/report.md")?
	Stdout.line!("History: ${here}/HISTORY.md")
}

# Deadline for one (framework, benchmark) pair, polled once a second. The
# longest healthy pair is a couple of minutes, so five is a real hang.
pair_deadline_polls = 300

# Run one (framework, benchmark) pair on its own runner invocation, headed
# (the benchmark's default, for timing accuracy: windows will flash on your
# display, which is expected). The nix shell sets $PLAYWRIGHT_BROWSERS_PATH
# and its chromium is passed with --chromeBinary. Without it the runner finds
# its own npm-downloaded chromium.
#
# The invocation is leashed, so a pair that hangs is killed as a whole
# process tree instead of stalling the run until someone notices. The leash
# is a process group and cannot reach the browser itself: puppeteer launches
# chromium detached into its own session, precisely so signals to the runner
# miss it. Killing a hung pair therefore orphans its browser on purpose, and
# barrier! sweeps it before the next pair launches.
#
# A pair that fails or times out is tolerated, not fatal: its result file is
# missing and the retry pass re-runs it.
run_pair! = |fork, in_fork, framework, bench, extra| {
	Stdout.line!("-- ${framework} ${bench}")?
	script = Str.join_with(
		[
			"cd '${fork}' && ${in_fork} bash -c '",
			"  set -eo pipefail",
			"  chrome_arg=",
			"  if [ -n \"$PLAYWRIGHT_BROWSERS_PATH\" ]; then",
			"    chrome_arg=\"--chromeBinary $(ls -d \"$PLAYWRIGHT_BROWSERS_PATH\"/chromium-*/chrome-linux64/chrome | head -1)\"",
			"  fi",
			"  cd webdriver-ts && npm run bench -- --framework ${framework} --benchmark ${bench} ${extra} $chrome_arg",
			"'",
		],
		"\n",
	)
	child = match Cmd.new(OsStr.from_str("bash")).args(["-c", script].map(OsStr.from_str)).stdout(Capture).stderr(Capture).spawn_leashed!() {
		Ok(c) => c
		Err(err) => fail!("could not start the benchmark runner: ${Str.inspect(err)}")?
	}
	report_pair!(framework, bench, wait_pair!(child, pair_deadline_polls))?
	barrier!(fork, in_fork)
}

# Poll once a second until the runner exits, and kill the whole leashed tree
# when the deadline passes. SIGKILL skips puppeteer's exit handlers, so a
# timed out pair reliably leaves its browser behind for barrier! to sweep.
wait_pair! = |child, polls_left| {
	match poll!(child) {
		Ok(Finished(exit)) => Finished(exit)
		Err(_) => Lost
		Ok(Running) => {
			if polls_left == 0 {
				_ = child.kill!()
				match child.wait!() {
					Ok(exit) => TimedOut(exit)
					Err(_) => Lost
				}
			} else {
				_ = Sleep.millis!(1000)
				wait_pair!(child, polls_left - 1)
			}
		}
	}
}

# Say how a pair ended. The pair's stdio is captured, so the runner's
# output lands here when the pair finishes rather than streaming live.
report_pair! = |framework, bench, outcome|
	match outcome {
		Finished(exit) => {
			print_output!(exit)
			if exit.status == Exited(0) {
				Ok({})
			} else {
				Stdout.line!("(runner exited with ${Str.inspect(exit.status)} on ${framework} ${bench}, the retry pass re-runs whatever is missing)")
			}
		}
		TimedOut(exit) => {
			print_output!(exit)
			Stdout.line!("(${framework} ${bench} hit the five minute deadline, killed its process tree, the retry pass re-runs it)")
		}
		Lost => Stdout.line!("(lost the runner process for ${framework} ${bench}, the retry pass re-runs whatever is missing)")
	}

print_output! = |exit| {
	out = Str.from_utf8_lossy(exit.stdout_bytes).trim()
	_ = if out.is_empty() { {} } else { Stdout.line!(out) ?? {} }
	err = Str.from_utf8_lossy(exit.stderr_bytes).trim()
	if err.is_empty() { {} } else { Stderr.line!(err) ?? {} }
}

# Hold until the pair's chromium is actually gone before the next pair
# launches. On a healthy pair the browser is already dead when the runner
# exits and this is one second of settle. When a browser outlives its runner
# (a killed tree cannot run puppeteer's cleanup) this waits up to ten seconds
# for it to unwind, then reaps it by force.
#
# The match is scoped to the browser this run uses, never a bare process
# name, so a desktop chromium survives it. With no $PLAYWRIGHT_BROWSERS_PATH
# the runner uses puppeteer's own download, matched by its temp profile dir.
# The [e] keeps that pattern from matching this script's own cmdline.
barrier! = |fork, in_fork|
	sh_lines!([
		"cd '${fork}' && ${in_fork} bash -c '",
		"  pat=",
		"  if [ -n \"$PLAYWRIGHT_BROWSERS_PATH\" ]; then",
		"    pat=$(ls -d \"$PLAYWRIGHT_BROWSERS_PATH\"/chromium-*/chrome-linux64/chrome 2>/dev/null | head -1)",
		"  fi",
		"  [ -n \"$pat\" ] || pat=puppeteer_dev_chrome_profil[e]",
		"  waited=0",
		"  while pgrep -f \"$pat\" >/dev/null; do",
		"    if [ \"$waited\" -ge 100 ]; then",
		"      echo \"-- chromium outlived its runner by 10s, reaping it\"",
		"      pkill -9 -f \"$pat\"",
		"      sleep 1",
		"      break",
		"    fi",
		"    sleep 0.1",
		"    waited=$((waited+1))",
		"  done",
		"  sleep 1",
		"'",
	])

# Samples of create 10k each round takes. See run_round!.
create10k_samples = ["1", "2", "3"]

# One round of the suite over the arms in the given order. The round starts
# from an empty slate for those arms, so a result left over from an earlier
# run or round cannot pass for one this round measured, and ends by copying
# what it measured into `dest`. The copies stay in webdriver-ts/results/ as
# well, where the next run that leaves a framework out reuses them.
run_round! = |fork, in_fork, arms, benches, fast, dest| {
	frameworks = Str.join_with(arms, " ")
	Stdout.line!("== round ${dest}: ${frameworks} ==")?
	with_results!(fork, frameworks, "", "rm -f")?
	# One runner invocation per (framework, benchmark) pair, walked in the
	# runner's own order: benchmark outer, framework inner. The runner has no
	# barrier between one pair's browser dying and the next one launching, so
	# a failed pair can leave renderer and GPU processes that the next pair
	# launches into (seen as a hang on the pair after a failed one). Driving
	# the pairs from here keeps the interleaving that makes the joy-dev vs joy
	# comparison drift-free, both arms hit each benchmark seconds apart, while
	# every pair starts against a clean process table. Costs one node startup
	# per pair, a few minutes on a full run.
	for bench in benches.split_on(" ") {
		for framework in arms {
			run_pair!(fork, in_fork, framework, bench, "")?
		}
	}
	retry_missing!(fork, in_fork, frameworks, benches)?
	stash_results!(fork, frameworks, "", dest)?

	if fast {
		Ok({})
	} else {
		# 07_create10k is not in the main list: batched runs bleed warmup
		# mousedowns into the trace and the runner rejects every sample after
		# the first. --count 1 is the only count a stock clone survives here.
		# Anything higher makes the runner batch every iteration into one
		# browser session, where it stops resetting the trace after the second
		# one, so a single trace ends up holding two clicks and the run dies on
		# "at most one mousedown event is expected" with no result at all.
		# One invocation is therefore one sample, and some frameworks are
		# bimodal on this benchmark, so it gets several invocations a round,
		# each kept in its own directory for render.mjs to pool.
		Stdout.line!("== create10k unbatched (batching bleeds traces) ==")?
		for sample in create10k_samples {
			with_results!(fork, frameworks, "07_", "rm -f")?
			for framework in arms {
				run_pair!(fork, in_fork, framework, "07_", "--count 1")?
			}
			retry_missing!(fork, in_fork, frameworks, "07_")?
			stash_results!(fork, frameworks, "07_", "${dest}/07-${sample}")?
		}
		Ok({})
	}
}

# Re-run any (framework, benchmark) pair that produced no result file.
#
# One bad trace costs a whole benchmark, not one sample: the runner puts all 15
# iterations of a batchable benchmark in a single forked browser, and on error
# it breaks out of the loop and returns nothing, so the good iterations are
# discarded with the bad one and writeResults gets an empty array ("Cannot
# compute stats on empty array"). It has a `retries` counter that it never uses.
# The hole then renders as a "-" in a table that otherwise looks complete.
#
# A stray failure is rare but not rare enough to ignore across four Joy arms and
# eleven benchmarks. One retry is enough: the failures seen so far do not
# reproduce, and a pair that fails twice is a real problem worth stopping for
# rather than papering over.
#
# Detection stays in bash, where the result names are globbed. The retries go
# through run_pair!, so a retried pair gets the same leash, deadline and
# barrier as a first attempt.
retry_missing! = |fork, in_fork, frameworks, benches| {
	missing = (list_missing!(fork, frameworks, benches) ?? "").trim()
	if missing.is_empty() {
		Ok({})
	} else {
		Stdout.line!("== retrying pairs that produced no result: ${missing} ==")?
		for pair in missing.split_on(" ") {
			match pair.split_first(":") {
				Ok(split) => {
					extra = if split.after == "07_" { "--count 1" } else { "" }
					run_pair!(fork, in_fork, split.before, split.after, extra)?
				}
				Err(NotFound) => {}
			}
		}
		Ok({})
	}
}

# Emit "entry:bench" for every pair whose result JSON is missing. "keyed" is a
# suffix of "non-keyed", so the keyed glob has to exclude the other. vanillajs
# has no version, hence the second pattern.
list_missing! = |fork, frameworks, benches|
	sh_capture!(
		Str.join_with(
			[
				"cd '${fork}/webdriver-ts/results' 2>/dev/null || exit 0",
				"missing=",
				"for entry in ${frameworks}; do",
				"  name=$(basename \"$entry\"); bracket=$(dirname \"$entry\")",
				"  for b in ${benches}; do",
				# 40_sizes writes its results as 41_, 42_ and 43_.
				"    r=$b; [ \"$b\" = 40_ ] && r=41_",
				"    if [ \"$bracket\" = keyed ]; then",
				"      hits=$(ls \"$name\"-v*-keyed_\"$r\"*.json 2>/dev/null | grep -vc -- \"-non-keyed_\")",
				"    else",
				"      hits=$(ls \"$name\"-v*-non-keyed_\"$r\"*.json \"$name\"-non-keyed_\"$r\"*.json 2>/dev/null | wc -l)",
				"    fi",
				"    if [ \"$hits\" -eq 0 ]; then missing=\"$missing $entry:$b\"; fi",
				"  done",
				"done",
				"echo $missing",
			],
			"\n",
		),
	)

# Hand the result files of the given entries to `command`, every benchmark's
# or, with `bench` set, that one's. A result is named
# <name>-v<version>-<bracket>_<bench>.json, and "keyed" is a suffix of
# "non-keyed", so the keyed glob has to exclude the other. vanillajs has no
# version, hence the second pattern.
with_results! = |fork, frameworks, bench, command|
	sh_lines!([
		"cd '${fork}/webdriver-ts/results' 2>/dev/null || exit 0",
		"for entry in ${frameworks}; do",
		"  name=$(basename \"$entry\"); bracket=$(dirname \"$entry\")",
		"  if [ \"$bracket\" = keyed ]; then",
		"    ls \"$name\"-v*-keyed_${bench}*.json 2>/dev/null | grep -v -- '-non-keyed_'",
		"  else",
		"    ls \"$name\"-v*-non-keyed_${bench}*.json \"$name\"-non-keyed_${bench}*.json 2>/dev/null",
		"  fi",
		"done | xargs -r ${command}",
	])

# Copy what a round measured into the run's directory.
stash_results! = |fork, frameworks, bench, dest| {
	sh!("mkdir -p '${dest}'")?
	abs = sh_capture!("cd '${dest}' && pwd")?
	with_results!(fork, frameworks, bench, "cp -t '${abs}'")
}

# Refuse to time anything unless every core runs the `performance` governor.
# Under a governor that scales the clock with load, a timing says as much
# about how busy the machine was a moment earlier as about the code. A
# machine with no cpufreq interface (a VM, or not Linux) has no governor to
# pin, and is let through.
check_governor! = ||
	sh_lines!([
		"govs=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u | tr '\\n' ' ')",
		"[ -n \"$govs\" ] || exit 0",
		"if [ \"$govs\" != 'performance ' ]; then",
		"  echo \"error: the CPU governor is $govs, not performance. Pin it for the run:\" >&2",
		"  echo '  sudo cpupower frequency-set -g performance' >&2",
		"  echo 'and set it back afterwards.' >&2",
		"  exit 1",
		"fi",
	])

# Count what each benchmark's measured click costs each Joy arm, exactly:
# wasm instructions, bytes moved by memory.copy and memory.fill, and DOM calls
# (see icount.mjs). No browser is involved, so this takes seconds, and the
# counts are the same on every run and every machine. Missing cargo fails the
# run like missing wasm-opt does, so every report carries the table.
count_instructions! = |fork, frameworks, dest|
	sh_lines!([
		"set -e",
		"cargo build --quiet --release --locked --manifest-path benchmarks/icount/Cargo.toml",
		"mkdir -p '${dest}'",
		"for entry in ${frameworks}; do",
		"  name=$(basename \"$entry\"); bracket=$(dirname \"$entry\")",
		"  case \"$name\" in joy|joy-dev) ;; *) continue ;; esac",
		"  dist='${fork}'/frameworks/$entry/dist",
		"  wasm='${dest}'/$name-$bracket.wasm",
		"  benchmarks/icount/target/release/icount \"$dist/app.wasm\" \"$wasm\"",
		"  node --no-warnings ${here}/icount.mjs \"$dist/runtime.js\" \"$wasm\" > '${dest}'/$name-$bracket.json",
		"  rm \"$wasm\"",
		"done",
	])

# Name the joy-dev results after the commit that built them, so a snapshot read
# months later says which binary produced it. Only joy-dev is touched: the
# published `joy` entry keeps the release version it ships, and joy-dev is
# local-only (excluded in the clone's .git/info/exclude), so the value is left
# in place rather than restored.
set_entry_version! = |fork, version|
	sh_lines!([
		"for bracket in keyed non-keyed; do",
		"  p='${fork}'/frameworks/$bracket/joy-dev/package.json",
		"  sed -i 's/\"frameworkVersion\": \"[^\"]*\"/\"frameworkVersion\": \"${version}\"/' \"$p\"",
		"done",
		"true",
	])

# Shrink an entry's wasm the way the other entries ship minified production
# builds, so the size column compares like with like. Every other framework
# here is measured through its own optimizer. The entries are built at
# `--opt=size` (build-local.sh), which already does most of the shrinking,
# and `-Oz` takes off about 0.5% more without costing any speed.
#
# The features are listed one by one so a newer Binaryen cannot fold a later
# proposal into the output. `--low-memory-unused` is left out even though it
# shrinks the output by about 1%. It assumes nothing lives below address 1024,
# and with the stack linked first that is the deepest part of the stack.
#
# Missing binaryen is fatal rather than a warning. Skipping would silently
# publish a number measured on a different binary from the last run's, and a
# size column is only worth having if every row was built the same way.
optimize_wasm! = |wasm|
	sh_lines!([
		"if ! command -v wasm-opt >/dev/null; then",
		"  echo 'error: wasm-opt not found. It comes from binaryen, which the dev shell provides, so run this from nix develop (or direnv allow).' >&2",
		"  exit 1",
		"fi",
		"wasm-opt --enable-bulk-memory --enable-simd --enable-sign-ext --enable-mutable-globals --enable-nontrapping-float-to-int -Oz '${wasm}' -o '${wasm}'",
	])

sh! = |script| run!("bash", ["-c", script])

sh_lines! = |lines| sh!(Str.join_with(lines, "\n"))

sh_capture! = |script| capture_line!("bash", ["-c", script])

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

		Err(_) => Err(Exit(1))
	}
}

# Run a command and return its first line of stdout, trimmed.
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

# WORKAROUND: roc-lang/roc#12692. A dev build frees a Child whose method a
# `match` with an early return called, which kills the child. Call
# `child.poll!()` directly when fixed.
poll! = |child| child.poll!()
