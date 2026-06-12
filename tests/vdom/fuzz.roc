app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
    playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.6.0/t00zRqBa9zpsMFrqXnM3wU2Vucyci4nnHdk3y6DBGg4.tar.br",
}

# Model-based fuzz test for Joy's virtual-DOM contract (render -> diff -> patch). It keeps
# a "shadow" model in the driver, applies a random sequence of structural ops to it
# (append / insert / remove / swap / update-label / toggle-selected / clear), pushes each
# resulting state into the Joy app (tests/apps/vdom) -- which exercises the diff -- and
# asserts the *live DOM* matches the shadow after every step. Because it asserts against
# Joy's own DOM output (not percy internals), it stays valid if percy is ever replaced.
#
# A mismatch means the incremental diff/patch diverged from the true model -- a real bug,
# reproducible from the printed seed. Config via env: FUZZ_SEED, FUZZ_ITERS, VDOM_URL.

import pf.Arg
import pf.Cmd
import pf.Env
import pf.Stdout

import playwright.Playwright {
    cmd_new: Cmd.new,
    cmd_args: Cmd.args,
    cmd_spawn_grouped!: Cmd.spawn_grouped!,
}

Row : { id : U64, label : Str, sel : Bool }

main! : List Arg.Arg => Result {} _
main! = |_args|
    base = Env.var!("VDOM_URL") |> Result.with_default("http://localhost:8090")
    seed = Env.var!("FUZZ_SEED") |> Result.try(Str.to_u64) |> Result.with_default(1)
    iters = Env.var!("FUZZ_ITERS") |> Result.try(Str.to_u64) |> Result.with_default(200)

    Stdout.line!("vdom fuzz: seed=${Num.to_str(seed)} iters=${Num.to_str(iters)} url=${base}/vdom")?

    { browser, page } = Playwright.launch_page!(Chromium)?
    Playwright.navigate!(page, "${base}/vdom/index.html")?
    Playwright.wait_for!(page, "#tbl", Attached)
    |> Result.map_err(|e| AppDidNotLoad(Inspect.to_str(e)))?

    fuzz_loop!(page, iters, iters, seed, [], 1)?

    Playwright.close!(browser)?
    Stdout.line!("OK: ${Num.to_str(iters)} iterations — live DOM matched the model at every step")?
    Ok({})

fuzz_loop! : _, U64, U64, U64, List Row, U64 => Result {} _
fuzz_loop! = |page, total, left, rng, rows, next_id|
    if left == 0 then
        Ok({})
    else
        len = List.len(rows)
        step_no = Num.to_str((total - left) + 1)
        (rng1, kind) = rand_below(rng, 5)
        if kind == 0 and len > 0 then
            # EVENT op: actually *click* a random row's label, firing its onclick
            # ("toggle:<id>"), which flips that row's selected flag in the app. This is the
            # real event-dispatch path: if the diff left a stale/mis-bound handler after a
            # prior insert/remove/reorder, the wrong row (or none) toggles and the DOM
            # diverges from the shadow below. Without this, the suite only proves handlers
            # are *attached*, never that they *fire correctly*.
            (rng2, k) = rand_below(rng1, len)
            sel = "#tbody>tr:nth-of-type(${Num.to_str(k + 1)})>td.label>a.lbl"
            _ = Playwright.evaluate!(page, "(()=>{const e=document.querySelector('${sel}');if(e)e.click();return 'ok';})()")?
            rows2 = List.map_with_index(rows, |r, i| if i == k then { r & sel: !r.sel } else r)
            check_dom!(page, rows2, step_no, "click row ${Num.to_str(k)}")?
            fuzz_loop!(page, total, left - 1, rng2, rows2, next_id)
        else
            # STATE op: apply a structural change and push the whole new state through the diff.
            (rng2, rows2, next_id2) = step(rng1, rows, next_id)
            _ = Playwright.evaluate!(page, "(()=>{window.__joy_port('set:${encode_rows(rows2)}');return 'ok';})()")?
            check_dom!(page, rows2, step_no, "set state")?
            fuzz_loop!(page, total, left - 1, rng2, rows2, next_id2)

# Assert the live DOM matches the shadow model after an op.
check_dom! : _, List Row, Str, Str => Result {} _
check_dom! = |page, rows, step_no, what|
    expected = encode_rows(rows)
    actual = Playwright.evaluate!(page, read_dom_js)?
    if actual == expected then
        Ok({})
    else
        Stdout.line!("MISMATCH at step ${step_no} (${what}):")?
        Stdout.line!("  expected: ${expected}")?
        Stdout.line!("  actual:   ${actual}")?
        Err(DomDivergedFromModel(step_no))

# Read the table back as "<id>,<label>,<sel>;..." — the same encoding as the shadow.
read_dom_js : Str
read_dom_js =
    "[...document.querySelectorAll('#tbody>tr')].map(t=>t.querySelector('td.id').textContent+','+t.querySelector('td.label .lbl').textContent+','+(t.classList.contains('selected')?'1':'0')).join(';')"

encode_rows : List Row -> Str
encode_rows = |rows|
    rows
    |> List.map(|r| "${Num.to_str(r.id)},${r.label},${if r.sel then "1" else "0"}")
    |> Str.join_with(";")

# Apply one random op to the shadow model. Threads the PRNG state through.
step : U64, List Row, U64 -> (U64, List Row, U64)
step = |rng, rows, next_id|
    len = List.len(rows)
    (rng1, op) = rand_below(rng, 7)
    when op is
        0 -> (rng1, List.append(rows, mk_row(next_id)), next_id + 1) # append
        1 -> # insert at random position
            (rng2, k) = rand_below(rng1, len + 1)
            (rng2, list_insert(rows, k, mk_row(next_id)), next_id + 1)
        2 -> # remove at random position
            if len == 0 then
                (rng1, rows, next_id)
            else
                (rng2, k) = rand_below(rng1, len)
                (rng2, list_remove(rows, k), next_id)

        3 -> # swap two positions
            if len < 2 then
                (rng1, rows, next_id)
            else
                (rng2, i) = rand_below(rng1, len)
                (rng3, j) = rand_below(rng2, len)
                (rng3, List.swap(rows, i, j), next_id)

        4 -> # update a row's label
            if len == 0 then
                (rng1, rows, next_id)
            else
                (rng2, k) = rand_below(rng1, len)
                (rng3, suffix) = rand_below(rng2, 100000)
                new_rows = List.map_with_index(rows, |r, i| if i == k then { r & label: "u${Num.to_str(suffix)}" } else r)
                (rng3, new_rows, next_id)

        5 -> # toggle a row's selected flag
            if len == 0 then
                (rng1, rows, next_id)
            else
                (rng2, k) = rand_below(rng1, len)
                new_rows = List.map_with_index(rows, |r, i| if i == k then { r & sel: !r.sel } else r)
                (rng2, new_rows, next_id)

        _ -> # clear (rare — only op 6 of 0..6)
            (rng1, [], next_id)

mk_row : U64 -> Row
mk_row = |row_id| { id: row_id, label: "r${Num.to_str(row_id)}", sel: Bool.false }

list_insert : List Row, U64, Row -> List Row
list_insert = |rows, k, x|
    before = List.sublist(rows, { start: 0, len: k })
    after = List.sublist(rows, { start: k, len: List.len(rows) })
    List.concat(List.append(before, x), after)

list_remove : List Row, U64 -> List Row
list_remove = |rows, k|
    before = List.sublist(rows, { start: 0, len: k })
    after = List.sublist(rows, { start: k + 1, len: List.len(rows) })
    List.concat(before, after)

# Splitmix-ish LCG; returns (next state, value in [0, n)). High bits used for quality.
rand_below : U64, U64 -> (U64, U64)
rand_below = |s, n|
    s2 = Num.add_wrap(Num.mul_wrap(s, 6364136223846793005), 1442695040888963407)
    hi = Num.div_trunc(s2, 4294967296)
    (s2, Num.rem(hi, n))
