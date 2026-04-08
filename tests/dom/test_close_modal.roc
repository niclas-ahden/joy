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

## DOM.close_modal! closes an open <dialog>.
main! : List Arg.Arg => Result {} _
main! = |_args|
    TestEnvironment.with!(|worker_url|
        { browser, page } = Playwright.launch_page!(Chromium)?
        Playwright.navigate!(page, "$(worker_url)/dom")?
        Playwright.wait_for!(page, "#btn-show", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        # Open then close
        Playwright.click!(page, "#btn-show")?
        Playwright.wait_for!(page, "#dialog-content", Visible)
        |> Result.map_err(|e| DialogDidNotOpen(Inspect.to_str(e)))?

        # Close using the button inside the dialog (modal captures focus)
        Playwright.click!(page, "#btn-close-inside")?

        # Status updates to "closed" after close_modal! runs
        Playwright.wait_for!(page, "text=closed", Attached)
        |> Result.map_err(|e| DialogDidNotClose(Inspect.to_str(e)))?

        status = Playwright.text_content!(page, "#status")?
        Assert.eq(status, "closed") ? WrongStatus(status)

        Playwright.close!(browser)?
        Ok({})
    )
