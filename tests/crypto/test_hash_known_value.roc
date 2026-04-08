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

## Verify chunk hashes match independently computed SHA-1 values.
## Uses SubtleCrypto via evaluate! to compute expected hashes in the browser,
## then compares with what hash_file_chunks! produced.
main! : List Arg.Arg => Result {} _
main! = |_args|
    TestEnvironment.with!(|worker_url|
        { browser, page } = Playwright.launch_page!(Chromium)?

        # Use a large chunk_size so the whole content fits in 1 chunk
        Playwright.navigate!(page, "$(worker_url)/crypto?chunk_size=1000")?
        Playwright.wait_for!(page, "#file-input", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        # Hash "abc" — a well-known test vector
        Playwright.set_input_files!(page, "#file-input", Buffers([{
            name: "abc.bin",
            mime_type: "application/octet-stream",
            buffer: Str.to_utf8("abc"),
        }]))?

        Playwright.wait_for!(page, "#done-result:not(:empty)", Attached)
        |> Result.map_err(|e| DoneEventDidNotFire(Inspect.to_str(e)))?

        # Get the chunk hash produced by hash_file_chunks!
        actual_hash = Playwright.text_content!(page, ".chunk[data-index='0'] .hash")?

        # Compute expected SHA-1("abc") independently via SubtleCrypto in the browser
        expected_hash = Playwright.evaluate!(page,
            """
            (async () => {
                const data = new TextEncoder().encode("abc");
                const hash = await crypto.subtle.digest("SHA-1", data);
                return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, "0")).join("");
            })()
            """
        )?

        Assert.eq(actual_hash, expected_hash) ? HashMismatch({ actual: actual_hash, expected: expected_hash })

        error_text = Playwright.text_content!(page, "#error")?
        Assert.eq(error_text, "") ? UnexpectedError(error_text)

        Playwright.close!(browser)?
        Ok({})
    )
