#!/usr/bin/env roc
# Phase regression benchmark: build the jsbench app with the host's joy_bench
# instrumentation, drive it in a real Chromium, and report per-phase medians
# for the steady-state workload the js-framework-benchmark also measures
# (update every 10th of 1000 rows). The phases are where a regression hides:
#
#   update  the app's `update` (roc_update, plus effect handling)
#   render  the app's `render` (roc_render builds the new tree)
#   diff    the host diffs new against previous and emits patch ops
#   paint   the runtime applies the ops to the real DOM
#
# Run from the repo root, inside the nix devShell (playwright + browsers),
# with a ../roc-playwright checkout (same requirement as e2e.roc):
#
#   tests/bench/bench.roc                  # run and compare against baseline.json
#   tests/bench/bench.roc --save-baseline  # accept the current numbers as the new baseline
#
# Tunables (env): BENCH_STEPS (default 200), BENCH_WARMUP (default 30),
# BENCH_PORT (default 8788), BENCH_THRESHOLD (slowdown ratio that prints a
# REGRESSION warning, default 1.10).
#
# performance.now() is deliberately coarsened by browsers, so treat
# single-digit-percent moves as noise: re-run before trusting a regression,
# and prefer a larger BENCH_STEPS when chasing a small one. The
# instrumentation is compiled out entirely without JOY_BENCH, so normal
# builds pay nothing.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "../../../roc-playwright/package/main.roc",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stderr
import pf.Stdout
import playwright.Playwright

hooks = {
	new: Cmd.new_str,
	args: Cmd.args_str,
	spawn_grouped!: Cmd.spawn_leashed!,
	write_stdin!: Cmd.Child.write_stdin!,
	read_stdout!: Cmd.Child.read_stdout!,
	kill!: Cmd.Child.kill!,
}

baseline_path = "tests/bench/baseline.json"

main! = |args| {
	save_baseline = match args.get(1) {
		Ok(arg) => OsStr.display(arg) == "--save-baseline"
		Err(_) => Bool.False
	}

	steps = U64.from_str(Env.var_str!("BENCH_STEPS") ?? "") ?? 200
	warmup = U64.from_str(Env.var_str!("BENCH_WARMUP") ?? "") ?? 30
	port = Env.var_str!("BENCH_PORT") ?? "8788"
	threshold = F64.from_str(Env.var_str!("BENCH_THRESHOLD") ?? "") ?? 1.10

	Stdout.line!("== building jsbench with joy_bench instrumentation ==")?
	build_code = Cmd.new_str("./build.roc")
		.args_str(["--opt=speed", "tests/apps/jsbench.roc"])
		.env_str("JOY_BENCH", "1")
		.exec_exit_code!()
		.ok_or(1)
	_ = if build_code == 0 {
		{}
	} else {
		fail!("build failed")?
	}

	# Spawned leashed, so the platform kills the server when this script
	# exits, pass or fail. Pinned mode: jsbench is the site's only app.
	server = Cmd.new_str("node")
		.args_str(["www/serve.mjs", port, "speed", "jsbench"])
		.spawn_leashed!()?
	url = "http://127.0.0.1:${port}/"
	wait_for_server!(url, 100)?

	Stdout.line!("== driving ${steps.to_str()} steps (${warmup.to_str()} warmup) in Chromium ==")?
	{ browser, page } = Playwright.launch_page!(hooks, Chromium(DefaultChannel))?
	Playwright.navigate!(page, url)?
	Playwright.wait_for!(page, "#run", Visible)?
	# The workload needs its 1000 rows first, and the create itself is not
	# measured.
	Playwright.click!(page, "#run")?
	Playwright.wait_for!(page, "#tbody tr", Visible)?

	# One evaluate drives every step: each button.click() dispatches into the
	# app synchronously, and the runtime's cumulative perf counters are
	# sampled around each click, so the deltas are per-step phase costs. The
	# sampling itself runs outside enter() and never lands in the counters.
	warmup_js = "(() => { const btn = document.getElementById('update'); for (let i = 0; i < ${warmup.to_str()}; i++) btn.click(); return 'ok'; })()"
	measure_js = "(() => { const app = window.app; app.perf.enabled = true; const btn = document.getElementById('update'); const c = () => [app.perf.updateMs, app.perf.renderMs, app.perf.diffMs, app.perf.paintMs, app.perf.busyMs]; const rows = []; for (let i = 0; i < ${steps.to_str()}; i++) { const a = c(); btn.click(); const b = c(); rows.push([b[0]-a[0], b[1]-a[1], b[2]-a[2], b[3]-a[3], b[4]-a[4]]); } return JSON.stringify(rows); })()"
	_ = Playwright.evaluate!(page, warmup_js)?
	raw = Playwright.evaluate!(page, measure_js)?
	Playwright.close!(browser)?
	server.kill!() ?? {}

	samples : Try(List(List(F64)), _)
	samples = Json.parse(raw)
	rows = samples ? |_| BadSamples(raw)

	current = {
		update: median(rows.map(|r| r.get(0) ?? 0.0)),
		render: median(rows.map(|r| r.get(1) ?? 0.0)),
		diff: median(rows.map(|r| r.get(2) ?? 0.0)),
		paint: median(rows.map(|r| r.get(3) ?? 0.0)),
		busy: median(rows.map(|r| r.get(4) ?? 0.0)),
	}

	Stdout.line!("")?
	Stdout.line!("phase   median ms (of ${rows.len().to_str()} steps)")?
	Stdout.line!("update  ${fmt3(current.update)}")?
	Stdout.line!("render  ${fmt3(current.render)}")?
	Stdout.line!("diff    ${fmt3(current.diff)}")?
	Stdout.line!("paint   ${fmt3(current.paint)}")?
	Stdout.line!("busy    ${fmt3(current.busy)}")?
	Stdout.line!("")?

	if save_baseline {
		json = "{\"update\": ${F64.to_str(current.update)}, \"render\": ${F64.to_str(current.render)}, \"diff\": ${F64.to_str(current.diff)}, \"paint\": ${F64.to_str(current.paint)}, \"busy\": ${F64.to_str(current.busy)}}"
		Path.utf8(baseline_path).write_utf8!(json)?
		Stdout.line!("Saved baseline to ${baseline_path}")
	} else {
		baseline_read = Path.utf8(baseline_path).read_utf8!()
		match baseline_read {
			Ok(content) => {
				decoded : Try({ update : F64, render : F64, diff : F64, paint : F64, busy : F64 }, _)
				decoded = Json.parse(content)
				base = decoded ? |_| BadBaseline(content)
				Stdout.line!("phase   current  baseline  ratio")?
				compare!("update", current.update, base.update, threshold)?
				compare!("render", current.render, base.render, threshold)?
				compare!("diff  ", current.diff, base.diff, threshold)?
				compare!("paint ", current.paint, base.paint, threshold)?
				compare!("busy  ", current.busy, base.busy, threshold)
			}
			Err(_) => Stdout.line!("No ${baseline_path} yet, run with --save-baseline to create one.")
		}
	}
}

compare! = |name, current, base, threshold| {
	# A phase can sit below the clock's resolution (base 0), and then there is
	# no ratio.
	if base > 0.0 {
		ratio = current / base
		warning = if ratio > threshold {
			"  REGRESSION (>${F64.to_str(threshold)}x)"
		} else {
			""
		}
		Stdout.line!("${name}  ${fmt3(current)}    ${fmt3(base)}     ${fmt2(ratio)}${warning}")
	} else {
		Stdout.line!("${name}  ${fmt3(current)}    ${fmt3(base)}     -")
	}
}

# Poll until the dev server answers. Bounded, so a server that never comes up
# fails the run instead of hanging it.
wait_for_server! = |url, attempts_left| {
	if attempts_left == 0 {
		Err(ServerNeverAnswered(url))
	} else {
		match Cmd.new_str("curl").args_str(["-sf", "-o", "/dev/null", url]).exec_exit_code!() {
			Ok(0) => Ok({})
			_ => {
				Sleep.millis!(100)
				wait_for_server!(url, attempts_left - 1)
			}
		}
	}
}

median : List(F64) -> F64
median = |values| {
	sorted = values.sort_with(
		|a, b| if a < b {
			LT
		} else if a > b {
			GT
		} else {
			EQ
		},
	)
	sorted.get(sorted.len() // 2) ?? 0.0
}

# Fixed-point display, since F64.to_str would print full precision.
fmt3 : F64 -> Str
fmt3 = |x| fixed(x, 1000, 3)

fmt2 : F64 -> Str
fmt2 = |x| fixed(x, 100, 2)

fixed : F64, I64, U64 -> Str
fixed = |x, scale, places| {
	scaled = F64.round_to_i64_try(x * I64.to_f64(scale)) ?? 0
	whole = scaled // scale
	frac = (scaled % scale).abs()
	"${whole.to_str()}.${pad_zeros(frac.to_str(), places)}"
}

pad_zeros : Str, U64 -> Str
pad_zeros = |s, width| {
	len = s.count_utf8_bytes()
	if len < width {
		Str.concat(Str.repeat("0", width - len), s)
	} else {
		s
	}
}

fail! = |message| {
	Stderr.line!("error: ${message}") ?? {}
	Err(Exit(1))
}
