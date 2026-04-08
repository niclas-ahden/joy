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

## Http.put_file! with Slice sends only a byte range of the file.
main! : List Arg.Arg => Result {} _
main! = |_args|
    TestEnvironment.with!(|worker_url|
        { browser, page } = Playwright.launch_page!(Chromium)?
        Playwright.navigate!(page, "$(worker_url)/http")?
        Playwright.wait_for!(page, "#btn-put-file-slice", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        # Select a file — "hello world" is 11 bytes, slice will take first 5
        Playwright.set_input_files!(page, "#file-input", Buffers([{
            name: "slice_test.txt",
            mime_type: "text/plain",
            buffer: Str.to_utf8("hello world"),
        }]))?

        Playwright.click!(page, "#btn-put-file-slice")?

        Playwright.wait_for!(page, "#response:not(:empty)", Attached)
        |> Result.map_err(|e| ResponseDidNotArrive(Inspect.to_str(e)))?

        response = Playwright.text_content!(page, "#response")?

        Assert.true(Str.contains(response, "\"method\": \"PUT\"")) ? WrongMethod(response)
        # The test app sends Slice({ file: 1, start: 0, len: 5 }) — only "hello"
        Assert.true(Str.contains(response, "\"body_size\": 5")) ? WrongBodySize(response)
        Assert.true(Str.contains(response, "x-slice")) ? MissingHeader(response)

        Playwright.close!(browser)?
        Ok({})
    )
