app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
    playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.6.0/t00zRqBa9zpsMFrqXnM3wU2Vucyci4nnHdk3y6DBGg4.tar.br",
    spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.2.0/Cv22_pXKIt82Cz5qzFxdm47SNo81RDx6j4gahQIJvME.tar.br",
}

import pf.Arg
import pf.Cmd
import pf.Env
import pf.Http

import playwright.Playwright {
    cmd_new: Cmd.new,
    cmd_args: Cmd.args,
    cmd_spawn_grouped!: Cmd.spawn_grouped!,
}

import spec.Assert
import spec.TestEnvironment {
    env_var!: Env.var!,
    http_send!: Http.send!,
    http_header: Http.header,
    pg_connect!: pg_connect_stub!,
    pg_cmd_new: pg_cmd_new_stub,
    pg_client_command!: pg_client_command_stub!,
}

pg_connect_stub! = |_| Err(NotImplemented)
pg_cmd_new_stub = |_| {}
pg_client_command_stub! = |_, _| Err(NotImplemented)

## Crypto.hash_file_chunks! with a non-existent file_id fires an error event, not a crash.
main! : List Arg.Arg => Result {} _
main! = |_args|
    TestEnvironment.with!(|worker_url|
        { browser, page } = Playwright.launch_page!(Chromium)?
        Playwright.navigate!(page, "$(worker_url)/crypto")?
        Playwright.wait_for!(page, "#btn-hash-invalid", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        Playwright.click!(page, "#btn-hash-invalid")?

        # The done event fires with an error payload
        Playwright.wait_for!(page, "#done-result:not(:empty)", Attached)
        |> Result.map_err(|e| ErrorEventDidNotFire(Inspect.to_str(e)))?

        done_result = Playwright.text_content!(page, "#done-result")?

        Assert.true(Str.contains(done_result, "\"err\"")) ? MissingErr(done_result)
        Assert.true(Str.contains(done_result, "not found")) ? MissingNotFound(done_result)

        # No chunk events should have fired
        chunk_count = Playwright.text_content!(page, "#chunk-count")?
        Assert.eq(chunk_count, "0") ? UnexpectedChunks(chunk_count)

        Playwright.close!(browser)?
        Ok({})
    )
