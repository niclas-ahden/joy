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

## SHA-256 produces 64-char hex hashes (32 bytes).
main! : List Arg.Arg => Result {} _
main! = |_args|
    TestEnvironment.with!(|worker_url|
        { browser, page } = Playwright.launch_page!(Chromium)?
        Playwright.navigate!(page, "$(worker_url)/crypto?chunk_size=100&algorithm=SHA-256")?
        Playwright.wait_for!(page, "#file-input", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        Playwright.set_input_files!(page, "#file-input", Buffers([{
            name: "test.bin",
            mime_type: "application/octet-stream",
            buffer: Str.to_utf8("test data for sha256"),
        }]))?

        Playwright.wait_for!(page, "#done-result:not(:empty)", Attached)
        |> Result.map_err(|e| DoneEventDidNotFire(Inspect.to_str(e)))?

        # SHA-256 hash is 64 hex chars (vs 40 for SHA-1)
        hash = Playwright.text_content!(page, ".chunk[data-index='0'] .hash")?
        Assert.eq(Str.count_utf8_bytes(hash), 64) ? WrongHashLength("expected 64 for SHA-256, got $(Num.to_str(Str.count_utf8_bytes(hash))): $(hash)")

        # Done event should also have a 64-char hash_of_chunk_hashes
        done_result = Playwright.text_content!(page, "#done-result")?
        Assert.true(Str.contains(done_result, "\"ok\"")) ? MissingOk(done_result)

        error_text = Playwright.text_content!(page, "#error")?
        Assert.eq(error_text, "") ? UnexpectedError(error_text)

        Playwright.close!(browser)?
        Ok({})
    )
