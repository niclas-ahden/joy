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

## DOM.replace_url! updates the URL in place: no reload, no new history entry.
main! : List Arg.Arg => Result {} _
main! = |_args|
    TestEnvironment.with!(|worker_url|
        { browser, page } = Playwright.launch_page!(Chromium)?
        Playwright.navigate!(page, "$(worker_url)/dom")?
        Playwright.wait_for!(page, "#btn-replace-url", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        # Put some client-only state on the page: open then close the modal so
        # status becomes "closed". A full reload would reset this to "", so it
        # doubles as our "did the page reload?" witness. (We close it again so
        # the modal backdrop doesn't intercept the later button click.)
        Playwright.click!(page, "#btn-show")?
        Playwright.wait_for!(page, "#dialog-content", Visible)
        |> Result.map_err(|e| DialogDidNotOpen(Inspect.to_str(e)))?
        Playwright.click!(page, "#btn-close-inside")?
        Playwright.wait_for!(page, "text=closed", Attached)
        |> Result.map_err(|e| DialogDidNotClose(Inspect.to_str(e)))?

        # Remember history length so we can prove replaceState didn't grow it.
        _ = Playwright.evaluate!(page, "String(window.__h = history.length)")?

        Playwright.click!(page, "#btn-replace-url")?

        # The URL updated in place.
        search = Playwright.evaluate!(page, "window.location.search")?
        Assert.eq(search, "?replaced=1") ? WrongSearch(search)

        # No new history entry (replace, not push).
        delta = Playwright.evaluate!(page, "String(history.length - window.__h)")?
        Assert.eq(delta, "0") ? HistoryGrew(delta)

        # No reload: the client-only state survived.
        status = Playwright.text_content!(page, "#status")?
        Assert.eq(status, "closed") ? PageReloaded(status)

        Playwright.close!(browser)?
        Ok({})
    )
