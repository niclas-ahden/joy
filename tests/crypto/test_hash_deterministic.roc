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

## Hashing the same file twice produces identical hashes.
main! : List Arg.Arg => Result {} _
main! = |_args|
    TestEnvironment.with!(|worker_url|
        content = Str.to_utf8("deterministic content to hash twice")
        file_payload = Buffers([{ name: "test.bin", mime_type: "application/octet-stream", buffer: content }])

        { browser, page } = Playwright.launch_page!(Chromium)?
        Playwright.navigate!(page, "$(worker_url)/crypto?chunk_size=10")?
        Playwright.wait_for!(page, "#file-input", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        # First hash
        Playwright.set_input_files!(page, "#file-input", file_payload)?
        Playwright.wait_for!(page, "#done-result:not(:empty)", Attached)
        |> Result.map_err(|e| FirstHashDidNotComplete(Inspect.to_str(e)))?

        first_done = Playwright.text_content!(page, "#done-result")?
        first_chunk0_hash = Playwright.text_content!(page, ".chunk[data-index='0'] .hash")?

        # Clear and hash again — selecting the same file triggers UserSelectedFile
        # which resets the model and re-hashes
        Playwright.set_input_files!(page, "#file-input", Paths([]))?
        Playwright.set_input_files!(page, "#file-input", file_payload)?
        Playwright.wait_for!(page, "#done-result:not(:empty)", Attached)
        |> Result.map_err(|e| SecondHashDidNotComplete(Inspect.to_str(e)))?

        second_done = Playwright.text_content!(page, "#done-result")?
        second_chunk0_hash = Playwright.text_content!(page, ".chunk[data-index='0'] .hash")?

        # Both runs should produce the same chunk hashes and hash_of_chunk_hashes.
        # (file_id differs between runs, so compare hashes not full payloads.)
        Assert.eq(first_chunk0_hash, second_chunk0_hash) ? ChunkHashMismatch({ first: first_chunk0_hash, second: second_chunk0_hash })

        # Extract hash_of_chunk_hashes from done payloads
        first_hoch = extract_hash_of_chunk_hashes(first_done)
        second_hoch = extract_hash_of_chunk_hashes(second_done)
        Assert.eq(first_hoch, second_hoch) ? HashOfChunkHashesMismatch({ first: first_hoch, second: second_hoch })

        error_text = Playwright.text_content!(page, "#error")?
        Assert.eq(error_text, "") ? UnexpectedError(error_text)

        Playwright.close!(browser)?
        Ok({})
    )

## Extract the hash_of_chunk_hashes value from a done payload string.
## Payload looks like: {"file_id":1,"ok":{"total_chunks":4,"hash_of_chunk_hashes":"abc..."}}
extract_hash_of_chunk_hashes : Str -> Str
extract_hash_of_chunk_hashes = |payload|
    marker = "\"hash_of_chunk_hashes\":\""
    when Str.split_first(payload, marker) is
        Ok({ after }) ->
            when Str.split_first(after, "\"") is
                Ok({ before }) -> before
                Err(_) -> ""

        Err(_) -> ""
