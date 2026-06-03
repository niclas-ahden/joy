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

## DOM.navigate! is fire-and-forget. It doesn't validate the target, so the
## browser still moves to a URL the server 404s. The Rust-side error branch in
## roc_fx_dom_navigate (set_href returning Err) is not reachable from a normal
## top-level page. It only fires in restricted contexts like cross-origin
## sandboxed frames, which this harness can't construct. So we test the
## observable contract here, not the unreachable console.log branch.
main! : List Arg.Arg => Result {} _
main! = |_args|
    TestEnvironment.with!(|worker_url|
        { browser, page } = Playwright.launch_page!(Chromium)?
        Playwright.navigate!(page, "$(worker_url)/dom")?
        Playwright.wait_for!(page, "#btn-navigate-missing", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        # Navigate to a path the server has no file for.
        Playwright.click!(page, "#btn-navigate-missing")?

        # The browser still navigates and lands on the server's 404 page.
        Playwright.wait_for!(page, "text=404 Not Found", Attached)
        |> Result.map_err(|e| DidNotNavigate(Inspect.to_str(e)))?

        # And the URL did change, confirming navigate! fired regardless of the
        # destination being valid.
        url_path = Playwright.evaluate!(page, "window.location.pathname")?
        Assert.eq(url_path, "/dom/nope") ? WrongUrl(url_path)

        Playwright.close!(browser)?
        Ok({})
    )
