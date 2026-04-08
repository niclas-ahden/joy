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

main! : List Arg.Arg => Result {} _
main! = |_args|
    TestEnvironment.with!(|worker_url|
        # The test app uses chunk_size_bytes: 10, so a 38-byte file produces 4 chunks:
        #   chunk 0: bytes 0-9   (10 bytes)
        #   chunk 1: bytes 10-19 (10 bytes)
        #   chunk 2: bytes 20-29 (10 bytes)
        #   chunk 3: bytes 30-37 (8 bytes)

        { browser, page } = Playwright.launch_page!(Chromium)?
        Playwright.navigate!(page, "$(worker_url)/crypto")?
        Playwright.wait_for!(page, "#file-input", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        Playwright.set_input_files!(page, "#file-input", Buffers([{
            name: "test.bin",
            mime_type: "application/octet-stream",
            buffer: Str.to_utf8("hello this is test content for hashing"),
        }]))?

        Playwright.wait_for!(page, "#done-result:not(:empty)", Attached)
        |> Result.map_err(|e| DoneEventDidNotFire(Inspect.to_str(e)))?

        # Verify chunk count
        chunk_count = Playwright.text_content!(page, "#chunk-count")?
        Assert.eq(chunk_count, "4") ? WrongChunkCount(chunk_count)

        # Verify all 4 chunks have events
        event_count = Playwright.query_count!(page, "#chunk-events .chunk")?
        Assert.eq(event_count, 4) ? WrongEventCount(Num.to_str(event_count))

        # Verify chunk 0 byte range
        chunk0_start = Playwright.text_content!(page, ".chunk[data-index='0'] .start")?
        chunk0_end = Playwright.text_content!(page, ".chunk[data-index='0'] .end")?
        Assert.eq(chunk0_start, "0") ? WrongStartByte(chunk0_start)
        Assert.eq(chunk0_end, "10") ? WrongEndByte(chunk0_end)

        # Verify last chunk byte range (partial chunk)
        chunk3_start = Playwright.text_content!(page, ".chunk[data-index='3'] .start")?
        chunk3_end = Playwright.text_content!(page, ".chunk[data-index='3'] .end")?
        Assert.eq(chunk3_start, "30") ? WrongStartByte(chunk3_start)
        Assert.eq(chunk3_end, "38") ? WrongEndByte(chunk3_end)

        # Verify total_chunks is reported correctly in chunk events
        chunk0_total = Playwright.text_content!(page, ".chunk[data-index='0'] .total")?
        Assert.eq(chunk0_total, "4") ? WrongTotalChunks(chunk0_total)

        # Verify chunk hashes are 40-char hex strings (SHA-1)
        chunk0_hash = Playwright.text_content!(page, ".chunk[data-index='0'] .hash")?
        Assert.eq(Str.count_utf8_bytes(chunk0_hash), 40) ? WrongHashLength(chunk0_hash)

        # Verify done event payload structure
        done_result = Playwright.text_content!(page, "#done-result")?
        Assert.true(Str.contains(done_result, "hash_of_chunk_hashes")) ? MissingHashOfChunkHashes(done_result)
        Assert.true(Str.contains(done_result, "total_chunks")) ? MissingTotalChunks(done_result)
        Assert.true(Str.contains(done_result, "\"ok\"")) ? MissingOkWrapper(done_result)

        # Verify no errors
        error_text = Playwright.text_content!(page, "#error")?
        Assert.eq(error_text, "") ? UnexpectedError(error_text)

        Playwright.close!(browser)?
        Ok({})
    )
