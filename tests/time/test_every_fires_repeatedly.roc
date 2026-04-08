app [main!] {
    pf: platform "https://github.com/growthagent/basic-cli/releases/download/0.27.0/G-A6F5ny0IYDx4hmF3t_YPHUSR28c9ZXMBnh0FEJjwk.tar.br",
    playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.6.0/t00zRqBa9zpsMFrqXnM3wU2Vucyci4nnHdk3y6DBGg4.tar.br",
    spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.2.0/Cv22_pXKIt82Cz5qzFxdm47SNo81RDx6j4gahQIJvME.tar.br",
}

import pf.Arg
import pf.Cmd
import pf.Env
import pf.Http
import pf.Sleep

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

## Time.every! fires repeatedly at the given interval.
main! : List Arg.Arg => Result {} _
main! = |_args|
    TestEnvironment.with!(|worker_url|
        { browser, page } = Playwright.launch_page!(Chromium)?
        Playwright.navigate!(page, "$(worker_url)/time")?
        Playwright.wait_for!(page, "#btn-every", Visible)
        |> Result.map_err(|e| WasmDidNotLoad(Inspect.to_str(e)))?

        Playwright.click!(page, "#btn-every")?

        # Wait for multiple intervals (100ms each, wait 550ms for ~5 fires)
        _ = Sleep.millis!(550)

        count_str = Playwright.text_content!(page, "#event-count")?
        count = Str.to_i64(count_str) |> Result.with_default(0)

        # Should have fired multiple times (at least 3, allowing for timing variance)
        Assert.true(count >= 3) ? TooFewFires("expected >= 3, got $(count_str)")

        last_event = Playwright.text_content!(page, "#last-event")?
        Assert.eq(last_event, "every") ? WrongEvent(last_event)

        # Cancel to clean up
        Playwright.click!(page, "#btn-cancel")?

        Playwright.close!(browser)?
        Ok({})
    )
