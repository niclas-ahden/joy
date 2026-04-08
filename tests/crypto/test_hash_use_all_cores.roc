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

## UseAllCores (parallelism=0) produces the same hashes as Exact(1).
main! : List Arg.Arg => Result {} _
main! = |_args|
    TestEnvironment.with!(|worker_url|
        content = Str.to_utf8("use all cores vs exact test!!")
        file_payload = Buffers([{ name: "test.bin", mime_type: "application/octet-stream", buffer: content }])

        { browser, page } = Playwright.launch_page!(Chromium)?

        # Run with Exact(1)
        Playwright.navigate!(page, "$(worker_url)/crypto?chunk_size=10&parallelism=1")?
        Playwright.wait_for!(page, "#file-input", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        Playwright.set_input_files!(page, "#file-input", file_payload)?
        Playwright.wait_for!(page, "#done-result:not(:empty)", Attached)
        |> Result.map_err(|e| ExactDidNotComplete(Inspect.to_str(e)))?

        exact_chunk0 = Playwright.text_content!(page, ".chunk[data-index='0'] .hash")?
        exact_done = Playwright.text_content!(page, "#done-result")?
        exact_hoch = extract_hash_of_chunk_hashes(exact_done)

        # Run with UseAllCores (parallelism=0)
        Playwright.navigate!(page, "$(worker_url)/crypto?chunk_size=10&parallelism=0")?
        Playwright.wait_for!(page, "#file-input", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        Playwright.set_input_files!(page, "#file-input", file_payload)?
        Playwright.wait_for!(page, "#done-result:not(:empty)", Attached)
        |> Result.map_err(|e| UseAllCoresDidNotComplete(Inspect.to_str(e)))?

        all_cores_chunk0 = Playwright.text_content!(page, ".chunk[data-index='0'] .hash")?
        all_cores_done = Playwright.text_content!(page, "#done-result")?
        all_cores_hoch = extract_hash_of_chunk_hashes(all_cores_done)

        Assert.eq(exact_chunk0, all_cores_chunk0) ? ChunkHashMismatch({ exact: exact_chunk0, all_cores: all_cores_chunk0 })
        Assert.eq(exact_hoch, all_cores_hoch) ? HashOfChunkHashesMismatch({ exact: exact_hoch, all_cores: all_cores_hoch })

        error_text = Playwright.text_content!(page, "#error")?
        Assert.eq(error_text, "") ? UnexpectedError(error_text)

        Playwright.close!(browser)?
        Ok({})
    )

extract_hash_of_chunk_hashes : Str -> Str
extract_hash_of_chunk_hashes = |payload|
    marker = "\"hash_of_chunk_hashes\":\""
    when Str.split_first(payload, marker) is
        Ok({ after }) ->
            when Str.split_first(after, "\"") is
                Ok({ before }) -> before
                Err(_) -> ""

        Err(_) -> ""
