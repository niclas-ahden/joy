app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
    playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.6.0/t00zRqBa9zpsMFrqXnM3wU2Vucyci4nnHdk3y6DBGg4.tar.br",
}

# Performance driver for the Joy bench app (tests/apps/bench). It opens the app in a
# headless browser, dispatches many `step` events to exercise the update cycle, and
# collects the per-update phase timings emitted by the `joy_bench` feature (which the
# instrumentation appends to `window.__joy_bench`).
#
# It prints one line `JOY_BENCH_RESULT <json-array>` to stdout; tests/bench/bench.sh
# turns that into medians and compares them against a saved baseline. The driver only
# measures WASM-internal time (via `performance.now()` inside the update), so the cost
# of Playwright round-trips does not pollute the numbers.
#
# Configuration via env vars:
#   BENCH_URL   - base URL of the static server (default http://localhost:8080)
#   BENCH_STEPS - number of measured update cycles (default 200)
#   BENCH_WARMUP- number of warmup update cycles, discarded (default 30)

import pf.Arg
import pf.Cmd
import pf.Env
import pf.Stdout

import playwright.Playwright {
    cmd_new: Cmd.new,
    cmd_args: Cmd.args,
    cmd_spawn_grouped!: Cmd.spawn_grouped!,
}

main! : List Arg.Arg => Result {} _
main! = |_args|
    base_url = Env.var!("BENCH_URL") |> Result.with_default("http://localhost:8080")
    steps = Env.var!("BENCH_STEPS") |> Result.try(Str.to_u64) |> Result.with_default(200)
    warmup = Env.var!("BENCH_WARMUP") |> Result.try(Str.to_u64) |> Result.with_default(30)

    { browser, page } = Playwright.launch_page!(Chromium)?

    Playwright.navigate!(page, "${base_url}/bench")?
    Playwright.wait_for!(page, "#step", Visible)
    |> Result.map_err(|e| BenchAppDidNotLoad(Inspect.to_str(e)))?

    # Warm up (JIT, allocator, layout), then clear the collected samples so only the
    # measured window remains.
    _ = Playwright.evaluate!(page, click_loop(warmup, "window.__joy_bench=[];"))?

    # Measured run: dispatch `steps` synchronous clicks, each triggering one full
    # render -> convert -> diff+patch cycle that the instrumentation records.
    _ = Playwright.evaluate!(page, click_loop(steps, ""))?

    json = Playwright.evaluate!(page, "JSON.stringify(window.__joy_bench||[])")?

    Stdout.line!("JOY_BENCH_RESULT ${json}")?

    Playwright.close!(browser)?
    Ok({})

# Build an expression (an IIFE, since `evaluate!` evaluates an expression and a bare
# `for` loop is a statement) that clicks #step `n` times, runs `after`, and returns "ok".
click_loop : U64, Str -> Str
click_loop = |n, after|
    "(()=>{for(let i=0;i<${Num.to_str(n)};i++){document.querySelector('#step').click();}${after}return 'ok';})()"
