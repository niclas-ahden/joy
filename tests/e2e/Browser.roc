import pf.Cmd
import pf.Duration
import pf.Env
import pf.OsStr
import playwright.Playwright exposing [assert!]

## Shared plumbing for the browser tests in this directory. Every test is a
## standalone app (see run.roc) driving its own browser, so the launch and
## navigate dance would otherwise repeat in each file. JOY_BROWSER picks the
## engine (chromium, the default, firefox or webkit), set by e2e.roc from its
## --browser flag. Assertions stay in the
## tests, through Playwright's assert!: each claim re-checks the page until it
## holds or the page's timeout expires, so the tests need no polling of their
## own.
Browser :: [].{
	## Like open!, at a page of an app by its path under the server, as in
	## "hydrate_lab/" or "hydrate_lab/stale" (a page of a server-rendered
	## app, see render_pages! in build.roc).
	open_page! = |path, ready| {
		base = Env.var_str!("E2E_URL") ?? "http://127.0.0.1:8787"
		{ browser, page } = Browser.launch!()?
		page.navigate!("${base}/${path}")?
		assert!(page.find(ready).is_visible())?
		Ok({ browser, page })
	}

	## A browser and a blank page in the engine JOY_BROWSER names, for a test
	## that navigates itself (holding a request first, say).
	launch! = || {
		browser_type = match Env.var_str!("JOY_BROWSER") ?? "chromium" {
			"firefox" => Firefox
			"webkit" => WebKit
			_ => Chromium(DefaultChannel)
		}
		Playwright.launch_page_with!(
			{ new: Cmd.new, os_str: OsStr.from_str, spawn!: Cmd.Command.spawn_leashed!, millis: Duration.millis },
			{ browser_type, timeout: TimeoutMilliseconds(10000) },
		)
	}

	## The server's base URL (see e2e.roc).
	base_url! = || Env.var_str!("E2E_URL") ?? "http://127.0.0.1:8787"

	open! = |app_name, ready| {
		base = Env.var_str!("E2E_URL") ?? "http://127.0.0.1:8787"
		browser_type = match Env.var_str!("JOY_BROWSER") ?? "chromium" {
			"firefox" => Firefox
			"webkit" => WebKit
			_ => Chromium(DefaultChannel)
		}
		{ browser, page } = Playwright.launch_page_with!(
			{ new: Cmd.new, os_str: OsStr.from_str, spawn!: Cmd.Command.spawn_leashed!, millis: Duration.millis },
			{ browser_type, timeout: TimeoutMilliseconds(10000) },
		)?
		page.navigate!("${base}/${app_name}/")?
		assert!(page.find(ready).is_visible())?
		Ok({ browser, page })
	}
}
