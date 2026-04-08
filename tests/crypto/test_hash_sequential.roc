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

## parallelism: Exact(1) produces the same hashes as Exact(4).
## Chunk hashes must not depend on worker count.
main! : List Arg.Arg => Result {} _
main! = |_args|
    TestEnvironment.with!(|worker_url|
        content = Str.to_utf8("sequential vs parallel test content!!")
        file_payload = Buffers([{ name: "test.bin", mime_type: "application/octet-stream", buffer: content }])

        { browser, page } = Playwright.launch_page!(Chromium)?

        # Run with parallelism=1 (sequential)
        Playwright.navigate!(page, "$(worker_url)/crypto?chunk_size=10&parallelism=1")?
        Playwright.wait_for!(page, "#file-input", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        Playwright.set_input_files!(page, "#file-input", file_payload)?
        Playwright.wait_for!(page, "#done-result:not(:empty)", Attached)
        |> Result.map_err(|e| SequentialDidNotComplete(Inspect.to_str(e)))?

        seq_done = Playwright.text_content!(page, "#done-result")?
        seq_chunk0 = Playwright.text_content!(page, ".chunk[data-index='0'] .hash")?

        # Run with parallelism=4
        Playwright.navigate!(page, "$(worker_url)/crypto?chunk_size=10&parallelism=4")?
        Playwright.wait_for!(page, "#file-input", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        Playwright.set_input_files!(page, "#file-input", file_payload)?
        Playwright.wait_for!(page, "#done-result:not(:empty)", Attached)
        |> Result.map_err(|e| ParallelDidNotComplete(Inspect.to_str(e)))?

        par_done = Playwright.text_content!(page, "#done-result")?
        par_chunk0 = Playwright.text_content!(page, ".chunk[data-index='0'] .hash")?

        # Chunk hashes and hash_of_chunk_hashes must match
        Assert.eq(seq_chunk0, par_chunk0) ? ChunkHashMismatch({ sequential: seq_chunk0, parallel: par_chunk0 })
        Assert.eq(seq_done, par_done) ? DoneMismatch({ sequential: seq_done, parallel: par_done })

        error_text = Playwright.text_content!(page, "#error")?
        Assert.eq(error_text, "") ? UnexpectedError(error_text)

        Playwright.close!(browser)?
        Ok({})
    )
