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

## DOM.navigate! triggers a full-page navigation (sets window.location.href).
main! : List Arg.Arg => Result {} _
main! = |_args|
    TestEnvironment.with!(|worker_url|
        { browser, page } = Playwright.launch_page!(Chromium)?
        Playwright.navigate!(page, "$(worker_url)/dom")?
        Playwright.wait_for!(page, "#btn-navigate", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        # The app renders the path it booted at (from location.pathname).
        path_before = Playwright.text_content!(page, "#path")?
        Assert.eq(path_before, "/dom") ? WrongPathBefore(path_before)

        # Trigger the navigation.
        Playwright.click!(page, "#btn-navigate")?

        # The destination is the same app booted at a new URL. Waiting for the
        # freshly rendered path proves the navigation completed. This is
        # race-free because wait_for! polls the newly loaded document, and the
        # source page (which renders "/dom") never contains this longer string.
        # Quote the selector: an unquoted text= value wrapped in slashes is
        # parsed as a regex, and "/dom/index.html" is an invalid one.
        Playwright.wait_for!(page, "text=\"/dom/index.html\"", Attached)
        |> Result.map_err(|e| DidNotNavigate(Inspect.to_str(e)))?

        # Assert against the real browser URL, not just our echoed flag. This is
        # what proves DOM.navigate! actually set window.location.
        url_path = Playwright.evaluate!(page, "window.location.pathname")?
        Assert.eq(url_path, "/dom/index.html") ? WrongUrl(url_path)

        # And the destination app re-initialised at that URL.
        path_after = Playwright.text_content!(page, "#path")?
        Assert.eq(path_after, "/dom/index.html") ? WrongPathAfter(path_after)

        Playwright.close!(browser)?
        Ok({})
    )
