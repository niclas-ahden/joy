app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
    spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.2.0/Cv22_pXKIt82Cz5qzFxdm47SNo81RDx6j4gahQIJvME.tar.br",
}

import pf.Arg
import pf.Cmd
import pf.Env
import pf.Http
import pf.Sleep
import pf.Stdout

import spec.Spec {
    cmd_new: Cmd.new,
    cmd_args: Cmd.args,
    cmd_envs: Cmd.envs,
    cmd_spawn_grouped!: Cmd.spawn_grouped!,
    stdout_line!: Stdout.line!,
    dir_list!: dir_list_as_strings!,
    utc_now!: utc_now_as_millis!,
    sleep_millis!: Sleep.millis!,
}

import pf.Dir
import pf.Path
import pf.Utc

dir_list_as_strings! : Str => Result (List Str) _
dir_list_as_strings! = |path|
    paths = Dir.list!(path)?
    Ok(List.map(paths, Path.display))

utc_now_as_millis! : {} => I128
utc_now_as_millis! = |{}|
    Utc.to_millis_since_epoch(Utc.now!({}))

max_workers! : {} => U16
max_workers! = |{}|
    when Env.var!("ROC_SPEC_MAX_WORKERS") is
        Ok(val) -> Str.to_u16(val) |> Result.with_default(4)
        Err(_) -> 4

default_base_port : U16
default_base_port = 9800

get_worker_envs : U64 -> List (Str, Str)
get_worker_envs = |worker_index|
    [
        ("WORKER_INDEX", Num.to_str(worker_index)),
        ("ROC_SPEC_BASE_PORT", Num.to_str(default_base_port)),
        ("ROC_SPEC_HOST", "localhost"),
    ]

before_each_noop! : U64 => Result {} []
before_each_noop! = |_worker_index|
    Ok({})

parse_args : List Arg.Arg -> { pattern : Str, fail_fast : Bool }
parse_args = |args|
    args_strs = args |> List.map(Arg.display) |> List.drop_first(1)
    {
        pattern: args_strs |> List.keep_if(|a| !Str.starts_with(a, "--")) |> List.first |> Result.with_default(""),
        fail_fast: List.contains(args_strs, "--fail-fast"),
    }

main! : List Arg.Arg => Result {} _
main! = |args|
    { pattern, fail_fast } = parse_args(args)
    workers = max_workers!({})

    Stdout.line!("Starting $(Num.to_str(workers)) workers...")?

    # Spawn a static file server per worker
    List.range({ start: At(0), end: Before(workers) })
        |> List.for_each_try!(|index|
            spawn_worker!(default_base_port, index)
        )?

    # Wait for all workers
    wait_for_all_workers!({
        count: workers,
        base_port: default_base_port,
        max_attempts: 150,
        delay_ms: 200,
    })?

    Stdout.line!("All $(Num.to_str(workers)) workers ready")?

    results = Spec.run_filtered!("tests", {
        max_workers: workers,
        worker_envs: get_worker_envs,
        before_each!: before_each_noop!,
        per_test_timeout_ms: 60000,
        quiet: Bool.true,
        fail_fast,
    }, pattern)?

    passed = List.count_if(results, |r| r.passed)
    total = List.len(results)

    Stdout.line!("")?
    Stdout.line!("$(Num.to_str(passed))/$(Num.to_str(total)) tests passed")?

    if passed == total then
        Ok({})
    else
        Err(TestsFailed)

spawn_worker! : U16, U16 => Result {} _
spawn_worker! = |base_port, index|
    port = base_port + index

    _ =
        Cmd.new("./test-server")
        |> Cmd.envs([("ROC_BASIC_WEBSERVER_PORT", Num.to_str(port))])
        |> Cmd.spawn_grouped!()
        |> Result.map_err(|_| ServerSpawnFailed(index))?

    Ok({})

wait_for_all_workers! : { count : U16, base_port : U16, max_attempts : U64, delay_ms : U64 } => Result {} _
wait_for_all_workers! = |config|
    poll_until_all_ready!(config, List.repeat(Bool.false, Num.to_u64(config.count)), 0)

poll_until_all_ready! : { count : U16, base_port : U16, max_attempts : U64, delay_ms : U64 }, List Bool, U64 => Result {} _
poll_until_all_ready! = |config, ready_status, attempt|
    if attempt >= config.max_attempts then
        not_ready =
            ready_status
            |> List.map_with_index(|is_ready, idx| if is_ready then "" else Num.to_str(idx))
            |> List.keep_if(|s| !Str.is_empty(s))
            |> Str.join_with(", ")
        Err(WorkersNotReady(not_ready))
    else if List.all(ready_status, |r| r) then
        Ok({})
    else
        new_ready = poll_all_workers!(config.base_port, ready_status, 0, [])

        if List.all(new_ready, |r| r) then
            Ok({})
        else
            _ = Sleep.millis!(config.delay_ms)
            poll_until_all_ready!(config, new_ready, attempt + 1)

poll_all_workers! : U16, List Bool, U64, List Bool => List Bool
poll_all_workers! = |base_port, ready_status, idx, acc|
    when List.get(ready_status, idx) is
        Err(_) -> acc
        Ok(is_ready) ->
            new_status =
                if is_ready then
                    Bool.true
                else
                    check_worker_ready!(base_port, Num.to_u16(idx))
            poll_all_workers!(base_port, ready_status, idx + 1, List.append(acc, new_status))

check_worker_ready! : U16, U16 => Bool
check_worker_ready! = |base_port, index|
    port = base_port + index
    url = "http://localhost:$(Num.to_str(port))/"

    request = {
        method: GET,
        headers: [],
        uri: url,
        body: [],
        timeout_ms: TimeoutMilliseconds(1000),
    }

    when Http.send!(request) is
        Ok(response) -> response.status < 500
        Err(_) -> Bool.false
