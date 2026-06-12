app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
    playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.6.0/t00zRqBa9zpsMFrqXnM3wU2Vucyci4nnHdk3y6DBGg4.tar.br",
}

# Memory-leak guard for Joy's vdom. Repeatedly creates a 1,000-row list and clears it,
# watching the WASM linear-memory size (where Joy's allocations live) after each cycle.
# WASM memory only ever grows, so after the first couple of cycles a *steady* per-cycle
# increase means memory isn't being reclaimed on clear -- i.e. a leak.
#
# This asserts a per-cycle growth threshold, so it FAILS while the leak exists and PASSES
# once it's fixed -- a regression guard for the event-teardown work. It reads the raw WASM
# heap size (window.__joy_wasm_bytes, exposed by the app), so unlike the benchmark's
# measureUserAgentSpecificMemory it needs no cross-origin-isolation headers.
#
# Config: VDOM_URL, LEAK_CYCLES (measured cycles), LEAK_WARMUP, LEAK_MAX_GROWTH_KB.

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
    base = Env.var!("VDOM_URL") |> Result.with_default("http://localhost:8090")
    cycles = Env.var!("LEAK_CYCLES") |> Result.try(Str.to_u64) |> Result.with_default(15)
    warmup = Env.var!("LEAK_WARMUP") |> Result.try(Str.to_u64) |> Result.with_default(3)
    max_kb = Env.var!("LEAK_MAX_GROWTH_KB") |> Result.try(Str.to_u64) |> Result.with_default(512)

    Stdout.line!("vdom leak: cycles=${Num.to_str(cycles)} warmup=${Num.to_str(warmup)} max_growth=${Num.to_str(max_kb)}KB/cycle")?

    { browser, page } = Playwright.launch_page!(Chromium)?
    Playwright.navigate!(page, "${base}/vdom/index.html")?
    Playwright.wait_for!(page, "#tbl", Attached)
    |> Result.map_err(|e| AppDidNotLoad(Inspect.to_str(e)))?

    # Warm up (initial allocations / first growth), discarding measurements.
    _ = cycle_n!(page, warmup, [])?
    measured = cycle_n!(page, cycles, [])?

    Playwright.close!(browser)?

    kb = |bytes| bytes // 1024
    trajectory = measured |> List.map(|b| Num.to_str(kb(b))) |> Str.join_with(" ")
    Stdout.line!("WASM heap KB after each clear: ${trajectory}")?

    first = List.first(measured) |> Result.with_default(0)
    last = List.last(measured) |> Result.with_default(0)
    n = List.len(measured)
    growth_per_cycle_kb =
        if last > first and n > 1 then kb(last - first) // (n - 1) else 0

    Stdout.line!("growth: ${Num.to_str(growth_per_cycle_kb)} KB/cycle (threshold ${Num.to_str(max_kb)})")?

    if growth_per_cycle_kb <= max_kb then
        Stdout.line!("OK: WASM heap is stable across create/clear cycles")?
        Ok({})
    else
        Stdout.line!("LEAK: WASM heap grows ${Num.to_str(growth_per_cycle_kb)} KB/cycle (> ${Num.to_str(max_kb)})")?
        Err(MemoryLeak(growth_per_cycle_kb))

# Run `n` create-1k/clear cycles, recording the WASM heap size (bytes) after each clear.
cycle_n! : _, U64, List U64 => Result (List U64) _
cycle_n! = |page, n, acc|
    if n == 0 then
        Ok(acc)
    else
        _ = Playwright.evaluate!(page, "(()=>{window.__joy_port('${big_set}');return 'ok';})()")?
        _ = Playwright.evaluate!(page, "(()=>{window.__joy_port('set:');return 'ok';})()")?
        bytes = Playwright.evaluate!(page, "String(window.__joy_wasm_bytes())")?
        cycle_n!(page, n - 1, List.append(acc, Str.to_u64(bytes) |> Result.with_default(0)))

# "set:" payload for 1,000 rows: "1,r1,0;2,r2,0;...".
big_set : Str
big_set =
    rows =
        List.range({ start: At(1), end: At(1000) })
        |> List.map(|i| "${Num.to_str(i)},r${Num.to_str(i)},0")
        |> Str.join_with(";")
    "set:${rows}"
